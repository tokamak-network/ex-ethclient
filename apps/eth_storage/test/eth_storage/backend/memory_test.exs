defmodule EthStorage.Backend.MemoryTest do
  use ExUnit.Case, async: true

  alias EthStorage.Backend.Memory

  setup do
    {:ok, state} = Memory.init([])
    %{state: state}
  end

  describe "init/1" do
    test "creates ETS tables for all logical tables" do
      {:ok, state} = Memory.init([])
      assert map_size(state) == length(Memory.tables())

      for table <- Memory.tables() do
        assert Map.has_key?(state, table)
      end
    end
  end

  describe "get/3" do
    test "returns nil for missing key", %{state: state} do
      assert {:ok, nil} = Memory.get(state, :headers, "missing")
    end

    test "returns error for unknown table", %{state: state} do
      assert {:error, :unknown_table} =
               Memory.get(state, :nonexistent, "key")
    end
  end

  describe "put/4" do
    test "stores and retrieves a value", %{state: state} do
      {:ok, state} = Memory.put(state, :headers, "key1", "value1")
      assert {:ok, "value1"} = Memory.get(state, :headers, "key1")
    end

    test "overwrites existing value", %{state: state} do
      {:ok, state} = Memory.put(state, :headers, "key1", "value1")
      {:ok, state} = Memory.put(state, :headers, "key1", "value2")
      assert {:ok, "value2"} = Memory.get(state, :headers, "key1")
    end

    test "stores in different tables independently", %{state: state} do
      {:ok, state} = Memory.put(state, :headers, "key", "header_data")
      {:ok, state} = Memory.put(state, :bodies, "key", "body_data")
      assert {:ok, "header_data"} = Memory.get(state, :headers, "key")
      assert {:ok, "body_data"} = Memory.get(state, :bodies, "key")
    end

    test "returns error for unknown table", %{state: state} do
      assert {:error, :unknown_table} =
               Memory.put(state, :nonexistent, "key", "val")
    end
  end

  describe "delete/3" do
    test "removes an existing key", %{state: state} do
      {:ok, state} = Memory.put(state, :headers, "key1", "value1")
      {:ok, state} = Memory.delete(state, :headers, "key1")
      assert {:ok, nil} = Memory.get(state, :headers, "key1")
    end

    test "no-op for missing key", %{state: state} do
      assert {:ok, _state} = Memory.delete(state, :headers, "missing")
    end

    test "returns error for unknown table", %{state: state} do
      assert {:error, :unknown_table} =
               Memory.delete(state, :nonexistent, "key")
    end
  end

  describe "batch_put/2" do
    test "inserts multiple entries across tables", %{state: state} do
      entries = [
        {:headers, "h1", "header1"},
        {:bodies, "b1", "body1"},
        {:headers, "h2", "header2"}
      ]

      {:ok, state} = Memory.batch_put(state, entries)

      assert {:ok, "header1"} = Memory.get(state, :headers, "h1")
      assert {:ok, "body1"} = Memory.get(state, :bodies, "b1")
      assert {:ok, "header2"} = Memory.get(state, :headers, "h2")
    end

    test "returns error if any table is unknown", %{state: state} do
      entries = [
        {:headers, "h1", "header1"},
        {:nonexistent, "x", "bad"}
      ]

      assert {:error, :unknown_table} = Memory.batch_put(state, entries)
    end
  end
end
