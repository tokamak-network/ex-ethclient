defmodule EthDashboard.CollectorTest do
  use ExUnit.Case, async: false

  alias EthDashboard.Collector

  setup do
    # Ensure Collector is running. Since it's a named process, the first
    # test starts it and subsequent tests reuse it.
    case GenServer.whereis(Collector) do
      nil ->
        {:ok, _pid} = Collector.start_link([])

      _pid ->
        :ok
    end

    :ok
  end

  describe "get_state/0" do
    test "returns initial state structure" do
      state = Collector.get_state()

      assert is_integer(state.peer_count)
      assert is_list(state.peers)
      assert is_binary(state.sync_status)
      assert is_integer(state.current_block)
      assert is_integer(state.target_block)
      assert is_float(state.blocks_per_sec)
      assert is_list(state.engine_requests)
      assert is_list(state.latest_blocks)
      assert is_integer(state.messages_sent)
      assert is_integer(state.messages_received)
      assert is_float(state.memory_mb)
      assert is_integer(state.process_count)
    end
  end

  describe "report_engine/2" do
    test "adds engine request entries" do
      Collector.report_engine("newPayload", "VALID")
      Collector.report_engine("forkchoiceUpdated", "SYNCING")

      Process.sleep(50)

      state = Collector.get_state()
      assert length(state.engine_requests) >= 2

      [latest | _] = state.engine_requests
      assert latest.method == "forkchoiceUpdated"
      assert latest.status == "SYNCING"
      assert is_binary(latest.time)
    end

    test "caps engine requests at 20" do
      for i <- 1..25 do
        Collector.report_engine("method_#{i}", "VALID")
      end

      Process.sleep(100)

      state = Collector.get_state()
      assert length(state.engine_requests) <= 20
    end
  end

  describe "report_block/4" do
    test "adds block entries" do
      hash = :crypto.strong_rand_bytes(32)
      Collector.report_block(100, hash, 5, 21_000)

      Process.sleep(50)

      state = Collector.get_state()
      assert length(state.latest_blocks) >= 1

      # Find the block we just added
      block = Enum.find(state.latest_blocks, &(&1.number == 100))
      assert block != nil
      assert block.tx_count == 5
      assert block.gas_used == 21_000
      assert is_binary(block.hash)
      assert String.length(block.hash) == 16
    end

    test "updates current_block to max" do
      Collector.report_block(5000, <<0::256>>, 0, 0)
      Collector.report_block(3000, <<1::256>>, 0, 0)

      Process.sleep(50)

      state = Collector.get_state()
      assert state.current_block >= 5000
    end

    test "caps latest blocks at 10" do
      for i <- 1..15 do
        Collector.report_block(10_000 + i, :crypto.strong_rand_bytes(32), 0, 0)
      end

      Process.sleep(100)

      state = Collector.get_state()
      assert length(state.latest_blocks) <= 10
    end
  end

  describe "report_message/1" do
    test "increments sent counter" do
      state_before = Collector.get_state()
      Collector.report_message(:sent)
      Collector.report_message(:sent)
      Collector.report_message(:sent)

      Process.sleep(50)

      state_after = Collector.get_state()
      assert state_after.messages_sent == state_before.messages_sent + 3
    end

    test "increments received counter" do
      state_before = Collector.get_state()
      Collector.report_message(:received)
      Collector.report_message(:received)

      Process.sleep(50)

      state_after = Collector.get_state()
      assert state_after.messages_received == state_before.messages_received + 2
    end
  end

  describe "tick" do
    test "updates system metrics after tick" do
      # Wait for at least one tick to have fired
      Process.sleep(1_200)

      state = Collector.get_state()
      assert state.memory_mb > 0.0
      assert is_integer(state.uptime_seconds)
    end
  end
end
