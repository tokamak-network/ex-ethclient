defmodule EthChain.TxPipelineTest do
  use ExUnit.Case, async: true

  alias EthChain.{Mempool, TxPipeline}
  alias EthCore.Types.{SignedTransaction, Transaction}

  setup do
    mempool_name = :"mempool_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({Mempool, name: mempool_name})
    %{mempool: mempool_name}
  end

  defp make_signed_tx(nonce \\ 0) do
    tx = %Transaction.Legacy{
      nonce: nonce,
      gas_price: 2_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }

    SignedTransaction.new(tx, 27, nonce + 1, nonce + 2)
  end

  defp encode_signed_tx(signed_tx) do
    EthCore.RLP.encode_signed(signed_tx)
  end

  describe "submit_transaction/2" do
    test "submits a valid raw transaction", %{mempool: mempool} do
      signed_tx = make_signed_tx()
      raw = encode_signed_tx(signed_tx)

      assert {:ok, tx_hash} = TxPipeline.submit_transaction(raw, mempool: mempool)
      assert is_binary(tx_hash)
      assert byte_size(tx_hash) == 32
      assert Mempool.size(mempool) == 1
    end

    test "rejects invalid RLP data", %{mempool: mempool} do
      assert {:error, _reason} =
               TxPipeline.submit_transaction(<<>>, mempool: mempool)
    end

    test "rejects garbage bytes", %{mempool: mempool} do
      assert {:error, _reason} =
               TxPipeline.submit_transaction(<<0x80>>, mempool: mempool)
    end
  end

  describe "process_peer_transactions/2" do
    test "adds valid transactions to mempool", %{mempool: mempool} do
      tx1 = make_signed_tx(0)
      tx2 = make_signed_tx(1)

      :ok = TxPipeline.process_peer_transactions([tx1, tx2], mempool: mempool)
      assert Mempool.size(mempool) == 2
    end

    test "silently drops duplicate transactions", %{mempool: mempool} do
      tx = make_signed_tx(0)

      :ok = TxPipeline.process_peer_transactions([tx, tx], mempool: mempool)
      assert Mempool.size(mempool) == 1
    end
  end
end
