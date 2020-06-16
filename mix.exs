defmodule Pointers.MixProject do
  use Mix.Project

  def project do
    [
      app: :pointers,
      version: "0.1.1-alpha",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
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
      {:pointers_ulid, ">= 0.2.0"},
      {:ecto_sql, "~> 3.4"},
      {:protocol_ex, "~> 0.4.3"},
    ]
  end

  @doc "helps make the table names configurable, though you also need to change this one in `lib/table.ex`"
  def schema_pointers_table do
    Application.get_env(:pointers, :schema_pointers_table, "pointers_table")
  end

  @doc "helps make the table names configurable, though you also need to change this one in `lib/table.ex`"
  def schema_pointers do
    Application.get_env(:pointers, :schema_pointers, "pointers")
  end

end
