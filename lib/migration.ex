defmodule Pointers.Migration do
  @moduledoc """
  Migration helpers for creating tables that participate in the pointers abasction.
  """

  import Ecto.Query, only: [from: 2]
  import Ecto.Migration
  alias Pointers.Config
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

  @spec add_pointer_ref_pk() :: nil
  def add_pointer_ref_pk(),
    do: add(:id, references(Config.pointer_table(), type: :uuid), primary_key: true)

  @doc "Creates a pointable table along with its trigger."
  @spec create_pointable_table(name :: binary, id :: binary, body :: term) :: term
  @spec create_pointable_table(name :: binary, id :: binary, opts :: Keyword.t, body :: term) :: term
  defmacro create_pointable_table(name, id, opts \\ [], body) do
    Pointers.ULID.cast!(id)
    opts = [primary_key: false] ++ opts
    quote do
      Pointers.Migration.insert_table_record(unquote(id), unquote(name))
      table = Ecto.Migration.table(unquote(name), unquote(opts))
      Ecto.Migration.create_if_not_exists table do
        Pointers.Migration.add_pointer_pk()
        unquote(body)
      end
      Pointers.Migration.create_pointer_trigger(unquote(name))
    end
  end

  @doc "Drops a pointable table"
  @spec drop_pointable_table(name :: binary, id :: binary) :: nil
  def drop_pointable_table(name, id) do
    drop_pointer_trigger(name)
    delete_table_record(id)
    drop_if_exists table(name)
  end

  @doc "Creates a trait table - one with a ULID primary key and no trigger"
  defmacro create_trait_table(name, opts \\ [], body) do
    opts = [primary_key: false] ++ opts
    quote do
      table = Ecto.Migration.table(unquote(name), unquote(opts))
      Ecto.Migration.create_if_not_exists table do
        Pointers.Migration.add_pointer_ref_pk()
        unquote(body)
      end
    end
  end

  @doc "Drops a trait table. Actually just drop_if_exists table(name)"
  @spec drop_trait_table(name :: binary) :: nil
  def drop_trait_table(name), do: drop_if_exists table(name)

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
    create_if_not_exists table(Config.table_table(), primary_key: false) do
      add_pointer_pk()
      add :table, :text, null: false
    end
    create_if_not_exists table(Config.pointer_table(), primary_key: false) do
      add_pointer_pk()
      ref = references Config.table_table(),
        on_delete: :delete_all, on_update: :update_all, type: :uuid
      add :table_id, ref, null: false
    end
    create_if_not_exists unique_index(Config.table_table(), :table)
    create_if_not_exists index(Config.pointer_table(), :table_id)
    flush()
    insert_table_record(Table.table_id(), Config.table_table())
    create_pointer_trigger_function()
    flush()
    create_pointer_trigger(Config.table_table())
  end

  def init_pointers(:down) do
    drop_pointer_trigger(Config.table_table())
    drop_pointer_trigger_function()
    drop_if_exists index(:pointers_pointer, :table_id)
    drop_if_exists index(:pointers_table, :table)
    drop_if_exists table(:pointers_pointer)
    drop_if_exists table(:pointers_table)
  end

  @doc false
  def create_pointer_trigger_function() do
    :ok = execute """
    create or replace function #{Config.trigger_function()}() returns trigger as $$
    declare table_id uuid;
    begin
      select id into table_id from #{Config.table_table()}
        where #{Config.table_table()}.table = TG_TABLE_NAME;
      if table_id is null then
        raise exception 'Table % does not participate in the pointers abstraction', TG_TABLE_NAME;
      end if;
      insert into #{Config.pointer_table()} (id, table_id) values (NEW.id, table_id)
      on conflict do nothing;
      return NEW;
    end;
    $$ language plpgsql
    """
  end

  @doc false
  def drop_pointer_trigger_function() do
    execute "drop function if exists #{Config.trigger_function()}()"
  end

  @doc false
  def create_pointer_trigger(table) do
    table = table_name(table)
    drop_pointer_trigger(table) # because there is no create trigger if not exists
    execute """
    create trigger "#{Config.trigger_prefix()}#{table}"
    before insert on "#{table}"
    for each row
    execute procedure #{Config.trigger_function()}()
    """
  end

  @doc false
  def drop_pointer_trigger(table) do
    table = table_name(table)
    execute """
    drop trigger if exists"#{Config.trigger_prefix()}#{table}" on "#{table}"
    """
  end

  #Insert a Table record. Not required when using `create_pointable_table`
  @doc false
  def insert_table_record(id, name) do
    id = Pointers.ULID.cast!(id)
    name = table_name(name)
    opts = [on_conflict: [set: [id: id]], conflict_target: [:table]]
    repo().insert_all(Pointers.Table, [%{id: id, table: name}], opts)
  end

  #Delete a Table record. Not required when using `drop_pointable_table`
  @doc false
  def delete_table_record(id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    repo().delete_all(from t in Config.table_table(), where: t.id == ^id)
  end

end
