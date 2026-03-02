defmodule EthCore.Signer.SignerTest do
  use ExUnit.Case, async: true

  alias EthCore.Signer
  alias EthCore.Transaction.{Legacy, EIP1559, EIP2930, EIP4844, EIP7702}

  @cow_privkey Base.decode16!(
                 "c85ef7d79691fe79573b1a7064c19c1a9819ebdbd1faaab1a8ec92344438aaf4",
                 case: :lower
               )
  @cow_address Base.decode16!("cd2a3d9f938e13cd947ec05abc7fe734df8dd826", case: :lower)

  @to_address Base.decode16!("095e7baea6a6c7c4c2dfeb977efac326af552d87", case: :lower)

  describe "Legacy tx signing" do
    test "sign legacy tx and recover sender" do
      tx = %Legacy{
        nonce: 0,
        gas_price: 1,
        gas_limit: 21_000,
        to: @to_address,
        value: 0,
        data: ""
      }

      signed = Signer.sign_transaction(tx, @cow_privkey)
      assert signed.v != nil
      assert signed.r != nil
      assert signed.s != nil

      {:ok, sender} = Signer.recover_sender(signed)
      assert sender == @cow_address
    end

    test "legacy tx v=27 or v=28 (pre-EIP-155)" do
      tx = %Legacy{
        nonce: 0,
        gas_price: 1,
        gas_limit: 21_000,
        to: @to_address,
        value: 0,
        data: ""
      }

      signed = Signer.sign_transaction(tx, @cow_privkey)
      assert signed.v in [27, 28]
    end
  end

  describe "EIP-155 signing" do
    test "EIP-155 v = chain_id * 2 + 35 + recovery_id" do
      tx = %Legacy{
        nonce: 0,
        gas_price: 1,
        gas_limit: 21_000,
        to: @to_address,
        value: 0,
        data: ""
      }

      signed = Signer.sign_transaction(tx, @cow_privkey, chain_id: 1)
      # v should be 37 or 38 for chain_id=1
      assert signed.v in [37, 38]
    end

    test "EIP-155 sign and recover sender" do
      tx = %Legacy{
        nonce: 5,
        gas_price: 20_000_000_000,
        gas_limit: 21_000,
        to: @to_address,
        value: 1_000_000,
        data: ""
      }

      signed = Signer.sign_transaction(tx, @cow_privkey, chain_id: 1)
      {:ok, sender} = Signer.recover_sender(signed)
      assert sender == @cow_address
    end
  end

  describe "EIP-1559 tx signing" do
    test "sign and recover sender" do
      tx = %EIP1559{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1_000_000_000,
        max_fee_per_gas: 20_000_000_000,
        gas_limit: 21_000,
        to: @to_address,
        value: 0,
        data: "",
        access_list: []
      }

      signed = Signer.sign_transaction(tx, @cow_privkey)
      assert signed.v in [0, 1]

      {:ok, sender} = Signer.recover_sender(signed)
      assert sender == @cow_address
    end
  end

  describe "EIP-2930 tx signing" do
    test "sign and recover sender" do
      tx = %EIP2930{
        chain_id: 1,
        nonce: 0,
        gas_price: 1,
        gas_limit: 21_000,
        to: @to_address,
        value: 0,
        data: "",
        access_list: []
      }

      signed = Signer.sign_transaction(tx, @cow_privkey)
      {:ok, sender} = Signer.recover_sender(signed)
      assert sender == @cow_address
    end
  end

  describe "EIP-4844 tx signing" do
    test "sign and recover sender" do
      tx = %EIP4844{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 21_000,
        to: @to_address,
        value: 0,
        data: "",
        access_list: [],
        max_fee_per_blob_gas: 1000,
        blob_versioned_hashes: [<<0x01>> <> :crypto.strong_rand_bytes(31)]
      }

      signed = Signer.sign_transaction(tx, @cow_privkey)
      {:ok, sender} = Signer.recover_sender(signed)
      assert sender == @cow_address
    end
  end

  describe "EIP-7702 tx signing" do
    test "sign and recover sender" do
      tx = %EIP7702{
        chain_id: 1,
        nonce: 0,
        max_priority_fee_per_gas: 1,
        max_fee_per_gas: 100,
        gas_limit: 21_000,
        to: @to_address,
        value: 0,
        data: "",
        access_list: [],
        authorization_list: []
      }

      signed = Signer.sign_transaction(tx, @cow_privkey)
      {:ok, sender} = Signer.recover_sender(signed)
      assert sender == @cow_address
    end
  end

  describe "recover_sender from fixture" do
    test "recover sender from known legacy tx bytes" do
      # From ethereum/tests TransactionTests/ttValue/TransactionWithHighValue.json
      hex =
        "f87f800182520894095e7baea6a6c7c4c2dfeb977efac326af552d87a0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff801ba048b55bfa915ac795c431978d8a6a992b628d557da5ff759b307d495a36649353a01fffd310ac743f371de3b9f7f9cb56c0b28ad43601b4ab949f53faa07bd2c804"

      raw = Base.decode16!(hex, case: :lower)

      {:ok, tx} = Legacy.decode(raw)
      {:ok, sender} = Signer.recover_sender(tx)

      expected = Base.decode16!("8411b12666f68ef74cace3615c9d5a377729d03f", case: :lower)
      assert sender == expected
    end
  end
end
