Code.eval_file("mess.exs", (if File.exists?("../../lib/mix/mess.exs"), do: "../../lib/mix/"))

defmodule Pointers.MixProject do
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
    end
    ++
    [
      app: :pointers,
      version: "0.6.0",
      elixir: "~> 1.10",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: "Ecto's missing universal foreign key",
      homepage_url: "https://github.com/bonfire-networks/pointers",
      source_url: "https://github.com/bonfire-networks/pointers",
      package: [
        licenses: ["Apache 2"],
        links: %{
          "Repository" => "https://github.com/bonfire-networks/pointers",
          "Hexdocs" => "https://hexdocs.pm/pointers"
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
    Mess.deps [
      {:ecto_sql, "~> 3.8"},
      {:flexto, "~> 0.2.3"},
      {:pointers_ulid, "~> 0.2"},
      {:telemetry, "~> 0.4 or ~> 1.0", optional: false, override: true},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
