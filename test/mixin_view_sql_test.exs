defmodule Needle.MixinViewSqlTest do
  use ExUnit.Case
  alias Needle.Migration

  @mixins [{"time_span", ["has_beginning", "has_end"]}, {"place", ["lat"]}]
  @base_columns ["id", "name", "note"]

  defp norm(sql), do: sql |> String.replace(~r/\s+/, " ") |> String.downcase() |> String.trim()

  defp branch(sql, op) do
    sql = norm(sql)
    [_, rest] = String.split(sql, "tg_op = '#{String.downcase(op)}') then", parts: 2)
    # [body | _] = Regex.split(~r/elsif \(tg_op|end if;/, rest, parts: 2)
    # a branch can hold its own `if … end if;`, so it ends at its `return`
    [body | _] = Regex.split(~r/return (new|old);/, rest, parts: 2)
    body
  end

  describe "mixin_view_sql" do
    test "n1: selects t.*, each mixin column, and left-joins each mixin on id" do
      sql = norm(Migration.mixin_view_sql("vf_intent", "vf_intent_view", @mixins))

      assert sql =~ ~s[create or replace view "vf_intent_view" as]
      assert sql =~ "select t.*"
      assert sql =~ ~s[m1."has_beginning"]
      assert sql =~ ~s[m1."has_end"]
      assert sql =~ ~s[m2."lat"]
      assert sql =~ ~s[from "vf_intent" t]
      assert sql =~ ~s[left join "time_span" m1 on m1."id" = t."id"]
      assert sql =~ ~s[left join "place" m2 on m2."id" = t."id"]
    end

    test "a mixin marked required is inner-joined, so an index on its columns can serve the view's order" do
      sql =
        norm(
          Migration.mixin_view_sql("vf_intent", "vf_intent_view", [
            {"time_span", ["has_beginning"], required: true},
            {"place", ["lat"]}
          ])
        )

      assert sql =~ ~s[ join "time_span" m1 on m1."id" = t."id"]
      refute sql =~ ~s[left join "time_span"]
      assert sql =~ ~s[left join "place" m2 on m2."id" = t."id"]
      assert sql =~ ~s[m1."has_beginning"]
    end
  end

  describe "mixin_view_trigger_sql" do
    setup do
      sql = Migration.mixin_view_trigger_sql("vf_intent", "vf_intent_view", @base_columns, @mixins)
      {:ok, sql: sql}
    end

    test "n2: has insert, update and delete branches and an instead of trigger", %{sql: sql} do
      n = norm(sql)
      assert n =~ "tg_op = 'insert') then"
      assert n =~ "tg_op = 'update') then"
      assert n =~ "tg_op = 'delete') then"
      assert n =~ "instead of insert or update or delete on \"vf_intent_view\""
      assert n =~ "return new"
      assert n =~ "return old"
    end

    test "n2: insert writes only base columns to the table and only mixin columns to each mixin",
         %{sql: sql} do
      ins = branch(sql, "INSERT")

      assert ins =~ ~s[insert into "vf_intent" ("id", "name", "note") values (new."id", new."name", new."note")]
      assert ins =~ ~s[insert into "time_span" ("id", "has_beginning", "has_end") values (new."id", new."has_beginning", new."has_end")]
      assert ins =~ ~s[insert into "place" ("id", "lat") values (new."id", new."lat")]

      refute ins =~ ~s[insert into "vf_intent" ("id", "name", "note", "has_beginning"]
      refute ins =~ ~s[insert into "time_span" ("id", "name"]
      refute ins =~ ~s["place" ("id", "has_beginning"]

      # the base table's pointable trigger is skipped inside this trigger, so the pointer is written here, before the base row
      assert ins =~ ~s[insert into "pointers_pointer" (id, table_id) values (new."id", table_id)]
      [before_base, _] = String.split(ins, ~s[insert into "vf_intent"], parts: 2)
      assert before_base =~ ~s[insert into "pointers_pointer"]
    end

    test "n3: update changes the base row and upserts each mixin row", %{sql: sql} do
      upd = branch(sql, "UPDATE")

      assert upd =~ ~s[update "vf_intent" set "name" = new."name", "note" = new."note" where "id" = old."id"]

      assert upd =~
               ~s[insert into "time_span" ("id", "has_beginning", "has_end") values (old."id", new."has_beginning", new."has_end") on conflict ("id") do update set "has_beginning" = excluded."has_beginning", "has_end" = excluded."has_end"]

      assert upd =~ ~s[insert into "place" ("id", "lat") values (old."id", new."lat") on conflict ("id") do update set "lat" = excluded."lat"]
    end

    test "delete removes the mixin rows, then the base row", %{sql: sql} do
      del = branch(sql, "DELETE")
      {t, _} = :binary.match(del, ~s[delete from "time_span"])
      {p, _} = :binary.match(del, ~s[delete from "place"])
      {b, _} = :binary.match(del, ~s[delete from "vf_intent" where])
      assert t < b and p < b

      # the pointer is marked deleted last, as the virtual trigger does
      {d, _} = :binary.match(del, ~s[update "pointers_pointer" set deleted_at])
      assert b < d
    end

    test "trigger function name is derived from the view name", %{sql: sql} do
      assert norm(sql) =~ ~s[create or replace function "vf_intent_view_mixin_trigger"()]
    end
  end

  describe "quoting (n4)" do
    test "view sql quotes identifiers and doubles embedded quotes" do
      sql = Migration.mixin_view_sql(~s[ta"ble], "my view", [{"mix in", [~s[co"l], "drop table x; --"]}])

      assert sql =~ ~s["ta""ble"]
      assert sql =~ ~s["my view"]
      assert sql =~ ~s["mix in"]
      assert sql =~ ~s["co""l"]
      assert sql =~ ~s["drop table x; --"]
    end

    test "trigger sql quotes identifiers and doubles embedded quotes" do
      sql =
        Migration.mixin_view_trigger_sql("my table", ~s[my"view], ["id", "a b"], [{"mix in", [~s[co"l]]}])

      assert sql =~ ~s["my table"]
      assert sql =~ ~s["my""view"]
      assert sql =~ ~s["a b"]
      assert sql =~ ~s["mix in"]
      assert sql =~ ~s["co""l"]
    end
  end

  describe "moving columns into mixins" do
    test "a required mixin gets a row for every row of the table, nulls included" do
      sql = norm(Migration.mixin_copy_sql("vf_intent", {"time_span", ["has_beginning", "has_end"], required: true}))

      assert sql =~
               ~s[insert into "time_span" ("id", "has_beginning", "has_end") select "id", "has_beginning", "has_end" from "vf_intent"]

      refute sql =~ " where "

      assert sql =~
               ~s[on conflict ("id") do update set "has_beginning" = excluded."has_beginning", "has_end" = excluded."has_end"]
    end

    test "an optional mixin gets a row only where one of its columns has a value" do
      sql = norm(Migration.mixin_copy_sql("vf_intent", {"place", ["lat", "long"], []}))

      assert sql =~ ~s[from "vf_intent" where "lat" is not null or "long" is not null]
    end

    test "copying back sets the table's columns from the mixin rows" do
      sql = norm(Migration.mixin_copy_back_sql("vf_intent", {"time_span", ["has_beginning"], []}))

      assert sql =~
               ~s[update "vf_intent" t set "has_beginning" = m."has_beginning" from "time_span" m where m."id" = t."id"]
    end

    test "the moved columns are dropped in one statement" do
      sql = norm(Migration.drop_columns_sql("vf_intent", ["has_beginning", "has_end"]))
      assert sql == ~s[alter table "vf_intent" drop column "has_beginning", drop column "has_end"]
    end

    test "the columns are added back with their types" do
      sql =
        norm(
          Migration.add_columns_sql("vf_intent", [
            {"has_beginning", "timestamp with time zone"},
            {"lat", "double precision"}
          ])
        )

      assert sql ==
               ~s[alter table "vf_intent" add column "has_beginning" timestamp with time zone, add column "lat" double precision]
    end
  end

  describe "pointer with a table name" do
    # references/2 reads the repo config from a migration runner process, so start a bare one
    setup do
      {:ok, runner} =
        Ecto.Migration.Runner.start_link({self(), Needle.Test.FakeRepo, [], __MODULE__, :up, :up, false})

      Process.put(:ecto_migration, %{runner: runner})
      :ok
    end

    test "references the named table" do
      ref = Migration.pointer("vf_intent", :strong)
      assert %Ecto.Migration.Reference{table: "vf_intent", type: :uuid, on_delete: :delete_all} = ref
    end

    test "still accepts a module" do
      ref = Migration.pointer(Needle.Pointer, :weak)
      assert %Ecto.Migration.Reference{on_delete: :nilify_all} = ref
      assert ref.table == Needle.Pointer.__schema__(:source)
    end
  end
end
