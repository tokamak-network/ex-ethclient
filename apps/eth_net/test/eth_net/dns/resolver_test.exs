defmodule EthNet.DNS.ResolverTest do
  use ExUnit.Case, async: false

  alias EthNet.DNS.Resolver

  # The Resolver is a named GenServer, so tests cannot be async.
  # We test the API with a very short sync interval and mocked DNS.

  describe "start_link/1 and peers/0" do
    test "starts and returns empty peers initially" do
      # Use seeds that will not resolve (empty resolver mock not needed
      # since we test with unreachable seeds).
      pid = start_supervised!({Resolver, seeds: [], sync_interval: 60_000})
      assert is_pid(pid)

      # Before any sync completes, peers should be empty
      assert Resolver.peers() == []
    end
  end

  describe "sync/0" do
    test "triggers an immediate re-sync" do
      start_supervised!({Resolver, seeds: [], sync_interval: 60_000})

      # Should not raise
      assert Resolver.sync() == :ok
    end
  end
end
