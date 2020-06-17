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

Dependency:

```elixir
{:pointers, "~> 0.1.0"}
```

You will also need to write a simple migration to set up the database
before you can start writing your regular migrations:

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

## Defining a pointable table

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
  use Pointers.Schema

  pointable_schema("myapp_greeting", "GREET1NGSFR0MD0CEXAMP1E000") do
    field :greeting, :string
  end
end
```

We import `Pointers.Schema` instead of `Ecto.Schema`, use
`pointable_schema` in place of `schema` and provide a sentinel ULID
for our table. Otherwise it's just like a regular schema definition.

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
appearance again here. It's *very* important that these match.

## Referencing with Pointers

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
    field :pointer, Pointer # who knows what it points to?
  end

end
```

If you choose to reference a specific table instead, you must ensure
that the referenced record exists in that table in the normal way.

## Dereferencing with Pointers

Unfortunately, reading pointers is a bit more involved than writing
them. It is likely that depending on the type being pointed to, you
will want to execute different queries.

Given a `Pointer` (such as one preloaded on another table), you can
inspect the table it points to and switch query based upon
this. `Pointers.plan` can turn a list of Pointers into a map of schema
module name to MapSet of ids so you can extend the strategy for bulk.

## Trait tables

An alternative idea I've been playing with recently takes inspiration
from game design, where ECS (entity component system) libraries are
the norm.

Objects normally can be thought of as a set of named fields. In an
ECS, an entity is just an id and it can have any number of
components. A component is the set of named fields traditionally like
an object, except we can have multiple of them.

ECS systems allow preserving the benefits of static typing while
allowing code to only care about the components it cares about. By
carving at the component level, we are able to build on some details
without being fully coupled to the implementation details.

Pointers allow us to point to records in a number of tables in the
database. By using ECS component-style tables (not themselves
pointable), code which cares about certain components may join to
those tables. Thus even though a pointer may point to conceptually
many tables, common components may be queried by code without having
to encode the knowledge of what the types are in the query. It's a bit
like graphql interfaces ("data interfaces") for the database.

When inserting a pointable type, it is up to the user's code to insert
the components they care about. When updating one, perhaps the
relevant components must be updated. When deleting one, you will have
to cascade deletes.

## TODO

* Docs!
* Tests!
* `mix pointers.gen.init` task to generate an init migration
* `mix pointers.gen.migration` task to generate a skeleton migration

### What lurks underneath?

`pointable_schema(name, id, block)`:

* create ecto schema configured with a ULID primary key
* create `table_id/0` returning the table's sentinel ULID

`init_pointers(:up)`:

* create tables for `Table` and `Pointer`.
* creates/replaces backing pointer trigger function.
* create backing pointer trigger for `Table` (NOT idempotent).

`init_pointers(:down)`:

* delete backing pointer trigger for `Table` (NOT idempotent).
* delete backing pointer trigger function.
* delete `Table` and `Pointer` tables.

`create_pointable_table(name, block)`:

* create table configured with a ULID primary key.
* create entry in `Table` table.
* create backing pointer trigger for table (NOT idempotent).

`drop_pointable_table(name)`:

* delete backing pointer trigger for table (NOT idempotent).
* delete entry from `Table` table.
* delete table.

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
3. Following a list of pointers requires a select query per table type
   that occurs in the input set.
4. Reliance on user attention. You have to follow the instructions
   correctly to make the system work at all.
5. Nonidempotency of migrations. Part of this is postgres not making
   it convenient, but we can and should do better.

Of these, only the last is likely to change. If you're going to pick
this library, do so in the full knowledge of the tradeoffs it makes.

Alternatives include (I'm sure you can think of others):

* Storing the table name alongside every foreign key.
* Creating a postgres datatype containing the id and table name and using that as a foreign key.
* Byte/String manipulation tricks.

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
