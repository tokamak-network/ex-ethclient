defmodule EthNet.Sync.ManagerTest do
  use ExUnit.Case, async: false

  alias EthNet.Sync.Manager
  alias EthCore.Types.BlockHeader

  @empty_hash :binary.copy(<<0>>, 32)
  @empty_bloom :binary.copy(<<0>>, 256)
  @empty_nonce :binary.copy(<<0>>, 8)
  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  setup do
    start_supervised!(Manager)
    :ok
  end

  defp make_header(number) do
    %BlockHeader{
      parent_hash: @empty_hash,
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

  test "starts with idle status" do
    status = Manager.status()
    assert status.status == :idle
    assert status.target_block == 0
    assert status.current_block == 0
    assert status.pending_headers == 0
    assert status.pending_bodies == 0
  end

  test "start_sync changes status to syncing" do
    Manager.start_sync(1000)
    # Give the cast time to process
    Process.sleep(50)

    status = Manager.status()
    assert status.status == :syncing
    assert status.target_block == 1000
  end

  test "handle_headers stores downloaded headers" do
    Manager.start_sync(1000)
    Process.sleep(50)

    headers = [make_header(1), make_header(2)]
    header_rlps = Enum.map(headers, &encode_header_rlp/1)

    Manager.handle_headers(self(), 1, header_rlps)
    Process.sleep(50)

    status = Manager.status()
    assert status.downloaded_headers == 2
  end

  test "handle_bodies logs receipt for unknown request without crashing" do
    Manager.start_sync(1000)
    Process.sleep(50)

    # Send bodies without a matching pending request — should not crash
    Manager.handle_bodies(self(), 999, [[[], []], [[], []]])
    Process.sleep(50)

    status = Manager.status()
    assert status.status == :syncing
    assert status.downloaded_bodies == 0
  end

  test "handle_new_block_hashes does not crash" do
    hash = :crypto.strong_rand_bytes(32)
    assert :ok == Manager.handle_new_block_hashes(self(), [{hash, 100}])
  end

  test "handle_new_block does not crash" do
    assert :ok == Manager.handle_new_block(self(), %{block: <<>>, total_difficulty: 0})
  end

  test "status reports pending counts" do
    status = Manager.status()
    assert is_integer(status.pending_headers)
    assert is_integer(status.pending_bodies)
    assert is_integer(status.downloaded_headers)
    assert is_integer(status.downloaded_bodies)
  end
end
