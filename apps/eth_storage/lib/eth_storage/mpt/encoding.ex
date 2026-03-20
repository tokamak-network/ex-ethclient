defmodule EthStorage.MPT.Encoding do
  @moduledoc """
  Hex-prefix encoding for Merkle Patricia Trie nibble paths.

  Implements the compact encoding scheme specified in the Ethereum Yellow Paper
  appendix C. Nibble paths are encoded with a prefix that indicates whether
  the path has odd or even length and whether it terminates at a leaf.
  """

  @doc """
  Converts a binary key to a list of nibbles (half-bytes).

  ## Examples

      iex> EthStorage.MPT.Encoding.to_nibbles(<<0xAB, 0xCD>>)
      [0xA, 0xB, 0xC, 0xD]
  """
  @spec to_nibbles(binary()) :: [0..15]
  def to_nibbles(bin) when is_binary(bin) do
    for <<nibble::4 <- bin>>, do: nibble
  end

  @doc """
  Encodes nibbles with hex-prefix encoding.

  The first nibble of the result encodes:
  - Bit 0 (lowest): 1 if odd number of nibbles
  - Bit 1: 1 if leaf (terminator)

  For even-length paths, an additional 0 nibble is prepended.
  """
  @spec encode_path(nibbles :: [0..15], leaf? :: boolean()) :: binary()
  def encode_path(nibbles, leaf?) do
    flag = if leaf?, do: 2, else: 0

    case rem(length(nibbles), 2) do
      1 ->
        # Odd: first byte = (flag + 1) as high nibble, first nibble as low
        [first | rest] = nibbles
        prefix_byte = (flag + 1) * 16 + first
        rest_bytes = nibbles_to_bytes(rest)
        <<prefix_byte>> <> rest_bytes

      0 ->
        # Even: first byte = flag as high nibble, 0 as low nibble
        prefix_byte = flag * 16
        rest_bytes = nibbles_to_bytes(nibbles)
        <<prefix_byte>> <> rest_bytes
    end
  end

  @doc """
  Decodes a hex-prefix encoded binary into nibbles and a leaf flag.
  """
  @spec decode_path(binary()) :: {nibbles :: [0..15], leaf? :: boolean()}
  def decode_path(<<first_byte, rest::binary>>) do
    high = div(first_byte, 16)
    low = rem(first_byte, 16)

    leaf? = high >= 2
    odd? = rem(high, 2) == 1

    rest_nibbles = to_nibbles(rest)

    nibbles =
      if odd? do
        [low | rest_nibbles]
      else
        rest_nibbles
      end

    {nibbles, leaf?}
  end

  @doc """
  Computes the longest common prefix between two nibble lists.

  Returns `{common_prefix, remaining_a, remaining_b}`.
  """
  @spec common_prefix([0..15], [0..15]) ::
          {[0..15], [0..15], [0..15]}
  def common_prefix(a, b), do: common_prefix(a, b, [])

  defp common_prefix([h | ta], [h | tb], acc) do
    common_prefix(ta, tb, [h | acc])
  end

  defp common_prefix(a, b, acc), do: {Enum.reverse(acc), a, b}

  @spec nibbles_to_bytes([0..15]) :: binary()
  defp nibbles_to_bytes([]), do: <<>>

  defp nibbles_to_bytes([high, low | rest]) do
    <<high * 16 + low>> <> nibbles_to_bytes(rest)
  end
end
