defmodule EthStorage.Backend.RocksDBTest do
  use ExUnit.Case, async: false

  @moduletag :rocksdb

  alias EthStorage.Backend.RocksDB

  @test_dir System.tmp_dir!() |> Path.join("rocksdb_test")

  setup do
    # Use a unique subdirectory per test to avoid conflicts
    dir = Path.join(@test_dir, "#{System.unique_integer([:positive])}")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)

    {:ok, state} = RocksDB.init(datadir: dir)

    on_exit(fn ->
      RocksDB.close(state)
      File.rm_rf!(dir)
    end)

    %{state: state, dir: dir}
  end

  describe "init/1" do
    test "opens a database and returns state", %{state: state} do
      assert %{db: _db, dir: _dir} = state
    end
  end

  describe "get/3" do
    test "returns nil for missing key", %{state: state} do
      assert {:ok, nil} = RocksDB.get(state, :headers, "missing")
    end

    test "returns error for unknown table", %{state: state} do
      assert {:error, :unknown_table} = RocksDB.get(state, :nonexistent, "key")
    end
  end

  describe "put/4" do
    test "stores and retrieves a value", %{state: state} do
      {:ok, state} = RocksDB.put(state, :headers, "key1", "value1")
      assert {:ok, "value1"} = RocksDB.get(state, :headers, "key1")
    end

    test "overwrites existing value", %{state: state} do
      {:ok, state} = RocksDB.put(state, :headers, "key1", "value1")
      {:ok, state} = RocksDB.put(state, :headers, "key1", "value2")
      assert {:ok, "value2"} = RocksDB.get(state, :headers, "key1")
    end

    test "returns error for unknown table", %{state: state} do
      assert {:error, :unknown_table} = RocksDB.put(state, :nonexistent, "key", "val")
    end
  end

  describe "delete/3" do
    test "removes an existing key", %{state: state} do
      {:ok, state} = RocksDB.put(state, :headers, "key1", "value1")
      {:ok, state} = RocksDB.delete(state, :headers, "key1")
      assert {:ok, nil} = RocksDB.get(state, :headers, "key1")
    end

    test "no-op for missing key", %{state: state} do
      assert {:ok, _state} = RocksDB.delete(state, :headers, "missing")
    end

    test "returns error for unknown table", %{state: state} do
      assert {:error, :unknown_table} = RocksDB.delete(state, :nonexistent, "key")
    end
  end

  describe "batch_put/2" do
    test "inserts multiple entries across tables", %{state: state} do
      entries = [
        {:headers, "h1", "header1"},
        {:bodies, "b1", "body1"},
        {:headers, "h2", "header2"}
      ]

      {:ok, state} = RocksDB.batch_put(state, entries)

      assert {:ok, "header1"} = RocksDB.get(state, :headers, "h1")
      assert {:ok, "body1"} = RocksDB.get(state, :bodies, "b1")
      assert {:ok, "header2"} = RocksDB.get(state, :headers, "h2")
    end

    test "returns error if any table is unknown", %{state: state} do
      entries = [
        {:headers, "h1", "header1"},
        {:nonexistent, "x", "bad"}
      ]

      assert {:error, :unknown_table} = RocksDB.batch_put(state, entries)
    end
  end

  describe "column family isolation" do
    test "data in one table is not visible in another", %{state: state} do
      {:ok, state} = RocksDB.put(state, :headers, "key1", "header_data")
      assert {:ok, nil} = RocksDB.get(state, :bodies, "key1")
    end

    test "same key can hold different values in different tables", %{state: state} do
      {:ok, state} = RocksDB.put(state, :headers, "key", "header_value")
      {:ok, state} = RocksDB.put(state, :bodies, "key", "body_value")
      assert {:ok, "header_value"} = RocksDB.get(state, :headers, "key")
      assert {:ok, "body_value"} = RocksDB.get(state, :bodies, "key")
    end
  end

  describe "persistence" do
    test "data survives close and reopen", %{dir: dir, state: state} do
      {:ok, _state} = RocksDB.put(state, :headers, "persist_key", "persist_value")
      :ok = RocksDB.close(state)

      {:ok, new_state} = RocksDB.init(datadir: dir)
      assert {:ok, "persist_value"} = RocksDB.get(new_state, :headers, "persist_key")
      RocksDB.close(new_state)
    end
  end

  describe "close/1" do
    test "closes the database successfully", %{state: state} do
      assert :ok = RocksDB.close(state)
    end
  end
end
