defmodule EthStorage.BlockStoreTest do
  use ExUnit.Case, async: true

  alias EthCore.Types.{Block, BlockHeader}
  alias EthStorage.{BlockStore, Encoding, Store}

  defp start_store(_context) do
    name = :"test_store_#{System.unique_integer([:positive])}"
    store = start_supervised!({Store, name: name})
    %{store: store}
  end

  defp sample_header(number) do
    %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: <<1::256>>,
      coinbase: <<0::160>>,
      state_root: <<2::256>>,
      transactions_root: <<3::256>>,
      receipts_root: <<4::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 1000,
      number: number,
      gas_limit: 8_000_000,
      gas_used: 500_000,
      timestamp: 1_600_000_000 + number,
      extra_data: <<>>,
      mix_hash: <<5::256>>,
      nonce: <<0, 0, 0, 0, 0, 0, 0, 1>>
    }
  end

  defp sample_block(number \\ 1) do
    %Block{
      header: sample_header(number),
      transactions: [],
      ommers: [],
      withdrawals: nil
    }
  end

  setup [:start_store]

  describe "store_block/2" do
    test "stores and returns block hash", %{store: store} do
      block = sample_block()
      assert {:ok, hash} = BlockStore.store_block(block, store)
      assert byte_size(hash) == 32
      assert hash == Encoding.block_hash(block.header)
    end

    test "block can be retrieved after storing", %{store: store} do
      block = sample_block(10)
      {:ok, hash} = BlockStore.store_block(block, store)

      {:ok, retrieved} = BlockStore.get_block_by_hash(hash, store)
      assert retrieved.header == block.header
    end
  end

  describe "get_header/2" do
    test "returns nil for non-existent hash", %{store: store} do
      assert {:ok, nil} = BlockStore.get_header(<<99::256>>, store)
    end

    test "returns stored header", %{store: store} do
      block = sample_block()
      {:ok, hash} = BlockStore.store_block(block, store)

      assert {:ok, header} = BlockStore.get_header(hash, store)
      assert header == block.header
    end
  end

  describe "get_block_by_number/2" do
    test "returns nil for non-existent number", %{store: store} do
      assert {:ok, nil} = BlockStore.get_block_by_number(999, store)
    end

    test "returns block by number after storing", %{store: store} do
      block = sample_block(5)
      {:ok, _hash} = BlockStore.store_block(block, store)

      assert {:ok, retrieved} = BlockStore.get_block_by_number(5, store)
      assert retrieved.header.number == 5
      assert retrieved.transactions == []
    end
  end

  describe "get_block_by_hash/2" do
    test "returns nil for non-existent hash", %{store: store} do
      assert {:ok, nil} = BlockStore.get_block_by_hash(<<0::256>>, store)
    end

    test "returns full block", %{store: store} do
      block = sample_block(3)
      {:ok, hash} = BlockStore.store_block(block, store)

      assert {:ok, retrieved} = BlockStore.get_block_by_hash(hash, store)
      assert retrieved.header == block.header
      assert retrieved.ommers == []
      assert is_nil(retrieved.withdrawals)
    end
  end

  describe "latest_block_number/1" do
    test "returns nil when no blocks stored", %{store: store} do
      assert {:ok, nil} = BlockStore.latest_block_number(store)
    end

    test "returns latest after setting", %{store: store} do
      Store.set_latest_block_number(store, 42)
      assert {:ok, 42} = BlockStore.latest_block_number(store)
    end
  end

  describe "multiple blocks" do
    test "can store and retrieve multiple blocks", %{store: store} do
      for n <- 0..4 do
        block = sample_block(n)
        {:ok, _hash} = BlockStore.store_block(block, store)
      end

      for n <- 0..4 do
        {:ok, block} = BlockStore.get_block_by_number(n, store)
        assert block.header.number == n
      end
    end
  end
end
