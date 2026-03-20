defmodule EthRpc.EthTest do
  use ExUnit.Case, async: false

  alias EthRpc.Eth
  alias EthRpc.TestStore

  # Helper to build a minimal block header struct for testing
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
    name = :"test_rpc_store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = TestStore.start_link(name: name)

    # Store genesis header
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

  describe "eth_ namespace (no store)" do
    test "eth_chainId returns mainnet chain id" do
      assert {:ok, "0x1"} = Eth.handle("eth_chainId", [])
    end

    test "eth_blockNumber returns 0x0 when store unavailable" do
      assert {:ok, "0x0"} = Eth.handle("eth_blockNumber", [])
    end

    test "eth_getBalance returns 0x0 for unknown address" do
      assert {:ok, "0x0"} =
               Eth.handle("eth_getBalance", [
                 "0x0000000000000000000000000000000000000000",
                 "latest"
               ])
    end

    test "eth_getTransactionCount returns zero" do
      assert {:ok, "0x0"} =
               Eth.handle("eth_getTransactionCount", [
                 "0x0000000000000000000000000000000000000000",
                 "latest"
               ])
    end

    test "eth_getCode returns empty code" do
      assert {:ok, "0x"} =
               Eth.handle("eth_getCode", [
                 "0x0000000000000000000000000000000000000000",
                 "latest"
               ])
    end

    test "eth_getStorageAt returns 32 zero bytes" do
      assert {:ok, result} =
               Eth.handle("eth_getStorageAt", [
                 "0x0000000000000000000000000000000000000000",
                 "0x0",
                 "latest"
               ])

      assert result == "0x" <> String.duplicate("0", 64)
    end

    test "eth_call returns empty result" do
      assert {:ok, "0x"} = Eth.handle("eth_call", [%{}, "latest"])
    end

    test "eth_estimateGas returns 21000" do
      assert {:ok, "0x5208"} = Eth.handle("eth_estimateGas", [%{}])
    end

    test "eth_gasPrice returns 1 gwei" do
      assert {:ok, "0x3B9ACA00"} = Eth.handle("eth_gasPrice", [])
    end

    test "eth_getBlockByNumber returns nil when no store" do
      assert {:ok, nil} =
               Eth.handle("eth_getBlockByNumber", ["0x0", true])
    end

    test "eth_getBlockByHash returns nil when no store" do
      assert {:ok, nil} =
               Eth.handle("eth_getBlockByHash", [
                 "0x" <> String.duplicate("0", 64),
                 true
               ])
    end

    test "eth_getTransactionByHash returns null" do
      assert {:ok, nil} =
               Eth.handle("eth_getTransactionByHash", [
                 "0x" <> String.duplicate("0", 64)
               ])
    end

    test "eth_getTransactionReceipt returns null" do
      assert {:ok, nil} =
               Eth.handle("eth_getTransactionReceipt", [
                 "0x" <> String.duplicate("0", 64)
               ])
    end

    test "eth_sendRawTransaction returns error when chain unavailable" do
      assert {:error, _code, _msg} =
               Eth.handle("eth_sendRawTransaction", ["0x00"])
    end

    test "eth_sendRawTransaction with invalid params returns error" do
      assert {:error, -32602, _msg} =
               Eth.handle("eth_sendRawTransaction", [])
    end

    test "eth_syncing returns false" do
      assert {:ok, false} = Eth.handle("eth_syncing", [])
    end

    test "eth_mining returns false" do
      assert {:ok, false} = Eth.handle("eth_mining", [])
    end

    test "eth_accounts returns empty list" do
      assert {:ok, []} = Eth.handle("eth_accounts", [])
    end
  end

  describe "eth_ namespace (with store)" do
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

    test "eth_blockNumber returns 0x0 with genesis" do
      assert {:ok, "0x0"} = Eth.handle("eth_blockNumber", [])
    end

    test "eth_getBalance returns 0x0 for unknown address" do
      assert {:ok, "0x0"} =
               Eth.handle("eth_getBalance", [
                 "0x1111111111111111111111111111111111111111",
                 "latest"
               ])
    end

    test "eth_getBlockByNumber with 0x0 returns genesis block" do
      assert {:ok, block} =
               Eth.handle("eth_getBlockByNumber", ["0x0", false])

      assert is_map(block)
      assert block["number"] == "0x0"
      assert block["gasLimit"] == "0x7a1200"
      assert block["gasUsed"] == "0x0"
      assert block["timestamp"] == "0x0"
    end

    test "eth_getBlockByNumber with latest tag" do
      assert {:ok, block} =
               Eth.handle("eth_getBlockByNumber", ["latest", false])

      assert is_map(block)
      assert block["number"] == "0x0"
    end

    test "eth_getBlockByNumber with earliest tag" do
      assert {:ok, block} =
               Eth.handle("eth_getBlockByNumber", ["earliest", false])

      assert is_map(block)
      assert block["number"] == "0x0"
    end

    test "eth_getBlockByNumber for non-existent block" do
      assert {:ok, nil} =
               Eth.handle("eth_getBlockByNumber", ["0xff", false])
    end

    test "eth_getBlockByHash with genesis hash" do
      hash = "0x" <> String.duplicate("0", 64)

      assert {:ok, block} =
               Eth.handle("eth_getBlockByHash", [hash, false])

      assert is_map(block)
      assert block["number"] == "0x0"
    end

    test "eth_getBalance with stored account", %{store_name: name} do
      address = <<1::160>>

      account = %EthCore.Types.Account{
        nonce: 5,
        balance: 1000,
        storage_root: EthCore.Types.Account.empty_trie_root(),
        code_hash: EthCore.Types.Account.empty_code_hash()
      }

      :ok = TestStore.put_account(name, address, :erlang.term_to_binary(account))

      addr_hex =
        "0x0000000000000000000000000000000000000001"

      assert {:ok, "0x3e8"} =
               Eth.handle("eth_getBalance", [addr_hex, "latest"])
    end

    test "eth_getTransactionCount with stored account", %{
      store_name: name
    } do
      address = <<2::160>>

      account = %EthCore.Types.Account{
        nonce: 42,
        balance: 0,
        storage_root: EthCore.Types.Account.empty_trie_root(),
        code_hash: EthCore.Types.Account.empty_code_hash()
      }

      :ok =
        TestStore.put_account(
          name,
          address,
          :erlang.term_to_binary(account)
        )

      addr_hex =
        "0x0000000000000000000000000000000000000002"

      assert {:ok, "0x2a"} =
               Eth.handle("eth_getTransactionCount", [
                 addr_hex,
                 "latest"
               ])
    end
  end

  describe "eth_sendRawTransaction (with mempool)" do
    setup do
      # Check if EthChain.Mempool is already registered
      case GenServer.whereis(EthChain.Mempool) do
        nil ->
          {:ok, mempool_pid} = EthChain.Mempool.start_link(name: EthChain.Mempool)

          on_exit(fn ->
            if Process.alive?(mempool_pid), do: GenServer.stop(mempool_pid)
          end)

          %{mempool: EthChain.Mempool}

        _pid ->
          %{mempool: EthChain.Mempool}
      end
    end

    test "submits valid raw transaction and returns hash" do
      tx = %EthCore.Types.Transaction.Legacy{
        nonce: 0,
        gas_price: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed_tx = EthCore.Types.SignedTransaction.new(tx, 27, 1, 2)
      raw = EthCore.RLP.encode_signed(signed_tx)
      hex = "0x" <> Base.encode16(raw, case: :lower)

      assert {:ok, hash_hex} = Eth.handle("eth_sendRawTransaction", [hex])
      assert String.starts_with?(hash_hex, "0x")
      assert byte_size(hash_hex) == 66
    end

    test "returns error for invalid transaction data" do
      assert {:error, _code, _msg} =
               Eth.handle("eth_sendRawTransaction", ["0x"])
    end
  end

  describe "net_ namespace" do
    test "net_version returns mainnet" do
      assert {:ok, "1"} = Eth.handle("net_version", [])
    end

    test "net_listening returns true" do
      assert {:ok, true} = Eth.handle("net_listening", [])
    end

    test "net_peerCount returns zero" do
      assert {:ok, "0x0"} = Eth.handle("net_peerCount", [])
    end
  end

  describe "web3_ namespace" do
    test "web3_clientVersion returns version string" do
      assert {:ok, "ex_ethclient/0.1.0"} =
               Eth.handle("web3_clientVersion", [])
    end

    test "web3_sha3 computes keccak256" do
      assert {:ok, hash} = Eth.handle("web3_sha3", ["0x"])
      assert String.starts_with?(hash, "0x")
      assert byte_size(hash) == 66
    end

    test "web3_sha3 with known input" do
      assert {:ok, hash} = Eth.handle("web3_sha3", ["0x"])

      assert hash ==
               "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    end

    test "web3_sha3 with invalid params returns error" do
      assert {:error, -32602, _} = Eth.handle("web3_sha3", [])
      assert {:error, -32602, _} = Eth.handle("web3_sha3", ["invalid"])
    end
  end

  describe "engine_ namespace" do
    test "engine_forkchoiceUpdatedV3 returns SYNCING when store unavailable" do
      assert {:ok, result} =
               Eth.handle("engine_forkchoiceUpdatedV3", [%{}])

      assert result["payloadStatus"]["status"] == "SYNCING"
      assert result["payloadId"] == nil
    end

    test "engine_newPayloadV3 returns INVALID for empty params" do
      assert {:ok, result} =
               Eth.handle("engine_newPayloadV3", [%{}])

      # Empty map missing required fields returns INVALID
      assert result["status"] == "INVALID"
    end

    test "engine_getPayloadV3 returns error" do
      assert {:error, -38001, "Unknown payload"} =
               Eth.handle("engine_getPayloadV3", [%{}])
    end

    test "engine_exchangeCapabilities returns supported methods" do
      assert {:ok, methods} =
               Eth.handle("engine_exchangeCapabilities", [])

      assert is_list(methods)
      assert "engine_forkchoiceUpdatedV3" in methods
    end
  end

  describe "unknown method" do
    test "returns method not found error" do
      assert {:error, -32601, _} =
               Eth.handle("eth_doesNotExist", [])
    end
  end
end
