defmodule Needle.Migration do
  @moduledoc "Helpers for writing Pointer-aware migrations."

  import Ecto.Query, only: [from: 2]
  import Ecto.Migration
  alias Needle.{Pointer, Table, UID}

  defdelegate init_pointers_ulid_extra(), to: UID.Migration

  @type pointer_type :: :strong | :weak | :unbreakable

  @doc "Creates a strong, weak or unbreakable pointer depending on `type`."
  @spec pointer(type :: pointer_type) :: term
  @spec pointer(module :: atom, type :: pointer_type) :: term
  def pointer(ref_table \\ Pointer, type) do
    # a table name is accepted as well as a schema module, for tables whose schema reads from a view
    source = if is_binary(ref_table), do: ref_table, else: ref_table.__schema__(:source)

    on_delete =
      case type do
        :strong -> :delete_all # pointer will be deleted when the thing it's pointing to is deleted
        :cascade -> :delete_all # alias of :strong  
        :weak -> :nilify_all # pointer will be set null when the thing it's pointing to is deleted.
        :nilify -> :nilify_all # alias of :weak
        :unbreakable -> :restrict # will prevent the thing it's pointing to from being deleted
      end

    references(source,
      type: :uuid,
      on_update: :update_all,
      on_delete: on_delete
    ) 
  end

  @doc """
  A reference to a pointer for use with `add/3`. A strong pointer will
  be deleted when the thing it's pointing to is deleted.
  """
  def strong_pointer(ref_table \\ Pointer), do: pointer(ref_table, :strong)

  @doc """
  A reference to a pointer for use with `add/3`. A weak pointer will
  be set null when the thing it's pointing to is deleted.
  """
  def weak_pointer(ref_table \\ Pointer), do: pointer(ref_table, :weak)

  @doc """
  A reference to a pointer for use with `add/3`. An unbreakable
  pointer will prevent the thing it's pointing to from being deleted.
  """
  def unbreakable_pointer(ref_table \\ Pointer), do: pointer(ref_table, :unbreakable)

  @doc """
  Adds a pointer field inside a `create table` or `create_mixin_table` block.

  ## Example
      add_pointer(:thread_id, :weak, Needle.Pointer, unique: true)
  """
  def add_pointer(field, type, ref_table \\ Pointer, opts \\ []) do
    Ecto.Migration.add(field, pointer(ref_table, type), opts)
  end

  @doc """
  Adds a pointer field only if it does not exist, for use in `alter table` blocks.

  WARNING: not fully idempotent — ecto_sql renders `add_if_not_exists` + a reference as `ADD COLUMN IF NOT EXISTS ..., ADD CONSTRAINT ..._fkey ...`, and Postgres does NOT skip the constraint clause when the column already exists, so a re-run errors with `duplicate_object`.
  Prefer `alter_add_pointer_if_not_exists/4` (which owns the whole `alter table`) in migrations that may run more than once.

  ## Example
      add_pointer_if_not_exists(:thread_id, :weak, Needle.Pointer, unique: true)
  """
  def add_pointer_if_not_exists(field, type, ref_table \\ Pointer, opts \\ []) do
    Ecto.Migration.add_if_not_exists(field, pointer(ref_table, type), opts)
  end

  @doc """
  Idempotently adds a pointer field to an existing table, wrapping its own `alter table`.

  Unlike `add_pointer_if_not_exists/4` (for use inside an `alter table` block), this checks whether the column exists first and skips the whole alter when it does, including the FK constraint, which ecto_sql would otherwise re-add unguarded.

  ## Example
      alter_add_pointer_if_not_exists("bonfire_data_shared_user_accounts", :user_id, :weak)
  """
  defmacro alter_add_pointer_if_not_exists(table, field, type, opts \\ []) do
    quote bind_quoted: [table: table, field: field, type: type, opts: opts] do
      unless Needle.Migration.column_exists?(repo(), table, field) do
        alter table(table) do
          Needle.Migration.add_pointer(field, type, Needle.Pointer, opts)
        end
      end
    end
  end

  @doc "Whether `column` exists on `table` (both may be atoms or strings), for migration guards."
  def column_exists?(repo, table, column) do
    %{rows: [[exists]]} =
      repo.query!(
        "SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2)",
        [table_name(table), table_name(column)]
      )

    exists
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
    Needle.UID.cast!(id)
    opts = [primary_key: false] ++ opts

    quote do
      Needle.Migration.insert_table_record(unquote(id), unquote(source))
      table = Ecto.Migration.table(unquote(source), unquote(opts))

      Ecto.Migration.create_if_not_exists table do
        Needle.Migration.add_pointer_pk()
        unquote(body)
      end

      Needle.Migration.create_pointable_triggers(unquote(id), unquote(source))
    end
  end

  def create_virtual(schema) when is_atom(schema) do
    create_virtual(schema.__schema__(:source), schema.__pointers__(:table_id))
  end

  def create_virtual(source, id) when is_binary(source) and is_binary(id) do
    {:ok, _} = Needle.UID.dump(Needle.UID.cast!(id))
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
    Needle.UID.cast!(id)
    drop_pointable_triggers(name)
    drop_table(name)
    delete_table_record(id)
  end

  def drop_virtual(schema) when is_atom(schema) do
    drop_virtual(schema.__schema__(:source), schema.__pointers__(:table_id))
  end

  def drop_virtual(name, id) when is_binary(name) and is_binary(id) do
    Needle.UID.cast!(id)
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

  @doc "Creates a mixin table - one with a UID primary key and no trigger"
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
        Needle.Migration.add_pointer_ref_pk()

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

    # Plain (not CONCURRENTLY) since init runs in a DDL transaction on an empty table. Supersedes
    # the old single-column (table_id) index, dropped for existing DBs in a dated migration.
    add_pointer_covering_index(concurrently: false)

    flush()
    add_is_not_deleted(pointer)
    create_pointers_trigger_function()
    create_pointable_trigger_function()
    create_virtual_trigger_function()
    flush()
    insert_table_record(Table.__pointers__(:table_id), table)
  end

  def init_pointers(:down) do
    pointer = Pointer.__schema__(:source)
    table = Table.__schema__(:source)
    drop_pointers_trigger_function()
    drop_pointable_trigger_function()
    drop_virtual_trigger_function()
    # legacy single-column index (older DBs) + its covering-index replacement
    drop_if_exists(index(pointer, :table_id))
    drop_pointer_covering_index()
    drop_if_exists(index(table, :table))
    drop_table(pointer)
    drop_table(table)
  end

  @pointer_covering_index_name :pointers_pointer_alive_type_id_idx

  @doc """
  Adds a partial covering index on `pointers_pointer (table_id, id) WHERE deleted_at IS NULL`.

  This matches the ubiquitous pointer access shape — virtual-view scans (`table_id = X`),
  feed/type filters (`table_id IN (...)`), and keyset pagination (`ORDER BY id DESC`) — all of
  which currently fall back to a PK scan that filters by `table_id`/`deleted_at`. The two-column
  partial index enables index-only scans (virtual views select only `id`) and serves `id DESC`
  via a backward scan, so no `DESC` is needed.

  `concurrently` is env-driven (`DB_MIGRATE_INDEXES_CONCURRENTLY`) via `create_index_for_pointer`;
  the calling migration must set `@disable_ddl_transaction true` (e.g. `use Needle.Migration.Indexable`).
  """
  def add_pointer_covering_index(opts \\ []) do
    Needle.Migration.Indexable.create_index_for_pointer(
      Pointer.__schema__(:source),
      [:table_id, :id],
      Keyword.merge([where: "deleted_at IS NULL", name: @pointer_covering_index_name], opts)
    )
  end

  def drop_pointer_covering_index do
    drop_if_exists(
      index(Pointer.__schema__(:source), [:table_id, :id], name: @pointer_covering_index_name)
    )
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
            select 'delete from "' || TG_ARGV[0] || '" where id = ''' || OLD.id || ''' :: uuid' into query;
            execute query;
          end if;
          return NEW;
        elsif (TG_OP = 'DELETE') then
          if (OLD.deleted_at is null) then
            select 'delete from "' || TG_ARGV[0] || '" where id = ''' || OLD.id || ''' :: uuid' into query;
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
    {:ok, table_id} = Needle.UID.dump(Needle.UID.cast!(table_id))
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
    {:ok, id} = Needle.UID.dump(Needle.UID.cast!(id))
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
    {:ok, id} = Needle.UID.dump(Needle.UID.cast!(id))
    id = Ecto.UUID.cast!(id)
    pointers = Pointer.__schema__(:source)

    execute("""
    create or replace view "#{source}" as
    select id as id from "#{pointers}"
    where table_id = ('#{id}' :: uuid) and deleted_at is null
    """)

    # TODO? should we manually create an index for the view?
  end

  @doc false
  def drop_virtual_view(source),
    do: execute(~s[drop view if exists "#{source}"])

  @doc """
  Creates a writable view joining `table` with its mixin tables, and the trigger that routes writes to them.

  `base_columns` are the table's columns (including `id`) and `mixins` is a list of `{mixin_source, [columns]}` or `{mixin_source, [columns], opts}`.

  A mixin is left-joined, so a row with no mixin row still shows. With `required: true` it is inner-joined instead, which lets an index on its columns serve an order or filter on them (a left join has to join every row before it can order), but a row with no mixin row then disappears from the view: every row must have one, even with only nulls. Inserts through the view always write one; a data move must too.

  The view selects `t.*`, so drop a column from `table` (once its data is moved into the mixin) before creating a view that takes the same column from a mixin, else Postgres refuses the view with `column specified more than once`.
  """
  def create_mixin_view(table, view, base_columns, mixins) do
    mixins = normalise_mixins(mixins)
    execute(mixin_view_sql(table, view, mixins))
    execute(mixin_view_trigger_function_sql(table, view, base_columns, mixins))
    # there is no create trigger if not exists
    execute(~s[drop trigger if exists #{quote_ident(view <> "_mixin_view_trigger")} on #{quote_ident(view)}])
    execute(mixin_view_create_trigger_sql(view))
  end

  @doc "Drops a view made by `create_mixin_view/4`, with its trigger function."
  def drop_mixin_view(view) do
    execute(~s[drop view if exists #{quote_ident(view)}])
    execute(~s[drop function if exists #{quote_ident(mixin_view_function_name(view))}() cascade])
  end

  @doc """
  Moves columns of `table` into mixin tables, and creates the writable view (`create_mixin_view/4`) that a schema then uses as its source: copies each mixin's columns (`mixin_copy_sql/2`), drops them from the table, then creates the view from the table's remaining columns. For a migration's `up`; `move_columns_from_mixins/3` is its `down`.

  The mixin tables must exist, with the same column names. `mixins` as in `create_mixin_view/4`.
  """
  def move_columns_to_mixins(table, view, mixins) do
    mixins = normalise_mixins(mixins)

    for mixin <- mixins, do: execute(mixin_copy_sql(table, mixin))
    execute(drop_columns_sql(table, Enum.flat_map(mixins, fn {_, cols, _} -> cols end)))
    # run the above before reading the table's remaining columns
    flush()

    create_mixin_view(table, view, table_columns(table), mixins)
  end

  @doc "Undoes `move_columns_to_mixins/3`: drops the view, adds the columns back to `table` with the types they have in the mixins, and copies the values back. The mixin rows stay, as other tables may share the mixin."
  def move_columns_from_mixins(table, view, mixins) do
    mixins = normalise_mixins(mixins)

    drop_mixin_view(view)

    columns =
      Enum.flat_map(mixins, fn {source, cols, _} ->
        types = column_types(source)
        for col <- cols, do: {col, Map.fetch!(types, col)}
      end)

    execute(add_columns_sql(table, columns))
    for mixin <- mixins, do: execute(mixin_copy_back_sql(table, mixin))
  end

  @doc "SQL copying a mixin's columns from `table` into the mixin table: every row for a `required` mixin (the view inner-joins it, so a row without one would disappear), else only rows where one of its columns has a value."
  def mixin_copy_sql(table, mixin) do
    [{source, cols, opts}] = normalise_mixins([mixin])
    all = ["id" | cols]
    qcols = Enum.map_join(all, ", ", &quote_ident/1)
    sets = Enum.map_join(cols, ", ", &"#{quote_ident(&1)} = excluded.#{quote_ident(&1)}")

    where =
      if opts[:required],
        do: "",
        else: " where " <> Enum.map_join(cols, " or ", &"#{quote_ident(&1)} is not null")

    """
    insert into #{quote_ident(source)} (#{qcols})
    select #{qcols} from #{quote_ident(table)}#{where}
    on conflict ("id") do update set #{sets}
    """
  end

  @doc "SQL copying a mixin's columns back into `table`, for `move_columns_from_mixins/3`."
  def mixin_copy_back_sql(table, mixin) do
    [{source, cols, _opts}] = normalise_mixins([mixin])
    sets = Enum.map_join(cols, ", ", &"#{quote_ident(&1)} = m.#{quote_ident(&1)}")

    ~s[update #{quote_ident(table)} t set #{sets} from #{quote_ident(source)} m where m."id" = t."id"]
  end

  @doc "SQL dropping `columns` from `table` in one statement."
  def drop_columns_sql(table, columns),
    do: "alter table #{quote_ident(table)} " <> Enum.map_join(columns, ", ", &"drop column #{quote_ident(&1)}")

  @doc "SQL adding `{column, sql_type}` columns to `table` in one statement."
  def add_columns_sql(table, columns),
    do:
      "alter table #{quote_ident(table)} " <>
        Enum.map_join(columns, ", ", fn {col, type} -> "add column #{quote_ident(col)} #{type}" end)

  # the table's columns as they are on this database, rather than a list that could miss one added later
  defp table_columns(table) do
    repo().query!(
      "select column_name from information_schema.columns where table_name = $1 and table_schema = current_schema() order by ordinal_position",
      [table]
    ).rows
    |> List.flatten()
  end

  # column name => its SQL type, as `format_type` writes it (eg. "timestamp with time zone")
  defp column_types(table) do
    repo().query!(
      "select a.attname, format_type(a.atttypid, a.atttypmod) from pg_attribute a where a.attrelid = ($1::text)::regclass and a.attnum > 0 and not a.attisdropped",
      [table]
    ).rows
    |> Map.new(fn [name, type] -> {name, type} end)
  end

  @doc "The SQL of a view selecting every column of `table` and the listed columns of each mixin, joined on `id` (see `create_mixin_view/4` for `required`)."
  def mixin_view_sql(table, view, mixins) do
    indexed = Enum.with_index(normalise_mixins(mixins), 1)

    columns =
      for {{_source, cols, _opts}, i} <- indexed, col <- cols do
        "#{mixin_alias(i)}.#{quote_ident(col)}"
      end

    joins =
      for {{source, _cols, opts}, i} <- indexed do
        join = if opts[:required], do: "join", else: "left join"
        "#{join} #{quote_ident(source)} #{mixin_alias(i)} on #{mixin_alias(i)}.\"id\" = t.\"id\""
      end

    """
    create or replace view #{quote_ident(view)} as
    select #{Enum.join(["t.*" | columns], ", ")}
    from #{quote_ident(table)} t
    #{Enum.join(joins, "\n")}
    """
  end

  @doc "The SQL of the trigger function and the `instead of` trigger that make the view from `mixin_view_sql/3` writable."
  def mixin_view_trigger_sql(table, view, base_columns, mixins) do
    mixin_view_trigger_function_sql(table, view, base_columns, mixins) <>
      ";\n" <> mixin_view_create_trigger_sql(view)
  end

  defp mixin_view_create_trigger_sql(view) do
    """
    create trigger #{quote_ident(view <> "_mixin_view_trigger")}
    instead of insert or update or delete on #{quote_ident(view)}
    for each row
    execute procedure #{quote_ident(mixin_view_function_name(view))}()
    """
  end

  defp mixin_view_trigger_function_sql(table, view, base_columns, mixins) do
    # the trigger treats every mixin the same, whatever its join; it only needs the source and columns
    mixins = for {source, cols, _opts} <- normalise_mixins(mixins), do: {source, cols}
    qt = quote_ident(table)
    qcols = fn cols -> Enum.map_join(cols, ", ", &quote_ident/1) end
    vals = fn row, cols -> Enum.map_join(cols, ", ", &"#{row}.#{quote_ident(&1)}") end
    # the id is never changed by an update
    updatable = Enum.reject(base_columns, &(&1 == "id"))

    insert_mixins =
      for {source, cols} <- mixins do
        all = ["id" | cols]
        "insert into #{quote_ident(source)} (#{qcols.(all)}) values (#{vals.("NEW", all)});"
      end

    upsert_mixins =
      for {source, cols} <- mixins do
        all = ["id" | cols]
        sets = Enum.map_join(cols, ", ", &"#{quote_ident(&1)} = excluded.#{quote_ident(&1)}")

        "insert into #{quote_ident(source)} (#{qcols.(all)}) values (OLD.\"id\", #{vals.("NEW", cols)}) on conflict (\"id\") do update set #{sets};"
      end

    delete_mixins =
      for {source, _cols} <- Enum.reverse(mixins) do
        "delete from #{quote_ident(source)} where \"id\" = OLD.\"id\";"
      end

    update_base =
      if updatable == [] do
        []
      else
        sets = Enum.map_join(updatable, ", ", &"#{quote_ident(&1)} = NEW.#{quote_ident(&1)}")
        ["update #{qt} set #{sets} where \"id\" = OLD.\"id\";"]
      end

    pointer = quote_ident(Pointer.__schema__(:source))
    tables = quote_ident(Table.__schema__(:source))

    # the base table's own pointable triggers only fire at trigger depth 0, so from this `instead of` trigger they are skipped, and this function writes the pointer itself, as the virtual trigger does
    # the pointer and base row go first on insert (mixins reference them) and last on delete
    """
    create or replace function #{quote_ident(mixin_view_function_name(view))}() returns trigger as $$
    declare table_id uuid;
    begin
      if (TG_OP = 'INSERT') then
        select id into table_id from #{tables} where "table" = #{quote_literal(table)};
        if table_id is null then
          raise exception 'Table % is not pointable', #{quote_literal(table)};
        end if;
        insert into #{pointer} (id, table_id) values (NEW."id", table_id) on conflict do nothing;
        insert into #{qt} (#{qcols.(base_columns)}) values (#{vals.("NEW", base_columns)});
        #{Enum.join(insert_mixins, "\n    ")}
        return NEW;
      elsif (TG_OP = 'UPDATE') then
        #{Enum.join(update_base ++ upsert_mixins, "\n    ")}
        return NEW;
      elsif (TG_OP = 'DELETE') then
        #{Enum.join(delete_mixins, "\n    ")}
        delete from #{qt} where "id" = OLD."id";
        update #{pointer} set deleted_at = now() at time zone 'utc' where id = OLD."id";
        return OLD;
      end if;
      return null;
    end;
    $$ language plpgsql
    """
  end

  defp mixin_view_function_name(view), do: view <> "_mixin_trigger"

  # `{source, cols}` or `{source, cols, opts}`, as `{source, cols, opts}`; anything else raises, rather than being skipped by a `for` pattern
  defp normalise_mixins(mixins) do
    Enum.map(mixins, fn
      {source, cols, opts} when is_list(cols) and is_list(opts) -> {source, cols, opts}
      {source, cols} when is_list(cols) -> {source, cols, []}
    end)
  end

  defp mixin_alias(i), do: "m#{i}"

  # double any embedded quote so a name cannot end the identifier early
  defp quote_ident(name), do: ~s["#{String.replace(to_string(name), ~s["], ~s[""])}"]

  defp quote_literal(value), do: "'#{String.replace(to_string(value), "'", "''")}'"

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
    {:ok, table_id} = Needle.UID.dump(Table.__pointers__(:table_id))
    {:ok, id} = Needle.UID.dump(Needle.UID.cast!(id))
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
    {:ok, id} = Needle.UID.dump(Needle.UID.cast!(id))
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
    do: Keyword.get(Application.get_env(:needle, __MODULE__, []), key, default)
end
