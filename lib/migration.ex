defmodule Pointers.Migration do
  @moduledoc "Helpers for writing Pointer-aware migrations."

  import Ecto.Query, only: [from: 2]
  import Ecto.Migration
  alias Pointers.{Pointer, Table, ULID}

  defdelegate init_pointers_ulid_extra(), to: ULID.Migration

  @type pointer_type :: :strong | :weak | :unbreakable

  @doc "Creates a strong, weak or unbreakable pointer depending on `type`."
  @spec pointer(type :: pointer_type) :: term
  @spec pointer(module :: atom, type :: pointer_type) :: term
  def pointer(table \\ Pointer, type)
  def pointer(table, :strong), do: strong_pointer(table)
  def pointer(table, :weak), do: weak_pointer(table)
  def pointer(table, :unbreakable), do: unbreakable_pointer(table)

  @doc """
  A reference to a pointer for use with `add/3`. A strong pointer will
  be deleted when the thing it's pointing to is deleted.
  """
  def strong_pointer(table \\ Pointer) do
    references table.__schema__(:source),
      type: :uuid,
      on_update: :update_all,
      on_delete: :delete_all
  end

  @doc """
  A reference to a pointer for use with `add/3`. A weak pointer will
  be set null when the thing it's pointing to is deleted.
  """
  def weak_pointer(table \\ Pointer) do
    references table.__schema__(:source),
      type: :uuid,
      on_update: :update_all,
      on_delete: :nilify_all
  end

  @doc """
  A reference to a pointer for use with `add/3`. An unbreakable
  pointer will prevent the thing it's pointing to from being deleted.
  """
  def unbreakable_pointer(table \\ Pointer) do
    references table.__schema__(:source),
      type: :uuid,
      on_update: :update_all,
      on_delete: :restrict
  end

  defp table_name(name) when is_atom(name), do: Atom.to_string(name)
  defp table_name(name) when is_binary(name), do: name

  config = Application.get_env(:pointers, __MODULE__, [])
  @pointable_trigger_function Keyword.get(config, :trigger_function, "pointers_trigger")
  @trigger_prefix Keyword.get(config, :trigger_prefix, "pointers_trigger_")
  @virtual_trigger_function Keyword.get(config, :virtual_trigger_function, "pointers_virtual_trigger")

  @doc """
  Adds a pointer primary key to the table.
  Not required if you are using `create_pointable_table`
  """
  @spec add_pointer_pk() :: nil
  def add_pointer_pk(), do: add(:id, :uuid, primary_key: true)

  @spec add_pointer_ref_pk() :: nil
  def add_pointer_ref_pk(),
    do: add(:id, strong_pointer(Pointer), primary_key: true)

  @doc "Creates a pointable table along with its trigger."
  @spec create_pointable_table(schema :: atom, body :: term) :: term
  @spec create_pointable_table(schema :: atom, opts :: Keyword.t, body :: term) :: term
  @spec create_pointable_table(source :: binary, id :: binary, body :: term) :: term
  @spec create_pointable_table(source :: binary, id :: binary, opts :: Keyword.t, body :: term) :: term

  # if you're wondering why we expand these, it's so aliases are expanded and turned into atoms
  defmacro create_pointable_table(a, b) do
    {a, _} = eval_expand(a, __CALLER__)
    cpt(a, b)
  end
  defmacro create_pointable_table(a, b, c) do
    {a, _} = eval_expand(a, __CALLER__)
    {b, _} = eval_expand(b, __CALLER__)
    cpt(a, b, c)
  end
  defmacro create_pointable_table(a, b, c, d) do
    {a, _} = eval_expand(a, __CALLER__)
    {b, _} = eval_expand(b, __CALLER__)
    {c, _} = eval_expand(c, __CALLER__)
     cpt(a, b, c, d)
  end

  defp cpt(schema, body) when is_atom(schema) do
    source = schema.__schema__(:source)
    id = schema.__pointers__(:table_id)
    cpt(source, id, [], body)
  end
  defp cpt(schema, opts, body) when is_atom(schema) and is_list(opts) do
    source = schema.__schema__(:source)
    id = schema.__pointers__(:table_id)
    cpt(source, id, opts, body)
  end
  defp cpt(source, id, body) when is_binary(source) and is_binary(id) do
    cpt(source, id, [], body)
  end
  defp cpt(source, id, opts, body) when is_binary(source) and is_binary(id) and is_list(opts) do
    Pointers.ULID.cast!(id)
    opts = [primary_key: false] ++ opts
    quote do
      Pointers.Migration.insert_table_record(unquote(id), unquote(source))
      table = Ecto.Migration.table(unquote(source), unquote(opts))
      Ecto.Migration.create_if_not_exists table do
        Pointers.Migration.add_pointer_pk()
        unquote(body)
      end
      Pointers.Migration.create_pointer_trigger(unquote(source))
    end
  end

  def create_virtual(schema) when is_atom(schema) do
    source = schema.__schema__(:source)
    id = schema.__pointers__(:table_id)
    create_virtual(source, id)
  end

  def create_virtual(source, id) when is_binary(source) and is_binary(id) do
    {:ok, _} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    insert_table_record(id, source)
    create_virtual_view(source, id)
    create_virtual_trigger(source, id)
  end

  @doc "Drops a pointable table"
  @spec drop_pointable_table(schema :: atom) :: nil
  @spec drop_pointable_table(name :: binary, id :: binary) :: nil
  def drop_pointable_table(schema) when is_atom(schema) do
    source = schema.__schema__(:source)
    id = schema.__pointers__(:table_id)
    drop_pointable_table(source, id)
  end

  def drop_pointable_table(name, id) when is_binary(name) and is_binary(id) do
    Pointers.ULID.cast!(id)
    drop_pointer_trigger(name)
    drop_table(name)
    delete_table_record(id)
  end

  def drop_virtual(schema) when is_atom(schema) do
    source = schema.__schema__(:source)
    id = schema.__pointers__(:table_id)
    drop_virtual(source, id)
  end

  def drop_virtual(name, id) when is_binary(name) and is_binary(id) do
    Pointers.ULID.cast!(id)
    drop_virtual_trigger(name)
    drop_virtual_view(name)
    delete_table_record(id)
  end

  def migrate_virtual(schema), do: migrate_virtual(direction(), schema)
  def migrate_virtual(:up, schema), do: create_virtual(schema)
  def migrate_virtual(:down, schema), do: drop_virtual(schema)
  def migrate_virtual(name, id) when is_binary(name) and is_binary(id),
    do: migrate_virtual(direction(), name, id)

  def migrate_virtual(:up, name, id), do: create_virtual(name, id)
  def migrate_virtual(:down, name, id), do: drop_virtual(name, id)

  @doc "Creates a mixin table - one with a ULID primary key and no trigger"
  @spec create_mixin_table(name :: atom | binary, opts :: list, body :: term) :: nil
  defmacro create_mixin_table(name, opts \\ [], body) do
    {name, _} = eval_expand(name, __CALLER__)
    name = cond do
      is_binary(name) -> name
      is_atom(name) ->
        if Code.ensure_loaded?(name),
          do: name.__schema__(:source),
          else: Atom.to_string(name)
    end
    opts = [primary_key: false] ++ opts
    quote do
      table = Ecto.Migration.table(unquote(name), unquote(opts))
      Ecto.Migration.create_if_not_exists table do
        Pointers.Migration.add_pointer_ref_pk()
        unquote(body)
      end
    end
  end

  @doc "Drops a mixin table."
  @spec drop_mixin_table(name :: atom | binary) :: nil
  def drop_mixin_table(name), do: drop_table(name)

  @doc "Creates a random table - one with a UUID v4 primary key."
  defmacro create_random_table(name, opts \\ [], body) do
    {name, _} = eval_expand(name, __CALLER__)
    name = cond do
      is_binary(name) -> name
      is_atom(name) ->
        if Code.ensure_loaded?(name),
          do: name.__schema__(:source),
          else: Atom.to_string(name)
    end
    opts = [primary_key: false] ++ opts
    quote do
      table = Ecto.Migration.table(unquote(name), unquote(opts))
      Ecto.Migration.create_if_not_exists table do
        add :id, :uuid, primary_key: true
        unquote(body)
      end
    end
  end

  @doc "Drops a random table."
  @spec drop_random_table(name :: atom | binary) :: nil
  def drop_random_table(name), do: drop_table(name)

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
    create_if_not_exists table(Table.__schema__(:source), primary_key: false) do
      add_pointer_pk()
      add :table, :text, null: false
    end
    create_if_not_exists table(Pointer.__schema__(:source), primary_key: false) do
      add_pointer_pk()
      ref = references Table.__schema__(:source),
        on_delete: :delete_all, on_update: :update_all, type: :uuid
      add :table_id, ref, null: false
    end
    create_if_not_exists unique_index(Table.__schema__(:source), :table)
    create_if_not_exists index(Pointer.__schema__(:source), :table_id)
    flush()
    insert_table_record(Table.__pointers__(:table_id), Table.__schema__(:source))
    create_pointer_trigger_function()
    create_virtual_trigger_function()
    flush()
    create_pointer_trigger(Table.__schema__(:source))
  end

  def init_pointers(:down) do
    drop_pointer_trigger(Table.__schema__(:source))
    drop_pointer_trigger_function()
    drop_virtual_trigger_function()
    drop_if_exists index(Pointer.__schema__(:source), :table_id)
    drop_if_exists index(Table.__schema__(:source), :table)
    drop_table(Pointer.__schema__(:source))
    drop_table(Table.__schema__(:source))
  end

  @doc false
  def create_pointer_trigger_function() do
    :ok = execute """
    create or replace function #{@pointable_trigger_function}() returns trigger as $$
    declare table_id uuid;
    begin
      select id into table_id from #{Table.__schema__(:source)}
        where #{Table.__schema__(:source)}.table = TG_TABLE_NAME;
      if table_id is null then
        raise exception 'Table % does not participate in the pointers system', TG_TABLE_NAME;
      end if;
      insert into #{Pointer.__schema__(:source)} (id, table_id) values (NEW.id, table_id)
      on conflict do nothing;
      return NEW;
    end;
    $$ language plpgsql
    """
  end

  @doc false
  def create_virtual_trigger_function() do
    :ok = execute """
    create or replace function #{@virtual_trigger_function}() returns trigger as $$
    begin
      insert into #{Pointer.__schema__(:source)} (id, table_id) values (NEW.id, TG_ARGV[0] :: uuid)
      on conflict do nothing;
      return NEW;
    end;
    $$ language plpgsql
    """
  end


  @doc false
  def drop_pointer_trigger_function() do
    execute "drop function if exists #{@pointable_trigger_function}() cascade"
  end

  @doc false
  def drop_virtual_trigger_function() do
    execute "drop function if exists #{@virtual_trigger_function}() cascade"
  end

  @doc false
  def create_pointer_trigger(table) do
    table = table_name(table)
    drop_pointer_trigger(table) # because there is no create trigger if not exists
    execute """
    create trigger "#{@trigger_prefix}#{table}"
    before insert on "#{table}"
    for each row execute procedure #{@pointable_trigger_function}()
    """
  end

  @doc false
  def drop_pointer_trigger(table) do
    table = table_name(table)
    execute """
    drop trigger if exists "#{@trigger_prefix}#{table}" on "#{table}"
    """
  end

  @doc false
  def create_virtual_trigger(table, id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    drop_virtual_trigger(table) # because there is no create trigger if not exists
    execute """
    create trigger "#{@trigger_prefix}#{table}"
    instead of insert on "#{table}"
    for each row execute procedure #{@virtual_trigger_function}('#{Ecto.UUID.cast!(id)}')
    """
  end

  @doc false
  def drop_virtual_trigger(table), do: drop_pointer_trigger(table)

  @doc false
  def create_virtual_view(source, id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    execute """
    create or replace view "#{source}" as select id as id from "#{Pointer.__schema__(:source)}" where table_id = ('#{Ecto.UUID.cast!(id)}')
    """
  end

  @doc false
  def drop_virtual_view(source) do
    execute """
    drop view if exists "#{source}"
    """
  end

  @doc false
  def insert_table_record(schema) do
    source = schema.__schema__(:source)
    id = schema.__pointers__(:table_id)
    insert_table_record(source, id)
  end

  #Insert a Table record. Not required when using `create_pointable_table`
  @doc false
  def insert_table_record(id, name) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    name = table_name(name)
    opts = [on_conflict: [set: [id: id]], conflict_target: [:table]]
    repo().insert_all(Table.__schema__(:source), [%{id: id, table: name}], opts)
  end

  # Delete a Table record. Not required when using `drop_pointable_table`
  @doc false
  def delete_table_record(id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    repo().delete_all(from t in Table.__schema__(:source), where: t.id == ^id)
  end

  def drop_table(name) do
    name = cond do
      is_binary(name) -> name
      is_atom(name) -> name.__schema__(:source)
    end
    execute "drop table if exists #{name} cascade"
  end

  defp eval(quoted, env) do
    Code.eval_quoted(quoted, [], env)
  end

  defp eval_expand(quoted, env), do: expand_alias(eval(quoted, env), env)

  defp expand_alias({:__aliases__, _, _} = ast, env),
    do: Macro.expand(ast, env)
  defp expand_alias(ast, _env),
    do: ast

end
