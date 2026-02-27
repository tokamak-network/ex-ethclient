defmodule EthCrypto.HashTest do
  use ExUnit.Case, async: true

  alias EthCrypto.Hash

  describe "keccak256/1" do
    test "empty input" do
      # Well-known: keccak256("") = c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470
      expected =
        Base.decode16!("C5D2460186F7233C927E7DB2DCC703C0E500B653CA82273B7BFAD8045D85A470",
          case: :upper
        )

      assert Hash.keccak256(<<>>) == expected
    end

    test "known test vector: 'hello'" do
      # keccak256("hello") = 1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8
      expected =
        Base.decode16!("1C8AFF950685C2ED4BC3174F3472287B56D9517B9C948127319A09A7A36DEAC8",
          case: :upper
        )

      assert Hash.keccak256("hello") == expected
    end

    test "returns 32 bytes" do
      result = Hash.keccak256("test data")
      assert byte_size(result) == 32
    end

    test "deterministic" do
      assert Hash.keccak256("abc") == Hash.keccak256("abc")
    end

    test "different inputs produce different hashes" do
      refute Hash.keccak256("a") == Hash.keccak256("b")
    end
  end
end
