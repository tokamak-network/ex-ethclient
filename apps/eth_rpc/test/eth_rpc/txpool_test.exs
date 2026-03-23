defmodule EthRpc.TxpoolTest do
  use ExUnit.Case, async: false

  alias EthRpc.Eth

  describe "txpool_content (no mempool)" do
    test "returns pending/queued structure" do
      assert {:ok, result} = Eth.handle("txpool_content", [])
      assert Map.has_key?(result, "pending")
      assert Map.has_key?(result, "queued")
      assert result["pending"] == %{}
      assert result["queued"] == %{}
    end
  end

  describe "txpool_status (no mempool)" do
    test "returns hex counts" do
      assert {:ok, result} = Eth.handle("txpool_status", [])
      assert result["pending"] == "0x0"
      assert result["queued"] == "0x0"
    end
  end

  describe "txpool_content (with mempool)" do
    setup do
      # Start mempool with the canonical name so the Txpool module can find it
      {:ok, pid} = EthChain.Mempool.start_link(name: EthChain.Mempool)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      %{pid: pid}
    end

    test "content returns pending/queued with transactions" do
      tx = %EthCore.Types.Transaction.Legacy{
        nonce: 0,
        gas_price: 1_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed_tx = EthCore.Types.SignedTransaction.new(tx, 27, 1, 1)
      {:ok, _hash} = EthChain.Mempool.add_transaction(signed_tx)

      assert {:ok, result} = Eth.handle("txpool_content", [])
      assert is_map(result["pending"])
      assert is_map(result["queued"])
    end

    test "status returns correct counts" do
      tx = %EthCore.Types.Transaction.Legacy{
        nonce: 0,
        gas_price: 1_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed_tx = EthCore.Types.SignedTransaction.new(tx, 27, 1, 1)
      {:ok, _hash} = EthChain.Mempool.add_transaction(signed_tx)

      assert {:ok, result} = Eth.handle("txpool_status", [])
      assert result["pending"] == "0x1"
      assert result["queued"] == "0x0"
    end
  end
end
