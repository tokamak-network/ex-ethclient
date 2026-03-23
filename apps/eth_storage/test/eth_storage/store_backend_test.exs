defmodule EthStorage.StoreBackendTest do
  @moduledoc """
  Tests the Store GenServer with configurable backends.

  Verifies that Store correctly reads backend configuration from opts
  and dispatches operations to the configured backend module.
  """

  use ExUnit.Case, async: false

  alias EthStorage.Store

  describe "Store with Memory backend (explicit)" do
    setup do
      name = :"store_mem_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        Store.start_link(
          name: name,
          backend: EthStorage.Backend.Memory,
          backend_opts: []
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      %{store: name}
    end

    test "put and get block header", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      assert :ok = Store.put_block_header(store, hash, "header_data")
      assert {:ok, "header_data"} = Store.get_block_header(store, hash)
    end

    test "returns nil for missing key", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      assert {:ok, nil} = Store.get_block_header(store, hash)
    end

    test "set and get latest block number", %{store: store} do
      assert :ok = Store.set_latest_block_number(store, 42)
      assert {:ok, 42} = Store.get_latest_block_number(store)
    end

    test "get_block_by_number round-trip", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      :ok = Store.set_canonical_hash(store, 0, hash)
      :ok = Store.put_block_header(store, hash, "hdr")
      :ok = Store.put_block_body(store, hash, "bdy")
      assert {:ok, {"hdr", "bdy"}} = Store.get_block_by_number(store, 0)
    end
  end

  describe "Store with DETS backend (explicit)" do
    setup do
      dir =
        Path.join(
          System.tmp_dir!(),
          "store_backend_dets_#{:erlang.unique_integer([:positive])}"
        )

      name = :"store_dets_back_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        Store.start_link(
          name: name,
          backend: EthStorage.Backend.DETS,
          backend_opts: [datadir: dir]
        )

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
        File.rm_rf!(dir)
      end)

      %{store: name}
    end

    test "put and get block header", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      assert :ok = Store.put_block_header(store, hash, "header_data")
      assert {:ok, "header_data"} = Store.get_block_header(store, hash)
    end

    test "returns nil for missing key", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      assert {:ok, nil} = Store.get_block_header(store, hash)
    end

    test "set and get latest block number", %{store: store} do
      assert :ok = Store.set_latest_block_number(store, 99)
      assert {:ok, 99} = Store.get_latest_block_number(store)
    end

    test "get_block_by_number round-trip", %{store: store} do
      hash = :crypto.strong_rand_bytes(32)
      :ok = Store.set_canonical_hash(store, 5, hash)
      :ok = Store.put_block_header(store, hash, "hdr5")
      :ok = Store.put_block_body(store, hash, "bdy5")
      assert {:ok, {"hdr5", "bdy5"}} = Store.get_block_by_number(store, 5)
    end
  end

  describe "Store respects application config defaults" do
    test "defaults to Memory backend from app config" do
      name = :"store_default_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Store.start_link(name: name)

      hash = :crypto.strong_rand_bytes(32)
      assert :ok = Store.put_block_header(name, hash, "default_backend_header")
      assert {:ok, "default_backend_header"} = Store.get_block_header(name, hash)

      GenServer.stop(pid)
    end
  end

  describe "Store backward compatibility" do
    test "accepts datadir at top level for DETS backend" do
      dir =
        Path.join(
          System.tmp_dir!(),
          "store_compat_#{:erlang.unique_integer([:positive])}"
        )

      name = :"store_compat_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        Store.start_link(
          name: name,
          backend: EthStorage.Backend.DETS,
          datadir: dir
        )

      hash = :crypto.strong_rand_bytes(32)
      assert :ok = Store.put_block_header(name, hash, "compat_header")
      assert {:ok, "compat_header"} = Store.get_block_header(name, hash)

      GenServer.stop(pid)
      File.rm_rf!(dir)
    end
  end
end
