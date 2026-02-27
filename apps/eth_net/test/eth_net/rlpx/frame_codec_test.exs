defmodule EthNet.RLPx.FrameCodecTest do
  use ExUnit.Case, async: true

  alias EthNet.RLPx.{FrameCodec, Handshake}

  setup do
    # Perform a full handshake to get session secrets
    init_priv = EthCrypto.Signature.generate_private_key()
    {:ok, init_pub} = EthCrypto.Signature.public_key_from_private(init_priv)
    resp_priv = EthCrypto.Signature.generate_private_key()
    {:ok, resp_pub} = EthCrypto.Signature.public_key_from_private(resp_priv)

    init_state = Handshake.initiator(init_priv, init_pub, resp_pub)
    {:ok, auth_msg, init_state} = Handshake.build_auth(init_state)
    {:ok, resp_state} = Handshake.read_auth(auth_msg, resp_priv, resp_pub)
    {:ok, ack_msg, resp_state} = Handshake.build_ack(resp_state)
    {:ok, init_state} = Handshake.read_ack(ack_msg, init_state)

    {:ok, init_secrets} = Handshake.derive_secrets(init_state)
    {:ok, resp_secrets} = Handshake.derive_secrets(resp_state)

    init_codec = FrameCodec.init(init_secrets)
    resp_codec = FrameCodec.init(resp_secrets)

    %{init_codec: init_codec, resp_codec: resp_codec}
  end

  test "encode/decode roundtrip", %{init_codec: init_codec, resp_codec: resp_codec} do
    payload = "hello ethereum"
    {:ok, frame, _init_codec} = FrameCodec.encode(init_codec, 0x00, payload)

    assert {:ok, msg_code, decoded_payload, <<>>, _resp_codec} =
             FrameCodec.decode(resp_codec, frame)

    assert msg_code == 0x00
    assert decoded_payload == payload
  end

  test "multiple frames maintain counter state", %{init_codec: init_codec, resp_codec: resp_codec} do
    {:ok, frame1, init_codec} = FrameCodec.encode(init_codec, 0x00, "message 1")
    {:ok, frame2, _init_codec} = FrameCodec.encode(init_codec, 0x01, "message 2")

    {:ok, 0x00, "message 1", <<>>, resp_codec} = FrameCodec.decode(resp_codec, frame1)
    {:ok, 0x01, "message 2", <<>>, _resp_codec} = FrameCodec.decode(resp_codec, frame2)
  end

  test "empty payload", %{init_codec: init_codec, resp_codec: resp_codec} do
    {:ok, frame, _init_codec} = FrameCodec.encode(init_codec, 0x10, <<>>)

    assert {:ok, 0x10, <<>>, <<>>, _resp_codec} = FrameCodec.decode(resp_codec, frame)
  end

  test "rejects tampered frame", %{init_codec: init_codec, resp_codec: resp_codec} do
    {:ok, frame, _init_codec} = FrameCodec.encode(init_codec, 0x00, "secret")

    # Tamper with header ciphertext
    <<byte, rest::binary>> = frame
    tampered = <<Bitwise.bxor(byte, 0xFF)>> <> rest

    assert {:error, :invalid_header_mac} = FrameCodec.decode(resp_codec, tampered)
  end
end
