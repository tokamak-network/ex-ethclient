defmodule EthStorage.Backend.ContractTest do
  @moduledoc """
  Tests the Backend behaviour contract against all implementations.

  Runs the same set of tests against Memory and DETS backends to ensure
  they conform to the same interface semantics.
  """

  use ExUnit.Case, async: false

  for backend <- [EthStorage.Backend.Memory, EthStorage.Backend.DETS] do
    describe "#{inspect(backend)}" do
      setup do
        opts =
          case unquote(backend) do
            EthStorage.Backend.Memory ->
              []

            EthStorage.Backend.DETS ->
              dir =
                Path.join(
                  System.tmp_dir!(),
                  "contract_dets_#{:erlang.unique_integer([:positive])}"
                )

              on_exit(fn -> File.rm_rf!(dir) end)
              [datadir: dir]
          end

        {:ok, state} = unquote(backend).init(opts)
        %{backend: unquote(backend), state: state}
      end

      test "put and get", %{backend: mod, state: state} do
        {:ok, state} = mod.put(state, :headers, "key1", "value1")
        assert {:ok, "value1"} = mod.get(state, :headers, "key1")
      end

      test "get missing key returns nil", %{backend: mod, state: state} do
        assert {:ok, nil} = mod.get(state, :headers, "nonexistent")
      end

      test "delete removes key", %{backend: mod, state: state} do
        {:ok, state} = mod.put(state, :headers, "key1", "value1")
        {:ok, state} = mod.delete(state, :headers, "key1")
        assert {:ok, nil} = mod.get(state, :headers, "key1")
      end

      test "batch_put inserts multiple", %{backend: mod, state: state} do
        entries = [{:headers, "k1", "v1"}, {:headers, "k2", "v2"}, {:bodies, "k3", "v3"}]
        {:ok, state} = mod.batch_put(state, entries)
        assert {:ok, "v1"} = mod.get(state, :headers, "k1")
        assert {:ok, "v2"} = mod.get(state, :headers, "k2")
        assert {:ok, "v3"} = mod.get(state, :bodies, "k3")
      end

      test "put overwrites existing value", %{backend: mod, state: state} do
        {:ok, state} = mod.put(state, :headers, "key1", "value1")
        {:ok, state} = mod.put(state, :headers, "key1", "value2")
        assert {:ok, "value2"} = mod.get(state, :headers, "key1")
      end

      test "unknown table returns error on get", %{backend: mod, state: state} do
        assert {:error, :unknown_table} = mod.get(state, :nonexistent, "key")
      end

      test "unknown table returns error on put", %{backend: mod, state: state} do
        assert {:error, :unknown_table} = mod.put(state, :nonexistent, "key", "val")
      end

      test "unknown table returns error on delete", %{backend: mod, state: state} do
        assert {:error, :unknown_table} = mod.delete(state, :nonexistent, "key")
      end

      test "tables are isolated from each other", %{backend: mod, state: state} do
        {:ok, state} = mod.put(state, :headers, "key", "header_data")
        {:ok, _state} = mod.put(state, :bodies, "key", "body_data")
        assert {:ok, "header_data"} = mod.get(state, :headers, "key")
      end
    end
  end
end
