defmodule Stamp.MixProject do
  use Mix.Project

  @source_url "https://github.com/a3kov/stamp"

  def project do
    [
      app: :stamp,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: @source_url,
      # Hex
      description: "Fast and flexible Snowflake-flavored ID generator",
      package: [
        files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE),
        licenses: ["Apache-2.0"],
        links: %{
          "GitHub" => @source_url,
          "Changelog" => "https://hexdocs.pm/stamp/changelog.html"
        }
      ],
      # Docs
      docs: [
        main: "readme",
        extras: ["README.md", "CHANGELOG.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 1.4"},
      {:based_integers, "~> 0.1"},
      {:ecto_sql, "~> 3.0", optional: true},
      {:benchee, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.40.3", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end
end
