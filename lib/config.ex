defmodule Pointers.Config do
  @moduledoc false

  def pointer_table(),
    do: Keyword.get(config(), :pointer_table, "pointers_pointer")

  def table_table(),
    do: Keyword.get(config(), :table_table, "pointers_table")

  def trigger_function(),
    do: Keyword.get(config(), :trigger_function, "pointers_trigger")

  def trigger_prefix(),
    do: Keyword.get(config(), :trigger_prefix, "pointers_trigger_")

  defp config(), do: Application.get_all_env(:pointers)

end
