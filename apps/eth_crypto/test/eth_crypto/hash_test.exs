defmodule EthCrypto.HashTest do
  use ExUnit.Case, async: true

  alias EthCrypto.Hash

  describe "keccak256/1" do
    test "empty string produces known hash" do
      # Widely known Ethereum empty-account code hash
      expected =
        Base.decode16!(
          "C5D2460186F7233C927E7DB2DCC703C0E500B653CA82273B7BFAD8045D85A470",
          case: :upper
        )

      assert Hash.keccak256("") == expected
    end

    test "hello world produces known hash" do
      expected =
        Base.decode16!(
          "47173285A8D7341E5E972FC677286384F802F8EF42A5EC5F03BBFA254CB01FAD",
          case: :upper
        )

      assert Hash.keccak256("hello world") == expected
    end

    test "always returns 32 bytes" do
      for input <- ["", "a", "abc", String.duplicate("x", 1000)] do
        result = Hash.keccak256(input)
        assert byte_size(result) == 32
      end
    end

    test "deterministic: same input always produces same output" do
      input = :crypto.strong_rand_bytes(64)
      assert Hash.keccak256(input) == Hash.keccak256(input)
    end

    test "different inputs produce different outputs" do
      refute Hash.keccak256("a") == Hash.keccak256("b")
    end
  end
end
