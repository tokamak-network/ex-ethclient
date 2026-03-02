defmodule EthCore.Types.Address do
  @enforce_keys [:bytes]
  defstruct [:bytes]

  @type t :: %__MODULE__{bytes: <<_::160>>}

  @spec new(binary()) :: {:ok, t()} | {:error, String.t()}
  def new(<<bytes::binary-size(20)>>), do: {:ok, %__MODULE__{bytes: bytes}}
  def new(_), do: {:error, "address must be exactly 20 bytes"}

  @spec from_hex(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_hex("0x" <> hex), do: from_hex(hex)

  def from_hex(hex) when byte_size(hex) == 40 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> new(bytes)
      :error -> {:error, "invalid hex string"}
    end
  end

  def from_hex(_), do: {:error, "hex address must be 40 characters"}

  @spec to_hex(t()) :: String.t()
  def to_hex(%__MODULE__{bytes: bytes}) do
    "0x" <> Base.encode16(bytes, case: :lower)
  end

  @spec zero() :: t()
  def zero, do: %__MODULE__{bytes: <<0::160>>}

  @spec from_private_key(<<_::256>>) :: t()
  def from_private_key(<<privkey::binary-size(32)>>) do
    address_bytes = EthCrypto.Key.privkey_to_address(privkey)
    %__MODULE__{bytes: address_bytes}
  end
end
