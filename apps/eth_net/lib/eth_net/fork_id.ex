defmodule EthNet.ForkID do
  @moduledoc """
  EIP-2124 / EIP-6122 ForkID calculation.

  ForkID uniquely identifies a chain's fork configuration for the eth protocol
  Status message. It consists of:
  - `fork_hash` (4 bytes): CRC32 checksum of genesis hash and passed fork block/timestamps
  - `fork_next` (integer): next upcoming fork value (0 if none)
  """

  @doc """
  Computes the ForkID for the given chain at the specified head.

  Returns `{fork_hash, fork_next}` where `fork_hash` is a 4-byte binary.
  """
  @spec compute(atom(), non_neg_integer(), non_neg_integer()) :: {<<_::32>>, non_neg_integer()}
  def compute(chain, head_block, head_timestamp \\ 0) do
    genesis_hash = EthNet.Chain.genesis_hash(chain)
    {block_values, time_values} = EthNet.Chain.all_fork_values(chain)

    # Start CRC32 with genesis hash
    crc = :erlang.crc32(genesis_hash)

    # Apply passed block forks
    {crc, remaining_blocks} = apply_forks(crc, block_values, head_block)

    # Apply passed timestamp forks
    {crc, remaining_times} = apply_forks(crc, time_values, head_timestamp)

    # fork_next = next upcoming fork (block or time)
    fork_next =
      case remaining_blocks ++ remaining_times do
        [next | _] -> next
        [] -> 0
      end

    {<<crc::big-unsigned-32>>, fork_next}
  end

  @doc """
  Encodes a ForkID for RLP: `[fork_hash, fork_next]`.
  """
  def encode({<<_::binary-size(4)>> = fork_hash, fork_next}) do
    [fork_hash, encode_fork_next(fork_next)]
  end

  @doc """
  Decodes a ForkID from RLP-decoded list: `[fork_hash, fork_next]`.
  """
  def decode([<<_::binary-size(4)>> = fork_hash, fork_next_bin]) do
    fork_next =
      case fork_next_bin do
        <<>> -> 0
        bin when is_binary(bin) -> :binary.decode_unsigned(bin)
      end

    {fork_hash, fork_next}
  end

  defp apply_forks(crc, fork_values, head) do
    {passed, remaining} = Enum.split_while(fork_values, &(&1 <= head))

    final_crc =
      Enum.reduce(passed, crc, fn fork_val, acc ->
        :erlang.crc32(acc, <<fork_val::big-unsigned-64>>)
      end)

    {final_crc, remaining}
  end

  defp encode_fork_next(0), do: <<>>

  defp encode_fork_next(n) do
    bin = :binary.encode_unsigned(n)
    bin
  end
end
