defmodule Pointers.MixProject do
  use Mix.Project

  def project do
    [
      app: :pointers,
      version: "0.3.2",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      description: "Ecto's missing universal foreign key",
      homepage_url: "https://github.com/commonspub/pointers",
      source_url: "https://github.com/commonspub/pointers",
      package: [
        licenses: ["Apache 2"],
        links: %{
          "Repository" => "https://github.com/commonspub/pointers",
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

  defp deps do
    [
      {:ecto_sql, "~> 3.4"},
      {:flexto, "~> 0.1"},
      {:pointers_ulid, "~> 0.2"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
    ]
  end

end
