defmodule EthStorage.GenesisTest do
  use ExUnit.Case, async: true

  alias EthStorage.{BlockStore, Genesis, Store}

  defp start_store(_context) do
    name = :"test_store_#{System.unique_integer([:positive])}"
    store = start_supervised!({Store, name: name})
    %{store: store}
  end

  describe "mainnet_header/0" do
    test "returns a valid block header with correct genesis values" do
      header = Genesis.mainnet_header()

      assert header.parent_hash == <<0::256>>
      assert header.coinbase == <<0::160>>
      assert header.difficulty == 17_179_869_184
      assert header.number == 0
      assert header.gas_limit == 5000
      assert header.gas_used == 0
      assert header.timestamp == 0
      assert header.mix_hash == <<0::256>>
      assert header.nonce == <<0, 0, 0, 0, 0, 0, 0, 0x42>>
      assert byte_size(header.logs_bloom) == 256
      assert header.logs_bloom == <<0::2048>>
    end

    test "ommers_hash matches keccak256(RLP([]))" do
      header = Genesis.mainnet_header()

      expected =
        Base.decode16!(
          "1DCC4DE8DEC75D7AAB85B567B6CCD41AD312451B948A7413F0A142FD40D49347",
          case: :upper
        )

      assert header.ommers_hash == expected
    end

    test "transactions_root and receipts_root are empty trie root" do
      header = Genesis.mainnet_header()

      empty_trie =
        Base.decode16!(
          "56E81F171BCC55A6FF8345E692C0F86E5B48E01B996CADC001622FB5E363B421",
          case: :upper
        )

      assert header.transactions_root == empty_trie
      assert header.receipts_root == empty_trie
    end

    test "state_root matches known mainnet value" do
      header = Genesis.mainnet_header()

      expected =
        Base.decode16!(
          "D7F8974FB5AC78D9AC099B9AD5018BEDC2CE0A72DAD1827A1709DA30580F0544",
          case: :upper
        )

      assert header.state_root == expected
    end

    test "extra_data is 32 bytes" do
      header = Genesis.mainnet_header()
      assert byte_size(header.extra_data) == 32
    end

    test "optional fields are nil for pre-merge genesis" do
      header = Genesis.mainnet_header()

      assert is_nil(header.base_fee_per_gas)
      assert is_nil(header.withdrawals_root)
      assert is_nil(header.blob_gas_used)
      assert is_nil(header.excess_blob_gas)
      assert is_nil(header.parent_beacon_block_root)
      assert is_nil(header.requests_hash)
    end
  end

  describe "mainnet_block/0" do
    test "returns block with genesis header and empty body" do
      block = Genesis.mainnet_block()

      assert block.header == Genesis.mainnet_header()
      assert block.transactions == []
      assert block.ommers == []
      assert is_nil(block.withdrawals)
    end
  end

  describe "mainnet_genesis_hash/0" do
    test "matches the well-known mainnet genesis hash" do
      expected =
        Base.decode16!(
          "D4E56740F876AEF8C010B86A40D5F56745A118D0906A34E69AEC8C0DB1CB8FA3",
          case: :upper
        )

      assert Genesis.mainnet_genesis_hash() == expected
    end

    test "is deterministic" do
      assert Genesis.mainnet_genesis_hash() == Genesis.mainnet_genesis_hash()
    end
  end

  describe "initialize/1" do
    setup [:start_store]

    test "stores genesis block in store", %{store: store} do
      assert :ok = Genesis.initialize(store)

      {:ok, 0} = Store.get_latest_block_number(store)
      {:ok, hash} = Store.get_canonical_hash(store, 0)
      assert hash == Genesis.mainnet_genesis_hash()

      {:ok, encoded_header} = Store.get_block_header(store, hash)
      assert is_binary(encoded_header)

      {:ok, encoded_body} = Store.get_block_body(store, hash)
      assert is_binary(encoded_body)
    end

    test "stored block can be retrieved via BlockStore", %{store: store} do
      :ok = Genesis.initialize(store)

      {:ok, block} = BlockStore.get_block_by_number(0, store)
      assert block.header == Genesis.mainnet_header()
      assert block.transactions == []
      assert block.ommers == []
    end

    test "stored block can be retrieved by hash", %{store: store} do
      :ok = Genesis.initialize(store)

      hash = Genesis.mainnet_genesis_hash()
      {:ok, block} = BlockStore.get_block_by_hash(hash, store)
      assert block.header.number == 0
      assert block.header.difficulty == 17_179_869_184
    end
  end
end
