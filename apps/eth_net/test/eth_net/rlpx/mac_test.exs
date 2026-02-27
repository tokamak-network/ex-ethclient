defmodule EthNet.RLPx.MacTest do
  use ExUnit.Case, async: true

  alias EthNet.RLPx.Mac

  test "new creates empty MAC state" do
    secret = :crypto.strong_rand_bytes(32)
    mac = Mac.new(secret)
    assert mac.secret == secret
    assert mac.buffer == <<>>
  end

  test "update accumulates data" do
    secret = :crypto.strong_rand_bytes(32)
    mac = Mac.new(secret) |> Mac.update("hello") |> Mac.update(" world")
    assert mac.buffer == "hello world"
  end

  test "digest_16 returns 16 bytes" do
    secret = :crypto.strong_rand_bytes(32)
    mac = Mac.new(secret) |> Mac.update("test data")
    digest = Mac.digest_16(mac)
    assert byte_size(digest) == 16
  end

  test "compute returns 16-byte MAC and updated state" do
    secret = :crypto.strong_rand_bytes(32)
    mac = Mac.new(secret) |> Mac.update("initial seed")
    data = :crypto.strong_rand_bytes(16)

    {mac_value, updated_mac} = Mac.compute(mac, data)
    assert byte_size(mac_value) == 16
    assert updated_mac.buffer != mac.buffer
  end

  test "compute is deterministic for same input" do
    secret = :crypto.strong_rand_bytes(32)
    data = :crypto.strong_rand_bytes(16)

    mac1 = Mac.new(secret) |> Mac.update("seed")
    mac2 = Mac.new(secret) |> Mac.update("seed")

    {result1, _} = Mac.compute(mac1, data)
    {result2, _} = Mac.compute(mac2, data)

    assert result1 == result2
  end
end
