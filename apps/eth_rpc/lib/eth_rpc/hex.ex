defmodule EthRpc.Hex do
  @moduledoc """
  Hex encoding/decoding utilities for JSON-RPC quantity and data values.

  Follows the Ethereum JSON-RPC convention:
  - Quantities: "0x" prefixed, no leading zeros (except "0x0")
  - Data: "0x" prefixed, even number of hex digits
  """

  @doc """
  Encodes a non-negative integer as a hex quantity string.

  Returns `"0x"` prefixed hex with no leading zeros.

  ## Examples

      iex> EthRpc.Hex.encode_quantity(0)
      "0x0"

      iex> EthRpc.Hex.encode_quantity(255)
      "0xff"
  """
  @spec encode_quantity(non_neg_integer()) :: String.t()
  def encode_quantity(0), do: "0x0"

  def encode_quantity(n) when is_integer(n) and n > 0 do
    ("0x" <> Integer.to_string(n, 16)) |> String.downcase()
  end

  @doc """
  Encodes binary data as a hex data string.

  Returns `"0x"` prefixed hex with even number of digits.

  ## Examples

      iex> EthRpc.Hex.encode_data(<<1, 2, 3>>)
      "0x010203"

      iex> EthRpc.Hex.encode_data(<<>>)
      "0x"
  """
  @spec encode_data(binary()) :: String.t()
  def encode_data(data) when is_binary(data) do
    "0x" <> Base.encode16(data, case: :lower)
  end

  @doc """
  Decodes a hex quantity string to an integer.

  ## Examples

      iex> EthRpc.Hex.decode_quantity("0xff")
      {:ok, 255}

      iex> EthRpc.Hex.decode_quantity("0x0")
      {:ok, 0}
  """
  @spec decode_quantity(String.t()) :: {:ok, non_neg_integer()} | {:error, :invalid_hex}
  def decode_quantity("0x" <> hex) when byte_size(hex) > 0 do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :invalid_hex}
    end
  end

  def decode_quantity(_), do: {:error, :invalid_hex}

  @doc """
  Decodes a hex data string to binary.

  ## Examples

      iex> EthRpc.Hex.decode_data("0x010203")
      {:ok, <<1, 2, 3>>}

      iex> EthRpc.Hex.decode_data("0x")
      {:ok, <<>>}
  """
  @spec decode_data(String.t()) :: {:ok, binary()} | {:error, :invalid_hex}
  def decode_data("0x" <> hex) do
    # Pad to even length
    padded = if rem(byte_size(hex), 2) == 1, do: "0" <> hex, else: hex

    case Base.decode16(padded, case: :mixed) do
      {:ok, data} -> {:ok, data}
      :error -> {:error, :invalid_hex}
    end
  end

  def decode_data(_), do: {:error, :invalid_hex}
end
