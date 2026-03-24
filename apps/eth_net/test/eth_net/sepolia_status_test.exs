defmodule EthNet.SepoliaStatusTest do
  use ExUnit.Case, async: true

  alias EthNet.Protocol.Eth68
  alias EthNet.Chain

  describe "build_status/1 for Sepolia" do
    test "builds a valid Status message" do
      {code, payload} = Eth68.build_status(:sepolia)

      # Status code is 0x10
      assert code == Eth68.status_code()

      # Decode and verify fields
      {:ok, status} = Eth68.decode_status(payload)
      assert status.network_id == 11_155_111
      assert status.genesis_hash == Chain.genesis_hash(:sepolia)
      assert status.total_difficulty == Chain.terminal_td(:sepolia)
    end

    test "uses Sepolia genesis hash, not mainnet" do
      {_code, payload} = Eth68.build_status(:sepolia)
      {:ok, status} = Eth68.decode_status(payload)

      refute status.genesis_hash == Chain.genesis_hash(:mainnet)
      assert status.genesis_hash == Chain.genesis_hash(:sepolia)
    end

    test "uses Sepolia network_id, not mainnet" do
      {_code, payload} = Eth68.build_status(:sepolia)
      {:ok, status} = Eth68.decode_status(payload)

      refute status.network_id == Chain.network_id(:mainnet)
      assert status.network_id == Chain.network_id(:sepolia)
    end

    test "includes a valid fork_id" do
      {_code, payload} = Eth68.build_status(:sepolia)
      {:ok, status} = Eth68.decode_status(payload)

      {fork_hash, fork_next} = status.fork_id
      assert byte_size(fork_hash) == 4
      assert is_integer(fork_next)
    end
  end

  describe "build_status/1 for mainnet" do
    test "builds a valid mainnet Status message" do
      {_code, payload} = Eth68.build_status(:mainnet)
      {:ok, status} = Eth68.decode_status(payload)

      assert status.network_id == 1
      assert status.genesis_hash == Chain.genesis_hash(:mainnet)
    end
  end

  describe "build_mainnet_status/0 backwards compatibility" do
    test "produces same result as build_status(:mainnet)" do
      {code1, payload1} = Eth68.build_mainnet_status()
      {code2, payload2} = Eth68.build_status(:mainnet)

      assert code1 == code2
      assert payload1 == payload2
    end
  end
end
