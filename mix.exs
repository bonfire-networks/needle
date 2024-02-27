Code.eval_file("mess.exs", (if File.exists?("../../lib/mix/mess.exs"), do: "../../lib/mix/"))

defmodule Needle.MixProject do
  use Mix.Project

  def project do
    if System.get_env("AS_UMBRELLA") == "1" do
      [
        build_path: "../../_build",
        config_path: "../../config/config.exs",
        deps_path: "../../deps",
        lockfile: "../../mix.lock"
      ]
    else
      []
    end ++
      [
        app: :needle,
        version: "0.7.1",
        elixir: "~> 1.10",
        elixirc_paths: elixirc_paths(Mix.env()),
        start_permanent: Mix.env() == :prod,
        description: "Universal foreign keys, virtual schemas, and shared data mixins",
        homepage_url: "https://github.com/bonfire-networks/needle",
        source_url: "https://github.com/bonfire-networks/needle",
        package: [
          licenses: ["Apache 2"],
          links: %{
            "Repository" => "https://github.com/bonfire-networks/needle",
            "Hexdocs" => "https://hexdocs.pm/needle"
          }
        ],
        docs: [
          # The first page to display from the docs
          main: "readme",
          # extra pages to include
          extras: ["README.md"]
        ],
        deps: deps()
      ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["test/support" | elixirc_paths(:dev)]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    Mess.deps([
      {:ecto_sql, "~> 3.8"},
      {:exto, "~> 0.3"},
      {:needle_ulid, "~> 0.3"},
      {:telemetry, "~> 0.4 or ~> 1.0", optional: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ])
  end
end
