defmodule EthNet.Protocol.Eth68Test do
  use ExUnit.Case, async: true

  alias EthNet.Protocol.Eth68

  # --- Status ---

  test "Status encode/decode roundtrip" do
    genesis = EthNet.Chain.genesis_hash(:mainnet)
    fork_id = EthNet.ForkID.compute(:mainnet, 0, 0)

    params = %{
      network_id: 1,
      total_difficulty: 58_750_000_000_000_000_000_000,
      best_hash: genesis,
      genesis_hash: genesis,
      fork_id: fork_id
    }

    {code, payload} = Eth68.encode_status(params)
    assert code == Eth68.status_code()

    {:ok, decoded} = Eth68.decode_status(payload)
    assert decoded.version == 68
    assert decoded.network_id == 1
    assert decoded.total_difficulty == 58_750_000_000_000_000_000_000
    assert decoded.best_hash == genesis
    assert decoded.genesis_hash == genesis
    assert decoded.fork_id == fork_id
  end

  test "build_mainnet_status produces valid Status" do
    {code, payload} = Eth68.build_mainnet_status()
    assert code == 0x10

    {:ok, decoded} = Eth68.decode_status(payload)
    assert decoded.network_id == 1
    assert decoded.genesis_hash == EthNet.Chain.genesis_hash(:mainnet)
  end

  test "eth_message? identifies eth sub-protocol" do
    assert Eth68.eth_message?(0x10)
    assert Eth68.eth_message?(0x11)
    refute Eth68.eth_message?(0x00)
    refute Eth68.eth_message?(0x0F)
  end

  # --- Message codes ---

  test "message codes have correct values" do
    assert Eth68.status_code() == 0x10
    assert Eth68.new_block_hashes_code() == 0x11
    assert Eth68.transactions_code() == 0x12
    assert Eth68.get_block_headers_code() == 0x13
    assert Eth68.block_headers_code() == 0x14
    assert Eth68.get_block_bodies_code() == 0x15
    assert Eth68.block_bodies_code() == 0x16
    assert Eth68.new_block_code() == 0x17
    assert Eth68.new_pooled_tx_hashes_code() == 0x18
    assert Eth68.get_pooled_transactions_code() == 0x19
    assert Eth68.pooled_transactions_code() == 0x1A
  end

  # --- GetBlockHeaders ---

  test "GetBlockHeaders encode/decode roundtrip with block number origin" do
    {code, payload} = Eth68.encode_get_block_headers(42, 100, 10, 0, false)
    assert code == Eth68.get_block_headers_code()

    {:ok, decoded} = Eth68.decode_get_block_headers(payload)
    assert decoded.request_id == 42
    assert decoded.origin == {:number, 100}
    assert decoded.amount == 10
    assert decoded.skip == 0
    assert decoded.reverse == false
  end

  test "GetBlockHeaders encode/decode roundtrip with hash origin" do
    hash = :crypto.strong_rand_bytes(32)
    {code, payload} = Eth68.encode_get_block_headers(1, hash, 5, 1, true)
    assert code == Eth68.get_block_headers_code()

    {:ok, decoded} = Eth68.decode_get_block_headers(payload)
    assert decoded.request_id == 1
    assert decoded.origin == {:hash, hash}
    assert decoded.amount == 5
    assert decoded.skip == 1
    assert decoded.reverse == true
  end

  test "GetBlockHeaders with reverse=false decodes correctly" do
    {_code, payload} = Eth68.encode_get_block_headers(1, 0, 1, 0, false)
    {:ok, decoded} = Eth68.decode_get_block_headers(payload)
    assert decoded.reverse == false
  end

  # --- BlockHeaders ---

  test "BlockHeaders encode/decode roundtrip" do
    headers = [<<1, 2, 3>>, <<4, 5, 6>>, <<7, 8, 9>>]
    {code, payload} = Eth68.encode_block_headers(42, headers)
    assert code == Eth68.block_headers_code()

    {:ok, decoded} = Eth68.decode_block_headers(payload)
    assert decoded.request_id == 42
    assert decoded.headers == headers
  end

  test "BlockHeaders encode/decode roundtrip with empty headers" do
    {_code, payload} = Eth68.encode_block_headers(1, [])
    {:ok, decoded} = Eth68.decode_block_headers(payload)
    assert decoded.request_id == 1
    assert decoded.headers == []
  end

  # --- GetBlockBodies ---

  test "GetBlockBodies encode/decode roundtrip" do
    hashes = [:crypto.strong_rand_bytes(32), :crypto.strong_rand_bytes(32)]
    {code, payload} = Eth68.encode_get_block_bodies(7, hashes)
    assert code == Eth68.get_block_bodies_code()

    {:ok, decoded} = Eth68.decode_get_block_bodies(payload)
    assert decoded.request_id == 7
    assert decoded.hashes == hashes
  end

  test "GetBlockBodies encode/decode roundtrip with empty hashes" do
    {_code, payload} = Eth68.encode_get_block_bodies(1, [])
    {:ok, decoded} = Eth68.decode_get_block_bodies(payload)
    assert decoded.request_id == 1
    assert decoded.hashes == []
  end

  # --- BlockBodies ---

  test "BlockBodies encode/decode roundtrip" do
    bodies = [<<10, 20>>, <<30, 40>>]
    {code, payload} = Eth68.encode_block_bodies(99, bodies)
    assert code == Eth68.block_bodies_code()

    {:ok, decoded} = Eth68.decode_block_bodies(payload)
    assert decoded.request_id == 99
    assert decoded.bodies == bodies
  end

  test "BlockBodies encode/decode roundtrip with empty bodies" do
    {_code, payload} = Eth68.encode_block_bodies(1, [])
    {:ok, decoded} = Eth68.decode_block_bodies(payload)
    assert decoded.request_id == 1
    assert decoded.bodies == []
  end

  # --- NewBlockHashes ---

  test "NewBlockHashes encode/decode roundtrip" do
    hash1 = :crypto.strong_rand_bytes(32)
    hash2 = :crypto.strong_rand_bytes(32)
    pairs = [{hash1, 100}, {hash2, 200}]

    {code, payload} = Eth68.encode_new_block_hashes(pairs)
    assert code == Eth68.new_block_hashes_code()

    {:ok, decoded} = Eth68.decode_new_block_hashes(payload)
    assert decoded == pairs
  end

  test "NewBlockHashes encode/decode roundtrip with empty list" do
    {_code, payload} = Eth68.encode_new_block_hashes([])
    {:ok, decoded} = Eth68.decode_new_block_hashes(payload)
    assert decoded == []
  end

  # --- NewPooledTransactionHashes (eth/68) ---

  test "NewPooledTransactionHashes encode/decode roundtrip" do
    hash1 = :crypto.strong_rand_bytes(32)
    hash2 = :crypto.strong_rand_bytes(32)
    entries = [{2, 1024, hash1}, {1, 512, hash2}]

    {code, payload} = Eth68.encode_new_pooled_tx_hashes(entries)
    assert code == Eth68.new_pooled_tx_hashes_code()

    {:ok, decoded} = Eth68.decode_new_pooled_tx_hashes(payload)
    assert decoded == entries
  end

  test "NewPooledTransactionHashes encode/decode roundtrip with empty list" do
    {_code, payload} = Eth68.encode_new_pooled_tx_hashes([])
    {:ok, decoded} = Eth68.decode_new_pooled_tx_hashes(payload)
    assert decoded == []
  end

  # --- Decode dispatcher ---

  test "decode dispatcher routes Status correctly" do
    genesis = EthNet.Chain.genesis_hash(:mainnet)
    fork_id = EthNet.ForkID.compute(:mainnet, 0, 0)

    params = %{
      network_id: 1,
      total_difficulty: 0,
      best_hash: genesis,
      genesis_hash: genesis,
      fork_id: fork_id
    }

    {code, payload} = Eth68.encode_status(params)
    {:ok, {:status, msg}} = Eth68.decode(code, payload)
    assert msg.network_id == 1
  end

  test "decode dispatcher routes GetBlockHeaders correctly" do
    {code, payload} = Eth68.encode_get_block_headers(1, 100, 10, 0, false)
    {:ok, {:get_block_headers, msg}} = Eth68.decode(code, payload)
    assert msg.request_id == 1
    assert msg.amount == 10
  end

  test "decode dispatcher routes BlockHeaders correctly" do
    {code, payload} = Eth68.encode_block_headers(1, [<<1, 2, 3>>])
    {:ok, {:block_headers, msg}} = Eth68.decode(code, payload)
    assert msg.request_id == 1
    assert msg.headers == [<<1, 2, 3>>]
  end

  test "decode dispatcher routes GetBlockBodies correctly" do
    hash = :crypto.strong_rand_bytes(32)
    {code, payload} = Eth68.encode_get_block_bodies(5, [hash])
    {:ok, {:get_block_bodies, msg}} = Eth68.decode(code, payload)
    assert msg.request_id == 5
    assert msg.hashes == [hash]
  end

  test "decode dispatcher routes BlockBodies correctly" do
    {code, payload} = Eth68.encode_block_bodies(3, [<<1>>])
    {:ok, {:block_bodies, msg}} = Eth68.decode(code, payload)
    assert msg.request_id == 3
  end

  test "decode dispatcher routes NewBlockHashes correctly" do
    hash = :crypto.strong_rand_bytes(32)
    {code, payload} = Eth68.encode_new_block_hashes([{hash, 42}])
    {:ok, {:new_block_hashes, msg}} = Eth68.decode(code, payload)
    assert msg == [{hash, 42}]
  end

  test "decode dispatcher routes NewPooledTransactionHashes correctly" do
    hash = :crypto.strong_rand_bytes(32)
    {code, payload} = Eth68.encode_new_pooled_tx_hashes([{2, 100, hash}])
    {:ok, {:new_pooled_tx_hashes, msg}} = Eth68.decode(code, payload)
    assert msg == [{2, 100, hash}]
  end

  test "decode dispatcher returns error for unknown code" do
    assert {:error, {:unknown_eth_message, 0xFF}} = Eth68.decode(0xFF, <<>>)
  end
end
