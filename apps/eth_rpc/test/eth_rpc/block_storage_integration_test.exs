defmodule EthRpc.BlockStorageIntegrationTest do
  @moduledoc """
  Integration test: store a block via BlockPipeline, then query via RPC.
  """
  use ExUnit.Case, async: false

  alias EthChain.BlockPipeline
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}
  alias EthRpc.{Eth, Hex}
  alias EthStorage.{BlockStore, Encoding, Store}

  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  setup do
    store_name = :"int_store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = start_supervised({Store, name: store_name})

    # Store genesis
    genesis = genesis_block()
    {:ok, _} = BlockStore.store_block(genesis, store_name)
    :ok = Store.set_latest_block_number(store_name, 0)

    # Configure RPC to use this store
    Application.put_env(:eth_rpc, :store, {Store, store_name})
    Application.put_env(:eth_rpc, :store_module, Store)

    on_exit(fn ->
      Application.delete_env(:eth_rpc, :store)
      Application.delete_env(:eth_rpc, :store_module)
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{store: store_name}
  end

  defp genesis_header do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: @empty_ommers_hash,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 0,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 0,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>
    }
  end

  defp genesis_block do
    %Block{
      header: genesis_header(),
      transactions: [],
      ommers: [],
      withdrawals: nil
    }
  end

  defp make_child_block(parent_header, txs) do
    gas_used = length(txs) * 21_000

    header = %BlockHeader{
      parent_hash: Encoding.block_hash(parent_header),
      ommers_hash: @empty_ommers_hash,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: parent_header.number + 1,
      gas_limit: parent_header.gas_limit,
      gas_used: gas_used,
      timestamp: parent_header.timestamp + 12,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>
    }

    %Block{header: header, transactions: txs, ommers: []}
  end

  defp make_tx(nonce) do
    tx = %Transaction.Legacy{
      nonce: nonce,
      gas_price: 1_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, nonce + 1, nonce + 2)
  end

  describe "block pipeline -> RPC query" do
    test "eth_getBlockByNumber returns stored block", %{store: store} do
      parent = genesis_header()
      block = make_child_block(parent, [])

      assert {:ok, _hash} = BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      # Query via RPC
      assert {:ok, result} = Eth.handle("eth_getBlockByNumber", ["0x1", false])
      assert result != nil
      assert result["number"] == "0x1"
    end

    test "eth_blockNumber returns latest block number", %{store: store} do
      parent = genesis_header()
      block = make_child_block(parent, [])

      assert {:ok, _hash} = BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      assert {:ok, "0x1"} = Eth.handle("eth_blockNumber", [])
    end

    test "eth_getBlockByHash returns stored block", %{store: store} do
      parent = genesis_header()
      block = make_child_block(parent, [])

      assert {:ok, block_hash} = BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      hash_hex = Hex.encode_data(block_hash)
      assert {:ok, result} = Eth.handle("eth_getBlockByHash", [hash_hex, false])
      assert result != nil
      assert result["number"] == "0x1"
    end

    test "eth_getTransactionByHash returns indexed transaction", %{store: store} do
      parent = genesis_header()
      tx = make_tx(0)
      block = make_child_block(parent, [tx])

      assert {:ok, _hash} = BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      tx_hash = SignedTransaction.tx_hash(tx)
      tx_hash_hex = Hex.encode_data(tx_hash)

      assert {:ok, result} = Eth.handle("eth_getTransactionByHash", [tx_hash_hex])
      assert result != nil
      assert result["blockNumber"] == "0x1"
      assert result["transactionIndex"] == "0x0"
    end

    test "eth_getTransactionReceipt returns stored receipt", %{store: store} do
      parent = genesis_header()
      tx = make_tx(0)
      block = make_child_block(parent, [tx])

      assert {:ok, _hash} = BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      tx_hash = SignedTransaction.tx_hash(tx)
      tx_hash_hex = Hex.encode_data(tx_hash)

      assert {:ok, result} = Eth.handle("eth_getTransactionReceipt", [tx_hash_hex])
      assert result != nil
      assert result["blockNumber"] == "0x1"
      assert result["transactionIndex"] == "0x0"
      assert result["status"] == "0x1"
    end
  end
end
