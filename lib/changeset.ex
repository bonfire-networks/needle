defmodule Pointers.Changeset do

  alias Ecto.Changeset

  def valid?(%Changeset{valid?: v}), do: v
  def valid?(cs) when is_list(cs), do: Enum.all?(cs, &valid?/1)

  def relate(changeset, inserted, to_field \\ :id, from_field \\ :id)
  def relate(changeset, %_thing{}=inserted, to_field, from_field) do
    Changeset.change(changeset, [{to_field, Map.fetch(inserted, from_field)}])
  end

  def insert_related(repo, new, changeset, to_field \\ :id, from_field \\ :id)
  def insert_related(repo, %_thing{}=new, changeset, to_field, from_field) do
    with {:ok, cs} <- relate(new, changeset, from_field, to_field), do: repo.insert(cs)
  end

end
