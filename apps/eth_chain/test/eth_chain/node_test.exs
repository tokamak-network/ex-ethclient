defmodule EthChain.NodeTest do
  use ExUnit.Case, async: true

  alias EthChain.Node
  alias EthStorage.{Genesis, Store}

  setup do
    store_name = :"store_#{System.unique_integer([:positive])}"
    {:ok, _pid} = start_supervised({Store, name: store_name})
    %{store: store_name}
  end

  describe "initialize/1" do
    test "stores genesis and returns head info", %{store: store} do
      assert {:ok, head} = Node.initialize(store)
      assert head.head_number == 0
      assert is_binary(head.head_hash)
      assert byte_size(head.head_hash) == 32

      # The hash should be the mainnet genesis hash
      expected_hash = Genesis.mainnet_genesis_hash()
      assert head.head_hash == expected_hash
    end

    test "double initialization is idempotent", %{store: store} do
      assert {:ok, head1} = Node.initialize(store)
      assert {:ok, head2} = Node.initialize(store)
      assert head1 == head2
    end
  end

  describe "chain_head/1" do
    test "returns correct info after genesis initialization", %{store: store} do
      :ok = Genesis.initialize(store)

      assert {:ok, head} = Node.chain_head(store)
      assert head.head_number == 0
      assert head.head_hash == Genesis.mainnet_genesis_hash()
    end

    test "returns defaults for empty store", %{store: store} do
      assert {:ok, head} = Node.chain_head(store)
      assert head.head_number == 0
      assert head.head_hash == <<0::256>>
    end
  end
end
