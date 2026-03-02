defmodule EthCore.Transaction.EIP1559 do
  alias EthCore.Transaction.RLPHelpers, as: H

  @type_byte 0x02

  defstruct [
    :chain_id,
    :nonce,
    :max_priority_fee_per_gas,
    :max_fee_per_gas,
    :gas_limit,
    :to,
    :value,
    :data,
    :access_list,
    :v,
    :r,
    :s
  ]

  @type t :: %__MODULE__{
          chain_id: non_neg_integer(),
          nonce: non_neg_integer(),
          max_priority_fee_per_gas: non_neg_integer(),
          max_fee_per_gas: non_neg_integer(),
          gas_limit: non_neg_integer(),
          to: binary() | nil,
          value: non_neg_integer(),
          data: binary(),
          access_list: [{binary(), [binary()]}],
          v: non_neg_integer() | nil,
          r: non_neg_integer() | nil,
          s: non_neg_integer() | nil
        }

  def type_byte, do: @type_byte

  @spec decode(binary()) :: {:ok, t()} | {:error, String.t()}
  def decode(<<@type_byte, rlp_payload::binary>>) do
    [chain_id, nonce, max_priority_fee, max_fee, gas_limit, to, value, data, access_list, v, r, s] =
      ExRLP.decode(rlp_payload)

    {:ok,
     %__MODULE__{
       chain_id: H.decode_integer(chain_id),
       nonce: H.decode_integer(nonce),
       max_priority_fee_per_gas: H.decode_integer(max_priority_fee),
       max_fee_per_gas: H.decode_integer(max_fee),
       gas_limit: H.decode_integer(gas_limit),
       to: H.decode_address(to),
       value: H.decode_integer(value),
       data: data,
       access_list: H.decode_access_list(access_list),
       v: H.decode_integer(v),
       r: H.decode_integer(r),
       s: H.decode_integer(s)
     }}
  rescue
    e -> {:error, "Failed to decode EIP-1559 tx: #{inspect(e)}"}
  end

  @spec encode(t()) :: binary()
  def encode(%__MODULE__{} = tx) do
    rlp_payload =
      [
        H.encode_integer(tx.chain_id),
        H.encode_integer(tx.nonce),
        H.encode_integer(tx.max_priority_fee_per_gas),
        H.encode_integer(tx.max_fee_per_gas),
        H.encode_integer(tx.gas_limit),
        H.encode_address(tx.to),
        H.encode_integer(tx.value),
        tx.data || "",
        H.encode_access_list(tx.access_list || []),
        H.encode_integer(tx.v || 0),
        H.encode_integer(tx.r || 0),
        H.encode_integer(tx.s || 0)
      ]
      |> ExRLP.encode()

    <<@type_byte>> <> rlp_payload
  end

  @spec signing_hash(t()) :: <<_::256>>
  def signing_hash(%__MODULE__{} = tx) do
    payload =
      [
        H.encode_integer(tx.chain_id),
        H.encode_integer(tx.nonce),
        H.encode_integer(tx.max_priority_fee_per_gas),
        H.encode_integer(tx.max_fee_per_gas),
        H.encode_integer(tx.gas_limit),
        H.encode_address(tx.to),
        H.encode_integer(tx.value),
        tx.data || "",
        H.encode_access_list(tx.access_list || [])
      ]
      |> ExRLP.encode()

    EthCrypto.Hash.keccak256(<<@type_byte>> <> payload)
  end
end
