[![hex.pm](https://img.shields.io/hexpm/v/pointers)](https://hex.pm/pointers)
[hexdocs](https://hexdocs.pm/pointers)

# pointers

Ecto's missing universal foreign key

> One foreign key to rule them all and in the darkness, bind them.

-- Gandalf, paraphrased.

A means of foreign keying many tables in one field. Designed for
highly interlinked data in highly dynamic schemata where tracking all
the foreign keys is neither desired nor practical.

Note: a universal foreign key is actually a hard problem. Many
approaches are on offer with a variety of tradeoffs. You should
carefully consider a variety of approaches rather than just blindly
adopting the one that fitted our project's needs the best!

## Background

A `Table` is a record of a table that may be linked to by a pointer.
A `Pointer` is a pointer id and a table id.

With these two ingredients, we can construct a means of pointing to
any table that has a `Table` entry.

`Pointer` and `Table` IDs are both `Pointers.ULID`, a UUID-like type
that combines a millisecond-precision timestamp and some randomness to
reduce the likelihood of a clash. It naturally sorts both in binary
and text form by time and as far as postgres is concerned, it's a UUID.

## Installation

Aside from the hex dependency, you will also need to write a simple
migration to set up the database before you can start writing your
regular migrations:

```elixir
defmodule MyApp.Repo.Migrations.InitPointers do
  use Ecto.Migration
  import Pointers.Migration

  def up(), do: inits(:up)
  def down(), do: inits(:down)

  defp inits(dir) do
    init_pointers_ulid_extra(dir) # this one is optional but recommended
    init_pointers(dir) # this one is not optional
  end
end
```

## Defining a Pointable Type

Pointable tables require a unique sentinel ULID to identify
them. These must be 26 characters long and in the alphabet of
[Crockford's Base32](https://en.wikipedia.org/wiki/Base32#Crockford's_Base32).
They should be easy to identify in a printout and might be silly.

There is a helper function, `synthesise!/1` in `Pointers.ULID` to
assist with this process - give it a 26-character long binary of ascii
alphanumerics and it will give you the closest ULID that matches back.

Let's look at a simple schema:

```elixir
defmodule MyApp.Greeting do
  use Pointers.Pointable,
    otp_app: :my_app,
    source: "myapp_greeting",
    table_id: "GREET1NGSFR0MD0CEXAMP1E000"

  pointable_schema do
    field :greeting, :string
  end
end
```

To declare a pointable schema, we start by using `Pointers.Pointable`,
providing the name of our otp application, the source table's name in
the database and our chosen sentinel ULID.

We then call `pointable_schema` and define any fields we wish to put
directly in the table. For the most part, `pointable_schema` is like
Ecto's `schema` macro, except you do not provide the table name and
let it handle the primary key.

If for some reason you wished to turn autogeneration off, you could
pass `autogenerate: false` to the options provided when using
`Pointers.Pointable`.

Now let's define the migration for our schema:

```elixir
defmodule MyApp.Repo.Migrations.Greeting do
  use Ecto.Migration
  import Pointers.Migration

  def up() do
    create_pointable_table(:greeting, "GREET1NGSFR0MD0CEXAMP1E000") do
      add :greeting, :text, null: false
    end
  end

  def down() do
    drop_pointable_table(:greeting, "GREET1NGSFR0MD0CEXAMP1E000")
  end
end
```

As you can see, it's pretty similar to defining a regular migration,
except you use `create_pointable_table` and
`drop_pointable_table`. Notice that our sentinel ULID makes an
appearance again here. It's *very* important that these match what we
declared in the schema.

## Referencing Pointers

Ecto does not know anything about our scheme, so unless we
specifically want something to reference one of the pointed tables, we
typically `belongs_to` with `Pointers.Pointer`. The table in which we
do this does not itself need to be pointable.

```elixir
defmodule MyApp.Foo do

  use Ecto.Schema
  alias Pointers.Pointer

  # regular ecto table, not pointable!
  schema "hello" do
    belongs_to :pointer, Pointer # who knows what it points to?
  end
end
```

You may choose to reference a specific schema rather than Pointer if it
will only point to a single table. If you do this, you must ensure
that the referenced record exists in that table in the normal
way. There may be some performance benefit, we didn't benchmark it.

The migration is slightly more complex, we have to decide what type of
a pointer it is. Pointers come in three categories:

* A strong pointer is not nullable and is deleted when the object it
  points to is deleted.
* A weak pointer is nullable and is nilified when the object it points
  to is deleted.
* An unbreakable pointer will raise when you attempt to delete the
  object it points to.

| Type        | Nullable? | On Delete   |
|-------------|-----------|-------------|
| Strong      | No        | Cascade     |
| Weak        | Yes       | Set Null    |
| Unbreakable | No        | Raise       |

In this case we will use a strong pointer, because we want it to be
deleted if the pointed object is deleted.

```elixir
defmodule MyApp.Repo.Migrations.Hello do
  use Ecto.Migration
  import Pointers.Migration

  def change() do
    create_if_not_exists table(:hello) do
      add :pointer, strong_pointer(), null: false
      add :greeting, :text, null: false
    end
  end
end
```

If you are pointing to a specific table instead of pointer,
`strong_pointer/1` allows you to pass the name of that module
(`strong_pointer/0` calls this with `Pointers.Pointer`).

## Dereferencing Pointers

It is common that even though you have a universal foreign key, you
will want to issue different queries based upon the type that is being
pointed to. For this reason, it is up to you to decide how to perform
an onward query.

`Pointers.schema/1` turns a `Pointer` into an Ecto schema module name
you can switch against. `Pointers.plan` breaks down a list of Pointers
into a map of ids keyed by schema module. It is handy to define some
functions in your (non-library) application that can load any type of
pointer in given contexts.

## Querying Pointers

Since `Pointer` has a table, you can use its `table_id` field to
filter by pointed type. `Pointers.Tables.id!/1` (or `ids!/1` for a
list) can be used to obtain the IDs for a table or tables.

Then you run into another problem, that even though you know all of
the tables you're working with will have a certain field, you need to
know which table they are to work with them! The solution to this is
what we are calling 'mixin tables' for convenience.

A mixin table has a `Pointer` primary key along with any other fields
you wish to store in this mixin. By moving fields out to mixin tables,
you gain knowledge of the table name to which you need to join.

An example mixin schema:

```elixir
defmodule My.Creator
  use Pointers.Mixin,
    otp_app: :my_app,
    source: "creator"

  mixin_schema do
    belongs_to :creator, My.User
  end
end
```

Mixin tables are not themselves pointable, so there is no need to
specify a table id as when defining a pointable schema.

The migration for this is slightly more complicated:

```elixir
defmodule My.Creator.Migration do

  import Ecto.Migration
  import Pointers.Migration

  defp creator_table(), do: My.Creator.__schema__(:source)
  defp user_table(), do: My.User.__schema__(:source)

  def migrate_creator(index_opts \\ []),
    do: migrate_creator(index_opts, direction())

  defp migrate_creator(index_opts, :up) do
    create_mixin_table(creator_table()) do
      add :creator_id, strong_pointer(user_table()), null: false 
    end
    create_if_not_exists(unique_index(creator_table(), [:creator_id], index_opts))
  end

  defp migrate_creator(index_opts, :down) do
    drop_if_exists(unique_index(creator_table(), [:creator_id], index_opts))
    drop_mixin_table(creator_table())
  end
end
```

## Elixir-based logic

The practical result of pointers is that it pushes a certain amount of
validation and consistency logic back into elixir land. It is
therefore your elixir code's responsibility to ensure that data is
inserted into the appropriate mixin tables when inserting a pointable
object and to manage deletions as appropriate.

When assembling queries with mixin tables, pay careful attention to
the type of join you are performing. An inner join is explicitly
asking not to be shown objects that do not have a record for that
mixin. You quite possibly wanted to left join.

## Configuration and overrides

Every pointable or mixin schema is overrideable with configuration
during compilation (this is why using them requires an `:otp_app` to
be specified). For example, we could override `Pointers.Table` (which
is a pointable table) thus:

```elixir
config :pointers, Pointers.Table, source: "my_pointers_table"
```

The `table_id` is also configurable, but we don't recommend you change it.

In addition, all pointable and mixin schemas permit extension with
[Flexto](https://github.com/commonspub/flexto). See the [Flexto
docs](https://hexdocs.pm/flexto/) for more information about how to
extend schemas via configuration. You will probably at the very least
want to insert some `has_one` for mixins off your pointables.

## Tradeoffs

All solutions to the universal foreign key problem have tradeofs. Here
are what we see as the deficiencies in our approach:

1. It forces a ULID on you. This is great for us, but not
   everyone. ULID exposes a timestamp with millisecond precision. If
   the time of creation of a resource is sensitive information for
   your purposes, ULIDs are not going to be suitable for you.
2. Ecto has no knowledge of the specialty of `Pointer`,
   e.g. `Repo.preload` does not work and you need to specify a join
   condition to join through a pointer. Use our functions.
3. Dereferencing a list of pointers requires a select query per table
   type that occurs in the input set.
4. Reliance on user attention. You have to follow the instructions
   correctly to make the system work at all.
5. There is likely some performance impact from postgres not
   understanding the relationships between the various tables
   properly. It's hard to gauge and we haven't even tried.

These are not likely to change. If you're going to pick
this library, do so in the full knowledge of the tradeoffs it makes.

Alternatives include (I'm sure you can think of others):

* Storing the table name in a second column alongside every foreign key.
* A compound datatype of id and table name.
* Byte/String manipulation tricks.
* Evil SQL hacks based upon compile time configuration.

While we have our gripes with this approach, once you've gotten the
hang of using it, it works out pretty well for most purposes and it's
one of the simpler options to work with.

## TODO

* Docs!
* Tests!
* `mix pointers.gen.migration.init` task to generate an init migration.
* `mix pointers.gen.schema.pointable` task to generate a pointable schema.
* `mix pointers.gen.schema.mixin` task to generate a mixin schema.
* Make sure table names are configurable when doing an OTP release

## Copyright and License

Copyright (c) 2020 pointers Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
