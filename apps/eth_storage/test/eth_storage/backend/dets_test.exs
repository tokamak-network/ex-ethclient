defmodule EthStorage.Backend.DETSTest do
  use ExUnit.Case, async: true

  alias EthStorage.Backend.DETS

  setup do
    dir = Path.join(System.tmp_dir!(), "dets_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, datadir: dir}
  end

  describe "init/1" do
    test "creates directory and DETS files", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert File.dir?(dir)

      for table <- DETS.tables() do
        assert File.exists?(Path.join(dir, "#{table}.dets"))
      end

      DETS.close(state)
    end

    test "opens all 11 logical tables", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert map_size(state.tables) == 11
      assert map_size(state.tables) == length(DETS.tables())

      for table <- DETS.tables() do
        assert Map.has_key?(state.tables, table)
      end

      DETS.close(state)
    end

    test "uses default datadir when not specified" do
      dir = "./data/storage"

      {:ok, state} = DETS.init([])
      assert state.dir == dir

      DETS.close(state)
      File.rm_rf!(dir)
    end
  end

  describe "get/3" do
    test "returns nil for missing key", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert {:ok, nil} = DETS.get(state, :headers, "missing")

      DETS.close(state)
    end

    test "returns error for unknown table", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert {:error, :unknown_table} = DETS.get(state, :nonexistent, "key")

      DETS.close(state)
    end
  end

  describe "put/4" do
    test "stores and retrieves a value", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      {:ok, state} = DETS.put(state, :headers, "key1", "value1")
      assert {:ok, "value1"} = DETS.get(state, :headers, "key1")

      DETS.close(state)
    end

    test "overwrites existing value", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      {:ok, state} = DETS.put(state, :headers, "key1", "value1")
      {:ok, state} = DETS.put(state, :headers, "key1", "value2")
      assert {:ok, "value2"} = DETS.get(state, :headers, "key1")

      DETS.close(state)
    end

    test "stores in different tables independently", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      {:ok, state} = DETS.put(state, :headers, "key", "header_data")
      {:ok, state} = DETS.put(state, :bodies, "key", "body_data")
      assert {:ok, "header_data"} = DETS.get(state, :headers, "key")
      assert {:ok, "body_data"} = DETS.get(state, :bodies, "key")

      DETS.close(state)
    end

    test "returns error for unknown table", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert {:error, :unknown_table} = DETS.put(state, :nonexistent, "key", "val")

      DETS.close(state)
    end
  end

  describe "delete/3" do
    test "removes an existing key", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      {:ok, state} = DETS.put(state, :headers, "key1", "value1")
      {:ok, state} = DETS.delete(state, :headers, "key1")
      assert {:ok, nil} = DETS.get(state, :headers, "key1")

      DETS.close(state)
    end

    test "no-op for missing key", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert {:ok, _state} = DETS.delete(state, :headers, "missing")

      DETS.close(state)
    end

    test "returns error for unknown table", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert {:error, :unknown_table} = DETS.delete(state, :nonexistent, "key")

      DETS.close(state)
    end
  end

  describe "batch_put/2" do
    test "inserts multiple entries across tables", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      entries = [
        {:headers, "h1", "header1"},
        {:bodies, "b1", "body1"},
        {:headers, "h2", "header2"}
      ]

      {:ok, state} = DETS.batch_put(state, entries)

      assert {:ok, "header1"} = DETS.get(state, :headers, "h1")
      assert {:ok, "body1"} = DETS.get(state, :bodies, "b1")
      assert {:ok, "header2"} = DETS.get(state, :headers, "h2")

      DETS.close(state)
    end

    test "returns error if any table is unknown", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      entries = [
        {:headers, "h1", "header1"},
        {:nonexistent, "x", "bad"}
      ]

      assert {:error, :unknown_table} = DETS.batch_put(state, entries)

      DETS.close(state)
    end
  end

  describe "persistence" do
    test "data survives close and reopen", %{datadir: dir} do
      # Write data
      {:ok, state} = DETS.init(datadir: dir)
      {:ok, state} = DETS.put(state, :headers, "key1", "value1")
      {:ok, state} = DETS.put(state, :bodies, "key2", "value2")
      {:ok, state} = DETS.put(state, :chain_config, "latest", "42")
      DETS.close(state)

      # Reopen and verify
      {:ok, state2} = DETS.init(datadir: dir)
      assert {:ok, "value1"} = DETS.get(state2, :headers, "key1")
      assert {:ok, "value2"} = DETS.get(state2, :bodies, "key2")
      assert {:ok, "42"} = DETS.get(state2, :chain_config, "latest")
      DETS.close(state2)
    end

    test "deleted data stays deleted after reopen", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)
      {:ok, state} = DETS.put(state, :headers, "key1", "value1")
      {:ok, state} = DETS.delete(state, :headers, "key1")
      DETS.close(state)

      {:ok, state2} = DETS.init(datadir: dir)
      assert {:ok, nil} = DETS.get(state2, :headers, "key1")
      DETS.close(state2)
    end
  end

  describe "close/1" do
    test "closes all tables cleanly", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      assert :ok = DETS.close(state)

      # After close, DETS info returns :undefined for closed tables
      for {_name, tab} <- state.tables do
        assert :dets.info(tab, :size) == :undefined
      end
    end
  end

  describe "all tables" do
    test "all 9 tables support put/get/delete", %{datadir: dir} do
      {:ok, state} = DETS.init(datadir: dir)

      for table <- DETS.tables() do
        key = "test_key_#{table}"
        value = "test_value_#{table}"

        {:ok, state_new} = DETS.put(state, table, key, value)
        assert {:ok, ^value} = DETS.get(state_new, table, key)

        {:ok, _state_del} = DETS.delete(state_new, table, key)
        assert {:ok, nil} = DETS.get(state_new, table, key)
      end

      DETS.close(state)
    end
  end
end
