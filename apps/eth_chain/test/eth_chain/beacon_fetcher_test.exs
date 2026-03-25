defmodule EthChain.BeaconFetcherTest do
  use ExUnit.Case, async: true

  alias EthChain.BeaconFetcher

  describe "parse_hex_or_int/1" do
    test "parses hex string" do
      assert BeaconFetcher.parse_hex_or_int("0x1a") == 26
    end

    test "parses decimal string" do
      assert BeaconFetcher.parse_hex_or_int("42") == 42
    end

    test "passes through integer" do
      assert BeaconFetcher.parse_hex_or_int(100) == 100
    end

    test "returns 0 for nil" do
      assert BeaconFetcher.parse_hex_or_int(nil) == 0
    end

    test "parses large hex block number" do
      assert BeaconFetcher.parse_hex_or_int("0xf4240") == 1_000_000
    end
  end

  describe "parse_beacon_block/1" do
    test "extracts execution_payload from valid beacon block JSON" do
      payload = %{
        "block_number" => "0x1",
        "block_hash" => "0xabc",
        "parent_hash" => "0xdef",
        "transactions" => []
      }

      json =
        Jason.encode!(%{
          "data" => %{
            "message" => %{
              "slot" => "100",
              "body" => %{
                "execution_payload" => payload
              }
            }
          }
        })

      assert {:ok, 100, ^payload} = BeaconFetcher.parse_beacon_block(json)
    end

    test "returns error when no execution_payload is present" do
      json =
        Jason.encode!(%{
          "data" => %{
            "message" => %{
              "slot" => "100",
              "body" => %{}
            }
          }
        })

      assert {:error, :no_execution_payload} = BeaconFetcher.parse_beacon_block(json)
    end

    test "returns error for unexpected JSON format" do
      json = Jason.encode!(%{"unexpected" => "format"})
      assert {:error, :unexpected_format} = BeaconFetcher.parse_beacon_block(json)
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode, _}} = BeaconFetcher.parse_beacon_block("not json")
    end

    test "handles integer slot values" do
      payload = %{"block_number" => "1", "block_hash" => "0xabc"}

      json =
        Jason.encode!(%{
          "data" => %{
            "message" => %{
              "slot" => "42",
              "body" => %{
                "execution_payload" => payload
              }
            }
          }
        })

      assert {:ok, 42, _} = BeaconFetcher.parse_beacon_block(json)
    end
  end

  describe "get_execution_payload/1" do
    test "finds execution_payload at top level" do
      body = %{"execution_payload" => %{"block_number" => "1"}}
      assert %{"block_number" => "1"} = BeaconFetcher.get_execution_payload(body)
    end

    test "falls back to execution_payload_header" do
      body = %{"execution_payload_header" => %{"block_number" => "2"}}
      assert %{"block_number" => "2"} = BeaconFetcher.get_execution_payload(body)
    end

    test "returns nil when neither present" do
      assert nil == BeaconFetcher.get_execution_payload(%{})
    end
  end

  describe "start_link/1 and status/0" do
    test "starts and returns initial status" do
      {:ok, pid} = BeaconFetcher.start_link(endpoint: "http://localhost:9999", network: :sepolia)

      status = BeaconFetcher.status()

      assert status.last_slot == 0
      assert status.last_block_number == 0
      assert status.endpoint == "http://localhost:9999"
      assert status.network == :sepolia
      assert status.errors == 0
      assert status.running == true

      GenServer.stop(pid)
    end
  end
end
