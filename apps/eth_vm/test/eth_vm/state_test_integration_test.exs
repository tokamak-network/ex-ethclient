defmodule EthVm.StateTestIntegrationTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :ethereum_tests

  @fixtures_dir Path.join([__DIR__, "..", "fixtures", "ethereum-tests"])

  describe "GeneralStateTests" do
    @tag :ethereum_tests
    test "runs representative stTransfer tests" do
      check_fixtures_available!()

      test_dir = Path.join(@fixtures_dir, "GeneralStateTests/stTransactionTest")

      if File.dir?(test_dir) do
        run_fixture_dir(test_dir)
      else
        # Try a single known test file
        alt_path = Path.join(@fixtures_dir, "GeneralStateTests/stExample/add11.json")

        if File.exists?(alt_path) do
          run_fixture_file(alt_path)
        else
          IO.puts("No stTransactionTest or stExample fixtures found, skipping")
        end
      end
    end

    @tag :ethereum_tests
    test "runs stCallCodes tests if available" do
      check_fixtures_available!()

      test_dir = Path.join(@fixtures_dir, "GeneralStateTests/stCallCodes")

      if File.dir?(test_dir) do
        run_fixture_dir(test_dir, max_files: 5)
      else
        IO.puts("stCallCodes fixtures not found, skipping")
      end
    end

    @tag :ethereum_tests
    test "runs stExample tests if available" do
      check_fixtures_available!()

      test_dir = Path.join(@fixtures_dir, "GeneralStateTests/stExample")

      if File.dir?(test_dir) do
        run_fixture_dir(test_dir)
      else
        IO.puts("stExample fixtures not found, skipping")
      end
    end

    @tag :ethereum_tests
    test "runs stPreCompiledContracts tests if available" do
      check_fixtures_available!()

      test_dir = Path.join(@fixtures_dir, "GeneralStateTests/stPreCompiledContracts")

      if File.dir?(test_dir) do
        run_fixture_dir(test_dir, max_files: 5)
      else
        IO.puts("stPreCompiledContracts fixtures not found, skipping")
      end
    end

    @tag :ethereum_tests
    test "runs a single fixture file from path" do
      check_fixtures_available!()

      # Find any .json file to test with
      case find_first_fixture() do
        nil ->
          IO.puts("No fixture files found")

        path ->
          run_fixture_file(path)
      end
    end
  end

  # --- Helpers ---

  defp check_fixtures_available! do
    unless File.dir?(@fixtures_dir) do
      flunk("""
      Ethereum test fixtures not found at:
        #{@fixtures_dir}

      To download them:
        cd apps/eth_vm/test/fixtures
        git clone https://github.com/ethereum/tests.git ethereum-tests

      Or to skip these tests:
        mix test --exclude ethereum_tests
      """)
    end
  end

  defp run_fixture_dir(dir, opts \\ []) do
    max_files = Keyword.get(opts, :max_files, 20)

    files =
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.sort()
      |> Enum.take(max_files)

    assert length(files) > 0, "No .json files found in #{dir}"

    results =
      Enum.flat_map(files, fn file ->
        path = Path.join(dir, file)

        case EthVm.StateTestRunner.run_file(path, fork: "Shanghai") do
          {:ok, file_results} ->
            file_results

          {:error, reason} ->
            [%{status: :fail, error: reason, test_name: file, fork: "Shanghai", index: 0}]
        end
      end)

    summary = EthVm.StateTestRunner.format_summary(results)
    IO.puts("\n#{Path.basename(dir)}: #{summary}")

    passed = Enum.count(results, &(&1.status == :pass))
    total = length(results)
    IO.puts("  Pass rate: #{passed}/#{total}")
  end

  defp run_fixture_file(path) do
    assert File.exists?(path), "Fixture file not found: #{path}"

    case EthVm.StateTestRunner.run_file(path, fork: "Shanghai") do
      {:ok, results} ->
        summary = EthVm.StateTestRunner.format_summary(results)
        IO.puts("\n#{Path.basename(path)}: #{summary}")

      {:error, reason} ->
        IO.puts("Error running #{Path.basename(path)}: #{inspect(reason)}")
    end
  end

  defp find_first_fixture do
    gst_dir = Path.join(@fixtures_dir, "GeneralStateTests")

    if File.dir?(gst_dir) do
      gst_dir
      |> File.ls!()
      |> Enum.sort()
      |> Enum.find_value(fn subdir ->
        full = Path.join(gst_dir, subdir)

        if File.dir?(full) do
          full
          |> File.ls!()
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.sort()
          |> List.first()
          |> case do
            nil -> nil
            file -> Path.join(full, file)
          end
        end
      end)
    end
  end
end
