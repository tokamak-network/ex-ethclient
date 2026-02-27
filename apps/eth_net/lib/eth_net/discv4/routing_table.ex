defmodule EthNet.DiscV4.RoutingTable do
  @moduledoc """
  Kademlia-like routing table with 256 k-buckets (k=16).
  Pure functional implementation — no GenServer, just data transformation.
  """

  alias EthNet.DiscV4.Node

  @k 16
  @num_buckets 256

  @type t :: %__MODULE__{
          self_id: <<_::512>>,
          buckets: %{non_neg_integer() => [Node.t()]}
        }

  defstruct [:self_id, buckets: %{}]

  @doc "Creates a new routing table for the given node ID."
  @spec new(<<_::512>>) :: t()
  def new(self_id) do
    %__MODULE__{self_id: self_id, buckets: %{}}
  end

  @doc "Inserts or updates a node in the appropriate bucket."
  @spec insert(t(), Node.t()) :: t()
  def insert(%__MODULE__{self_id: self_id} = table, %Node{id: id} = node) do
    if id == self_id do
      table
    else
      bucket_idx = Node.log_distance(self_id, id)
      bucket_idx = min(bucket_idx, @num_buckets - 1)
      bucket = Map.get(table.buckets, bucket_idx, [])

      updated_bucket =
        case Enum.find_index(bucket, &(&1.id == id)) do
          nil ->
            # New node — add to end if bucket not full
            if length(bucket) < @k do
              bucket ++ [node]
            else
              # Bucket full, ignore (could implement eviction later)
              bucket
            end

          idx ->
            # Existing node — move to end (most recently seen)
            {_old, rest} = List.pop_at(bucket, idx)
            rest ++ [node]
        end

      %{table | buckets: Map.put(table.buckets, bucket_idx, updated_bucket)}
    end
  end

  @doc "Returns the closest `count` nodes to the target ID."
  @spec closest(t(), <<_::512>>, pos_integer()) :: [Node.t()]
  def closest(%__MODULE__{} = table, target_id, count \\ 16) do
    all_nodes(table)
    |> Enum.sort_by(fn node ->
      hash_a = EthCrypto.Hash.keccak256(node.id)
      hash_b = EthCrypto.Hash.keccak256(target_id)
      :crypto.exor(hash_a, hash_b)
    end)
    |> Enum.take(count)
  end

  @doc "Returns all nodes in the table."
  @spec all_nodes(t()) :: [Node.t()]
  def all_nodes(%__MODULE__{buckets: buckets}) do
    buckets
    |> Map.values()
    |> List.flatten()
  end

  @doc "Returns the total number of nodes."
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = table), do: length(all_nodes(table))

  @doc "Removes a node by ID."
  @spec remove(t(), <<_::512>>) :: t()
  def remove(%__MODULE__{self_id: self_id} = table, node_id) do
    bucket_idx = min(Node.log_distance(self_id, node_id), @num_buckets - 1)
    bucket = Map.get(table.buckets, bucket_idx, [])
    updated = Enum.reject(bucket, &(&1.id == node_id))
    %{table | buckets: Map.put(table.buckets, bucket_idx, updated)}
  end

  @doc "Returns a random target ID for lookup diversity."
  @spec random_target() :: <<_::512>>
  def random_target, do: :crypto.strong_rand_bytes(64)
end
