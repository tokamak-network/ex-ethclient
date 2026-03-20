defmodule EthStorage.StoreDETSTest do
  use ExUnit.Case, async: true

  alias EthStorage.Store
  alias EthStorage.Backend.DETS

  setup do
    dir = Path.join(System.tmp_dir!(), "store_dets_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, datadir: dir}
  end

  describe "Store with DETS backend" do
    test "starts and stores block header", %{datadir: dir} do
      name = :"store_dets_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Store.start_link(
          name: name,
          backend: DETS,
          datadir: dir
        )

      hash = :crypto.strong_rand_bytes(32)
      header = "rlp_encoded_header"

      assert :ok = Store.put_block_header(name, hash, header)
      assert {:ok, ^header} = Store.get_block_header(name, hash)

      GenServer.stop(pid)
    end

    test "stores and retrieves block by number", %{datadir: dir} do
      name = :"store_dets_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Store.start_link(
          name: name,
          backend: DETS,
          datadir: dir
        )

      hash = :crypto.strong_rand_bytes(32)
      header = "genesis_header"
      body = "genesis_body"

      :ok = Store.set_canonical_hash(name, 0, hash)
      :ok = Store.put_block_header(name, hash, header)
      :ok = Store.put_block_body(name, hash, body)

      assert {:ok, {^header, ^body}} = Store.get_block_by_number(name, 0)

      GenServer.stop(pid)
    end

    test "data persists after restart", %{datadir: dir} do
      name1 = :"store_dets_#{System.unique_integer([:positive])}"

      {:ok, pid1} =
        Store.start_link(
          name: name1,
          backend: DETS,
          datadir: dir
        )

      hash = :crypto.strong_rand_bytes(32)
      :ok = Store.put_block_header(name1, hash, "my_header")
      :ok = Store.set_latest_block_number(name1, 42)

      GenServer.stop(pid1)

      # Restart with a new name but same datadir
      name2 = :"store_dets_#{System.unique_integer([:positive])}"

      {:ok, pid2} =
        Store.start_link(
          name: name2,
          backend: DETS,
          datadir: dir
        )

      assert {:ok, "my_header"} = Store.get_block_header(name2, hash)
      assert {:ok, 42} = Store.get_latest_block_number(name2)

      GenServer.stop(pid2)
    end

    test "stores genesis block and retrieves it", %{datadir: dir} do
      name = :"store_dets_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Store.start_link(
          name: name,
          backend: DETS,
          datadir: dir
        )

      genesis_hash = :crypto.strong_rand_bytes(32)
      genesis_header = "genesis_header_rlp"
      genesis_body = "genesis_body_rlp"

      :ok = Store.set_canonical_hash(name, 0, genesis_hash)
      :ok = Store.put_block_header(name, genesis_hash, genesis_header)
      :ok = Store.put_block_body(name, genesis_hash, genesis_body)
      :ok = Store.set_latest_block_number(name, 0)

      assert {:ok, {^genesis_header, ^genesis_body}} =
               Store.get_block_by_number(name, 0)

      assert {:ok, 0} = Store.get_latest_block_number(name)

      GenServer.stop(pid)
    end
  end
end
