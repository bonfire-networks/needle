defmodule Pointers.MixProject do
  use Mix.Project

  def project do
    [
      app: :pointers,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      description: "A maintained ULID datatype for Ecto",
      homepage_url: "https://github.com/commonspub/pointers_ulid",
      source_url: "https://github.com/commonspub/pointers_ulid",
      package: [
        licenses: ["Apache 2"],
        links: %{
          "Repository" => "https://github.com/commonspub/pointers_ulid",
          "Hexdocs" => "https://hexdocs.pm/pointers_ulid",
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

  defp deps do
    [
      {:pointers_ulid, "~> 0.2"},
      {:ecto_sql, "~> 3.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
    ]
  end
end
