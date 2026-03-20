defmodule EthChain.MempoolTest do
  use ExUnit.Case, async: true

  alias EthChain.Mempool
  alias EthCore.Types.{Block, BlockHeader, SignedTransaction, Transaction}

  setup do
    name = :"mempool_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Mempool.start_link(name: name)
    %{mempool: name, pid: pid}
  end

  defp make_tx(gas_price, nonce \\ 0) do
    tx = %Transaction.Legacy{
      nonce: nonce,
      gas_price: gas_price,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, nonce + 1, gas_price + 1)
  end

  @empty_ommers_hash EthCrypto.Hash.keccak256(ExRLP.encode([]))

  defp make_block(txs) do
    header = %BlockHeader{
      parent_hash: <<0::256>>,
      ommers_hash: @empty_ommers_hash,
      coinbase: <<0::160>>,
      state_root: <<0::256>>,
      transactions_root: <<0::256>>,
      receipts_root: <<0::256>>,
      logs_bloom: <<0::2048>>,
      difficulty: 0,
      number: 1,
      gas_limit: 30_000_000,
      gas_used: 0,
      timestamp: 1_000_000,
      extra_data: <<>>,
      mix_hash: <<0::256>>,
      nonce: <<0::64>>
    }

    %Block{header: header, transactions: txs, ommers: []}
  end

  describe "add_transaction/2" do
    test "adds a transaction and returns its hash", %{mempool: m} do
      tx = make_tx(100)
      assert {:ok, tx_hash} = Mempool.add_transaction(tx, m)
      assert is_binary(tx_hash)
      assert byte_size(tx_hash) == 32
    end

    test "rejects duplicate transaction", %{mempool: m} do
      tx = make_tx(100)
      assert {:ok, _} = Mempool.add_transaction(tx, m)
      assert {:error, :already_exists} = Mempool.add_transaction(tx, m)
    end
  end

  describe "remove_transaction/2" do
    test "removes an existing transaction", %{mempool: m} do
      tx = make_tx(100)
      {:ok, tx_hash} = Mempool.add_transaction(tx, m)
      assert :ok = Mempool.remove_transaction(tx_hash, m)
      assert Mempool.size(m) == 0
    end

    test "removing non-existent hash is a no-op", %{mempool: m} do
      assert :ok = Mempool.remove_transaction(<<0::256>>, m)
    end
  end

  describe "pending_transactions/1" do
    test "returns empty list when pool is empty", %{mempool: m} do
      assert Mempool.pending_transactions(m) == []
    end

    test "returns transactions sorted by gas price descending", %{mempool: m} do
      tx_low = make_tx(10, 0)
      tx_mid = make_tx(50, 1)
      tx_high = make_tx(100, 2)

      Mempool.add_transaction(tx_low, m)
      Mempool.add_transaction(tx_high, m)
      Mempool.add_transaction(tx_mid, m)

      pending = Mempool.pending_transactions(m)
      prices = Enum.map(pending, fn %SignedTransaction{tx: tx} -> tx.gas_price end)
      assert prices == [100, 50, 10]
    end
  end

  describe "remove_block_transactions/2" do
    test "removes transactions included in block", %{mempool: m} do
      tx1 = make_tx(100, 0)
      tx2 = make_tx(200, 1)
      tx3 = make_tx(300, 2)

      Mempool.add_transaction(tx1, m)
      Mempool.add_transaction(tx2, m)
      Mempool.add_transaction(tx3, m)

      assert Mempool.size(m) == 3

      block = make_block([tx1, tx3])
      Mempool.remove_block_transactions(block, m)

      assert Mempool.size(m) == 1
      [remaining] = Mempool.pending_transactions(m)
      assert remaining.tx.gas_price == 200
    end
  end

  describe "size/1" do
    test "returns 0 for empty pool", %{mempool: m} do
      assert Mempool.size(m) == 0
    end

    test "returns correct count after adds and removes", %{mempool: m} do
      tx1 = make_tx(100, 0)
      tx2 = make_tx(200, 1)

      {:ok, hash1} = Mempool.add_transaction(tx1, m)
      Mempool.add_transaction(tx2, m)
      assert Mempool.size(m) == 2

      Mempool.remove_transaction(hash1, m)
      assert Mempool.size(m) == 1
    end
  end
end
