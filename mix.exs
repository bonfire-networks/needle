defmodule Pointers.MixProject do
  use Mix.Project

  def project do
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
          "Hexdocs" => "https://hexdocs.pm/pointers",
        },
      ],
      docs: [
        main: "readme", # The first page to display from the docs
        extras: ["README.md"], # extra pages to include
      ],
      deps: deps(),
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
    [
      {:ecto_sql, "~> 3.4"},
      {:flexto, "~> 0.2.3"},
      {:pointers_ulid, "~> 0.2"},
      {:telemetry, "~> 0.4 or ~> 1.0", optional: false, override: true},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
    ]
  end

end
