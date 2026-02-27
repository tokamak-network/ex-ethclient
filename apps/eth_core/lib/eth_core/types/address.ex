defmodule EthCore.Types.Address do
  @moduledoc """
  A 20-byte Ethereum address with EIP-55 checksum support.
  """

  @type t :: <<_::160>>

  @zero <<0::160>>

  defguard is_address(a) when is_binary(a) and byte_size(a) == 20

  @doc "Returns the zero address (20 zero bytes)."
  @spec zero() :: t()
  def zero, do: @zero

  @doc "Creates an Address from a raw 20-byte binary."
  @spec new(binary()) :: {:ok, t()} | {:error, :invalid_address}
  def new(<<_::binary-size(20)>> = bytes), do: {:ok, bytes}
  def new(_), do: {:error, :invalid_address}

  @doc "Creates an Address from a hex string (with or without 0x prefix)."
  @spec from_hex(String.t()) :: {:ok, t()} | {:error, :invalid_hex}
  def from_hex("0x" <> hex), do: from_hex(hex)

  def from_hex(hex) when is_binary(hex) and byte_size(hex) == 40 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_hex}
    end
  end

  def from_hex(_), do: {:error, :invalid_hex}

  @doc "Converts an address to a 0x-prefixed hex string (lowercase)."
  @spec to_hex(t()) :: String.t()
  def to_hex(<<_::binary-size(20)>> = addr) do
    "0x" <> Base.encode16(addr, case: :lower)
  end

  @doc """
  Converts an address to EIP-55 checksummed hex string.
  Requires EthCrypto.Hash.keccak256 to be available.
  """
  @spec to_checksum_hex(t()) :: String.t()
  def to_checksum_hex(<<_::binary-size(20)>> = addr) do
    hex = Base.encode16(addr, case: :lower)
    hash = EthCrypto.Hash.keccak256(hex) |> Base.encode16(case: :lower)

    checksummed =
      hex
      |> String.graphemes()
      |> Enum.zip(String.graphemes(hash))
      |> Enum.map(fn {char, hash_char} ->
        if char in ~w(a b c d e f) and hash_char in ~w(8 9 a b c d e f) do
          String.upcase(char)
        else
          char
        end
      end)
      |> Enum.join()

    "0x" <> checksummed
  end

  @doc """
  Creates an Address from an EIP-55 checksummed hex string.
  Returns error if the checksum is invalid.
  """
  @spec from_checksum_hex(String.t()) :: {:ok, t()} | {:error, :invalid_checksum | :invalid_hex}
  def from_checksum_hex("0x" <> hex) when byte_size(hex) == 40 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} ->
        if valid_checksum?("0x" <> hex) do
          {:ok, bytes}
        else
          {:error, :invalid_checksum}
        end

      :error ->
        {:error, :invalid_hex}
    end
  end

  def from_checksum_hex(_), do: {:error, :invalid_hex}

  @doc "Checks if a 0x-prefixed hex string has a valid EIP-55 checksum."
  @spec valid_checksum?(String.t()) :: boolean()
  def valid_checksum?("0x" <> hex) when byte_size(hex) == 40 do
    # All lowercase or all uppercase is always valid
    lower = String.downcase(hex)

    if hex == lower or hex == String.upcase(hex) do
      true
    else
      case Base.decode16(lower, case: :lower) do
        {:ok, bytes} ->
          expected = to_checksum_hex(bytes)
          "0x" <> hex == expected

        :error ->
          false
      end
    end
  end

  def valid_checksum?(_), do: false

  @doc "Derives an address from a 64-byte uncompressed public key (without 0x04 prefix)."
  @spec from_public_key(<<_::512>>) :: t()
  def from_public_key(<<_::binary-size(64)>> = public_key) do
    <<_::binary-size(12), address::binary-size(20)>> = EthCrypto.Hash.keccak256(public_key)
    address
  end
end
