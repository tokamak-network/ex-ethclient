defmodule EthRpcTest do
  use ExUnit.Case
  doctest EthRpc

  test "greets the world" do
    assert EthRpc.hello() == :world
  end
end
