defmodule EthRpc.BlockQueriesTest do
  use ExUnit.Case, async: false

  alias EthCore.Types.{BlockHeader, SignedTransaction, Transaction}
  alias EthRpc.{Eth, Hex, TestStore}

  # -- Test helpers -----------------------------------------------------------

  defp make_header(number) do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<0::256>>,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: number,
      gas_limit: 8_000_000,
      gas_used: 63_000,
      timestamp: 1_700_000_000 + number,
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

  defp make_signed_tx(nonce, to_byte) do
    tx = %Transaction.Legacy{
      nonce: nonce,
      gas_price: 2_000_000_000,
      gas_limit: 21_000,
      to: <<to_byte::160>>,
      value: 1_000_000 * (nonce + 1),
      data: <<>>
    }

    # Use fake but deterministic signature values
    SignedTransaction.new(tx, 27, nonce + 100, nonce + 200)
  end

  defp make_receipt(type, cumulative_gas) do
    %EthCore.Types.Receipt{
      type: type,
      status: 1,
      cumulative_gas_used: cumulative_gas,
      logs_bloom: <<0::2048>>,
      logs: []
    }
  end

  defp start_store_with_block do
    name = :"test_bq_store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = TestStore.start_link(name: name)

    header = make_header(5)
    block_hash = EthStorage.Encoding.block_hash(header)

    txs = [make_signed_tx(0, 1), make_signed_tx(1, 2), make_signed_tx(2, 3)]

    encoded_header = :erlang.term_to_binary(header)

    encoded_body =
      :erlang.term_to_binary(%{transactions: txs, ommers: [], withdrawals: nil})

    :ok = TestStore.put_block_header(name, block_hash, encoded_header)
    :ok = TestStore.put_block_body(name, block_hash, encoded_body)
    :ok = TestStore.set_canonical_hash(name, 5, block_hash)
    :ok = TestStore.set_latest_block_number(name, 5)

    # Store tx locations
    Enum.with_index(txs, fn signed_tx, idx ->
      tx_hash = SignedTransaction.tx_hash(signed_tx)
      :ok = TestStore.put_tx_location(name, tx_hash, block_hash, idx)
    end)

    # Store receipts
    Enum.with_index(txs, fn _tx, idx ->
      receipt = make_receipt(0, 21_000 * (idx + 1))
      :ok = TestStore.put_receipt(name, block_hash, idx, :erlang.term_to_binary(receipt))
    end)

    Application.put_env(:eth_rpc, :store, {TestStore, name})
    Application.put_env(:eth_rpc, :store_module, TestStore)

    on_exit(fn ->
      Application.delete_env(:eth_rpc, :store)
      Application.delete_env(:eth_rpc, :store_module)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{store_name: name, block_hash: block_hash, txs: txs, header: header}
  end

  # -- Tests ------------------------------------------------------------------

  describe "eth_getBlockTransactionCountByNumber" do
    setup do
      start_store_with_block()
    end

    test "returns transaction count for existing block" do
      assert {:ok, "0x3"} =
               Eth.handle("eth_getBlockTransactionCountByNumber", ["0x5"])
    end

    test "returns transaction count for latest tag" do
      assert {:ok, "0x3"} =
               Eth.handle("eth_getBlockTransactionCountByNumber", ["latest"])
    end

    test "returns null for non-existent block" do
      assert {:ok, nil} =
               Eth.handle("eth_getBlockTransactionCountByNumber", ["0xff"])
    end
  end

  describe "eth_getBlockTransactionCountByHash" do
    setup do
      start_store_with_block()
    end

    test "returns transaction count for existing block", %{block_hash: hash} do
      hash_hex = Hex.encode_data(hash)

      assert {:ok, "0x3"} =
               Eth.handle("eth_getBlockTransactionCountByHash", [hash_hex])
    end

    test "returns null for non-existent block hash" do
      fake_hash = "0x" <> String.duplicate("ff", 32)

      assert {:ok, nil} =
               Eth.handle("eth_getBlockTransactionCountByHash", [fake_hash])
    end
  end

  describe "eth_getTransactionByBlockNumberAndIndex" do
    setup do
      start_store_with_block()
    end

    test "returns transaction at index 0", %{txs: txs} do
      assert {:ok, result} =
               Eth.handle("eth_getTransactionByBlockNumberAndIndex", ["0x5", "0x0"])

      assert result["transactionIndex"] == "0x0"
      assert result["blockNumber"] == "0x5"

      expected_hash = Hex.encode_data(SignedTransaction.tx_hash(Enum.at(txs, 0)))
      assert result["hash"] == expected_hash
    end

    test "returns transaction at index 2", %{txs: txs} do
      assert {:ok, result} =
               Eth.handle("eth_getTransactionByBlockNumberAndIndex", ["0x5", "0x2"])

      assert result["transactionIndex"] == "0x2"

      expected_hash = Hex.encode_data(SignedTransaction.tx_hash(Enum.at(txs, 2)))
      assert result["hash"] == expected_hash
    end

    test "returns null for out-of-range index" do
      assert {:ok, nil} =
               Eth.handle("eth_getTransactionByBlockNumberAndIndex", ["0x5", "0xa"])
    end

    test "returns null for non-existent block number" do
      assert {:ok, nil} =
               Eth.handle("eth_getTransactionByBlockNumberAndIndex", ["0xff", "0x0"])
    end
  end

  describe "eth_getTransactionByBlockHashAndIndex" do
    setup do
      start_store_with_block()
    end

    test "returns transaction at index 1", %{block_hash: hash, txs: txs} do
      hash_hex = Hex.encode_data(hash)

      assert {:ok, result} =
               Eth.handle("eth_getTransactionByBlockHashAndIndex", [hash_hex, "0x1"])

      assert result["transactionIndex"] == "0x1"
      assert result["blockNumber"] == "0x5"

      expected_hash = Hex.encode_data(SignedTransaction.tx_hash(Enum.at(txs, 1)))
      assert result["hash"] == expected_hash
    end

    test "returns null for out-of-range index", %{block_hash: hash} do
      hash_hex = Hex.encode_data(hash)

      assert {:ok, nil} =
               Eth.handle("eth_getTransactionByBlockHashAndIndex", [hash_hex, "0xf"])
    end

    test "returns null for non-existent hash" do
      fake_hash = "0x" <> String.duplicate("ab", 32)

      assert {:ok, nil} =
               Eth.handle("eth_getTransactionByBlockHashAndIndex", [fake_hash, "0x0"])
    end
  end

  describe "eth_getBlockReceipts" do
    setup do
      start_store_with_block()
    end

    test "returns all receipts for a block" do
      assert {:ok, receipts} =
               Eth.handle("eth_getBlockReceipts", ["0x5"])

      assert length(receipts) == 3

      Enum.each(receipts, fn r ->
        assert r["status"] == "0x1"
        assert r["blockNumber"] == "0x5"
        assert Map.has_key?(r, "transactionHash")
        assert Map.has_key?(r, "transactionIndex")
        assert Map.has_key?(r, "blockHash")
        assert Map.has_key?(r, "from")
        assert Map.has_key?(r, "gasUsed")
      end)
    end

    test "returns null for non-existent block" do
      assert {:ok, nil} =
               Eth.handle("eth_getBlockReceipts", ["0xff"])
    end
  end

  describe "eth_getTransactionByHash with tx index" do
    setup do
      start_store_with_block()
    end

    test "returns transaction by its hash", %{txs: txs} do
      signed_tx = Enum.at(txs, 1)
      tx_hash_hex = Hex.encode_data(SignedTransaction.tx_hash(signed_tx))

      assert {:ok, result} =
               Eth.handle("eth_getTransactionByHash", [tx_hash_hex])

      assert result["hash"] == tx_hash_hex
      assert result["transactionIndex"] == "0x1"
      assert result["blockNumber"] == "0x5"
      assert result["nonce"] == "0x1"
    end

    test "returns null for unknown tx hash" do
      fake_hash = "0x" <> String.duplicate("cc", 32)

      assert {:ok, nil} =
               Eth.handle("eth_getTransactionByHash", [fake_hash])
    end
  end

  describe "eth_getTransactionReceipt with tx index" do
    setup do
      start_store_with_block()
    end

    test "returns receipt for known transaction", %{txs: txs} do
      signed_tx = Enum.at(txs, 0)
      tx_hash_hex = Hex.encode_data(SignedTransaction.tx_hash(signed_tx))

      assert {:ok, result} =
               Eth.handle("eth_getTransactionReceipt", [tx_hash_hex])

      assert result["transactionHash"] == tx_hash_hex
      assert result["transactionIndex"] == "0x0"
      assert result["blockNumber"] == "0x5"
      assert result["status"] == "0x1"
      assert result["cumulativeGasUsed"] == "0x5208"
      assert Map.has_key?(result, "from")
      assert Map.has_key?(result, "to")
      assert Map.has_key?(result, "gasUsed")
      assert Map.has_key?(result, "contractAddress")
      assert Map.has_key?(result, "logsBloom")
      assert Map.has_key?(result, "logs")
      assert Map.has_key?(result, "type")
    end

    test "returns null for unknown tx hash" do
      fake_hash = "0x" <> String.duplicate("dd", 32)

      assert {:ok, nil} =
               Eth.handle("eth_getTransactionReceipt", [fake_hash])
    end
  end

  describe "transaction formatting includes all required fields" do
    setup do
      start_store_with_block()
    end

    test "formatted transaction has all JSON-RPC fields", %{txs: txs} do
      signed_tx = Enum.at(txs, 0)
      tx_hash_hex = Hex.encode_data(SignedTransaction.tx_hash(signed_tx))

      assert {:ok, result} =
               Eth.handle("eth_getTransactionByHash", [tx_hash_hex])

      required_fields = [
        "hash",
        "nonce",
        "blockHash",
        "blockNumber",
        "transactionIndex",
        "from",
        "to",
        "value",
        "gas",
        "input",
        "v",
        "r",
        "s",
        "type"
      ]

      for field <- required_fields do
        assert Map.has_key?(result, field),
               "Missing field: #{field}"
      end

      # Legacy tx should have gasPrice
      assert Map.has_key?(result, "gasPrice")
    end
  end
end
