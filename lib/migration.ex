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
    references(table.__schema__(:source),
      type: :uuid,
      on_update: :update_all,
      on_delete: :delete_all
    )
  end

  @doc """
  A reference to a pointer for use with `add/3`. A weak pointer will
  be set null when the thing it's pointing to is deleted.
  """
  def weak_pointer(table \\ Pointer) do
    references(table.__schema__(:source),
      type: :uuid,
      on_update: :update_all,
      on_delete: :nilify_all
    )
  end

  @doc """
  A reference to a pointer for use with `add/3`. An unbreakable
  pointer will prevent the thing it's pointing to from being deleted.
  """
  def unbreakable_pointer(table \\ Pointer) do
    references(table.__schema__(:source),
      type: :uuid,
      on_update: :update_all,
      on_delete: :restrict
    )
  end

  defp table_name(name) when is_atom(name), do: Atom.to_string(name)
  defp table_name(name) when is_binary(name), do: name

  @doc false
  @spec add_pointer_pk() :: nil
  def add_pointer_pk(), do: add(:id, :uuid, primary_key: true)

  @doc false
  @spec add_pointer_ref_pk() :: nil
  def add_pointer_ref_pk(),
    do: add(:id, strong_pointer(Pointer), primary_key: true)

  @doc "Creates a pointable table along with its trigger."
  @spec create_pointable_table(schema :: atom, body :: term) :: term
  @spec create_pointable_table(
          schema :: atom,
          opts :: Keyword.t(),
          body :: term
        ) :: term
  @spec create_pointable_table(source :: binary, id :: binary, body :: term) ::
          term
  @spec create_pointable_table(
          source :: binary,
          id :: binary,
          opts :: Keyword.t(),
          body :: term
        ) :: term

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
    cpt(schema.__schema__(:source), schema.__pointers__(:table_id), [], body)
  end

  defp cpt(schema, opts, body) when is_atom(schema) and is_list(opts) do
    cpt(schema.__schema__(:source), schema.__pointers__(:table_id), opts, body)
  end

  defp cpt(source, id, body) when is_binary(source) and is_binary(id) do
    cpt(source, id, [], body)
  end

  defp cpt(source, id, opts, body)
       when is_binary(source) and is_binary(id) and is_list(opts) do
    Pointers.ULID.cast!(id)
    opts = [primary_key: false] ++ opts

    quote do
      Pointers.Migration.insert_table_record(unquote(id), unquote(source))
      table = Ecto.Migration.table(unquote(source), unquote(opts))

      Ecto.Migration.create_if_not_exists table do
        Pointers.Migration.add_pointer_pk()
        unquote(body)
      end

      Pointers.Migration.create_pointable_triggers(unquote(id), unquote(source))
    end
  end

  def create_virtual(schema) when is_atom(schema) do
    create_virtual(schema.__schema__(:source), schema.__pointers__(:table_id))
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
    drop_pointable_table(
      schema.__schema__(:source),
      schema.__pointers__(:table_id)
    )
  end

  def drop_pointable_table(name, id) when is_binary(name) and is_binary(id) do
    Pointers.ULID.cast!(id)
    drop_pointable_triggers(name)
    drop_table(name)
    delete_table_record(id)
  end

  def drop_virtual(schema) when is_atom(schema) do
    drop_virtual(schema.__schema__(:source), schema.__pointers__(:table_id))
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
  @spec create_mixin_table(name :: atom | binary, opts :: list, body :: term) ::
          nil
  defmacro create_mixin_table(name, opts \\ [], body) do
    {name, _} = eval_expand(name, __CALLER__)

    name =
      cond do
        is_binary(name) ->
          name

        is_atom(name) ->
          if Code.ensure_loaded?(name),
            do: name.__schema__(:source),
            else: Atom.to_string(name)
      end

    opts = [primary_key: false] ++ List.wrap(opts)

    quote do
      name = unquote(name)
      table = Ecto.Migration.table(name, unquote(opts))

      Ecto.Migration.create_if_not_exists table do
        Pointers.Migration.add_pointer_ref_pk()

        unquote(body)
      end

      # execute """
      # ALTER TABLE #{name} add constraint pointer_is_not_deleted check (is_not_deleted(id))
      # """
    end
  end

  @doc "Drops a mixin table."
  @spec drop_mixin_table(name :: atom | binary) :: nil
  def drop_mixin_table(name), do: drop_table(name)

  @doc "Creates a random table - one with a UUID v4 primary key."
  defmacro create_random_table(name, opts \\ [], body) do
    {name, _} = eval_expand(name, __CALLER__)

    name =
      cond do
        is_binary(name) ->
          name

        is_atom(name) ->
          if Code.ensure_loaded?(name),
            do: name.__schema__(:source),
            else: Atom.to_string(name)
      end

    opts = [primary_key: false] ++ List.wrap(opts)

    quote do
      table = Ecto.Migration.table(unquote(name), unquote(opts))

      Ecto.Migration.create_if_not_exists table do
        add(:id, :uuid, primary_key: true)
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
    pointer = Pointer.__schema__(:source)
    table = Table.__schema__(:source)

    create_if_not_exists table(table, primary_key: false) do
      add_pointer_pk()
      add(:table, :text)
    end

    create_if_not_exists table(pointer, primary_key: false) do
      add_pointer_pk()

      ref =
        references(table,
          on_delete: :delete_all,
          on_update: :update_all,
          type: :uuid
        )

      add(:table_id, ref, null: false)
      add(:deleted_at, :timestamptz, null: true)
    end

    create_if_not_exists(unique_index(table, :table))
    create_if_not_exists(index(pointer, :table_id))
    flush()
    add_is_not_deleted(pointer)
    create_pointers_trigger_function()
    create_pointable_trigger_function()
    create_virtual_trigger_function()
    flush()
    insert_table_record(Table.__pointers__(:table_id), table)
  end

  def add_is_not_deleted(table) do
    execute("""
     create or replace function is_not_deleted(uuid) returns boolean as $$
    select exists (
        select 1
        from #{table}
        where id   = $1
          and deleted_at IS NULL
    );
    $$ language sql;
    """)
  end

  def init_pointers(:down) do
    pointer = Pointer.__schema__(:source)
    table = Table.__schema__(:source)
    drop_pointers_trigger_function()
    drop_pointable_trigger_function()
    drop_virtual_trigger_function()
    drop_if_exists(index(pointer, :table_id))
    drop_if_exists(index(table, :table))
    drop_table(pointer)
    drop_table(table)
  end

  @doc false
  def create_pointers_trigger_function() do
    fun = pointers_trigger_function()

    :ok =
      execute("""
      create or replace function "#{fun}"() returns trigger as $$
      declare query text;
      begin
        if (TG_OP = 'UPDATE') then
          if (OLD.deleted_at is null and NEW.deleted_at is not null) then
            select 'delete from "' || TG_ARGV[0] || '" where id = ''' | OLD.id | ''' :: uuid' into query;
            execute query;
          end if;
          return NEW;
        elsif (TG_OP = 'DELETE') then
          if (OLD.deleted_at is null) then
            select 'delete from "' || TG_ARGV[0] || '" where id = ''' | OLD.id | ''' :: uuid' into query;
            execute query;
          end if;
          return OLD;
        else
          return NEW;
        end if;
      end;
      $$ language plpgsql
      """)
  end

  @doc false
  def create_pointable_trigger_function() do
    fun = pointable_trigger_function()
    pointer = Pointer.__schema__(:source)
    table = Table.__schema__(:source)

    :ok =
      execute("""
      create or replace function "#{fun}"() returns trigger as $$
      declare table_id uuid;
      begin
        if (TG_OP = 'INSERT') then
          if (TG_NARGS = 1) then
            select TG_ARGV[0] :: uuid into table_id;
          else
            select id into table_id from "#{table}"
              where "table" = TG_TABLE_NAME;
          end if;
          if table_id is null then
            raise exception 'Table % is not pointable', TG_TABLE_NAME;
          end if;
          insert into "#{pointer}" (id, table_id) values (NEW.id, table_id)
          on conflict do nothing;
          return NEW;
        elsif (TG_OP = 'DELETE') then
          update "#{pointer}" set deleted_at = now() at time zone 'utc' where id = OLD.id;
          return OLD;
        else
          raise exception 'operation: %', TG_OP;
        end if;
      end;
      $$ language plpgsql
      """)
  end

  def create_virtual_trigger_function() do
    fun = virtual_trigger_function()
    pointer = Pointer.__schema__(:source)

    :ok =
      execute("""
      create or replace function "#{fun}"() returns trigger as $$
      begin
        if (TG_OP = 'INSERT') then
          insert into "#{pointer}" (id, table_id) values (NEW.id, TG_ARGV[0] :: uuid)
          on conflict do nothing;
          return NEW;
        elsif (TG_OP = 'DELETE') then
          update "#{pointer}" set deleted_at = now() at time zone 'utc' where id = OLD.id;
          return OLD;
        else
          raise exception 'operation: %', TG_OP;
        end if;
      end;
      $$ language plpgsql
      """)
  end

  @doc false
  def drop_pointers_trigger_function() do
    execute(~s[drop function if exists "#{pointers_trigger_function()}"() cascade])
  end

  @doc false
  def drop_pointable_trigger_function() do
    execute(~s[drop function if exists "#{pointable_trigger_function()}"() cascade])
  end

  @doc false
  def drop_virtual_trigger_function() do
    execute(~s[drop function if exists "#{virtual_trigger_function()}"() cascade])
  end

  @doc false
  def create_pointable_triggers(table_id, source) do
    {:ok, table_id} = Pointers.ULID.dump(Pointers.ULID.cast!(table_id))
    pointer = Pointer.__schema__(:source)
    table_id = Ecto.UUID.cast!(table_id)
    # because there is no create trigger if not exists
    drop_pointable_triggers(source)

    # after inserting into the pointable, a shadow record should be created in the pointable table
    # Note: `pg_trigger_depth()` is used to stop the triggers from issuing a single extra delete
    # (that would fail) when called from the other triggers installed by this function
    execute("""
    create trigger "#{source}_insert_trigger"
    before insert on "#{source}"
    for each row when (pg_trigger_depth() < 1)
    execute procedure "#{pointable_trigger_function()}"('#{table_id}')
    """)

    # after deleting from the pointable table, the pointer should be marked deleted
    execute("""
    create trigger "#{source}_delete_trigger"
    after delete on "#{source}"
    for each row when (pg_trigger_depth() < 1)
    execute procedure "#{pointable_trigger_function()}"()
    """)

    # after marking a pointer deleted, the shadow record should be deleted
    execute("""
    create trigger "#{source}_soft_delete_trigger"
    after update on "#{pointer}"
    for each row
    when (
      pg_trigger_depth() < 1
      and OLD.deleted_at is null
      and NEW.deleted_at is not null
      and OLD.table_id = '#{table_id}' :: uuid
    )
    execute procedure "#{pointers_trigger_function()}"('#{source}')
    """)

    # after deleting from pointers, the shadow record should be
    # deleted if it wasn't already marked deleted
    execute("""
    create trigger "#{source}_delete_trigger"
    after delete on "#{pointer}"
    for each row
    when (
      pg_trigger_depth() < 1
      and OLD.deleted_at is null
      and OLD.table_id = '#{table_id}' :: uuid
    )
    execute procedure "#{pointers_trigger_function()}"('#{source}')
    """)
  end

  @doc false

  def drop_pointable_triggers(table) do
    pointers = Pointer.__schema__(:source)
    table = table_name(table)
    execute(~s[drop trigger if exists "#{table}_insert_trigger" on "#{table}"])
    execute(~s[drop trigger if exists "#{table}_delete_trigger" on "#{table}"])

    execute(~s[drop trigger if exists "#{table}_soft_delete_trigger" on "#{pointers}"])

    execute(~s[drop trigger if exists "#{table}_delete_trigger" on "#{pointers}"])
  end

  @doc false
  def create_virtual_trigger(table, id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    id = Ecto.UUID.cast!(id)
    # because there is no create trigger if not exists
    drop_virtual_trigger(table)

    execute("""
     create trigger "#{table}_insert_delete_trigger"
     instead of insert or delete on "#{table}"
     for each row
     execute procedure "#{virtual_trigger_function()}"('#{id}')
    """)
  end

  @doc false
  def drop_virtual_trigger(table) do
    table = table_name(table)

    execute(~s[drop trigger if exists "#{table}_insert_delete_trigger" on "#{table}"])
  end

  @doc false
  def create_virtual_view(source, id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    id = Ecto.UUID.cast!(id)
    pointers = Pointer.__schema__(:source)

    execute("""
    create or replace view "#{source}" as
    select id as id from "#{pointers}"
    where table_id = ('#{id}' :: uuid) and deleted_at is null
    """)
  end

  @doc false
  def drop_virtual_view(source),
    do: execute(~s[drop view if exists "#{source}"])

  @doc false
  def insert_table_record(schema) do
    insert_table_record(
      schema.__schema__(:source),
      schema.__pointers__(:table_id)
    )
  end

  # Insert a Table record. Not required when using `create_pointable_table`
  @doc false
  def insert_table_record(id, name) do
    {:ok, table_id} = Pointers.ULID.dump(Table.__pointers__(:table_id))
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    table = table_name(name)
    opts = [on_conflict: :nothing]

    repo().insert_all(
      Table.__schema__(:source),
      [%{id: id, table: table}],
      opts
    )

    repo().insert_all(
      Pointer.__schema__(:source),
      [%{id: id, table_id: table_id}],
      opts
    )
  end

  # Delete a Table record. Not required when using `drop_pointable_table`
  @doc false
  def delete_table_record(id) do
    {:ok, id} = Pointers.ULID.dump(Pointers.ULID.cast!(id))
    table = Table.__schema__(:source)
    repo().delete_all(from(t in table, where: t.id == ^id))
  end

  def drop_table(name) do
    name =
      cond do
        is_binary(name) -> name
        is_atom(name) -> name.__schema__(:source)
      end

    execute(~s[drop table if exists "#{name}" cascade])
  end

  defp eval(quoted, env), do: Code.eval_quoted(quoted, [], env)

  defp eval_expand(quoted, env), do: expand_alias(eval(quoted, env), env)

  defp expand_alias({:__aliases__, _, _} = ast, env), do: Macro.expand(ast, env)
  defp expand_alias(ast, _env), do: ast

  defp pointers_trigger_function(),
    do: config(:pointers_trigger_function, "pointers_pointers_trigger")

  defp pointable_trigger_function(),
    do: config(:pointable_trigger_function, "pointers_pointable_trigger")

  defp virtual_trigger_function(),
    do: config(:virtual_trigger_function, "pointers_virtual_trigger")

  defp config(key, default),
    do: Keyword.get(Application.get_env(:pointers, __MODULE__, []), key, default)
end
