defmodule EthStorage.MPT.Node do
  @moduledoc """
  Trie node types for the Merkle Patricia Trie.

  The MPT uses four node types:
  - **Empty**: represents the absence of a node
  - **Leaf**: stores a key suffix and value
  - **Extension**: stores a shared key prefix and a child reference
  - **Branch**: 16-way branch plus an optional value slot
  """

  @type nibble :: 0..15
  @type node_ref :: binary()

  @type t ::
          :empty
          | {:leaf, [nibble()], binary()}
          | {:extension, [nibble()], node_ref()}
          | {:branch, tuple(), binary() | nil}

  @doc "Creates an empty node."
  @spec empty() :: :empty
  def empty, do: :empty

  @doc "Creates a leaf node with the given nibble path and value."
  @spec leaf([nibble()], binary()) :: t()
  def leaf(nibbles, value), do: {:leaf, nibbles, value}

  @doc "Creates an extension node with the given nibble path and child."
  @spec extension([nibble()], node_ref()) :: t()
  def extension(nibbles, child), do: {:extension, nibbles, child}

  @doc "Creates an empty branch node."
  @spec empty_branch() :: t()
  def empty_branch do
    children = :erlang.make_tuple(16, <<>>)
    {:branch, children, nil}
  end

  @doc "Gets a child reference from a branch node at the given index."
  @spec branch_child({:branch, tuple(), binary() | nil}, nibble()) ::
          binary()
  def branch_child({:branch, children, _value}, index)
      when index >= 0 and index <= 15 do
    :erlang.element(index + 1, children)
  end

  @doc "Sets a child reference in a branch node at the given index."
  @spec branch_set_child(
          {:branch, tuple(), binary() | nil},
          nibble(),
          binary()
        ) :: t()
  def branch_set_child({:branch, children, value}, index, child)
      when index >= 0 and index <= 15 do
    {:branch, :erlang.setelement(index + 1, children, child), value}
  end

  @doc "Gets the value slot of a branch node."
  @spec branch_value({:branch, tuple(), binary() | nil}) :: binary() | nil
  def branch_value({:branch, _children, value}), do: value

  @doc "Sets the value slot of a branch node."
  @spec branch_set_value({:branch, tuple(), binary() | nil}, binary() | nil) ::
          t()
  def branch_set_value({:branch, children, _value}, new_value) do
    {:branch, children, new_value}
  end

  @doc "Counts non-empty children in a branch node."
  @spec branch_child_count({:branch, tuple(), binary() | nil}) ::
          non_neg_integer()
  def branch_child_count({:branch, children, _value}) do
    Enum.count(0..15, fn i ->
      :erlang.element(i + 1, children) != <<>>
    end)
  end

  @doc "Finds the single non-empty child index in a branch, if exactly one."
  @spec branch_single_child({:branch, tuple(), binary() | nil}) ::
          {nibble(), binary()} | nil
  def branch_single_child({:branch, children, _value}) do
    result =
      Enum.reduce_while(0..15, nil, fn i, acc ->
        child = :erlang.element(i + 1, children)

        if child != <<>> do
          case acc do
            nil -> {:cont, {i, child}}
            _ -> {:halt, :multiple}
          end
        else
          {:cont, acc}
        end
      end)

    case result do
      :multiple -> nil
      other -> other
    end
  end
end
