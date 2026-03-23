defmodule EthNet.Sync.FullSyncTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias EthNet.Sync.Manager
  alias EthCore.Types.BlockHeader
  # Note: we don't alias EthStorage.Encoding here since eth_net doesn't depend on eth_storage.
  # Instead we compute block hashes directly.

  # --- Test helpers ---

  @empty_hash :binary.copy(<<0>>, 32)
  @empty_bloom :binary.copy(<<0>>, 256)
  @empty_nonce :binary.copy(<<0>>, 8)
  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  defp make_header(number, parent_hash \\ nil) do
    parent = parent_hash || @empty_hash

    %BlockHeader{
      parent_hash: parent,
      ommers_hash: @empty_ommers_hash,
      coinbase: :binary.copy(<<0>>, 20),
      state_root: @empty_hash,
      transactions_root: @empty_hash,
      receipts_root: @empty_hash,
      logs_bloom: @empty_bloom,
      difficulty: 0,
      number: number,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 1_700_000_000 + number,
      extra_data: <<>>,
      mix_hash: @empty_hash,
      nonce: @empty_nonce,
      base_fee_per_gas: 1_000_000_000
    }
  end

  defp encode_header_rlp(header) do
    EthCore.RLP.encode_header(header)
  end

  defp block_hash(header) do
    header
    |> EthCore.RLP.encode_header()
    |> EthCrypto.Hash.keccak256()
  end

  defp make_chain(start_number, count) do
    Enum.map(start_number..(start_number + count - 1), fn n ->
      parent_hash =
        if n == start_number do
          @empty_hash
        else
          block_hash(make_header(n - 1))
        end

      make_header(n, parent_hash)
    end)
  end

  # A mock block pipeline that always succeeds and records processed blocks
  defp mock_pipeline_success do
    test_pid = self()

    fn block, _store ->
      send(test_pid, {:block_processed, block.header.number})
      hash = block_hash(block.header)
      {:ok, hash}
    end
  end

  # A mock block pipeline that fails on a specific block number
  defp mock_pipeline_fail_at(fail_number) do
    test_pid = self()

    fn block, _store ->
      if block.header.number == fail_number do
        send(test_pid, {:block_failed, block.header.number})
        {:error, :validation_failed}
      else
        send(test_pid, {:block_processed, block.header.number})
        hash = block_hash(block.header)
        {:ok, hash}
      end
    end
  end

  # Collects all {:send_eth_message, ...} messages from the process mailbox
  defp collect_eth_messages(timeout \\ 100) do
    receive do
      {:send_eth_message, code, payload} ->
        [{code, payload} | collect_eth_messages(timeout)]
    after
      timeout -> []
    end
  end

  # --- Tests ---

  describe "header request -> body request flow" do
    test "receiving headers triggers body request to peer" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_flow,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      # Start sync — it will try to request headers from peers and fail (no peers),
      # so we drive it manually
      GenServer.cast(pid, {:start_sync, 5, []})
      Process.sleep(50)

      # Simulate receiving headers from peer (peer is self() so we get messages)
      headers = make_chain(1, 3)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)

      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(100)

      # We should have received a GetBlockBodies message
      messages = collect_eth_messages()
      assert length(messages) > 0

      {code, _payload} = hd(messages)
      # GetBlockBodies code = 0x10 + 0x05 = 0x15
      assert code == 0x15
    end

    test "decoded headers are stored in received_headers map" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_headers_stored,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 5, []})
      Process.sleep(50)

      headers = make_chain(1, 2)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)

      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(50)

      status = Manager.status(pid)
      assert status.downloaded_headers == 2
    end
  end

  describe "block assembly from headers + bodies" do
    test "assembles and processes blocks when bodies arrive" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_assembly,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 3, []})
      Process.sleep(50)

      # Send headers
      headers = make_chain(1, 3)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(50)

      # Consume the GetBlockBodies message sent to us
      _messages = collect_eth_messages()

      # Now find the body request_id — it should be 2 (after the initial header request used 1)
      # Send matching bodies (empty transactions and ommers for each block)
      bodies = Enum.map(1..3, fn _n -> [[], []] end)
      # The body request_id is 1 (next_request_id starts at 1, header request
      # via :request_headers never succeeded due to no peers)
      Manager.handle_bodies(pid, self(), 1, bodies)
      Process.sleep(200)

      # Verify blocks were processed
      assert_received {:block_processed, 1}
      assert_received {:block_processed, 2}
      assert_received {:block_processed, 3}
    end

    test "handles empty body list by padding" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_pad,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 2, []})
      Process.sleep(50)

      headers = make_chain(1, 2)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(50)

      _messages = collect_eth_messages()

      # Send fewer bodies than headers — should pad with empty bodies
      bodies = [[[], []]]
      Manager.handle_bodies(pid, self(), 1, bodies)
      Process.sleep(200)

      assert_received {:block_processed, 1}
      assert_received {:block_processed, 2}
    end
  end

  describe "block validation during sync" do
    test "stops processing on block validation failure" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_fail,
          block_pipeline: mock_pipeline_fail_at(2),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 3, []})
      Process.sleep(50)

      headers = make_chain(1, 3)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(50)

      _messages = collect_eth_messages()

      bodies = Enum.map(1..3, fn _n -> [[], []] end)
      Manager.handle_bodies(pid, self(), 1, bodies)
      Process.sleep(200)

      # Block 1 should have been processed, block 2 should have failed
      assert_received {:block_processed, 1}
      assert_received {:block_failed, 2}
      # Block 3 should NOT have been processed
      refute_received {:block_processed, 3}
    end
  end

  describe "sync progress tracking" do
    test "current_block updates as blocks are processed" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_progress,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 3, []})
      Process.sleep(50)

      headers = make_chain(1, 3)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(50)

      _messages = collect_eth_messages()

      bodies = Enum.map(1..3, fn _n -> [[], []] end)
      Manager.handle_bodies(pid, self(), 1, bodies)
      Process.sleep(200)

      status = Manager.status(pid)
      assert status.current_block == 3
    end

    test "starts at block 0" do
      {:ok, pid} = Manager.start_link(name: :test_sync_start)

      status = Manager.status(pid)
      assert status.current_block == 0
      assert status.status == :idle
    end
  end

  describe "transition from :syncing to :synced" do
    test "transitions to :synced when target is reached" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_complete,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 2, []})
      Process.sleep(50)

      headers = make_chain(1, 2)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(50)

      _messages = collect_eth_messages()

      bodies = Enum.map(1..2, fn _n -> [[], []] end)
      Manager.handle_bodies(pid, self(), 1, bodies)
      Process.sleep(200)

      status = Manager.status(pid)
      assert status.status == :synced
      assert status.current_block == 2
      assert status.target_block == 2
    end

    test "stays :syncing when target not yet reached" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_partial,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 10, []})
      Process.sleep(50)

      # Only send 3 of 10 blocks
      headers = make_chain(1, 3)
      header_rlps = Enum.map(headers, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 1, header_rlps)
      Process.sleep(50)

      _messages = collect_eth_messages()

      bodies = Enum.map(1..3, fn _n -> [[], []] end)
      Manager.handle_bodies(pid, self(), 1, bodies)
      Process.sleep(200)

      status = Manager.status(pid)
      # Still syncing because current_block(3) < target_block(10)
      assert status.status == :syncing
      assert status.current_block == 3
    end
  end

  describe "error handling" do
    test "handles invalid header RLP gracefully" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_bad_rlp,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 5, []})
      Process.sleep(50)

      # Send garbage as header RLP
      Manager.handle_headers(pid, self(), 1, [<<0xFF, 0xFE>>])
      Process.sleep(50)

      # Should still be syncing, not crashed
      status = Manager.status(pid)
      assert status.status == :syncing
      assert status.downloaded_headers == 0
    end

    test "handles bodies for unknown request gracefully" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_unknown_req,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 5, []})
      Process.sleep(50)

      # Send bodies with a request_id that was never tracked
      Manager.handle_bodies(pid, self(), 999, [[[], []]])
      Process.sleep(50)

      # Should not crash
      status = Manager.status(pid)
      assert status.status == :syncing
    end
  end

  describe "batch continuation" do
    test "requests next batch of headers after processing first batch" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_continuation,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 6, []})
      Process.sleep(50)

      # First batch: blocks 1-3
      headers_batch1 = make_chain(1, 3)
      header_rlps1 = Enum.map(headers_batch1, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 1, header_rlps1)
      Process.sleep(50)

      # Consume GetBlockBodies message
      _messages1 = collect_eth_messages()

      bodies1 = Enum.map(1..3, fn _n -> [[], []] end)
      Manager.handle_bodies(pid, self(), 1, bodies1)
      Process.sleep(200)

      status = Manager.status(pid)
      assert status.current_block == 3
      assert status.status == :syncing

      # The manager should have sent a new GetBlockHeaders request
      # (to our pid since get_best_peer will fail and retry, but the
      # :request_headers message was sent to self())
      # We need to supply the next batch

      # Second batch: blocks 4-6
      headers_batch2 = make_chain(4, 3)
      header_rlps2 = Enum.map(headers_batch2, &encode_header_rlp/1)
      Manager.handle_headers(pid, self(), 3, header_rlps2)
      Process.sleep(50)

      _messages2 = collect_eth_messages()

      bodies2 = Enum.map(1..3, fn _n -> [[], []] end)
      Manager.handle_bodies(pid, self(), 2, bodies2)
      Process.sleep(200)

      status = Manager.status(pid)
      assert status.current_block == 6
      assert status.status == :synced
    end
  end

  describe "new block announcements" do
    test "handle_new_block_hashes updates target when higher" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_announce,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 5, []})
      Process.sleep(50)

      hash = :crypto.strong_rand_bytes(32)
      GenServer.cast(pid, {:new_block_hashes, self(), [{hash, 100}]})
      Process.sleep(50)

      status = Manager.status(pid)
      assert status.target_block == 100
    end

    test "handle_new_block_hashes does not lower target" do
      {:ok, pid} =
        Manager.start_link(
          name: :test_sync_no_lower,
          block_pipeline: mock_pipeline_success(),
          store: nil
        )

      GenServer.cast(pid, {:start_sync, 100, []})
      Process.sleep(50)

      hash = :crypto.strong_rand_bytes(32)
      GenServer.cast(pid, {:new_block_hashes, self(), [{hash, 50}]})
      Process.sleep(50)

      status = Manager.status(pid)
      assert status.target_block == 100
    end
  end
end
