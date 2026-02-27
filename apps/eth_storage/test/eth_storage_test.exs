defmodule EthStorageTest do
  use ExUnit.Case
  doctest EthStorage

  test "greets the world" do
    assert EthStorage.hello() == :world
  end
end
