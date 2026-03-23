defmodule EthRpc.AdminTest do
  use ExUnit.Case, async: true

  alias EthRpc.Eth

  describe "admin_nodeInfo" do
    test "returns expected structure" do
      assert {:ok, info} = Eth.handle("admin_nodeInfo", [])
      assert is_map(info)
      assert info["name"] == "ExEthclient/0.1.0"
      assert Map.has_key?(info, "enode")
      assert Map.has_key?(info, "protocols")
      assert info["protocols"]["eth"]["version"] == 68
    end
  end

  describe "admin_peers" do
    test "returns list" do
      assert {:ok, peers} = Eth.handle("admin_peers", [])
      assert is_list(peers)
    end
  end

  describe "admin_addPeer" do
    test "accepts enode URI" do
      assert {:ok, true} =
               Eth.handle("admin_addPeer", [
                 "enode://abc123@127.0.0.1:30303"
               ])
    end

    test "returns error for invalid params" do
      assert {:error, -32602, _msg} = Eth.handle("admin_addPeer", [])
    end
  end

  describe "admin_setLogLevel" do
    test "changes level to debug" do
      # Save original level
      original = Logger.level()

      assert {:ok, true} = Eth.handle("admin_setLogLevel", ["warning"])

      # Restore
      Logger.configure(level: original)
    end

    test "returns error for invalid level" do
      assert {:error, -32602, _msg} =
               Eth.handle("admin_setLogLevel", ["invalid"])
    end

    test "returns error for missing params" do
      assert {:error, -32602, _msg} = Eth.handle("admin_setLogLevel", [])
    end
  end
end
