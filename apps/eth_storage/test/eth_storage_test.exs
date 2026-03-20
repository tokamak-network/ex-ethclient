defmodule EthStorageTest do
  use ExUnit.Case

  test "store_name returns the default store module" do
    assert EthStorage.store_name() == EthStorage.Store
  end
end
