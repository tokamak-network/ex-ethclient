defmodule EthNet.RLPx.HandshakeTest do
  use ExUnit.Case, async: true

  alias EthNet.RLPx.Handshake

  setup do
    # Initiator
    init_priv = EthCrypto.Signature.generate_private_key()
    {:ok, init_pub} = EthCrypto.Signature.public_key_from_private(init_priv)

    # Responder
    resp_priv = EthCrypto.Signature.generate_private_key()
    {:ok, resp_pub} = EthCrypto.Signature.public_key_from_private(resp_priv)

    %{
      init_priv: init_priv,
      init_pub: init_pub,
      resp_priv: resp_priv,
      resp_pub: resp_pub
    }
  end

  test "full handshake roundtrip", ctx do
    # Initiator creates auth
    init_state = Handshake.initiator(ctx.init_priv, ctx.init_pub, ctx.resp_pub)
    {:ok, auth_msg, init_state} = Handshake.build_auth(init_state)

    # Responder reads auth
    {:ok, resp_state} = Handshake.read_auth(auth_msg, ctx.resp_priv, ctx.resp_pub)
    assert resp_state.remote_public_key == ctx.init_pub

    # Responder creates ack
    {:ok, ack_msg, resp_state} = Handshake.build_ack(resp_state)

    # Initiator reads ack
    {:ok, init_state} = Handshake.read_ack(ack_msg, init_state)
    assert init_state.remote_ephemeral_public_key == resp_state.ephemeral_public_key

    # Both derive secrets
    {:ok, init_secrets} = Handshake.derive_secrets(init_state)
    {:ok, resp_secrets} = Handshake.derive_secrets(resp_state)

    # AES and MAC secrets should match
    assert init_secrets.aes_secret == resp_secrets.aes_secret
    assert init_secrets.mac_secret == resp_secrets.mac_secret
  end

  test "auth message has correct format", ctx do
    init_state = Handshake.initiator(ctx.init_priv, ctx.init_pub, ctx.resp_pub)
    {:ok, auth_msg, _state} = Handshake.build_auth(init_state)

    # Should start with 2-byte size prefix
    <<size::big-unsigned-16, rest::binary>> = auth_msg
    assert size == byte_size(rest)
  end

  test "ack message has correct format", ctx do
    init_state = Handshake.initiator(ctx.init_priv, ctx.init_pub, ctx.resp_pub)
    {:ok, auth_msg, _init_state} = Handshake.build_auth(init_state)
    {:ok, resp_state} = Handshake.read_auth(auth_msg, ctx.resp_priv, ctx.resp_pub)
    {:ok, ack_msg, _resp_state} = Handshake.build_ack(resp_state)

    <<size::big-unsigned-16, rest::binary>> = ack_msg
    assert size == byte_size(rest)
  end
end
