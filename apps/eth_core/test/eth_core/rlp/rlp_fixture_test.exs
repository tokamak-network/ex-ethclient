defmodule EthCore.RLP.FixtureTest do
  use ExUnit.Case, async: true

  alias EthCore.Test.FixtureLoader

  @valid_tests FixtureLoader.load_rlp_tests()
  @invalid_tests FixtureLoader.load_invalid_rlp_tests()

  describe "ethereum/tests rlptest.json encode" do
    for {name, %{"in" => input, "out" => expected_hex}} <- @valid_tests do
      @tag_name name
      @tag_input input
      @tag_expected expected_hex

      test "encode #{name}" do
        expected_bytes = decode_hex(@tag_expected)
        elixir_input = convert_input(@tag_input)
        encoded = ExRLP.encode(elixir_input)
        assert encoded == expected_bytes
      end
    end
  end

  describe "ethereum/tests rlptest.json decode" do
    for {name, %{"in" => input, "out" => expected_hex}} <- @valid_tests do
      @tag_name name
      @tag_input input
      @tag_expected expected_hex

      test "decode #{name}" do
        rlp_bytes = decode_hex(@tag_expected)
        expected_elixir = convert_input(@tag_input)
        decoded = ExRLP.decode(rlp_bytes)
        normalized_expected = normalize_decoded(expected_elixir)
        assert decoded == normalized_expected
      end
    end
  end

  describe "ethereum/tests rlptest.json roundtrip" do
    for {name, %{"in" => input}} <- @valid_tests do
      @tag_name name
      @tag_input input

      test "roundtrip #{name}" do
        elixir_input = convert_input(@tag_input)
        encoded = ExRLP.encode(elixir_input)
        decoded = ExRLP.decode(encoded)
        normalized = normalize_decoded(elixir_input)
        assert decoded == normalized
      end
    end
  end

  describe "ethereum/tests invalidRLPTest.json" do
    for {name, %{"out" => hex}} <- @invalid_tests do
      @tag_hex hex

      test "invalid #{name}" do
        rlp_bytes = decode_hex(@tag_hex)

        assert_raise ExRLP.DecodeError, fn ->
          ExRLP.decode(rlp_bytes)
        end
      end
    end
  end

  describe "specific RLP encoding cases" do
    test "empty string encodes to 0x80" do
      assert ExRLP.encode("") == <<0x80>>
    end

    test "single byte 0x00 encodes to 0x00" do
      assert ExRLP.encode(<<0x00>>) == <<0x00>>
    end

    test "'dog' encodes to 0x83646f67" do
      assert ExRLP.encode("dog") == <<0x83, 0x64, 0x6F, 0x67>>
    end

    test "empty list encodes to 0xc0" do
      assert ExRLP.encode([]) == <<0xC0>>
    end

    test "integer 1 encodes to 0x01" do
      assert ExRLP.encode(<<1>>) == <<0x01>>
    end

    test "integer 128 encodes to 0x8180" do
      assert ExRLP.encode(<<128>>) == <<0x81, 0x80>>
    end

    test "nested empty lists" do
      # [[[], []], []] from listsoflists fixture
      assert ExRLP.encode([[[], []], []]) == <<0xC4, 0xC2, 0xC0, 0xC0, 0xC0>>
    end

    test "string list" do
      assert ExRLP.encode(["dog", "god", "cat"]) ==
               <<0xCC, 0x83, 0x64, 0x6F, 0x67, 0x83, 0x67, 0x6F, 0x64, 0x83, 0x63, 0x61, 0x74>>
    end
  end

  # --- Helpers ---

  defp decode_hex(""), do: <<>>
  defp decode_hex("0x" <> hex), do: Base.decode16!(hex, case: :mixed)
  defp decode_hex(hex), do: Base.decode16!(hex, case: :mixed)

  defp convert_input(input) when is_binary(input) do
    case input do
      "#" <> big_int_str ->
        int_to_binary(String.to_integer(big_int_str))

      _ ->
        input
    end
  end

  defp convert_input(input) when is_integer(input) and input == 0, do: ""
  defp convert_input(input) when is_integer(input), do: int_to_binary(input)
  defp convert_input(input) when is_list(input), do: Enum.map(input, &convert_input/1)

  defp int_to_binary(0), do: ""

  defp int_to_binary(n) when is_integer(n) and n > 0 do
    :binary.encode_unsigned(n)
  end

  defp normalize_decoded(value) when is_binary(value), do: value
  defp normalize_decoded(value) when is_list(value), do: Enum.map(value, &normalize_decoded/1)
end
