defmodule EthVm.StateTestRunner do
  @moduledoc """
  Runs Ethereum GeneralStateTest JSON fixtures against the EVM.

  Parses the standard test format, sets up pre-state accounts, executes the
  transaction via the NIF, and validates the post-state root hash against
  the expected value.

  ## GeneralStateTest format

  Each fixture file contains one or more named tests. Each test specifies:
  - `env`: block-level context (coinbase, gas limit, number, timestamp, etc.)
  - `pre`: initial world state (accounts with balances, nonces, code, storage)
  - `transaction`: the transaction to execute (with indexed data/gas/value arrays)
  - `post`: expected post-state root hashes per fork, indexed by data/gas/value

  ## Usage

      {:ok, results} = EthVm.StateTestRunner.run_file("path/to/test.json")
      {:ok, results} = EthVm.StateTestRunner.run_file("path/to/test.json", fork: "Shanghai")
  """

  alias EthStorage.MPT.Trie
  alias EthStorage.AccountRLP
  alias EthVm.StateLoader

  require Logger

  @type test_result :: %{
          test_name: String.t(),
          fork: String.t(),
          index: non_neg_integer(),
          status: :pass | :fail | :skip,
          expected_hash: binary() | nil,
          actual_hash: binary() | nil,
          error: term() | nil
        }

  @supported_forks ~w(
    Shanghai Cancun Prague Merge
    Berlin London Istanbul Constantinople
    ConstantinopleFix Byzantium Homestead Frontier
  )

  # --- Public API ---

  @doc """
  Runs all tests in a GeneralStateTest JSON fixture file.

  Returns a list of test results, one per (test_name, fork, index) combination.

  ## Options

    - `:fork` - Only run tests for a specific fork (e.g. "Shanghai").
      Defaults to running all supported forks present in the fixture.
    - `:evm_module` - EVM module to use. Defaults to `EthVm.Nif`.
  """
  @spec run_file(Path.t(), keyword()) :: {:ok, [test_result()]} | {:error, term()}
  def run_file(path, opts \\ []) do
    with {:ok, contents} <- File.read(path),
         {:ok, json} <- Jason.decode(contents) do
      results =
        json
        |> Enum.flat_map(fn {test_name, test_data} ->
          run_single_test(test_name, test_data, opts)
        end)

      {:ok, results}
    end
  end

  @doc """
  Runs all fixture files in a directory (recursively).

  Returns aggregated results from all files.
  """
  @spec run_directory(Path.t(), keyword()) :: {:ok, [test_result()]} | {:error, term()}
  def run_directory(dir_path, opts \\ []) do
    case File.ls(dir_path) do
      {:ok, entries} ->
        results =
          entries
          |> Enum.sort()
          |> Enum.flat_map(fn entry ->
            full_path = Path.join(dir_path, entry)

            cond do
              File.dir?(full_path) ->
                case run_directory(full_path, opts) do
                  {:ok, sub_results} -> sub_results
                  {:error, _} -> []
                end

              String.ends_with?(entry, ".json") ->
                case run_file(full_path, opts) do
                  {:ok, file_results} -> file_results
                  {:error, _} -> []
                end

              true ->
                []
            end
          end)

        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Formats test results as a summary string.
  """
  @spec format_summary([test_result()]) :: String.t()
  def format_summary(results) do
    total = length(results)
    passed = Enum.count(results, &(&1.status == :pass))
    failed = Enum.count(results, &(&1.status == :fail))
    skipped = Enum.count(results, &(&1.status == :skip))

    failures =
      results
      |> Enum.filter(&(&1.status == :fail))
      |> Enum.map(fn r ->
        expected =
          if r.expected_hash, do: Base.encode16(r.expected_hash, case: :lower), else: "nil"

        actual = if r.actual_hash, do: Base.encode16(r.actual_hash, case: :lower), else: "nil"
        error_str = if r.error, do: " error=#{inspect(r.error)}", else: ""

        "  FAIL #{r.test_name} [#{r.fork}##{r.index}]: " <>
          "expected=#{expected} actual=#{actual}#{error_str}"
      end)
      |> Enum.join("\n")

    summary = "Results: #{passed} passed, #{failed} failed, #{skipped} skipped (#{total} total)"

    if failures == "" do
      summary
    else
      summary <> "\n\nFailures:\n" <> failures
    end
  end

  # --- Internal ---

  @spec run_single_test(String.t(), map(), keyword()) :: [test_result()]
  defp run_single_test(test_name, test_data, opts) do
    env_data = Map.get(test_data, "env", %{})
    pre_data = Map.get(test_data, "pre", %{})
    tx_data = Map.get(test_data, "transaction", %{})
    post_data = Map.get(test_data, "post", %{})
    target_fork = Keyword.get(opts, :fork)

    forks =
      if target_fork do
        if Map.has_key?(post_data, target_fork), do: [target_fork], else: []
      else
        post_data
        |> Map.keys()
        |> Enum.filter(&(&1 in @supported_forks))
      end

    Enum.flat_map(forks, fn fork ->
      post_entries = Map.get(post_data, fork, [])

      Enum.with_index(post_entries, fn post_entry, idx ->
        run_test_case(test_name, fork, idx, env_data, pre_data, tx_data, post_entry, opts)
      end)
    end)
  end

  @spec run_test_case(
          String.t(),
          String.t(),
          non_neg_integer(),
          map(),
          map(),
          map(),
          map(),
          keyword()
        ) :: test_result()
  defp run_test_case(test_name, fork, idx, env_data, pre_data, tx_data, post_entry, opts) do
    indexes = Map.get(post_entry, "indexes", %{})
    expected_hash = decode_hex(Map.get(post_entry, "hash", "0x"))
    data_idx = Map.get(indexes, "data", 0)
    gas_idx = Map.get(indexes, "gas", 0)
    value_idx = Map.get(indexes, "value", 0)

    try do
      # 1. Build EVM environment from test env
      env = build_env(env_data, fork)

      # 2. Build pre-state as accounts map for the NIF
      {pre_accounts, pre_trie} = build_pre_state(pre_data)

      # 3. Build the transaction
      case build_transaction(tx_data, data_idx, gas_idx, value_idx, pre_accounts) do
        {:ok, signed_tx, from_address} ->
          # 4. Build state binary for the NIF
          state_data = build_state_data(pre_accounts, signed_tx, from_address)

          # 5. Execute via the EVM
          evm_module = Keyword.get(opts, :evm_module, EthVm.Nif)

          case execute_tx(evm_module, env, signed_tx, state_data, from_address) do
            {:ok, exec_result} ->
              # 6. Apply state changes and compute post-state root
              actual_hash = compute_post_state_root(pre_trie, pre_accounts, exec_result, env)

              status = if actual_hash == expected_hash, do: :pass, else: :fail

              %{
                test_name: test_name,
                fork: fork,
                index: idx,
                status: status,
                expected_hash: expected_hash,
                actual_hash: actual_hash,
                error: nil
              }

            {:error, reason} ->
              # Transaction execution failed -- compute post-state as if
              # the transaction was invalid (pre-state unchanged)
              actual_hash = Trie.root_hash(pre_trie)

              status = if actual_hash == expected_hash, do: :pass, else: :fail

              %{
                test_name: test_name,
                fork: fork,
                index: idx,
                status: status,
                expected_hash: expected_hash,
                actual_hash: actual_hash,
                error: reason
              }
          end

        {:error, reason} ->
          # Could not build transaction (e.g. signing failure)
          actual_hash = Trie.root_hash(pre_trie)
          status = if actual_hash == expected_hash, do: :pass, else: :fail

          %{
            test_name: test_name,
            fork: fork,
            index: idx,
            status: status,
            expected_hash: expected_hash,
            actual_hash: actual_hash,
            error: reason
          }
      end
    rescue
      e ->
        %{
          test_name: test_name,
          fork: fork,
          index: idx,
          status: :fail,
          expected_hash: nil,
          actual_hash: nil,
          error: Exception.message(e)
        }
    end
  end

  @spec build_env(map(), String.t()) :: EthVm.Types.Environment.t()
  defp build_env(env_data, fork) do
    %EthVm.Types.Environment{
      coinbase:
        decode_address(Map.get(env_data, "currentCoinbase", "0x" <> String.duplicate("00", 20))),
      gas_limit: decode_integer(Map.get(env_data, "currentGasLimit", "0x0")),
      number: decode_integer(Map.get(env_data, "currentNumber", "0x0")),
      timestamp: decode_integer(Map.get(env_data, "currentTimestamp", "0x0")),
      difficulty: decode_integer(Map.get(env_data, "currentDifficulty", "0x0")),
      base_fee_per_gas: decode_integer(Map.get(env_data, "currentBaseFee", "0x0")),
      prev_randao: decode_hex_or_default(Map.get(env_data, "currentRandom"), <<0::256>>),
      excess_blob_gas: decode_integer(Map.get(env_data, "currentExcessBlobGas", "0x0")),
      chain_id: 1,
      block_hash_lookup: build_block_hash_lookup(env_data)
    }
    |> maybe_set_fork_timestamp(fork)
  end

  @spec maybe_set_fork_timestamp(EthVm.Types.Environment.t(), String.t()) ::
          EthVm.Types.Environment.t()
  defp maybe_set_fork_timestamp(env, "Cancun") do
    # Set timestamp high enough for Cancun detection in spec_id_for_block
    %{env | timestamp: max(env.timestamp, 1_710_338_135)}
  end

  defp maybe_set_fork_timestamp(env, "Prague") do
    # Prague needs a timestamp beyond Cancun; use a large future timestamp
    %{env | timestamp: max(env.timestamp, 1_900_000_000)}
  end

  defp maybe_set_fork_timestamp(env, "Shanghai") do
    %{env | timestamp: max(env.timestamp, 1_681_338_455)}
  end

  defp maybe_set_fork_timestamp(env, "Merge") do
    %{env | number: max(env.number, 15_537_394)}
  end

  defp maybe_set_fork_timestamp(env, "London") do
    %{env | number: max(env.number, 12_965_000)}
  end

  defp maybe_set_fork_timestamp(env, "Berlin") do
    %{env | number: max(env.number, 12_244_000)}
  end

  defp maybe_set_fork_timestamp(env, "Istanbul") do
    %{env | number: max(env.number, 9_069_000)}
  end

  defp maybe_set_fork_timestamp(env, "Constantinople") do
    %{env | number: max(env.number, 7_280_000)}
  end

  defp maybe_set_fork_timestamp(env, "ConstantinopleFix") do
    %{env | number: max(env.number, 7_280_000)}
  end

  defp maybe_set_fork_timestamp(env, "Byzantium") do
    %{env | number: max(env.number, 4_370_000)}
  end

  defp maybe_set_fork_timestamp(env, "Homestead") do
    %{env | number: max(env.number, 1_150_000)}
  end

  defp maybe_set_fork_timestamp(env, _fork), do: env

  @spec build_block_hash_lookup(map()) :: (non_neg_integer() -> binary() | nil) | nil
  defp build_block_hash_lookup(env_data) do
    case Map.get(env_data, "previousHash") do
      nil ->
        nil

      prev_hash_hex ->
        prev_hash = decode_hex(prev_hash_hex)
        block_number = decode_integer(Map.get(env_data, "currentNumber", "0x0"))

        fn num ->
          if num == block_number - 1 and block_number > 0 do
            prev_hash
          else
            nil
          end
        end
    end
  end

  @spec build_pre_state(map()) :: {%{binary() => map()}, Trie.t()}
  defp build_pre_state(pre_data) do
    accounts =
      Enum.reduce(pre_data, %{}, fn {addr_hex, account_data}, acc ->
        address = decode_address(addr_hex)
        balance = decode_integer(Map.get(account_data, "balance", "0x0"))
        nonce = decode_integer(Map.get(account_data, "nonce", "0x0"))
        code = decode_hex(Map.get(account_data, "code", "0x"))

        storage =
          account_data
          |> Map.get("storage", %{})
          |> Enum.reduce(%{}, fn {key_hex, val_hex}, sacc ->
            key = decode_hex_padded(key_hex, 32)
            val = decode_hex_padded(val_hex, 32)
            Map.put(sacc, key, val)
          end)

        code_hash =
          if code == <<>> do
            EthCore.Types.Account.empty_code_hash()
          else
            EthCrypto.Hash.keccak256(code)
          end

        account_info = %{
          nonce: nonce,
          balance: balance,
          code: code,
          code_hash: code_hash,
          storage: storage
        }

        Map.put(acc, address, account_info)
      end)

    # Build the state trie for root hash computation
    trie = build_state_trie(accounts)

    {accounts, trie}
  end

  @spec build_state_trie(%{binary() => map()}) :: Trie.t()
  defp build_state_trie(accounts) do
    Enum.reduce(accounts, Trie.new(), fn {address, info}, trie ->
      storage_root = compute_storage_root(info.storage)

      code_hash =
        Map.get(info, :code_hash, EthCore.Types.Account.empty_code_hash())

      account = %EthCore.Types.Account{
        nonce: info.nonce,
        balance: info.balance,
        storage_root: storage_root,
        code_hash: code_hash
      }

      encoded = AccountRLP.encode(account)
      key = EthCrypto.Hash.keccak256(address)
      Trie.put(trie, key, encoded)
    end)
  end

  @spec compute_storage_root(%{binary() => binary()}) :: binary()
  defp compute_storage_root(storage) when map_size(storage) == 0 do
    EthCore.Types.Account.empty_trie_root()
  end

  defp compute_storage_root(storage) do
    trie =
      Enum.reduce(storage, Trie.new(), fn {key, value}, trie ->
        # Storage values are RLP-encoded (stripped of leading zeros)
        int_value = :binary.decode_unsigned(value)

        if int_value == 0 do
          trie
        else
          trimmed = :binary.encode_unsigned(int_value)
          rlp_value = ExRLP.encode(trimmed)
          slot_key = EthCrypto.Hash.keccak256(key)
          Trie.put(trie, slot_key, rlp_value)
        end
      end)

    Trie.root_hash(trie)
  end

  @spec build_transaction(map(), non_neg_integer(), non_neg_integer(), non_neg_integer(), map()) ::
          {:ok, EthCore.Types.SignedTransaction.t(), binary()} | {:error, term()}
  defp build_transaction(tx_data, data_idx, gas_idx, value_idx, _pre_accounts) do
    secret_key = decode_hex(Map.get(tx_data, "secretKey", "0x"))
    data_list = Map.get(tx_data, "data", ["0x"])
    gas_list = Map.get(tx_data, "gasLimit", ["0x5208"])
    value_list = Map.get(tx_data, "value", ["0x0"])

    data = decode_hex(Enum.at(data_list, data_idx, "0x"))
    gas_limit = decode_integer(Enum.at(gas_list, gas_idx, "0x5208"))
    value = decode_integer(Enum.at(value_list, value_idx, "0x0"))
    nonce = decode_integer(Map.get(tx_data, "nonce", "0x0"))
    to_hex = Map.get(tx_data, "to", "")
    gas_price = decode_integer(Map.get(tx_data, "gasPrice", "0x0"))
    max_fee = decode_integer(Map.get(tx_data, "maxFeePerGas", "0x0"))
    max_priority = decode_integer(Map.get(tx_data, "maxPriorityFeePerGas", "0x0"))

    to =
      cond do
        is_nil(to_hex) or to_hex == "" or to_hex == "0x" -> nil
        true -> decode_address(to_hex)
      end

    # Derive sender address from secret key
    {:ok, public_key} = ExSecp256k1.create_public_key(secret_key)
    # public_key from ExSecp256k1 is 65 bytes (with 04 prefix)
    <<4, raw_pubkey::binary-64>> = public_key
    from_address = EthCore.Types.Address.from_public_key(raw_pubkey)

    # Determine transaction type based on available fields
    {tx, chain_id} =
      build_tx_struct(
        tx_data,
        nonce,
        gas_price,
        max_fee,
        max_priority,
        gas_limit,
        to,
        value,
        data
      )

    case EthCore.Transaction.Signer.sign(tx, secret_key, chain_id) do
      {:ok, signed_tx} ->
        # Inject the from address for state loading
        {:ok, signed_tx, from_address}

      {:error, reason} ->
        {:error, {:signing_failed, reason}}
    end
  end

  @spec build_tx_struct(
          map(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary() | nil,
          non_neg_integer(),
          binary()
        ) ::
          {EthCore.Types.Transaction.t(), non_neg_integer() | nil}
  defp build_tx_struct(
         tx_data,
         nonce,
         gas_price,
         max_fee,
         max_priority,
         gas_limit,
         to,
         value,
         data
       ) do
    access_list = parse_access_list(Map.get(tx_data, "accessLists", nil), 0)

    cond do
      max_fee > 0 ->
        # EIP-1559 transaction
        tx = %EthCore.Types.Transaction.EIP1559{
          chain_id: 1,
          nonce: nonce,
          max_priority_fee_per_gas: max_priority,
          max_fee_per_gas: max_fee,
          gas_limit: gas_limit,
          to: to,
          value: value,
          data: data,
          access_list: access_list || []
        }

        {tx, nil}

      access_list != nil ->
        # EIP-2930 transaction
        tx = %EthCore.Types.Transaction.EIP2930{
          chain_id: 1,
          nonce: nonce,
          gas_price: gas_price,
          gas_limit: gas_limit,
          to: to,
          value: value,
          data: data,
          access_list: access_list
        }

        {tx, nil}

      true ->
        # Legacy transaction
        tx = %EthCore.Types.Transaction.Legacy{
          nonce: nonce,
          gas_price: gas_price,
          gas_limit: gas_limit,
          to: to,
          value: value,
          data: data
        }

        {tx, 1}
    end
  end

  @spec parse_access_list(list() | nil, non_neg_integer()) ::
          [{binary(), [binary()]}] | nil
  defp parse_access_list(nil, _idx), do: nil

  defp parse_access_list(access_lists, idx) when is_list(access_lists) do
    case Enum.at(access_lists, idx) do
      nil ->
        nil

      entries when is_list(entries) ->
        Enum.map(entries, fn entry ->
          address = decode_address(Map.get(entry, "address", "0x" <> String.duplicate("00", 20)))

          storage_keys =
            entry
            |> Map.get("storageKeys", [])
            |> Enum.map(&decode_hex_padded(&1, 32))

          {address, storage_keys}
        end)

      _ ->
        nil
    end
  end

  defp parse_access_list(_, _idx), do: nil

  @spec build_state_data(%{binary() => map()}, EthCore.Types.SignedTransaction.t(), binary()) ::
          binary()
  defp build_state_data(pre_accounts, _signed_tx, _from_address) do
    # Serialize all pre-state accounts for the NIF
    nif_accounts =
      Enum.reduce(pre_accounts, %{}, fn {address, info}, acc ->
        Map.put(acc, address, %{
          nonce: info.nonce,
          balance: info.balance,
          code: info.code,
          storage: info.storage
        })
      end)

    StateLoader.serialize_state(nif_accounts)
  end

  @spec execute_tx(
          module(),
          EthVm.Types.Environment.t(),
          EthCore.Types.SignedTransaction.t(),
          binary(),
          binary()
        ) ::
          {:ok, map()} | {:error, term()}
  defp execute_tx(evm_module, env, signed_tx, state_data, from_address) do
    tx = signed_tx.tx
    type_byte = EthCore.Types.Transaction.type(tx)
    to = Map.get(tx, :to) || <<>>
    value = encode_u256(Map.get(tx, :value, 0))
    gas_limit = Map.get(tx, :gas_limit, 21_000)
    data = Map.get(tx, :data, <<>>)
    nonce = Map.get(tx, :nonce, 0)

    gas_price =
      case type_byte do
        t when t in [0, 1] -> encode_u256(Map.get(tx, :gas_price, 0))
        _ -> encode_u256(Map.get(tx, :max_fee_per_gas, 0))
      end

    max_priority_fee =
      case type_byte do
        t when t >= 2 -> encode_u256(Map.get(tx, :max_priority_fee_per_gas, 0))
        _ -> <<>>
      end

    access_list_data = encode_access_list(Map.get(tx, :access_list, []))

    case evm_module do
      EthVm.Nif ->
        EthVm.Native.execute_tx_v3(
          env.number || 0,
          env.timestamp || 0,
          env.coinbase || <<0::160>>,
          env.base_fee_per_gas || 0,
          env.prev_randao || <<0::256>>,
          env.gas_limit || 30_000_000,
          env.excess_blob_gas || 0,
          type_byte,
          from_address,
          to,
          value,
          gas_limit,
          gas_price,
          max_priority_fee,
          <<>>,
          data,
          nonce,
          state_data,
          access_list_data,
          <<>>,
          <<>>
        )

      _ ->
        # For other EVM modules, use the behaviour interface
        evm_module.execute_transaction(env, signed_tx, nil)
    end
  end

  @spec compute_post_state_root(
          Trie.t(),
          %{binary() => map()},
          map(),
          EthVm.Types.Environment.t()
        ) ::
          binary()
  defp compute_post_state_root(pre_trie, pre_accounts, exec_result, _env) do
    # The NIF returns state changes under :state_changes, not :account_updates
    state_changes = Map.get(exec_result, :state_changes, %{})

    # Apply state changes from execution result to the pre-state trie
    updated_trie =
      Enum.reduce(state_changes, pre_trie, fn {address, update}, trie ->
        address_bin =
          if is_binary(address) and byte_size(address) == 20 do
            address
          else
            decode_address("0x" <> to_string(address))
          end

        # Merge update with existing pre-state
        existing =
          Map.get(pre_accounts, address_bin, %{nonce: 0, balance: 0, code: <<>>, storage: %{}})

        new_nonce = Map.get(update, :nonce, existing.nonce)

        # Balance from the NIF is a big-endian binary; convert to integer
        raw_balance = Map.get(update, :balance, existing.balance)

        new_balance =
          cond do
            is_integer(raw_balance) -> raw_balance
            is_binary(raw_balance) and byte_size(raw_balance) == 0 -> 0
            is_binary(raw_balance) -> :binary.decode_unsigned(raw_balance)
            true -> 0
          end

        # Code from the NIF is bytecode binary
        new_code = Map.get(update, :code, existing.code)

        # Storage from the NIF uses trimmed big-endian keys/values.
        # We need to normalize to 32-byte padded keys for consistency with pre-state.
        nif_storage = Map.get(update, :storage, %{})

        normalized_storage =
          Enum.reduce(nif_storage, %{}, fn {key, val}, acc ->
            padded_key = pad_to_32_bytes(key)
            padded_val = pad_to_32_bytes(val)
            Map.put(acc, padded_key, padded_val)
          end)

        # Merge: NIF storage overwrites pre-state storage slots
        new_storage = Map.merge(existing.storage, normalized_storage)

        code_hash =
          if new_code == <<>> or is_nil(new_code) do
            EthCore.Types.Account.empty_code_hash()
          else
            EthCrypto.Hash.keccak256(new_code)
          end

        storage_root = compute_storage_root(new_storage)

        account = %EthCore.Types.Account{
          nonce: new_nonce,
          balance: new_balance,
          storage_root: storage_root,
          code_hash: code_hash
        }

        # Check if account should be deleted (EIP-161: empty accounts)
        key = EthCrypto.Hash.keccak256(address_bin)

        if EthCore.Types.Account.empty?(account) do
          Trie.delete(trie, key)
        else
          encoded = AccountRLP.encode(account)
          Trie.put(trie, key, encoded)
        end
      end)

    Trie.root_hash(updated_trie)
  end

  @spec pad_to_32_bytes(binary()) :: binary()
  defp pad_to_32_bytes(bin) when byte_size(bin) == 32, do: bin

  defp pad_to_32_bytes(bin) when is_binary(bin) and byte_size(bin) < 32 do
    padding = 32 - byte_size(bin)
    <<0::size(padding * 8)>> <> bin
  end

  defp pad_to_32_bytes(bin) when is_binary(bin) do
    binary_part(bin, byte_size(bin) - 32, 32)
  end

  # --- Hex decoding helpers ---

  @spec decode_hex(String.t() | nil) :: binary()
  defp decode_hex(nil), do: <<>>
  defp decode_hex("0x"), do: <<>>
  defp decode_hex("0x" <> hex), do: decode_raw_hex(hex)
  defp decode_hex(""), do: <<>>
  defp decode_hex(hex), do: decode_raw_hex(hex)

  @spec decode_raw_hex(String.t()) :: binary()
  defp decode_raw_hex(hex) do
    # Pad to even length
    padded = if rem(String.length(hex), 2) == 1, do: "0" <> hex, else: hex

    case Base.decode16(padded, case: :mixed) do
      {:ok, bin} -> bin
      :error -> <<>>
    end
  end

  @spec decode_hex_padded(String.t(), non_neg_integer()) :: binary()
  defp decode_hex_padded(hex_str, target_bytes) do
    bin = decode_hex(hex_str)
    size = byte_size(bin)

    cond do
      size == target_bytes -> bin
      size < target_bytes -> <<0::size((target_bytes - size) * 8)>> <> bin
      true -> binary_part(bin, size - target_bytes, target_bytes)
    end
  end

  @spec decode_hex_or_default(String.t() | nil, binary()) :: binary()
  defp decode_hex_or_default(nil, default), do: default
  defp decode_hex_or_default("0x", default), do: default
  defp decode_hex_or_default("", default), do: default
  defp decode_hex_or_default(hex, _default), do: decode_hex(hex)

  @spec decode_integer(String.t() | nil) :: non_neg_integer()
  defp decode_integer(nil), do: 0
  defp decode_integer("0x"), do: 0
  defp decode_integer("0x0"), do: 0

  defp decode_integer("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {val, ""} -> val
      _ -> 0
    end
  end

  defp decode_integer(str) when is_binary(str) do
    case Integer.parse(str) do
      {val, ""} -> val
      _ -> 0
    end
  end

  defp decode_integer(_), do: 0

  @spec decode_address(String.t()) :: binary()
  defp decode_address(hex_str) do
    bin = decode_hex(hex_str)
    size = byte_size(bin)

    cond do
      size == 20 -> bin
      size < 20 -> <<0::size((20 - size) * 8)>> <> bin
      true -> binary_part(bin, size - 20, 20)
    end
  end

  @spec encode_u256(non_neg_integer()) :: binary()
  defp encode_u256(0), do: <<>>

  defp encode_u256(n) when is_integer(n) and n > 0 do
    :binary.encode_unsigned(n, :big)
  end

  @spec encode_access_list([{binary(), [binary()]}] | nil) :: binary()
  defp encode_access_list(nil), do: <<>>
  defp encode_access_list([]), do: <<>>

  defp encode_access_list(entries) do
    num_entries = length(entries)

    entry_data =
      Enum.reduce(entries, <<>>, fn {address, storage_keys}, acc ->
        addr = pad_to(address, 20)
        num_keys = length(storage_keys)

        keys_data =
          Enum.reduce(storage_keys, <<>>, fn key, kacc ->
            kacc <> pad_to(key, 32)
          end)

        acc <> addr <> <<num_keys::unsigned-big-32>> <> keys_data
      end)

    <<num_entries::unsigned-big-32>> <> entry_data
  end

  @spec pad_to(binary(), non_neg_integer()) :: binary()
  defp pad_to(bin, target) when byte_size(bin) == target, do: bin

  defp pad_to(bin, target) when byte_size(bin) < target do
    padding_size = target - byte_size(bin)
    <<0::size(padding_size * 8)>> <> bin
  end

  defp pad_to(bin, target) do
    binary_part(bin, byte_size(bin) - target, target)
  end
end
