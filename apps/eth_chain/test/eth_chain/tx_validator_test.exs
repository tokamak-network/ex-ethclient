defmodule EthChain.TxValidatorTest do
  use ExUnit.Case, async: true

  alias EthChain.TxValidator
  alias EthCore.Types.{SignedTransaction, Transaction}
  alias EthCore.Transaction.Signer

  # Generate a valid private key for signing
  @private_key :crypto.strong_rand_bytes(32)

  defp sign_tx(tx) do
    {:ok, signed} = Signer.sign(tx, @private_key, 1)
    signed
  end

  defp valid_legacy_tx do
    %Transaction.Legacy{
      nonce: 0,
      gas_price: 1_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>
    }
  end

  defp valid_eip1559_tx do
    %Transaction.EIP1559{
      chain_id: 1,
      nonce: 0,
      max_priority_fee_per_gas: 1_000_000_000,
      max_fee_per_gas: 2_000_000_000,
      gas_limit: 21_000,
      to: <<1::160>>,
      value: 0,
      data: <<>>,
      access_list: []
    }
  end

  describe "validate_for_mempool/2" do
    test "valid legacy transaction passes" do
      signed = sign_tx(valid_legacy_tx())
      assert :ok == TxValidator.validate_for_mempool(signed)
    end

    test "valid EIP-1559 transaction passes" do
      signed = sign_tx(valid_eip1559_tx())
      assert :ok == TxValidator.validate_for_mempool(signed)
    end

    test "invalid signature fails" do
      tx = valid_legacy_tx()
      # Create a signed tx with invalid signature components
      bad_signed = SignedTransaction.new(tx, 27, 0, 0)
      assert {:error, :invalid_signature} == TxValidator.validate_for_mempool(bad_signed)
    end

    test "gas too low fails" do
      tx = %Transaction.Legacy{
        nonce: 0,
        gas_price: 1_000_000_000,
        gas_limit: 100,
        to: <<1::160>>,
        value: 0,
        data: <<>>
      }

      signed = sign_tx(tx)
      assert {:error, :gas_too_low} == TxValidator.validate_for_mempool(signed)
    end

    test "exceeds block gas limit fails" do
      signed = sign_tx(valid_legacy_tx())

      assert {:error, :exceeds_block_gas_limit} ==
               TxValidator.validate_for_mempool(signed, block_gas_limit: 10_000)
    end

    test "chain_id mismatch fails for typed transaction" do
      signed = sign_tx(valid_eip1559_tx())

      assert {:error, :chain_id_mismatch} ==
               TxValidator.validate_for_mempool(signed, chain_id: 42)
    end

    test "chain_id check is skipped for legacy transactions" do
      signed = sign_tx(valid_legacy_tx())
      assert :ok == TxValidator.validate_for_mempool(signed, chain_id: 42)
    end

    test "max_priority_fee > max_fee fails for EIP-1559" do
      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 3_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>,
        access_list: []
      }

      signed = sign_tx(tx)

      assert {:error, :priority_fee_exceeds_max_fee} ==
               TxValidator.validate_for_mempool(signed)
    end

    test "equal max_priority_fee and max_fee passes for EIP-1559" do
      tx = %Transaction.EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 2_000_000_000,
        max_fee_per_gas: 2_000_000_000,
        gas_limit: 21_000,
        to: <<1::160>>,
        value: 0,
        data: <<>>,
        access_list: []
      }

      signed = sign_tx(tx)
      assert :ok == TxValidator.validate_for_mempool(signed)
    end
  end
end
