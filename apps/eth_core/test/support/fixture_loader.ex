defmodule EthCore.Test.FixtureLoader do
  @fixtures_path Path.join([__DIR__, "..", "..", "..", "..", "fixtures", "ethereum-tests"])

  def fixtures_path, do: @fixtures_path

  def load_rlp_tests do
    load_json("RLPTests/rlptest.json")
  end

  def load_invalid_rlp_tests do
    load_json("RLPTests/invalidRLPTest.json")
  end

  def load_transaction_tests(subdir) do
    dir = Path.join([@fixtures_path, "TransactionTests", subdir])

    dir
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".json"))
    |> Enum.flat_map(fn file ->
      data = dir |> Path.join(file) |> File.read!() |> Jason.decode!()

      Enum.map(data, fn {name, test_data} ->
        {file <> "/" <> name, test_data}
      end)
    end)
  end

  defp load_json(relative_path) do
    @fixtures_path
    |> Path.join(relative_path)
    |> File.read!()
    |> Jason.decode!()
  end
end
