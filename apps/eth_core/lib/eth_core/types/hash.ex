defmodule EthCore.Types.Hash do
  @moduledoc """
  A 32-byte Keccak-256 hash used throughout Ethereum.
  """

  @type t :: <<_::256>>

  @zero <<0::256>>

  defguard is_hash(h) when is_binary(h) and byte_size(h) == 32

  @doc "Returns the zero hash (32 zero bytes)."
  @spec zero() :: t()
  def zero, do: @zero

  @doc "Creates a Hash from a raw 32-byte binary."
  @spec new(binary()) :: {:ok, t()} | {:error, :invalid_hash}
  def new(<<_::binary-size(32)>> = bytes), do: {:ok, bytes}
  def new(_), do: {:error, :invalid_hash}

  @doc "Creates a Hash from a hex string (with or without 0x prefix)."
  @spec from_hex(String.t()) :: {:ok, t()} | {:error, :invalid_hex}
  def from_hex("0x" <> hex), do: from_hex(hex)

  def from_hex(hex) when is_binary(hex) and byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_hex}
    end
  end

  def from_hex(_), do: {:error, :invalid_hex}

  @doc "Converts a hash to a 0x-prefixed hex string."
  @spec to_hex(t()) :: String.t()
  def to_hex(<<_::binary-size(32)>> = hash) do
    "0x" <> Base.encode16(hash, case: :lower)
  end
end
