defmodule EthCore.RLP do
  @moduledoc """
  RLP encoding/decoding for Ethereum types using ex_rlp.

  Provides encoding functions that convert Ethereum structs to RLP-compatible
  lists and back. Integers are encoded as big-endian binaries with no leading zeros.
  """

  require Logger

  alias EthCore.Types.{
    Account,
    Authorization,
    BlockHeader,
    SignedTransaction,
    Transaction,
    Withdrawal
  }

  @doc "Encodes a value to RLP binary."
  @spec encode(term()) :: binary()
  def encode(value) do
    ExRLP.encode(value)
  end

  @doc "Decodes an RLP binary."
  @spec decode(binary()) :: term()
  def decode(data) do
    ExRLP.decode(data)
  end

  # --- Integer encoding helpers ---

  @doc "Encodes a non-negative integer as a big-endian binary with no leading zeros."
  @spec encode_integer(non_neg_integer()) :: binary()
  def encode_integer(0), do: <<>>
  def encode_integer(n) when is_integer(n) and n > 0, do: :binary.encode_unsigned(n)

  @doc "Decodes a big-endian binary to a non-negative integer."
  @spec decode_integer(binary()) :: non_neg_integer()
  def decode_integer(<<>>), do: 0
  def decode_integer(bin) when is_binary(bin), do: :binary.decode_unsigned(bin)

  # --- Transaction encoding ---

  @doc """
  Encodes a transaction for signing (without signature).
  For legacy transactions with chain_id (EIP-155), appends [chain_id, 0, 0].
  """
  @spec encode_for_signing(Transaction.t(), non_neg_integer() | nil) :: binary()
  def encode_for_signing(%Transaction.Legacy{} = tx, chain_id) do
    base = [
      encode_integer(tx.nonce),
      encode_integer(tx.gas_price),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>
    ]

    list =
      if chain_id do
        base ++ [encode_integer(chain_id), <<>>, <<>>]
      else
        base
      end

    ExRLP.encode(list)
  end

  def encode_for_signing(%Transaction.EIP2930{} = tx, _chain_id) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.gas_price),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || [])
    ]

    <<1>> <> ExRLP.encode(list)
  end

  def encode_for_signing(%Transaction.EIP1559{} = tx, _chain_id) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.max_priority_fee_per_gas),
      encode_integer(tx.max_fee_per_gas),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || [])
    ]

    <<2>> <> ExRLP.encode(list)
  end

  def encode_for_signing(%Transaction.EIP4844{} = tx, _chain_id) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.max_priority_fee_per_gas),
      encode_integer(tx.max_fee_per_gas),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || []),
      encode_integer(tx.max_fee_per_blob_gas),
      tx.blob_versioned_hashes || []
    ]

    <<3>> <> ExRLP.encode(list)
  end

  def encode_for_signing(%Transaction.EIP7702{} = tx, _chain_id) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.max_priority_fee_per_gas),
      encode_integer(tx.max_fee_per_gas),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || []),
      encode_authorization_list(tx.authorization_list || [])
    ]

    <<4>> <> ExRLP.encode(list)
  end

  @doc "Encodes a signed transaction to RLP binary (network encoding)."
  @spec encode_signed(SignedTransaction.t()) :: binary()
  def encode_signed(%SignedTransaction{tx: %Transaction.Legacy{} = tx, v: v, r: r, s: s}) do
    list = [
      encode_integer(tx.nonce),
      encode_integer(tx.gas_price),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_integer(v),
      encode_integer(r),
      encode_integer(s)
    ]

    ExRLP.encode(list)
  end

  def encode_signed(%SignedTransaction{tx: %Transaction.EIP2930{} = tx, v: v, r: r, s: s}) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.gas_price),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || []),
      encode_integer(v),
      encode_integer(r),
      encode_integer(s)
    ]

    <<1>> <> ExRLP.encode(list)
  end

  def encode_signed(%SignedTransaction{tx: %Transaction.EIP1559{} = tx, v: v, r: r, s: s}) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.max_priority_fee_per_gas),
      encode_integer(tx.max_fee_per_gas),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || []),
      encode_integer(v),
      encode_integer(r),
      encode_integer(s)
    ]

    <<2>> <> ExRLP.encode(list)
  end

  def encode_signed(%SignedTransaction{tx: %Transaction.EIP4844{} = tx, v: v, r: r, s: s}) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.max_priority_fee_per_gas),
      encode_integer(tx.max_fee_per_gas),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || []),
      encode_integer(tx.max_fee_per_blob_gas),
      tx.blob_versioned_hashes || [],
      encode_integer(v),
      encode_integer(r),
      encode_integer(s)
    ]

    <<3>> <> ExRLP.encode(list)
  end

  def encode_signed(%SignedTransaction{tx: %Transaction.EIP7702{} = tx, v: v, r: r, s: s}) do
    list = [
      encode_integer(tx.chain_id),
      encode_integer(tx.nonce),
      encode_integer(tx.max_priority_fee_per_gas),
      encode_integer(tx.max_fee_per_gas),
      encode_integer(tx.gas_limit),
      encode_address(tx.to),
      encode_integer(tx.value),
      tx.data || <<>>,
      encode_access_list(tx.access_list || []),
      encode_authorization_list(tx.authorization_list || []),
      encode_integer(v),
      encode_integer(r),
      encode_integer(s)
    ]

    <<4>> <> ExRLP.encode(list)
  end

  # --- Block Header encoding ---

  @doc "Encodes a block header to an RLP list."
  @spec encode_header(BlockHeader.t()) :: binary()
  def encode_header(%BlockHeader{} = h) do
    base = [
      h.parent_hash,
      h.ommers_hash,
      h.coinbase,
      h.state_root,
      h.transactions_root,
      h.receipts_root,
      h.logs_bloom,
      encode_integer(h.difficulty),
      encode_integer(h.number),
      encode_integer(h.gas_limit),
      encode_integer(h.gas_used),
      encode_integer(h.timestamp),
      h.extra_data,
      h.mix_hash,
      h.nonce
    ]

    optional =
      []
      |> maybe_append(h.base_fee_per_gas, &encode_integer/1)
      |> maybe_append(h.withdrawals_root, & &1)
      |> maybe_append(h.blob_gas_used, &encode_integer/1)
      |> maybe_append(h.excess_blob_gas, &encode_integer/1)
      |> maybe_append(h.parent_beacon_block_root, & &1)
      |> maybe_append(h.requests_hash, & &1)

    ExRLP.encode(base ++ optional)
  end

  # --- Account encoding ---

  @doc "Encodes an account state to RLP."
  @spec encode_account(Account.t()) :: binary()
  def encode_account(%Account{} = a) do
    ExRLP.encode([
      encode_integer(a.nonce),
      encode_integer(a.balance),
      a.storage_root,
      a.code_hash
    ])
  end

  # --- Withdrawal encoding ---

  @doc "Encodes a withdrawal to RLP."
  @spec encode_withdrawal(Withdrawal.t()) :: binary()
  def encode_withdrawal(%Withdrawal{} = w) do
    ExRLP.encode([
      encode_integer(w.index),
      encode_integer(w.validator_index),
      w.address,
      encode_integer(w.amount)
    ])
  end

  # --- Decoding ---

  @doc """
  Decodes a signed transaction from RLP binary (network encoding).
  Supports EIP-2718 typed transaction envelope and legacy RLP.

  First byte < 0x80: typed transaction (byte value = type ID)
  First byte >= 0xC0: legacy RLP list
  """
  @spec decode_signed(binary()) :: {:ok, SignedTransaction.t()} | {:error, term()}
  def decode_signed(<<type_byte, rest::binary>>) when type_byte in 1..0x7F do
    decode_typed_signed(type_byte, rest)
  end

  def decode_signed(<<first_byte, _::binary>> = data) when first_byte >= 0xC0 do
    decode_signed_legacy(data)
  end

  def decode_signed(<<>>), do: {:error, :empty_data}
  def decode_signed(_), do: {:error, :invalid_transaction_data}

  defp decode_typed_signed(1, rlp_data), do: decode_signed_eip2930(rlp_data)
  defp decode_typed_signed(2, rlp_data), do: decode_signed_eip1559(rlp_data)
  defp decode_typed_signed(3, rlp_data), do: decode_signed_eip4844(rlp_data)
  defp decode_typed_signed(4, rlp_data), do: decode_signed_eip7702(rlp_data)
  defp decode_typed_signed(type, _), do: {:error, {:unknown_tx_type, type}}

  defp decode_signed_legacy(data) do
    with {:ok, decoded} <- safe_rlp_decode(data),
         [nonce, gas_price, gas_limit, to, value, input_data, v, r, s]
         when is_binary(nonce) and is_binary(gas_price) and is_binary(gas_limit) and
                is_binary(to) and is_binary(value) and is_binary(input_data) and
                is_binary(v) and is_binary(r) and is_binary(s) <- decoded do
      tx = %Transaction.Legacy{
        nonce: decode_integer(nonce),
        gas_price: decode_integer(gas_price),
        gas_limit: decode_integer(gas_limit),
        to: decode_address(to),
        value: decode_integer(value),
        data: input_data
      }

      {:ok,
       SignedTransaction.new(
         tx,
         decode_integer(v),
         decode_integer(r),
         decode_integer(s)
       )}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_legacy_transaction}
    end
  end

  defp decode_signed_eip2930(rlp_data) do
    with {:ok, decoded} <- safe_rlp_decode(rlp_data),
         [chain_id, nonce, gas_price, gas_limit, to, value, input_data, access_list, v, r, s]
         when is_binary(chain_id) and is_binary(nonce) and is_binary(gas_price) and
                is_binary(gas_limit) and is_binary(to) and is_binary(value) and
                is_binary(input_data) and is_list(access_list) and is_binary(v) and
                is_binary(r) and is_binary(s) <- decoded,
         {:ok, parsed_access_list} <- safe_decode_access_list(access_list) do
      tx = %Transaction.EIP2930{
        chain_id: decode_integer(chain_id),
        nonce: decode_integer(nonce),
        gas_price: decode_integer(gas_price),
        gas_limit: decode_integer(gas_limit),
        to: decode_address(to),
        value: decode_integer(value),
        data: input_data,
        access_list: parsed_access_list
      }

      {:ok,
       SignedTransaction.new(
         tx,
         decode_integer(v),
         decode_integer(r),
         decode_integer(s)
       )}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_eip2930_transaction}
    end
  end

  defp decode_signed_eip1559(rlp_data) do
    with {:ok, decoded} <- safe_rlp_decode(rlp_data),
         [
           chain_id,
           nonce,
           max_priority_fee,
           max_fee,
           gas_limit,
           to,
           value,
           input_data,
           access_list,
           v,
           r,
           s
         ]
         when is_binary(chain_id) and is_binary(nonce) and is_binary(max_priority_fee) and
                is_binary(max_fee) and is_binary(gas_limit) and is_binary(to) and
                is_binary(value) and is_binary(input_data) and is_list(access_list) and
                is_binary(v) and is_binary(r) and is_binary(s) <- decoded,
         {:ok, parsed_access_list} <- safe_decode_access_list(access_list) do
      tx = %Transaction.EIP1559{
        chain_id: decode_integer(chain_id),
        nonce: decode_integer(nonce),
        max_priority_fee_per_gas: decode_integer(max_priority_fee),
        max_fee_per_gas: decode_integer(max_fee),
        gas_limit: decode_integer(gas_limit),
        to: decode_address(to),
        value: decode_integer(value),
        data: input_data,
        access_list: parsed_access_list
      }

      {:ok,
       SignedTransaction.new(
         tx,
         decode_integer(v),
         decode_integer(r),
         decode_integer(s)
       )}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_eip1559_transaction}
    end
  end

  defp decode_signed_eip4844(rlp_data) do
    with {:ok, decoded} <- safe_rlp_decode(rlp_data),
         {:ok, fields} <- validate_eip4844_fields(decoded),
         {:ok, parsed_access_list} <- safe_decode_access_list(fields.access_list) do
      tx = %Transaction.EIP4844{
        chain_id: decode_integer(fields.chain_id),
        nonce: decode_integer(fields.nonce),
        max_priority_fee_per_gas: decode_integer(fields.max_priority_fee),
        max_fee_per_gas: decode_integer(fields.max_fee),
        gas_limit: decode_integer(fields.gas_limit),
        to: decode_address(fields.to),
        value: decode_integer(fields.value),
        data: fields.input_data,
        access_list: parsed_access_list,
        max_fee_per_blob_gas: decode_integer(fields.max_fee_per_blob_gas),
        blob_versioned_hashes: fields.blob_versioned_hashes
      }

      {:ok,
       SignedTransaction.new(
         tx,
         decode_integer(fields.v),
         decode_integer(fields.r),
         decode_integer(fields.s)
       )}
    else
      {:error, _} = error -> error
    end
  end

  defp validate_eip4844_fields([
         chain_id,
         nonce,
         max_priority_fee,
         max_fee,
         gas_limit,
         to,
         value,
         input_data,
         access_list,
         max_fee_per_blob_gas,
         blob_versioned_hashes,
         v,
         r,
         s
       ])
       when is_list(access_list) and is_list(blob_versioned_hashes) do
    {:ok,
     %{
       chain_id: chain_id,
       nonce: nonce,
       max_priority_fee: max_priority_fee,
       max_fee: max_fee,
       gas_limit: gas_limit,
       to: to,
       value: value,
       input_data: input_data,
       access_list: access_list,
       max_fee_per_blob_gas: max_fee_per_blob_gas,
       blob_versioned_hashes: blob_versioned_hashes,
       v: v,
       r: r,
       s: s
     }}
  end

  defp validate_eip4844_fields(_), do: {:error, :invalid_eip4844_transaction}

  defp decode_signed_eip7702(rlp_data) do
    with {:ok, decoded} <- safe_rlp_decode(rlp_data),
         {:ok, fields} <- validate_eip7702_fields(decoded),
         {:ok, parsed_access_list} <- safe_decode_access_list(fields.access_list),
         {:ok, parsed_auth_list} <- safe_decode_authorization_list(fields.authorization_list) do
      tx = %Transaction.EIP7702{
        chain_id: decode_integer(fields.chain_id),
        nonce: decode_integer(fields.nonce),
        max_priority_fee_per_gas: decode_integer(fields.max_priority_fee),
        max_fee_per_gas: decode_integer(fields.max_fee),
        gas_limit: decode_integer(fields.gas_limit),
        to: decode_address(fields.to),
        value: decode_integer(fields.value),
        data: fields.input_data,
        access_list: parsed_access_list,
        authorization_list: parsed_auth_list
      }

      {:ok,
       SignedTransaction.new(
         tx,
         decode_integer(fields.v),
         decode_integer(fields.r),
         decode_integer(fields.s)
       )}
    else
      {:error, _} = error -> error
    end
  end

  defp validate_eip7702_fields([
         chain_id,
         nonce,
         max_priority_fee,
         max_fee,
         gas_limit,
         to,
         value,
         input_data,
         access_list,
         authorization_list,
         v,
         r,
         s
       ])
       when is_list(access_list) and is_list(authorization_list) do
    {:ok,
     %{
       chain_id: chain_id,
       nonce: nonce,
       max_priority_fee: max_priority_fee,
       max_fee: max_fee,
       gas_limit: gas_limit,
       to: to,
       value: value,
       input_data: input_data,
       access_list: access_list,
       authorization_list: authorization_list,
       v: v,
       r: r,
       s: s
     }}
  end

  defp validate_eip7702_fields(_), do: {:error, :invalid_eip7702_transaction}

  @doc "Decodes a block header from RLP binary."
  @spec decode_header(binary()) :: {:ok, BlockHeader.t()} | {:error, term()}
  def decode_header(data) when is_binary(data) do
    case safe_rlp_decode(data) do
      {:ok, fields} when is_list(fields) -> decode_header_fields(fields)
      {:ok, _} -> {:error, :invalid_header}
      {:error, _} = error -> error
    end
  end

  defp decode_header_fields(fields) when length(fields) >= 15 do
    [
      parent_hash,
      ommers_hash,
      coinbase,
      state_root,
      transactions_root,
      receipts_root,
      logs_bloom,
      difficulty,
      number,
      gas_limit,
      gas_used,
      timestamp,
      extra_data,
      mix_hash,
      nonce
      | optional
    ] = fields

    header = %BlockHeader{
      parent_hash: parent_hash,
      ommers_hash: ommers_hash,
      coinbase: coinbase,
      state_root: state_root,
      transactions_root: transactions_root,
      receipts_root: receipts_root,
      logs_bloom: logs_bloom,
      difficulty: decode_integer(difficulty),
      number: decode_integer(number),
      gas_limit: decode_integer(gas_limit),
      gas_used: decode_integer(gas_used),
      timestamp: decode_integer(timestamp),
      extra_data: extra_data,
      mix_hash: mix_hash,
      nonce: nonce
    }

    header = apply_optional_header_fields(header, optional)
    {:ok, header}
  end

  defp decode_header_fields(_), do: {:error, :invalid_header}

  defp apply_optional_header_fields(header, []), do: header

  defp apply_optional_header_fields(header, [base_fee | rest]) do
    header = %{header | base_fee_per_gas: decode_integer(base_fee)}
    apply_optional_header_field(header, rest, :withdrawals_root)
  end

  defp apply_optional_header_field(header, [], _), do: header

  defp apply_optional_header_field(header, [val | rest], :withdrawals_root) do
    header = %{header | withdrawals_root: val}
    apply_optional_header_field(header, rest, :blob_gas_used)
  end

  defp apply_optional_header_field(header, [val | rest], :blob_gas_used) do
    header = %{header | blob_gas_used: decode_integer(val)}
    apply_optional_header_field(header, rest, :excess_blob_gas)
  end

  defp apply_optional_header_field(header, [val | rest], :excess_blob_gas) do
    header = %{header | excess_blob_gas: decode_integer(val)}
    apply_optional_header_field(header, rest, :parent_beacon_block_root)
  end

  defp apply_optional_header_field(header, [val | rest], :parent_beacon_block_root) do
    header = %{header | parent_beacon_block_root: val}
    apply_optional_header_field(header, rest, :requests_hash)
  end

  defp apply_optional_header_field(header, [val | _rest], :requests_hash) do
    %{header | requests_hash: val}
  end

  # --- Receipt/Log encoding/decoding ---

  @doc "Encodes a receipt to RLP binary."
  @spec encode_receipt(EthCore.Types.Receipt.t()) :: binary()
  def encode_receipt(%EthCore.Types.Receipt{type: type} = receipt)
      when type in [0, 1, 2, 3, 4] do
    logs_encoded =
      Enum.map(receipt.logs, fn log ->
        [log.address, log.topics, log.data]
      end)

    fields = [
      encode_integer(receipt.status),
      encode_integer(receipt.cumulative_gas_used),
      receipt.logs_bloom,
      logs_encoded
    ]

    case type do
      0 -> ExRLP.encode(fields)
      _ -> <<type>> <> ExRLP.encode(fields)
    end
  end

  @doc "Decodes a receipt from RLP binary."
  @spec decode_receipt(binary()) :: {:ok, EthCore.Types.Receipt.t()} | {:error, term()}
  def decode_receipt(<<type_byte, rest::binary>>) when type_byte in [1, 2, 3, 4] do
    decode_receipt_fields(type_byte, rest)
  end

  def decode_receipt(<<first_byte, _::binary>> = data) when first_byte >= 0xC0 do
    decode_receipt_fields(0, data)
  end

  def decode_receipt(_), do: {:error, :invalid_receipt}

  defp decode_receipt_fields(type, rlp_data) do
    with {:ok, decoded} <- safe_rlp_decode(rlp_data),
         [status, cumulative_gas_used, logs_bloom, logs_encoded]
         when is_binary(status) and is_binary(cumulative_gas_used) and
                is_binary(logs_bloom) and is_list(logs_encoded) <- decoded,
         {:ok, logs} <- safe_decode_logs(logs_encoded) do
      {:ok,
       %EthCore.Types.Receipt{
         type: type,
         status: decode_integer(status),
         cumulative_gas_used: decode_integer(cumulative_gas_used),
         logs_bloom: logs_bloom,
         logs: logs
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_receipt}
    end
  end

  # --- Encoding helpers ---

  defp encode_address(nil), do: <<>>
  defp encode_address(addr) when is_binary(addr), do: addr

  defp encode_access_list(list) do
    Enum.map(list, fn {address, storage_keys} ->
      [address, storage_keys]
    end)
  end

  defp encode_authorization_list(auths) do
    Enum.map(auths, fn %Authorization{} = auth ->
      [
        encode_integer(auth.chain_id),
        auth.address,
        encode_integer(auth.nonce),
        encode_integer(auth.y_parity),
        encode_integer(auth.r),
        encode_integer(auth.s)
      ]
    end)
  end

  # --- Decoding helpers ---

  # Wraps ExRLP.decode in a safe error tuple.
  # ExRLP raises on invalid input; we convert to {:error, :invalid_rlp}.
  defp safe_rlp_decode(data) when is_binary(data) do
    {:ok, ExRLP.decode(data)}
  rescue
    e in [ArgumentError, FunctionClauseError, MatchError, ErlangError] ->
      Logger.debug("RLP decode failed: #{Exception.message(e)}")
      {:error, :invalid_rlp}
  end

  defp decode_address(<<>>), do: nil
  defp decode_address(<<_::binary-size(20)>> = addr), do: addr
  defp decode_address(_), do: nil

  # Safe access list decoder: validates structure of each entry.
  defp safe_decode_access_list(list) when is_list(list) do
    result =
      Enum.reduce_while(list, [], fn entry, acc ->
        case entry do
          [address, storage_keys]
          when is_binary(address) and byte_size(address) == 20 and is_list(storage_keys) ->
            {:cont, [{address, storage_keys} | acc]}

          _ ->
            {:halt, :error}
        end
      end)

    case result do
      :error -> {:error, :invalid_access_list}
      entries -> {:ok, Enum.reverse(entries)}
    end
  end

  defp safe_decode_access_list(_), do: {:error, :invalid_access_list}

  # Safe authorization list decoder: validates structure and field types.
  defp safe_decode_authorization_list(list) when is_list(list) do
    result =
      Enum.reduce_while(list, [], fn entry, acc ->
        case entry do
          [chain_id, address, nonce, y_parity, r, s]
          when is_binary(chain_id) and is_binary(address) and byte_size(address) == 20 and
                 is_binary(nonce) and is_binary(y_parity) and is_binary(r) and is_binary(s) ->
            y_val = decode_integer(y_parity)

            if y_val in [0, 1] do
              auth = %Authorization{
                chain_id: decode_integer(chain_id),
                address: address,
                nonce: decode_integer(nonce),
                y_parity: y_val,
                r: decode_integer(r),
                s: decode_integer(s)
              }

              {:cont, [auth | acc]}
            else
              {:halt, :error}
            end

          _ ->
            {:halt, :error}
        end
      end)

    case result do
      :error -> {:error, :invalid_authorization_list}
      entries -> {:ok, Enum.reverse(entries)}
    end
  end

  defp safe_decode_authorization_list(_), do: {:error, :invalid_authorization_list}

  # Safe log decoder
  defp safe_decode_logs(logs_encoded) when is_list(logs_encoded) do
    result =
      Enum.reduce_while(logs_encoded, [], fn entry, acc ->
        case entry do
          [address, topics, data]
          when is_binary(address) and is_list(topics) and is_binary(data) ->
            {:cont, [%EthCore.Types.Log{address: address, topics: topics, data: data} | acc]}

          _ ->
            {:halt, :error}
        end
      end)

    case result do
      :error -> {:error, :invalid_log}
      entries -> {:ok, Enum.reverse(entries)}
    end
  end

  defp safe_decode_logs(_), do: {:error, :invalid_log}

  defp maybe_append(list, nil, _fun), do: list
  defp maybe_append(list, value, fun), do: list ++ [fun.(value)]
end
