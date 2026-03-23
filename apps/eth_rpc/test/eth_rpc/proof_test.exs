defmodule EthRpc.ProofTest do
  use ExUnit.Case, async: false

  alias EthRpc.Eth
  alias EthRpc.TestStore

  defp start_test_store do
    name = :"test_proof_store_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = TestStore.start_link(name: name)
    {pid, name}
  end

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

  describe "eth_getStorageAt" do
    test "returns stored value", %{store_name: name} do
      address = <<1::160>>
      slot = <<0::256>>
      value = <<42::256>>

      # Store using the same key derivation as eth_get_storage_at
      key = EthCrypto.Hash.keccak256(address <> slot)
      :ok = TestStore.put_storage_trie_node(name, key, value)

      addr_hex = "0x" <> String.duplicate("0", 38) <> "01"
      slot_hex = "0x" <> String.duplicate("0", 64)

      assert {:ok, result} = Eth.handle("eth_getStorageAt", [addr_hex, slot_hex, "latest"])
      # value is 42 = 0x2a, padded to 32 bytes
      assert result == "0x" <> String.duplicate("0", 62) <> "2a"
    end

    test "returns zero for missing storage slot" do
      addr_hex = "0x" <> String.duplicate("0", 40)
      slot_hex = "0x" <> String.duplicate("0", 64)

      assert {:ok, result} = Eth.handle("eth_getStorageAt", [addr_hex, slot_hex, "latest"])
      assert result == "0x" <> String.duplicate("0", 64)
    end
  end

  describe "eth_getProof" do
    test "returns valid proof structure for unknown account" do
      addr_hex = "0x" <> String.duplicate("0", 40)
      storage_keys = []

      assert {:ok, result} = Eth.handle("eth_getProof", [addr_hex, storage_keys, "latest"])
      assert is_map(result)
      assert result["address"] == addr_hex
      assert result["balance"] == "0x0"
      assert result["nonce"] == "0x0"
      assert is_binary(result["codeHash"])
      assert is_binary(result["storageHash"])
      assert is_list(result["accountProof"])
      assert is_list(result["storageProof"])
    end

    test "returns proof with stored account", %{store_name: name} do
      address = <<1::160>>

      account = %EthCore.Types.Account{
        nonce: 5,
        balance: 1000,
        storage_root: EthCore.Types.Account.empty_trie_root(),
        code_hash: EthCore.Types.Account.empty_code_hash()
      }

      :ok = TestStore.put_account(name, address, :erlang.term_to_binary(account))

      addr_hex = "0x" <> String.duplicate("0", 38) <> "01"

      assert {:ok, result} =
               Eth.handle("eth_getProof", [addr_hex, ["0x0"], "latest"])

      assert result["balance"] == "0x3e8"
      assert result["nonce"] == "0x5"
      assert length(result["storageProof"]) == 1

      [sp] = result["storageProof"]
      assert sp["key"] == "0x0"
      assert is_binary(sp["value"])
      assert is_list(sp["proof"])
    end

    test "returns error for invalid params" do
      assert {:error, -32602, _} = Eth.handle("eth_getProof", [])
    end
  end
end
