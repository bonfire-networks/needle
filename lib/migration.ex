defmodule Pointers.Migration do
  @moduledoc """
  Migration helpers for creating tables that participate in the pointers abasction.
  """

  import Ecto.Query, only: [from: 2]
  import Ecto.Migration
  alias Pointers.Table

  defdelegate init_pointers_ulid_extra(), to: Pointers.ULID.Migration

  defp table_name(name) when is_atom(name), do: Atom.to_string(name)
  defp table_name(name) when is_binary(name), do: name

  @doc """
  Adds a pointer primary key to the table.
  Not required if you are using `create_pointable_table`
  """
  @spec add_pointer_pk() :: nil
  def add_pointer_pk(), do: add(:id, :uuid, primary_key: true)

  @doc "Creates a pointable table along with its trigger."
  @spec create_pointable_table(name :: binary, id :: binary, body :: term) :: term
  @spec create_pointable_table(name :: binary, id :: binary, opts :: Keyword.t, body :: term) :: term
  defmacro create_pointable_table(name, id, opts \\ [], body) do
    Pointers.ULID.cast!(id)
    opts = [primary_key: false] ++ opts
    quote do
      Pointers.Migration.insert_table_record(unquote(id), unquote(name))
      Ecto.Migration.create_if_not_exists Ecto.Migration.table(unquote(name), unquote(opts)) do
        Pointers.Migration.add_pointer_pk()
        unquote(body)
      end
      Pointers.Migration.create_pointer_trigger(unquote(name))
    end
  end

  @doc "Drops a pointable table"
  @spec drop_pointable_table(name :: binary) :: nil
  def drop_pointable_table(name) do
    drop_pointer_trigger(name)
    delete_table_record(name)
    drop_if_exists table(name)
  end

  @doc """
  When migrating up: initialises the pointers database.
  When migrating down: deinitialises the pointers database.
  """
  @spec init_pointers() :: nil
  def init_pointers(), do: init_pointers(direction())

  @doc """
  Given `:up`: initialises the pointers database.
  Given `:down`: deinitialises the pointers database.
  """
  @spec init_pointers(direction :: :up | :down) :: nil
  def init_pointers(:up) do
    create table(:pointers_table, primary_key: false) do
      add_pointer_pk()
      add :table, :text, null: false
    end
    create table(:pointers_pointer, primary_key: false) do
      add_pointer_pk()
      add :table_id, references(:pointers_table, on_delete: :delete_all, type: :uuid), null: false
    end
    create unique_index(:pointers_table, :table)
    create index(:pointers_pointer, :table_id)
    flush()
    insert_table_record(Table.table_id(), :pointers_table)
    create_pointer_trigger_function()
    create_pointer_trigger(:pointers_table)
  end

  def init_pointers(:down) do
    drop_pointer_trigger(:pointers_table)
    :ok = execute "drop function backing_pointer_trigger()"
    drop_if_exists index(:pointers_pointer, :table_id)
    drop_if_exists index(:pointers_table, :table)
    drop_if_exists table(:pointers_pointer)
    drop_if_exists table(:pointers_table)
  end

  defp create_pointer_trigger_function() do
    :ok = execute """
    create or replace function backing_pointer_trigger() returns trigger as $$
    declare table_id uuid;
    begin
      select id into table_id from pointers_table where pointers_table.table = TG_TABLE_NAME;
      if table_id is null then
        raise exception 'Table % does not participate in the pointers abstraction', TG_TABLE_NAME;
      end if;
      insert into pointers_pointer (id, table_id) values (NEW.id, table_id);
      return NEW;
    end;
    $$ language plpgsql
    """
  end

  @doc false
  def create_pointer_trigger(table) do
    table = table_name(table)
    execute """
    create trigger "backing_pointer_trigger_#{table}"
    before insert on "#{table}"
    for each row
    execute procedure backing_pointer_trigger()
    """
  end

  @doc false
  def drop_pointer_trigger(table) do
    table = table_name(table)
    execute """
    drop trigger "backing_pointer_trigger_#{table}" on "#{table}"
    """
  end

  @doc "Insert a Table record. Not required when using `create_pointable_table`"
  def insert_table_record(id, name) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    name = table_name(name)
    repo().insert_all("pointers_table", [%{id: id, table: name}], on_conflict: :nothing)
  end

  @doc "Delete a Table record. Not required when using `drop_pointable_table`"
  def delete_table_record(id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    repo().delete_all(from t in "pointers_table", where: t.id == ^id)
  end

end
