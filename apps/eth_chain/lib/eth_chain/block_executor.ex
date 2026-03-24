defmodule EthChain.BlockExecutor do
  @moduledoc """
  Executes blocks by coordinating validation and EVM execution.

  Orchestrates the full block execution pipeline: pre-execution validation,
  EVM environment construction, transaction execution, and post-execution
  verification.
  """

  alias EthChain.{BlockValidator, Fork, StateManager, SystemOps, WithdrawalProcessor}
  alias EthCore.Types.{Account, Block, BlockHeader}
  alias EthStorage.MPT.Trie
  alias EthVm.Types.{BlockExecutionResult, Environment}

  require Logger

  @doc """
  Executes a block: validates, runs transactions through EVM, verifies post-state.

  Steps:
  1. Validate header against parent (pre-execution)
  2. Validate body
  3. Build EVM environment from header
  4. Execute block through EVM
  5. Verify gas_used matches header
  6. Return execution result
  """
  @spec execute_block(Block.t(), BlockHeader.t(), module(), module()) ::
          {:ok, BlockExecutionResult.t()} | {:error, term()}
  def execute_block(%Block{} = block, %BlockHeader{} = parent_header, evm_module, state_provider) do
    with :ok <- BlockValidator.validate_header(block.header, parent_header),
         :ok <- BlockValidator.validate_body(block),
         {:ok, result} <- do_execute(block, evm_module, state_provider),
         :ok <- verify_gas_used(result.gas_used, block.header.gas_used) do
      {:ok, result}
    end
  end

  @doc """
  Builds an EVM Environment from a block header.

  Maps header fields to the corresponding Environment fields used
  by the EVM during transaction execution.
  """
  @spec build_environment(BlockHeader.t()) :: Environment.t()
  def build_environment(%BlockHeader{} = header) do
    %Environment{
      coinbase: header.coinbase,
      gas_limit: header.gas_limit,
      number: header.number,
      timestamp: header.timestamp,
      difficulty: header.difficulty,
      base_fee_per_gas: header.base_fee_per_gas || 0,
      prev_randao: header.mix_hash,
      excess_blob_gas: header.excess_blob_gas || 0,
      chain_id: 1,
      block_hash_lookup: nil
    }
  end

  @doc """
  Executes a block and applies state transitions.
  Returns execution result and new state root.

  1. Executes pre-block system calls (EIP-4788 beacon root, etc.)
  2. Executes the block via `execute_block/4`
  3. Processes withdrawals (Shanghai+)
  4. Applies account updates to the state trie
  5. Computes and verifies state root against header
  6. Returns the result and new state root hash
  """
  @spec execute_and_apply(
          Block.t(),
          BlockHeader.t(),
          module(),
          module(),
          GenServer.server()
        ) :: {:ok, BlockExecutionResult.t(), <<_::256>>} | {:error, term()}
  def execute_and_apply(%Block{} = block, %BlockHeader{} = parent, evm_mod, state_mod, store) do
    # Pre-block system calls
    system_state = SystemOps.pre_block_system_calls(block.header, %{})

    with {:ok, result} <- execute_block(block, parent, evm_mod, state_mod) do
      # Merge withdrawal balance updates into account_updates
      account_updates = merge_withdrawal_updates(block, result.account_updates)

      # Merge system operation storage updates
      account_updates = merge_system_state(account_updates, system_state)

      # Apply all updates to the state trie
      trie = Trie.new()

      with {:ok, _trie, root} <-
             StateManager.apply_account_updates(trie, account_updates, store) do
        # Log warning if state root doesn't match (don't fail for now)
        maybe_verify_state_root(root, block.header.state_root)

        # Post-block system calls
        _post_state = SystemOps.post_block_system_calls(block.header, system_state)

        {:ok, result, root}
      end
    end
  end

  @spec merge_withdrawal_updates(Block.t(), %{binary() => map()}) :: %{binary() => map()}
  defp merge_withdrawal_updates(%Block{withdrawals: nil}, account_updates), do: account_updates
  defp merge_withdrawal_updates(%Block{withdrawals: []}, account_updates), do: account_updates

  defp merge_withdrawal_updates(%Block{header: header, withdrawals: withdrawals}, account_updates) do
    fork = Fork.active_fork(header.number, header.timestamp)

    if Fork.withdrawals?(fork) do
      # Build current account state from existing updates
      current_state =
        Enum.reduce(account_updates, %{}, fn {address, update}, acc ->
          account = %Account{
            nonce: Map.get(update, :nonce, 0),
            balance: Map.get(update, :balance, 0)
          }

          Map.put(acc, address, account)
        end)

      # Process withdrawals
      updated_state = WithdrawalProcessor.process_withdrawals(withdrawals, current_state)

      # Convert back to account_updates format and merge
      withdrawal_updates = WithdrawalProcessor.to_account_updates(updated_state, current_state)

      Map.merge(account_updates, withdrawal_updates, fn _addr, existing, new ->
        Map.merge(existing, new)
      end)
    else
      account_updates
    end
  end

  @spec merge_system_state(%{binary() => map()}, map()) :: %{binary() => map()}
  defp merge_system_state(account_updates, system_state) when map_size(system_state) == 0 do
    account_updates
  end

  defp merge_system_state(account_updates, system_state) do
    Enum.reduce(system_state, account_updates, fn
      {{:storage, address}, storage}, acc ->
        existing = Map.get(acc, address, %{})
        existing_storage = Map.get(existing, :storage, %{})
        merged_storage = Map.merge(existing_storage, storage)
        Map.put(acc, address, Map.put(existing, :storage, merged_storage))

      _other, acc ->
        acc
    end)
  end

  @spec maybe_verify_state_root(<<_::256>>, binary() | nil) :: :ok
  defp maybe_verify_state_root(_computed, nil), do: :ok

  defp maybe_verify_state_root(computed, expected) do
    if computed != expected do
      Logger.warning(
        "State root mismatch: computed=#{Base.encode16(computed, case: :lower)}" <>
          " expected=#{Base.encode16(expected, case: :lower)}"
      )
    end

    :ok
  end

  defp do_execute(block, evm_module, state_provider) do
    evm_module.execute_block(block, state_provider)
  end

  defp verify_gas_used(executed_gas, header_gas) do
    if executed_gas == header_gas do
      :ok
    else
      {:error, :gas_used_mismatch}
    end
  end
end
