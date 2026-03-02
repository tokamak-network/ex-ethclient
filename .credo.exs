%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/fixtures/"]
      },
      strict: true,
      checks: %{
        enabled: [
          {Credo.Check.Readability.ModuleDoc, false}
        ]
      }
    }
  ]
}
