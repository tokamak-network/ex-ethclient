defmodule EthCore.Types.Hash do
  @enforce_keys [:bytes]
  defstruct [:bytes]

  @type t :: %__MODULE__{bytes: <<_::256>>}

  @spec new(binary()) :: {:ok, t()} | {:error, String.t()}
  def new(<<bytes::binary-size(32)>>), do: {:ok, %__MODULE__{bytes: bytes}}
  def new(_), do: {:error, "hash must be exactly 32 bytes"}

  @spec from_hex(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_hex("0x" <> hex), do: from_hex(hex)

  def from_hex(hex) when byte_size(hex) == 64 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> new(bytes)
      :error -> {:error, "invalid hex string"}
    end
  end

  def from_hex(_), do: {:error, "hex hash must be 64 characters"}

  @spec to_hex(t()) :: String.t()
  def to_hex(%__MODULE__{bytes: bytes}) do
    "0x" <> Base.encode16(bytes, case: :lower)
  end

  @spec zero() :: t()
  def zero, do: %__MODULE__{bytes: <<0::256>>}

  @spec compute(binary()) :: t()
  def compute(data) when is_binary(data) do
    %__MODULE__{bytes: EthCrypto.Hash.keccak256(data)}
  end
end
