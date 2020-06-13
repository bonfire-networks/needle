defmodule Pointers.Migration do
  @moduledoc """
  Migration helpers for creating tables that participate in the pointers abasction.
  """

  import Pointers.MixProject
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
    create_if_not_exists table(schema_pointers_table(), primary_key: false) do
      add_pointer_pk()
      add :table, :text, null: false
    end
    create_if_not_exists table(schema_pointers(), primary_key: false) do
      add_pointer_pk()
      add :table_id, references(schema_pointers_table(), on_delete: :delete_all, on_update: :update_all, type: :uuid), null: false
    end
    create_if_not_exists unique_index(schema_pointers_table(), :table)
    create_if_not_exists index(schema_pointers(), :table_id)
    flush()
    drop_main_pointer_trigger_function() # workaround for pre-existing pointers/triggers
    drop_pointer_trigger(schema_pointers_table())
    flush()
    insert_table_record(Table.table_id(), schema_pointers_table())
    flush()
    create_main_pointer_trigger_function()
    flush()
    create_pointer_trigger(schema_pointers_table()) 
    flush()
  end

  def init_pointers(:down) do
    drop_pointer_trigger(schema_pointers_table())
    drop_main_pointer_trigger_function()
    flush()
    drop_if_exists index(schema_pointers(), :table_id)
    drop_if_exists index(schema_pointers_table(), :table)
    drop_if_exists table(schema_pointers())
    drop_if_exists table(schema_pointers_table())
  end

  @doc "Special function to run if upgrading an old schema with pointers to this pointers lib"
  def upgrade_table_key(:up) do
    drop(constraint(schema_pointers(), "mn_pointer_table_id_fkey"))
  
    alter table(schema_pointers()) do
      modify(:table_id, references(schema_pointers_table(), on_delete: :delete_all, on_update: :update_all, type: :uuid), null: false)
    end
  end
  
  defp create_main_pointer_trigger_function() do
    table_name = table_name(schema_pointers_table())
    pointers_name = table_name(schema_pointers())
    :ok = execute """
    create or replace function insert_pointer() returns trigger as $$
    declare table_id uuid;
    begin
      select id into table_id from #{table_name} where #{table_name}.table = TG_TABLE_NAME;
      if table_id is null then
        raise exception 'Table % does not participate in the pointers abstraction', TG_TABLE_NAME;
      end if;
      insert into #{pointers_name} (id, table_id) values (NEW.id, table_id);
      return NEW;
    end;
    $$ language plpgsql
    """
  end

  @doc false
  def drop_main_pointer_trigger_function() do
    execute """
    drop function if exists insert_pointer() cascade
    """
  end

  @doc false
  def create_pointer_trigger(table) do
    table = table_name(table)
    execute """
    create trigger "insert_pointer_#{table}"
    before insert on "#{table}"
    for each row
    execute procedure insert_pointer()
    """
  end

  @doc false
  def drop_pointer_trigger(table) do
    table = table_name(table)
    execute """
    drop trigger if exists "insert_pointer_#{table}" on "#{table}"
    """
  end

  @doc "Insert a Table record. Not required when using `create_pointable_table`"
  def insert_table_record(id, name) do
    cast_id = Pointers.ULID.cast!(id)
    # {:ok, ulid_id} = Pointers.ULID.dump(cast_id)
    # {:ok, table_id} = Ecto.UUID.load(ulid_id)
    table_name = table_name(name)
    pointers_name = table_name(schema_pointers())
    
    repo().insert_all(Pointers.Table, [%{id: cast_id, table: table_name}], on_conflict: [set: [id: cast_id]], conflict_target: [:table])
    # repo().query("INSERT INTO #{pointers_name} AS m0 (id,table) VALUES ($1,$2) ON CONFLICT (table) DO UPDATE SET id = $1", [cast_id, name])
  end

  @doc "Delete a Table record. Not required when using `drop_pointable_table`"
  def delete_table_record(id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    repo().delete_all(from t in schema_pointers_table(), where: t.id == ^id)
  end

end
