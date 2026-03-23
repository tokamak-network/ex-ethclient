defmodule EthChain.WithdrawalProcessorTest do
  use ExUnit.Case, async: true

  alias EthChain.WithdrawalProcessor
  alias EthCore.Types.{Account, Withdrawal}

  @gwei_to_wei 1_000_000_000

  @address1 <<1::160>>
  @address2 <<2::160>>

  describe "process_withdrawals/2" do
    test "processes single withdrawal and adds to balance" do
      withdrawal = %Withdrawal{
        index: 0,
        validator_index: 100,
        address: @address1,
        amount: 32
      }

      existing = %{@address1 => %Account{nonce: 5, balance: 1000}}
      result = WithdrawalProcessor.process_withdrawals([withdrawal], existing)

      assert result[@address1].balance == 1000 + 32 * @gwei_to_wei
      assert result[@address1].nonce == 5
    end

    test "creates new account for withdrawal to nonexistent address" do
      withdrawal = %Withdrawal{
        index: 0,
        validator_index: 100,
        address: @address1,
        amount: 10
      }

      result = WithdrawalProcessor.process_withdrawals([withdrawal], %{})

      assert result[@address1].balance == 10 * @gwei_to_wei
      assert result[@address1].nonce == 0
    end

    test "converts amount from Gwei to Wei correctly" do
      withdrawal = %Withdrawal{
        index: 0,
        validator_index: 100,
        address: @address1,
        amount: 1
      }

      result = WithdrawalProcessor.process_withdrawals([withdrawal], %{})

      assert result[@address1].balance == @gwei_to_wei
    end

    test "empty withdrawals returns unchanged state" do
      state = %{@address1 => Account.new(500)}
      result = WithdrawalProcessor.process_withdrawals([], state)

      assert result == state
    end

    test "multiple withdrawals to same address sum correctly" do
      w1 = %Withdrawal{index: 0, validator_index: 100, address: @address1, amount: 10}
      w2 = %Withdrawal{index: 1, validator_index: 101, address: @address1, amount: 20}

      result = WithdrawalProcessor.process_withdrawals([w1, w2], %{})

      assert result[@address1].balance == 30 * @gwei_to_wei
    end

    test "multiple withdrawals to different addresses" do
      w1 = %Withdrawal{index: 0, validator_index: 100, address: @address1, amount: 10}
      w2 = %Withdrawal{index: 1, validator_index: 101, address: @address2, amount: 20}

      result = WithdrawalProcessor.process_withdrawals([w1, w2], %{})

      assert result[@address1].balance == 10 * @gwei_to_wei
      assert result[@address2].balance == 20 * @gwei_to_wei
    end
  end

  describe "to_account_updates/2" do
    test "returns updates only for changed accounts" do
      original = %{@address1 => Account.new(100)}

      updated = %{
        @address1 => %Account{nonce: 0, balance: 200},
        @address2 => Account.new(50)
      }

      updates = WithdrawalProcessor.to_account_updates(updated, original)

      assert Map.has_key?(updates, @address1)
      assert updates[@address1].balance == 200
      assert Map.has_key?(updates, @address2)
      assert updates[@address2].balance == 50
    end

    test "excludes unchanged accounts" do
      account = Account.new(100)
      original = %{@address1 => account}
      updated = %{@address1 => account}

      updates = WithdrawalProcessor.to_account_updates(updated, original)

      assert updates == %{}
    end
  end
end
