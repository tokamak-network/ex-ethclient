defmodule EthStorage.MPT.Trie do
  @moduledoc """
  Merkle Patricia Trie implementation for Ethereum state storage.

  Provides an in-memory trie with get, put, delete, and root hash computation.
  Nodes are stored in an internal map keyed by their Keccak-256 hash.
  Nodes smaller than 32 bytes are inlined rather than referenced by hash.
  """

  alias EthStorage.MPT.{Encoding, Node}

  @type t :: %__MODULE__{
          root: binary(),
          db: %{binary() => binary()}
        }

  defstruct root: <<>>,
            db: %{}

  @empty_root_rlp ExRLP.encode("")
  @empty_trie_hash EthCrypto.Hash.keccak256(@empty_root_rlp)

  @doc "Creates a new empty trie."
  @spec new() :: t()
  def new, do: %__MODULE__{root: <<>>, db: %{}}

  @doc "Returns the root hash of the trie."
  @spec root_hash(t()) :: <<_::256>>
  def root_hash(%__MODULE__{root: <<>>}), do: @empty_trie_hash

  def root_hash(%__MODULE__{root: root}) when byte_size(root) == 32 do
    root
  end

  def root_hash(%__MODULE__{root: root}) do
    # Inlined node — hash it
    EthCrypto.Hash.keccak256(root)
  end

  @doc "Returns the empty trie root hash (keccak256 of RLP-encoded empty string)."
  @spec empty_root_hash() :: <<_::256>>
  def empty_root_hash, do: @empty_trie_hash

  @doc "Gets a value from the trie by key."
  @spec get(t(), binary()) :: {:ok, binary() | nil}
  def get(%__MODULE__{root: <<>>}, _key), do: {:ok, nil}

  def get(%__MODULE__{} = trie, key) do
    nibbles = Encoding.to_nibbles(key)
    node = resolve_node(trie, trie.root)
    {:ok, do_get(trie, node, nibbles)}
  end

  @doc "Inserts or updates a key-value pair in the trie."
  @spec put(t(), binary(), binary()) :: t()
  def put(%__MODULE__{} = trie, key, value) do
    nibbles = Encoding.to_nibbles(key)
    node = resolve_node(trie, trie.root)
    {new_node, new_db} = do_put(trie, node, nibbles, value)
    trie = %{trie | db: Map.merge(trie.db, new_db)}
    ref = store_node(trie, new_node)
    new_db2 = node_db_entries(new_node)
    %{trie | root: ref, db: Map.merge(trie.db, Map.merge(new_db, new_db2))}
  end

  @doc "Deletes a key from the trie."
  @spec delete(t(), binary()) :: t()
  def delete(%__MODULE__{root: <<>>} = trie, _key), do: trie

  def delete(%__MODULE__{} = trie, key) do
    nibbles = Encoding.to_nibbles(key)
    node = resolve_node(trie, trie.root)

    case do_delete(trie, node, nibbles) do
      {:empty, new_db} ->
        %{trie | root: <<>>, db: Map.merge(trie.db, new_db)}

      {new_node, new_db} when new_node != :empty ->
        trie = %{trie | db: Map.merge(trie.db, new_db)}
        ref = store_node(trie, new_node)
        new_db2 = node_db_entries(new_node)
        %{trie | root: ref, db: Map.merge(trie.db, Map.merge(new_db, new_db2))}
    end
  end

  # --- Internal: get ---

  defp do_get(_trie, :empty, _nibbles), do: nil

  defp do_get(_trie, {:leaf, path, value}, nibbles) do
    if path == nibbles, do: value, else: nil
  end

  defp do_get(trie, {:extension, path, child_ref}, nibbles) do
    path_len = length(path)

    if Enum.take(nibbles, path_len) == path do
      remaining = Enum.drop(nibbles, path_len)
      child = resolve_node(trie, child_ref)
      do_get(trie, child, remaining)
    else
      nil
    end
  end

  defp do_get(_trie, {:branch, _children, value}, []) do
    value
  end

  defp do_get(trie, {:branch, _children, _value} = branch, [nibble | rest]) do
    child_ref = Node.branch_child(branch, nibble)

    if child_ref == <<>> do
      nil
    else
      child = resolve_node(trie, child_ref)
      do_get(trie, child, rest)
    end
  end

  # --- Internal: put ---

  defp do_put(_trie, :empty, nibbles, value) do
    {Node.leaf(nibbles, value), %{}}
  end

  defp do_put(_trie, {:leaf, path, existing_value}, nibbles, value) do
    {common, rem_path, rem_nibbles} = Encoding.common_prefix(path, nibbles)

    cond do
      rem_path == [] and rem_nibbles == [] ->
        # Same key — update value
        {Node.leaf(path, value), %{}}

      rem_path == [] ->
        # Existing leaf becomes a branch value
        [nb | rest_nibbles] = rem_nibbles
        branch = Node.empty_branch()
        branch = Node.branch_set_value(branch, existing_value)
        new_leaf = Node.leaf(rest_nibbles, value)
        new_leaf_ref = encode_and_ref(new_leaf)
        new_db = node_db_entries_with_ref(new_leaf, new_leaf_ref)
        branch = Node.branch_set_child(branch, nb, new_leaf_ref)
        wrap_with_extension(common, branch, new_db)

      rem_nibbles == [] ->
        # New key is a prefix of existing
        [nb | rest_path] = rem_path
        branch = Node.empty_branch()
        branch = Node.branch_set_value(branch, value)
        old_leaf = Node.leaf(rest_path, existing_value)
        old_leaf_ref = encode_and_ref(old_leaf)
        old_db = node_db_entries_with_ref(old_leaf, old_leaf_ref)
        branch = Node.branch_set_child(branch, nb, old_leaf_ref)
        wrap_with_extension(common, branch, old_db)

      true ->
        # Fork: create a branch with two children
        [nb_path | rest_path] = rem_path
        [nb_nibbles | rest_nibbles] = rem_nibbles
        branch = Node.empty_branch()

        old_leaf = Node.leaf(rest_path, existing_value)
        old_ref = encode_and_ref(old_leaf)
        old_db = node_db_entries_with_ref(old_leaf, old_ref)
        branch = Node.branch_set_child(branch, nb_path, old_ref)

        new_leaf = Node.leaf(rest_nibbles, value)
        new_ref = encode_and_ref(new_leaf)
        new_db = node_db_entries_with_ref(new_leaf, new_ref)
        branch = Node.branch_set_child(branch, nb_nibbles, new_ref)

        db = Map.merge(old_db, new_db)
        wrap_with_extension(common, branch, db)
    end
  end

  defp do_put(trie, {:extension, path, child_ref}, nibbles, value) do
    {common, rem_path, rem_nibbles} = Encoding.common_prefix(path, nibbles)

    cond do
      rem_path == [] ->
        # Entire extension path matched, recurse into child
        child = resolve_node(trie, child_ref)
        {new_child, new_db} = do_put(trie, child, rem_nibbles, value)
        new_child_ref = encode_and_ref(new_child)
        child_db = node_db_entries_with_ref(new_child, new_child_ref)
        db = Map.merge(new_db, child_db)
        {Node.extension(path, new_child_ref), db}

      true ->
        # Partial match: split the extension
        [nb_path | rest_path] = rem_path
        branch = Node.empty_branch()

        # Remaining extension or direct child ref
        {old_child_in_branch, old_db} =
          if rest_path == [] do
            {child_ref, %{}}
          else
            ext = Node.extension(rest_path, child_ref)
            ref = encode_and_ref(ext)
            {ref, node_db_entries_with_ref(ext, ref)}
          end

        branch = Node.branch_set_child(branch, nb_path, old_child_in_branch)

        {branch, new_db} =
          case rem_nibbles do
            [] ->
              {Node.branch_set_value(branch, value), %{}}

            [nb_nibbles | rest_nibbles] ->
              new_leaf = Node.leaf(rest_nibbles, value)
              new_ref = encode_and_ref(new_leaf)
              leaf_db = node_db_entries_with_ref(new_leaf, new_ref)
              {Node.branch_set_child(branch, nb_nibbles, new_ref), leaf_db}
          end

        db = Map.merge(old_db, new_db)
        wrap_with_extension(common, branch, db)
    end
  end

  defp do_put(_trie, {:branch, _children, _value} = branch, [], value) do
    {Node.branch_set_value(branch, value), %{}}
  end

  defp do_put(trie, {:branch, _children, _value} = branch, [nibble | rest], value) do
    child_ref = Node.branch_child(branch, nibble)

    child =
      if child_ref == <<>> do
        Node.empty()
      else
        resolve_node(trie, child_ref)
      end

    {new_child, new_db} = do_put(trie, child, rest, value)
    new_child_ref = encode_and_ref(new_child)
    child_db = node_db_entries_with_ref(new_child, new_child_ref)
    db = Map.merge(new_db, child_db)
    {Node.branch_set_child(branch, nibble, new_child_ref), db}
  end

  # --- Internal: delete ---

  defp do_delete(_trie, :empty, _nibbles), do: {:empty, %{}}

  defp do_delete(_trie, {:leaf, path, _value} = node, nibbles) do
    if path == nibbles do
      {:empty, %{}}
    else
      {node, %{}}
    end
  end

  defp do_delete(trie, {:extension, path, child_ref}, nibbles) do
    path_len = length(path)

    if Enum.take(nibbles, path_len) == path do
      remaining = Enum.drop(nibbles, path_len)
      child = resolve_node(trie, child_ref)

      case do_delete(trie, child, remaining) do
        {:empty, new_db} ->
          {:empty, new_db}

        {{:leaf, child_path, val}, new_db} ->
          # Merge extension + leaf
          {Node.leaf(path ++ child_path, val), new_db}

        {{:extension, child_path, child_child}, new_db} ->
          # Merge extension + extension
          {Node.extension(path ++ child_path, child_child), new_db}

        {new_child, new_db} ->
          new_child_ref = encode_and_ref(new_child)
          child_db = node_db_entries_with_ref(new_child, new_child_ref)
          {Node.extension(path, new_child_ref), Map.merge(new_db, child_db)}
      end
    else
      {{:extension, path, child_ref}, %{}}
    end
  end

  defp do_delete(trie, {:branch, _children, _value} = branch, []) do
    branch = Node.branch_set_value(branch, nil)
    compact_branch(trie, branch)
  end

  defp do_delete(trie, {:branch, _children, _value} = branch, [nibble | rest]) do
    child_ref = Node.branch_child(branch, nibble)

    if child_ref == <<>> do
      {branch, %{}}
    else
      child = resolve_node(trie, child_ref)

      case do_delete(trie, child, rest) do
        {:empty, new_db} ->
          new_branch = Node.branch_set_child(branch, nibble, <<>>)
          {result, db2} = compact_branch(trie, new_branch)
          {result, Map.merge(new_db, db2)}

        {new_child, new_db} ->
          new_ref = encode_and_ref(new_child)
          child_db = node_db_entries_with_ref(new_child, new_ref)
          new_branch = Node.branch_set_child(branch, nibble, new_ref)
          {new_branch, Map.merge(new_db, child_db)}
      end
    end
  end

  # Compact a branch that may have only one child remaining
  defp compact_branch(trie, {:branch, _children, value} = branch) do
    child_count = Node.branch_child_count(branch)

    cond do
      child_count == 0 and value != nil ->
        {Node.leaf([], value), %{}}

      child_count == 0 and value == nil ->
        {:empty, %{}}

      child_count == 1 and value == nil ->
        {idx, child_ref} = Node.branch_single_child(branch)
        child = resolve_node(trie, child_ref)

        case child do
          {:leaf, child_path, val} ->
            {Node.leaf([idx | child_path], val), %{}}

          {:extension, child_path, child_child} ->
            {Node.extension([idx | child_path], child_child), %{}}

          _ ->
            new_ref = encode_and_ref(child)
            child_db = node_db_entries_with_ref(child, new_ref)
            {Node.extension([idx], new_ref), child_db}
        end

      true ->
        {branch, %{}}
    end
  end

  # --- Internal: node encoding and storage ---

  defp resolve_node(_trie, <<>>), do: Node.empty()

  defp resolve_node(trie, ref) when byte_size(ref) == 32 do
    case Map.fetch(trie.db, ref) do
      {:ok, encoded} -> decode_node(encoded)
      :error -> Node.empty()
    end
  end

  defp resolve_node(_trie, encoded) when is_binary(encoded) do
    decode_node(encoded)
  end

  defp encode_node(:empty), do: <<>>

  defp encode_node({:leaf, nibbles, value}) do
    ExRLP.encode([Encoding.encode_path(nibbles, true), value])
  end

  defp encode_node({:extension, nibbles, child_ref}) do
    ExRLP.encode([Encoding.encode_path(nibbles, false), child_ref])
  end

  defp encode_node({:branch, children, value}) do
    items =
      Enum.map(0..15, fn i -> :erlang.element(i + 1, children) end)

    items = items ++ [value || <<>>]
    ExRLP.encode(items)
  end

  defp decode_node(<<>>) do
    Node.empty()
  end

  defp decode_node(encoded) do
    case ExRLP.decode(encoded) do
      items when is_list(items) and length(items) == 17 ->
        children_list = Enum.take(items, 16)
        value_item = List.last(items)
        children = List.to_tuple(children_list)
        value = if value_item == <<>>, do: nil, else: value_item
        {:branch, children, value}

      [path_encoded, value_or_child] ->
        {nibbles, leaf?} = Encoding.decode_path(path_encoded)

        if leaf? do
          Node.leaf(nibbles, value_or_child)
        else
          Node.extension(nibbles, value_or_child)
        end

      _other ->
        Node.empty()
    end
  end

  defp store_node(_trie, :empty), do: <<>>

  defp store_node(_trie, node) do
    encoded = encode_node(node)

    if byte_size(encoded) < 32 do
      # Inline: return the RLP directly as the reference
      encoded
    else
      hash = EthCrypto.Hash.keccak256(encoded)
      # Store in trie db happens via caller merging
      hash
    end
  end

  defp encode_and_ref(node) do
    encoded = encode_node(node)

    if byte_size(encoded) < 32 do
      encoded
    else
      EthCrypto.Hash.keccak256(encoded)
    end
  end

  defp node_db_entries(:empty), do: %{}

  defp node_db_entries(node) do
    encoded = encode_node(node)

    if byte_size(encoded) >= 32 do
      hash = EthCrypto.Hash.keccak256(encoded)
      %{hash => encoded}
    else
      %{}
    end
  end

  defp node_db_entries_with_ref(node, ref) do
    encoded = encode_node(node)

    if byte_size(ref) == 32 do
      %{ref => encoded}
    else
      %{}
    end
  end

  defp wrap_with_extension([], node, db), do: {node, db}

  defp wrap_with_extension(prefix, node, db) do
    node_ref = encode_and_ref(node)
    node_entries = node_db_entries_with_ref(node, node_ref)
    {Node.extension(prefix, node_ref), Map.merge(db, node_entries)}
  end
end
