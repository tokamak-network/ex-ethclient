defmodule Mix.Tasks.EthTest.State do
  @moduledoc """
  Runs Ethereum GeneralStateTest fixtures against the EVM.

  ## Usage

      mix eth_test.state path/to/fixture.json
      mix eth_test.state path/to/directory/
      mix eth_test.state path/to/fixture.json --fork Shanghai
      mix eth_test.state path/to/directory/ --fork Cancun --verbose

  ## Options

    - `--fork` - Only run tests for a specific fork (e.g. Shanghai, Cancun)
    - `--verbose` - Print details for each test case
    - `--max-files` - Maximum number of files to process in a directory (default: unlimited)

  ## Fixture Download

  To get the official Ethereum test fixtures:

      cd apps/eth_vm/test/fixtures
      git clone https://github.com/ethereum/tests.git ethereum-tests

  Individual test suites are under `ethereum-tests/GeneralStateTests/`.
  """

  use Mix.Task

  @shortdoc "Run Ethereum GeneralStateTest fixtures"

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, paths, _} =
      OptionParser.parse(args,
        strict: [
          fork: :string,
          verbose: :boolean,
          max_files: :integer
        ]
      )

    if paths == [] do
      Mix.shell().error("Usage: mix eth_test.state <path> [--fork FORK] [--verbose]")
      exit({:shutdown, 1})
    end

    Mix.Task.run("app.start")

    runner_opts = build_runner_opts(opts)
    verbose = Keyword.get(opts, :verbose, false)

    all_results =
      Enum.flat_map(paths, fn path ->
        path = Path.expand(path)
        run_path(path, runner_opts, verbose, opts)
      end)

    print_final_summary(all_results)
  end

  @spec build_runner_opts(keyword()) :: keyword()
  defp build_runner_opts(opts) do
    runner_opts = []

    case Keyword.get(opts, :fork) do
      nil -> runner_opts
      fork -> Keyword.put(runner_opts, :fork, fork)
    end
  end

  @spec run_path(Path.t(), keyword(), boolean(), keyword()) :: [map()]
  defp run_path(path, runner_opts, verbose, opts) do
    cond do
      File.regular?(path) and String.ends_with?(path, ".json") ->
        run_single_file(path, runner_opts, verbose)

      File.dir?(path) ->
        run_dir(path, runner_opts, verbose, opts)

      true ->
        Mix.shell().error("Not a valid file or directory: #{path}")
        []
    end
  end

  @spec run_single_file(Path.t(), keyword(), boolean()) :: [map()]
  defp run_single_file(path, runner_opts, verbose) do
    Mix.shell().info("Running: #{Path.relative_to_cwd(path)}")

    case EthVm.StateTestRunner.run_file(path, runner_opts) do
      {:ok, results} ->
        if verbose, do: print_verbose_results(results)
        print_file_summary(path, results)
        results

      {:error, reason} ->
        Mix.shell().error("  Error: #{inspect(reason)}")
        []
    end
  end

  @spec run_dir(Path.t(), keyword(), boolean(), keyword()) :: [map()]
  defp run_dir(dir, runner_opts, verbose, opts) do
    max_files = Keyword.get(opts, :max_files)
    Mix.shell().info("Scanning: #{Path.relative_to_cwd(dir)}")

    files = collect_json_files(dir)

    files =
      if max_files do
        Enum.take(files, max_files)
      else
        files
      end

    Mix.shell().info("  Found #{length(files)} test file(s)")

    files
    |> Enum.flat_map(fn file ->
      run_single_file(file, runner_opts, verbose)
    end)
  end

  @spec collect_json_files(Path.t()) :: [Path.t()]
  defp collect_json_files(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        entries
        |> Enum.sort()
        |> Enum.flat_map(fn entry ->
          full = Path.join(dir, entry)

          cond do
            File.dir?(full) -> collect_json_files(full)
            String.ends_with?(entry, ".json") -> [full]
            true -> []
          end
        end)

      {:error, _} ->
        []
    end
  end

  @spec print_verbose_results([map()]) :: :ok
  defp print_verbose_results(results) do
    Enum.each(results, fn r ->
      status_str =
        case r.status do
          :pass -> "PASS"
          :fail -> "FAIL"
          :skip -> "SKIP"
        end

      Mix.shell().info("  #{status_str} #{r.test_name} [#{r.fork}##{r.index}]")

      if r.status == :fail do
        if r.expected_hash do
          Mix.shell().info("    expected: #{Base.encode16(r.expected_hash, case: :lower)}")
        end

        if r.actual_hash do
          Mix.shell().info("    actual:   #{Base.encode16(r.actual_hash, case: :lower)}")
        end

        if r.error do
          Mix.shell().info("    error:    #{inspect(r.error)}")
        end
      end
    end)

    :ok
  end

  @spec print_file_summary(Path.t(), [map()]) :: :ok
  defp print_file_summary(path, results) do
    passed = Enum.count(results, &(&1.status == :pass))
    failed = Enum.count(results, &(&1.status == :fail))
    skipped = Enum.count(results, &(&1.status == :skip))
    total = length(results)

    status =
      cond do
        failed > 0 -> "FAIL"
        total == 0 -> "EMPTY"
        true -> "OK"
      end

    Mix.shell().info(
      "  [#{status}] #{Path.basename(path)}: #{passed}/#{total} passed" <>
        if(failed > 0, do: ", #{failed} failed", else: "") <>
        if(skipped > 0, do: ", #{skipped} skipped", else: "")
    )

    :ok
  end

  @spec print_final_summary([map()]) :: :ok
  defp print_final_summary(results) do
    total = length(results)
    passed = Enum.count(results, &(&1.status == :pass))
    failed = Enum.count(results, &(&1.status == :fail))
    skipped = Enum.count(results, &(&1.status == :skip))

    Mix.shell().info("""

    ====================================
     Ethereum State Test Results
    ====================================
     Total:   #{total}
     Passed:  #{passed}
     Failed:  #{failed}
     Skipped: #{skipped}
     Rate:    #{if total > 0, do: Float.round(passed / total * 100, 1), else: 0.0}%
    ====================================
    """)

    if failed > 0 do
      exit({:shutdown, 1})
    end

    :ok
  end
end
