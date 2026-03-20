defmodule EthRpc.EthTest do
  use ExUnit.Case, async: true

  alias EthRpc.Eth

  describe "eth_ namespace" do
    test "eth_chainId returns mainnet chain id" do
      assert {:ok, "0x1"} = Eth.handle("eth_chainId", [])
    end

    test "eth_blockNumber returns hex block number" do
      assert {:ok, "0x0"} = Eth.handle("eth_blockNumber", [])
    end

    test "eth_getBalance returns zero balance" do
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

    test "eth_getBlockByNumber returns null" do
      assert {:ok, nil} =
               Eth.handle("eth_getBlockByNumber", ["0x0", true])
    end

    test "eth_getBlockByHash returns null" do
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

    test "eth_sendRawTransaction returns error" do
      assert {:error, -32603, _msg} =
               Eth.handle("eth_sendRawTransaction", ["0x00"])
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
      # keccak256 of empty string
      assert {:ok, hash} = Eth.handle("web3_sha3", ["0x"])
      assert String.starts_with?(hash, "0x")
      # 32 bytes = 64 hex chars + 0x prefix
      assert byte_size(hash) == 66
    end

    test "web3_sha3 with known input" do
      # keccak256("") = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
      assert {:ok, hash} = Eth.handle("web3_sha3", ["0x"])

      assert hash ==
               "0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"
    end

    test "web3_sha3 with invalid params returns error" do
      assert {:error, -32602, _} = Eth.handle("web3_sha3", [])
      assert {:error, -32602, _} = Eth.handle("web3_sha3", ["invalid"])
    end
  end

  describe "unknown method" do
    test "returns method not found error" do
      assert {:error, -32601, _} =
               Eth.handle("eth_doesNotExist", [])
    end
  end
end
