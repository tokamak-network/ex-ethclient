defmodule EthNet.Protocol.Eth69Test do
  use ExUnit.Case, async: true

  alias EthNet.Protocol.Eth69
  alias EthNet.Protocol.Eth68

  # --- Status ---

  describe "Status" do
    test "encode/decode round-trip (no totalDifficulty)" do
      genesis = EthNet.Chain.genesis_hash(:mainnet)
      fork_id = EthNet.ForkID.compute(:mainnet, 0, 0)

      params = %{
        network_id: 1,
        genesis_hash: genesis,
        fork_id: fork_id,
        best_hash: genesis
      }

      {code, payload} = Eth69.encode_status(params)
      assert code == Eth69.status_code()
      assert code == 0x10

      {:ok, decoded} = Eth69.decode_status(payload)
      assert decoded.version == 69
      assert decoded.network_id == 1
      assert decoded.genesis_hash == genesis
      assert decoded.fork_id == fork_id
      assert decoded.best_hash == genesis
      # No totalDifficulty field
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

      {_code, payload} = Eth69.encode_status(params)
      {:ok, decoded} = Eth69.decode_status(payload)
      assert decoded.fork_id == fork_id
    end

    test "status with different network_id" do
      genesis = :crypto.strong_rand_bytes(32)
      fork_id = {<<0xDE, 0xAD, 0xBE, 0xEF>>, 0}

      params = %{
        network_id: 5,
        genesis_hash: genesis,
        fork_id: fork_id,
        best_hash: genesis
      }

      {_code, payload} = Eth69.encode_status(params)
      {:ok, decoded} = Eth69.decode_status(payload)
      assert decoded.network_id == 5
    end
  end

  # --- Message code delegation ---

  describe "message code delegation" do
    test "message codes match eth/68" do
      assert Eth69.status_code() == Eth68.status_code()
      assert Eth69.new_block_hashes_code() == Eth68.new_block_hashes_code()
      assert Eth69.transactions_code() == Eth68.transactions_code()
      assert Eth69.get_block_headers_code() == Eth68.get_block_headers_code()
      assert Eth69.block_headers_code() == Eth68.block_headers_code()
      assert Eth69.get_block_bodies_code() == Eth68.get_block_bodies_code()
      assert Eth69.block_bodies_code() == Eth68.block_bodies_code()
      assert Eth69.new_block_code() == Eth68.new_block_code()
      assert Eth69.new_pooled_tx_hashes_code() == Eth68.new_pooled_tx_hashes_code()
      assert Eth69.get_pooled_transactions_code() == Eth68.get_pooled_transactions_code()
      assert Eth69.pooled_transactions_code() == Eth68.pooled_transactions_code()
    end
  end

  # --- Delegated message round-trips ---

  describe "delegated messages" do
    test "GetBlockHeaders delegates to eth/68" do
      {code, payload} = Eth69.encode_get_block_headers(1, 100, 10, 0, false)
      assert code == Eth68.get_block_headers_code()

      {:ok, decoded} = Eth69.decode_get_block_headers(payload)
      assert decoded.request_id == 1
      assert decoded.amount == 10
    end

    test "BlockHeaders delegates to eth/68" do
      headers = [<<1, 2, 3>>]
      {code, payload} = Eth69.encode_block_headers(42, headers)
      assert code == Eth68.block_headers_code()

      {:ok, decoded} = Eth69.decode_block_headers(payload)
      assert decoded.headers == headers
    end

    test "GetBlockBodies delegates to eth/68" do
      hash = :crypto.strong_rand_bytes(32)
      {code, payload} = Eth69.encode_get_block_bodies(5, [hash])
      assert code == Eth68.get_block_bodies_code()

      {:ok, decoded} = Eth69.decode_get_block_bodies(payload)
      assert decoded.hashes == [hash]
    end

    test "BlockBodies delegates to eth/68" do
      {code, payload} = Eth69.encode_block_bodies(3, [<<1>>])
      assert code == Eth68.block_bodies_code()

      {:ok, decoded} = Eth69.decode_block_bodies(payload)
      assert decoded.request_id == 3
    end

    test "NewBlockHashes delegates to eth/68" do
      hash = :crypto.strong_rand_bytes(32)
      {code, payload} = Eth69.encode_new_block_hashes([{hash, 42}])
      assert code == Eth68.new_block_hashes_code()

      {:ok, decoded} = Eth69.decode_new_block_hashes(payload)
      assert decoded == [{hash, 42}]
    end

    test "Transactions delegates to eth/68" do
      {code, payload} = Eth69.encode_transactions([<<0xAB>>])
      assert code == Eth68.transactions_code()

      {:ok, decoded} = Eth69.decode_transactions(payload)
      assert decoded == [<<0xAB>>]
    end

    test "NewPooledTransactionHashes delegates to eth/68" do
      hash = :crypto.strong_rand_bytes(32)
      {code, payload} = Eth69.encode_new_pooled_tx_hashes([{2, 100, hash}])
      assert code == Eth68.new_pooled_tx_hashes_code()

      {:ok, decoded} = Eth69.decode_new_pooled_tx_hashes(payload)
      assert decoded == [{2, 100, hash}]
    end

    test "GetPooledTransactions delegates to eth/68" do
      hash = :crypto.strong_rand_bytes(32)
      {code, payload} = Eth69.encode_get_pooled_transactions(10, [hash])
      assert code == Eth68.get_pooled_transactions_code()

      {:ok, decoded} = Eth69.decode_get_pooled_transactions(payload)
      assert decoded.hashes == [hash]
    end

    test "PooledTransactions delegates to eth/68" do
      {code, payload} = Eth69.encode_pooled_transactions(11, [<<0xFF>>])
      assert code == Eth68.pooled_transactions_code()

      {:ok, decoded} = Eth69.decode_pooled_transactions(payload)
      assert decoded.transactions == [<<0xFF>>]
    end

    test "eth_message? delegates to eth/68" do
      assert Eth69.eth_message?(0x10)
      assert Eth69.eth_message?(0x1A)
      refute Eth69.eth_message?(0x00)
    end
  end
end
