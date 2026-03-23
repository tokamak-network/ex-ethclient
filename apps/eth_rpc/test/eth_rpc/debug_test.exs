defmodule EthRpc.DebugTest do
  use ExUnit.Case, async: false

  alias EthRpc.Eth
  alias EthRpc.TestStore

  defp genesis_header do
    %EthCore.Types.BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<0::256>>,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 0,
      gas_limit: 8_000_000,
      gas_used: 0,
      timestamp: 0,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>,
      base_fee_per_gas: 1_000_000_000,
      withdrawals_root: nil,
      blob_gas_used: nil,
      excess_blob_gas: nil,
      parent_beacon_block_root: nil,
      requests_hash: nil
    }
  end

  defp start_test_store do
    name = :"test_debug_store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = TestStore.start_link(name: name)

    header = genesis_header()
    encoded_header = :erlang.term_to_binary(header)
    block_hash = <<0::256>>

    :ok = TestStore.put_block_header(name, block_hash, encoded_header)

    :ok =
      TestStore.put_block_body(
        name,
        block_hash,
        :erlang.term_to_binary(%{transactions: [], ommers: []})
      )

    :ok = TestStore.set_canonical_hash(name, 0, block_hash)
    :ok = TestStore.set_latest_block_number(name, 0)

    {pid, name}
  end

  describe "debug_ namespace (no store)" do
    test "debug_getRawHeader returns nil when no store" do
      assert {:ok, nil} = Eth.handle("debug_getRawHeader", ["0x0"])
    end

    test "debug_getRawBlock returns nil when no store" do
      assert {:ok, nil} = Eth.handle("debug_getRawBlock", ["0x0"])
    end

    test "debug_getRawTransaction returns nil when no store" do
      assert {:ok, nil} =
               Eth.handle("debug_getRawTransaction", [
                 "0x" <> String.duplicate("0", 64)
               ])
    end

    test "debug_getRawReceipts returns empty list when no store" do
      assert {:ok, []} = Eth.handle("debug_getRawReceipts", ["0x0"])
    end

    test "debug_getRawHeader with invalid params returns error" do
      assert {:error, -32602, _msg} = Eth.handle("debug_getRawHeader", [])
    end
  end

  describe "debug_ namespace (with store)" do
    setup do
      {pid, name} = start_test_store()

      Application.put_env(:eth_rpc, :store, {TestStore, name})
      Application.put_env(:eth_rpc, :store_module, TestStore)

      on_exit(fn ->
        Application.delete_env(:eth_rpc, :store)
        Application.delete_env(:eth_rpc, :store_module)
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{store_name: name}
    end

    test "debug_getRawReceipts returns list for existing block" do
      assert {:ok, receipts} = Eth.handle("debug_getRawReceipts", ["0x0"])
      assert is_list(receipts)
    end
  end
end
