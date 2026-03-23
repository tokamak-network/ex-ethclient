defmodule EthNet.Protocol.Eth70Test do
  use ExUnit.Case, async: true

  alias EthNet.Protocol.Eth70
  alias EthNet.Protocol.Eth68

  # --- Status ---

  describe "Status" do
    test "encode/decode round-trip with version 70" do
      genesis = EthNet.Chain.genesis_hash(:mainnet)
      fork_id = EthNet.ForkID.compute(:mainnet, 0, 0)

      params = %{
        network_id: 1,
        genesis_hash: genesis,
        fork_id: fork_id,
        best_hash: genesis
      }

      {code, payload} = Eth70.encode_status(params)
      assert code == Eth70.status_code()
      assert code == 0x10

      {:ok, decoded} = Eth70.decode_status(payload)
      assert decoded.version == 70
      assert decoded.network_id == 1
      assert decoded.genesis_hash == genesis
      assert decoded.fork_id == fork_id
      assert decoded.best_hash == genesis
      # No totalDifficulty field (same as eth/69)
      refute Map.has_key?(decoded, :total_difficulty)
    end

    test "status with valid fork_id" do
      genesis = EthNet.Chain.genesis_hash(:mainnet)
      fork_id = EthNet.ForkID.compute(:mainnet, 20_000_000, 1_700_000_000)

      params = %{
        network_id: 1,
        genesis_hash: genesis,
        fork_id: fork_id,
        best_hash: :crypto.strong_rand_bytes(32)
      }

      {_code, payload} = Eth70.encode_status(params)
      {:ok, decoded} = Eth70.decode_status(payload)
      assert decoded.version == 70
      assert decoded.fork_id == fork_id
    end

    test "status with different network_id" do
      genesis = :crypto.strong_rand_bytes(32)
      fork_id = {<<0xCA, 0xFE, 0xBA, 0xBE>>, 0}

      params = %{
        network_id: 11_155_111,
        genesis_hash: genesis,
        fork_id: fork_id,
        best_hash: genesis
      }

      {_code, payload} = Eth70.encode_status(params)
      {:ok, decoded} = Eth70.decode_status(payload)
      assert decoded.network_id == 11_155_111
    end
  end

  # --- Delegation to eth/68 ---

  describe "delegation to eth/68" do
    test "message codes match eth/68" do
      assert Eth70.status_code() == Eth68.status_code()
      assert Eth70.new_block_hashes_code() == Eth68.new_block_hashes_code()
      assert Eth70.transactions_code() == Eth68.transactions_code()
      assert Eth70.get_block_headers_code() == Eth68.get_block_headers_code()
      assert Eth70.block_headers_code() == Eth68.block_headers_code()
      assert Eth70.get_block_bodies_code() == Eth68.get_block_bodies_code()
      assert Eth70.block_bodies_code() == Eth68.block_bodies_code()
      assert Eth70.new_block_code() == Eth68.new_block_code()
      assert Eth70.new_pooled_tx_hashes_code() == Eth68.new_pooled_tx_hashes_code()
      assert Eth70.get_pooled_transactions_code() == Eth68.get_pooled_transactions_code()
      assert Eth70.pooled_transactions_code() == Eth68.pooled_transactions_code()
    end

    test "GetBlockHeaders delegates to eth/68" do
      {code, payload} = Eth70.encode_get_block_headers(1, 100, 10, 0, false)
      assert code == Eth68.get_block_headers_code()

      {:ok, decoded} = Eth70.decode_get_block_headers(payload)
      assert decoded.request_id == 1
    end

    test "BlockHeaders delegates to eth/68" do
      {code, payload} = Eth70.encode_block_headers(42, [<<1, 2, 3>>])
      assert code == Eth68.block_headers_code()

      {:ok, decoded} = Eth70.decode_block_headers(payload)
      assert decoded.headers == [<<1, 2, 3>>]
    end

    test "NewBlockHashes delegates to eth/68" do
      hash = :crypto.strong_rand_bytes(32)
      {code, payload} = Eth70.encode_new_block_hashes([{hash, 42}])
      assert code == Eth68.new_block_hashes_code()

      {:ok, decoded} = Eth70.decode_new_block_hashes(payload)
      assert decoded == [{hash, 42}]
    end

    test "eth_message? delegates to eth/68" do
      assert Eth70.eth_message?(0x10)
      refute Eth70.eth_message?(0x00)
    end
  end
end
