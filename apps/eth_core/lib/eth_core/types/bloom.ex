defmodule EthCore.Types.Bloom do
  @moduledoc """
  Ethereum 2048-bit (256-byte) bloom filter for log entries.

  Implements the bloom filter algorithm used in Ethereum block headers
  and transaction receipts to efficiently test whether a log entry
  might be present in a block.
  """

  alias EthCore.Types.Log

  @type t :: <<_::2048>>

  @bloom_bits 2048
  @bloom_bytes div(@bloom_bits, 8)

  @doc """
  Returns an empty bloom filter (all zeros).
  """
  @spec empty() :: t()
  def empty, do: <<0::2048>>

  @doc """
  Creates a bloom filter from a list of Log structs.

  For each log, the address and all topics are added to the bloom.
  """
  @spec create([Log.t()]) :: t()
  def create(logs) when is_list(logs) do
    logs_bloom(logs)
  end

  @doc """
  Convenience function: creates a bloom filter from a list of Log structs.

  Equivalent to `create/1`.
  """
  @spec logs_bloom([Log.t()]) :: t()
  def logs_bloom(logs) when is_list(logs) do
    Enum.reduce(logs, empty(), fn log, bloom ->
      bloom = add_to_bloom(bloom, log.address)

      Enum.reduce(log.topics, bloom, fn topic, acc ->
        add_to_bloom(acc, topic)
      end)
    end)
  end

  @doc """
  Adds a single value to an existing bloom filter.

  Uses the Ethereum bloom algorithm: takes keccak256 of the value,
  then sets 3 bits determined by pairs of bytes from the hash.
  """
  @spec add_to_bloom(t(), binary()) :: t()
  def add_to_bloom(<<_::2048>> = bloom, value) when is_binary(value) do
    hash = EthCrypto.Hash.keccak256(value)
    bloom_bytes = :binary.bin_to_list(bloom)

    bloom_bytes =
      Enum.reduce([0, 2, 4], bloom_bytes, fn i, acc ->
        <<_::binary-size(i), b1, b2, _::binary>> = hash
        bit = Bitwise.band(b1 * 256 + b2, @bloom_bits - 1)
        byte_index = @bloom_bytes - 1 - div(bit, 8)
        bit_index = rem(bit, 8)

        List.update_at(acc, byte_index, fn byte ->
          Bitwise.bor(byte, Bitwise.bsl(1, bit_index))
        end)
      end)

    :binary.list_to_bin(bloom_bytes)
  end

  @doc """
  Checks if a value might be present in the bloom filter.

  Returns `true` if all bits for the value are set (may be a false positive).
  Returns `false` if any bit is not set (definitely not present).
  """
  @spec contains?(t(), binary()) :: boolean()
  def contains?(<<_::2048>> = bloom, value) when is_binary(value) do
    hash = EthCrypto.Hash.keccak256(value)
    bloom_bytes = :binary.bin_to_list(bloom)

    Enum.all?([0, 2, 4], fn i ->
      <<_::binary-size(i), b1, b2, _::binary>> = hash
      bit = Bitwise.band(b1 * 256 + b2, @bloom_bits - 1)
      byte_index = @bloom_bytes - 1 - div(bit, 8)
      bit_index = rem(bit, 8)

      byte = Enum.at(bloom_bytes, byte_index)
      Bitwise.band(byte, Bitwise.bsl(1, bit_index)) != 0
    end)
  end

  @doc """
  Merges two bloom filters using bitwise OR.
  """
  @spec merge(t(), t()) :: t()
  def merge(<<bloom1::2048>>, <<bloom2::2048>>) do
    <<Bitwise.bor(bloom1, bloom2)::2048>>
  end
end
