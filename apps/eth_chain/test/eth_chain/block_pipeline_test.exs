defmodule EthChain.BlockPipelineTest do
  use ExUnit.Case, async: true

  alias EthChain.{BlockPipeline, Mempool}
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}
  alias EthStorage.{BlockStore, Encoding, Store}

  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  setup do
    store_name = :"store_#{System.unique_integer([:positive])}"
    {:ok, _store_pid} = start_supervised({Store, name: store_name})

    mempool_name = :"mempool_#{System.unique_integer([:positive])}"
    {:ok, _mempool_pid} = start_supervised({Mempool, name: mempool_name})

    # Store a custom genesis block with high gas_limit
    genesis = custom_genesis_block()
    {:ok, _hash} = BlockStore.store_block(genesis, store_name)
    :ok = EthStorage.Store.set_latest_block_number(store_name, 0)

    %{store: store_name, mempool: mempool_name}
  end

  defp custom_genesis_header do
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

  defp custom_genesis_block do
    %Block{
      header: custom_genesis_header(),
      transactions: [],
      ommers: [],
      withdrawals: nil
    }
  end

  defp make_child_block(parent_header, txs) do
    gas_used = length(txs) * 21_000
    # gas_limit must be within 1/1024 of parent and >= gas_used
    child_gas_limit = valid_child_gas_limit(parent_header.gas_limit)

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
      gas_limit: child_gas_limit,
      gas_used: gas_used,
      timestamp: parent_header.timestamp + 12,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>
    }

    %Block{header: header, transactions: txs, ommers: []}
  end

  defp valid_child_gas_limit(parent_gas_limit) do
    # Must satisfy: abs(child - parent) < parent / 1024
    parent_gas_limit
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

  describe "process_block/3" do
    test "processes a valid block after genesis and stores it", %{store: store} do
      parent = custom_genesis_header()
      block = make_child_block(parent, [])

      assert {:ok, block_hash} =
               BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      assert is_binary(block_hash)
      assert byte_size(block_hash) == 32

      # Verify block stored in BlockStore
      assert {:ok, stored_block} = BlockStore.get_block_by_number(1, store)
      assert stored_block.header.number == 1
    end

    test "stores receipts after execution", %{store: store} do
      parent = custom_genesis_header()
      tx = make_tx(0)
      block = make_child_block(parent, [tx])

      assert {:ok, block_hash} =
               BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      # Receipt should be stored at index 0
      assert {:ok, receipt_bin} = Store.get_receipt(store, block_hash, 0)
      assert receipt_bin != nil
      receipt = :erlang.binary_to_term(receipt_bin)
      assert receipt.status == 1
      assert receipt.cumulative_gas_used == 21_000
    end

    test "indexes transaction hashes", %{store: store} do
      parent = custom_genesis_header()
      tx = make_tx(0)
      block = make_child_block(parent, [tx])

      assert {:ok, block_hash} =
               BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      # Transaction hash should be indexed
      tx_hash = SignedTransaction.tx_hash(tx)
      assert {:ok, {stored_block_hash, 0}} = Store.get_tx_location(store, tx_hash)
      assert stored_block_hash == block_hash
    end

    test "updates latest block number", %{store: store} do
      parent = custom_genesis_header()
      block = make_child_block(parent, [])

      assert {:ok, _block_hash} =
               BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      assert {:ok, 1} = Store.get_latest_block_number(store)
    end

    test "rejects block with missing parent", %{store: store} do
      fake_parent = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: @empty_ommers_hash,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 999,
        gas_limit: 5000,
        gas_used: 0,
        timestamp: 1_000_000,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>
      }

      block = make_child_block(fake_parent, [])

      assert {:error, :parent_not_found} =
               BlockPipeline.process_block(block, store, evm: EthVm.Mock)
    end

    test "removes included transactions from mempool", %{store: store, mempool: mempool} do
      tx = make_tx(0)
      {:ok, _hash} = Mempool.add_transaction(tx, mempool)
      assert Mempool.size(mempool) == 1

      parent = custom_genesis_header()
      block = make_child_block(parent, [tx])

      assert {:ok, _} =
               BlockPipeline.process_block(block, store, mempool: mempool, evm: EthVm.Mock)

      assert Mempool.size(mempool) == 0
    end

    test "stores multiple receipts and indexes multiple transactions", %{store: store} do
      parent = custom_genesis_header()
      tx1 = make_tx(0)
      tx2 = make_tx(1)
      block = make_child_block(parent, [tx1, tx2])

      assert {:ok, block_hash} =
               BlockPipeline.process_block(block, store, evm: EthVm.Mock)

      # Both receipts stored
      assert {:ok, r0_bin} = Store.get_receipt(store, block_hash, 0)
      assert {:ok, r1_bin} = Store.get_receipt(store, block_hash, 1)
      r0 = :erlang.binary_to_term(r0_bin)
      r1 = :erlang.binary_to_term(r1_bin)
      assert r0.cumulative_gas_used == 21_000
      assert r1.cumulative_gas_used == 42_000

      # Both tx hashes indexed
      assert {:ok, {^block_hash, 0}} =
               Store.get_tx_location(store, SignedTransaction.tx_hash(tx1))

      assert {:ok, {^block_hash, 1}} =
               Store.get_tx_location(store, SignedTransaction.tx_hash(tx2))
    end
  end

  describe "process_new_block/3" do
    test "delegates to process_block", %{store: store, mempool: mempool} do
      parent = custom_genesis_header()
      block = make_child_block(parent, [])

      assert {:ok, block_hash} =
               BlockPipeline.process_new_block(block, store, mempool: mempool, evm: EthVm.Mock)

      assert is_binary(block_hash)
      assert byte_size(block_hash) == 32

      # Verify stored
      assert {:ok, stored_block} = BlockStore.get_block_by_number(1, store)
      assert stored_block.header.number == 1
    end

    test "rejects block with missing parent", %{store: store} do
      fake_parent = %BlockHeader{
        parent_hash: <<0::256>>,
        ommers_hash: @empty_ommers_hash,
        coinbase: <<0::160>>,
        state_root: <<0::256>>,
        transactions_root: <<0::256>>,
        receipts_root: <<0::256>>,
        logs_bloom: <<0::2048>>,
        difficulty: 0,
        number: 999,
        gas_limit: 5000,
        gas_used: 0,
        timestamp: 1_000_000,
        extra_data: <<>>,
        mix_hash: <<0::256>>,
        nonce: <<0::64>>
      }

      block = make_child_block(fake_parent, [])

      assert {:error, :parent_not_found} =
               BlockPipeline.process_new_block(block, store, evm: EthVm.Mock)
    end
  end

  describe "process_blocks/3" do
    test "processes a batch of blocks", %{store: store} do
      parent = custom_genesis_header()
      block1 = make_child_block(parent, [])

      assert {:ok, 1} = BlockPipeline.process_blocks([block1], store, evm: EthVm.Mock)

      # Verify latest block number updated
      assert {:ok, 1} = Store.get_latest_block_number(store)
    end

    test "returns error on first invalid block", %{store: store} do
      # Block with bad parent hash
      bad_block = %Block{
        header: %BlockHeader{
          parent_hash: <<99::256>>,
          ommers_hash: @empty_ommers_hash,
          coinbase: <<0::160>>,
          state_root: <<0::256>>,
          transactions_root: <<0::256>>,
          receipts_root: <<0::256>>,
          logs_bloom: <<0::2048>>,
          difficulty: 0,
          number: 1,
          gas_limit: 5000,
          gas_used: 0,
          timestamp: 12,
          extra_data: <<>>,
          mix_hash: <<0::256>>,
          nonce: <<0::64>>
        },
        transactions: [],
        ommers: []
      }

      assert {:error, :parent_not_found} =
               BlockPipeline.process_blocks([bad_block], store, evm: EthVm.Mock)
    end
  end
end
