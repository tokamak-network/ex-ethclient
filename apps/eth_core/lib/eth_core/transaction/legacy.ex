defmodule EthCore.Transaction.Legacy do
  alias EthCore.Transaction.RLPHelpers, as: H

  defstruct [
    :nonce,
    :gas_price,
    :gas_limit,
    :to,
    :value,
    :data,
    :v,
    :r,
    :s
  ]

  @type t :: %__MODULE__{
          nonce: non_neg_integer(),
          gas_price: non_neg_integer(),
          gas_limit: non_neg_integer(),
          to: binary() | nil,
          value: non_neg_integer(),
          data: binary(),
          v: non_neg_integer() | nil,
          r: non_neg_integer() | nil,
          s: non_neg_integer() | nil
        }

  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(rlp_bytes) when is_binary(rlp_bytes) do
    [nonce, gas_price, gas_limit, to, value, data, v, r, s] = ExRLP.decode(rlp_bytes)

    {:ok,
     %__MODULE__{
       nonce: H.decode_integer(nonce),
       gas_price: H.decode_integer(gas_price),
       gas_limit: H.decode_integer(gas_limit),
       to: H.decode_address(to),
       value: H.decode_integer(value),
       data: data,
       v: H.decode_integer(v),
       r: H.decode_integer(r),
       s: H.decode_integer(s)
     }}
  rescue
    e -> {:error, "Failed to decode legacy tx: #{inspect(e)}"}
  end

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = tx) do
    [
      H.encode_integer(tx.nonce),
      H.encode_integer(tx.gas_price),
      H.encode_integer(tx.gas_limit),
      H.encode_address(tx.to),
      H.encode_integer(tx.value),
      tx.data || "",
      H.encode_integer(tx.v || 0),
      H.encode_integer(tx.r || 0),
      H.encode_integer(tx.s || 0)
    ]
    |> ExRLP.encode()
  end

  @spec signing_hash(t()) :: <<_::256>>
  def signing_hash(%__MODULE__{} = tx) do
    [
      H.encode_integer(tx.nonce),
      H.encode_integer(tx.gas_price),
      H.encode_integer(tx.gas_limit),
      H.encode_address(tx.to),
      H.encode_integer(tx.value),
      tx.data || ""
    ]
    |> ExRLP.encode()
    |> EthCrypto.Hash.keccak256()
  end

  @spec signing_hash(t(), non_neg_integer()) :: <<_::256>>
  def signing_hash(%__MODULE__{} = tx, chain_id) do
    [
      H.encode_integer(tx.nonce),
      H.encode_integer(tx.gas_price),
      H.encode_integer(tx.gas_limit),
      H.encode_address(tx.to),
      H.encode_integer(tx.value),
      tx.data || "",
      H.encode_integer(chain_id),
      "",
      ""
    ]
    |> ExRLP.encode()
    |> EthCrypto.Hash.keccak256()
  end
end
