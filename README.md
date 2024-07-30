# Needles and Pointers: Universal foreign keys, virtual schemas, and shared data fields for Ecto

> One foreign key to rule them all and in the darkness, bind them. - Gandalf, paraphrased.

[![hex.pm](https://img.shields.io/hexpm/v/needle)](https://hex.pm/packages/needle)
[hexdocs](https://hexdocs.pm/needle)

## Intro

Bonfire uses the excellent PostgreSQL database for most data storage. PostgreSQL allows us to make a wide range of queries and to make them relatively fast while upholding data integrity guarantees.

Postgres is a relational schema-led database - it expects you to pre-define tables and the fields in each table (represented in tabular form, i.e. as a collection of tables with each table consisting of a set of rows and columns). Fields can contain data or a reference to a row in another table. 

This usually means that a field containing a reference has to be pre-defined with a foreign key pointing to a specific field (typically a primary key, like an ID column) *in a specific table*. 

A simple example would be a blogging app, which might have a `post` table with `author` field that references the `user` table.

A social network, by contrast, is actually a graph of objects. Objects need to be able to refer to other objects by their ID without knowing their type. 

A simple example would be likes, you might have a `likes` table with `liked_post_id` field that references the `post` table. But you don't just have posts that can be liked, but also videos, images, polls, etc, each with their own table, but probably do not want to have to add `liked_video_id`, `liked_image_id`, etc?

We needed the flexibility to have a foreign key that can reference any referenceable object. We call our system `Needle`.

This guide is a brief introduction to Needle. It assumes some foundational knowledge:

* Basic understanding of how relational databases like Postgresql work, in particular:
  * Tables being made up of fields.
  * What a primary key is and why it's useful.
  * Foreign keys and relationships between tables (1 to 1, 1 to Many, Many to 1, Many to Many).
  * Views as virtual tables backed by a SQL query.

* Basic understanding of Elixir (enough to follow the examples).
* Basic working knowledge of the [Ecto](https://hexdocs.pm/ecto/Ecto.html) database library (schema and migration definitions)


## What is Needle?

A means of foreign keying many tables in one field. Designed for highly interlinked data in highly dynamic schemata where tracking all the foreign keys is neither desired nor practical.

> A universal foreign key is actually a hard problem. Many approaches are on offer with a variety of tradeoffs. If plugging into Bonfire's Needle-based core extensions isn't a requirement for you (i.e. you don't need to put things into feeds or use boundaries for access-control) should carefully consider a variety of approaches rather than just blindly adopting the one that fitted our project's needs the best!


## Identifying objects - the ULID type

All referenceable objects in the system have a unique ID (primary key) whose type is the `Needle.ULID`. [ULIDs](https://github.com/ulid/spec) are a lot like a `UUID` in that you can generate unique ones independently of the database. It's also a little different, being made up of two parts:

* The current timestamp, to millisecond precision.
* Strong random padding for uniqueness.

This means that it naturally sorts by time to the millisecond (close enough for us), giving us a performance advantage compared to queries ordered by a separate creation datetime field (by contrast, UUIDv4 is randomly distributed).

If you've only worked with integer primary keys before, you are probably used to letting the database dispense an ID for you. With `ULID` (or `UUID`), IDs can be known *before* they are stored, greatly easing the process of storing a graph of data and allowing us to do more of the preparation work outside of a transaction for increased performance.

In PostgreSQL, we actually store `ULID`s as `UUID` columns, thanks to both being the same size (and the lack of a `ULID` column type shipping with postgresql). You mostly will not notice this because it's handled for you, but there are a few places it can come up:

* Ecto debug and error output may show either binary values or UUID-formatted values.
* Hand-written SQL may need to convert table IDs to the `UUID` format before use.


## It's just a table

The `Needle` system is mostly based around a single table represented by the `Needle.Pointer` schema with the following fields:

* `id` (ULID) - the database-wide unique id for the object, primary key.
* `table_id` (ULID) - identifies the type of the object, references `Needle.Table`.
* `deleted_at` (timestamp, default: `null`) - when the object was deleted.

Every object that is stored in the system will have a record in this table. It may also have records in other tables (handy for storing more than 3 fields about the object!).

A `Table` is a record of a table that may be linked to by a pointer. A `Pointer` is a pointer ID and a table ID.
With these two ingredients, we can construct a means of pointing to any table that has a `Table` entry.

But don't worry about `Needle.Table` for now, just know that every object type will have a record there so `Needle.Pointer.table_id` can reference it.


## Installation

Aside from adding the dependency, you will also need to write add a migration to set up the database before you can start writing your regular migrations:

```elixir
defmodule MyApp.Repo.Migrations.InitPointers do
  @moduledoc false
  use Ecto.Migration
  import Needle.Migration

  def up(), do: inits(:up)
  def down(), do: inits(:down)

  defp inits(dir) do
    init_pointers_ulid_extra(dir) # this one is optional but recommended
    init_pointers(dir) # this one is not optional
  end
end
```

> Note: Pointers is already a default dependency of most Bonfire extensions, so you shouldn't need to add the migration if building a new extension.


## Declaring Object Types

### Picking a table id

The first step to declaring a new type is picking a unique table ID in ULID format. 

You could just generate a random ULID, but since these IDs are special, we tend to assign a synthetic ULID that are readable as words so they stand out in debug output.

For example, the ID for the `Feed` table is: `1TFEEDS0NTHES0V1S0FM0RTA1S`, which can be read as "It feeds on the souls of mortals". Feel free to have a little fun coming up with them, it makes debug output a little more cheery! The rules are:

* The alphabet is [Crockford's Base32](https://en.wikipedia.org/wiki/Base32#Crockford's_Base32).
* They must be 26 characters in length.
* The first character must be a digit in the range 0-7.

To help you with this, the `Needle.ULID.synthesise!/1` method takes an alphanumeric binary and tries to return you it transliterated into a valid ULID. Example usage:

```
iex(1)> Needle.ULID.synthesise!("itfeedsonthesouls")

11:20:28.299 [error] Too short, need 9 chars.
:ok
iex(2)> Needle.ULID.synthesise!("itfeedsonthesoulsofmortalsandothers")

11:20:31.819 [warn]  Too long, chopping off last 9 chars
"1TFEEDS0NTHES0V1S0FM0RTA1S"
iex(3)> Needle.ULID.synthesise!("itfeedsonthesoulsofmortals")
"1TFEEDS0NTHES0V1S0FM0RTA1S"
iex(4)> Needle.ULID.synthesise!("gtfeedsonthesoulsofmortals")

11:21:03.268 [warn]  First character must be a digit in the range 0-7, replacing with 7
"7TFEEDS0NTHES0V1S0FM0RTA1S"
```

### Virtual pointables ("virtuals")

`Needle.Virtual` is the simplest and most common type of object. Here's a definition of block:

```elixir
defmodule Bonfire.Data.Social.Block do

  use Needle.Virtual,
    otp_app: :bonfire_data_social,
    table_id: "310CK1NGSTVFFAV01DSSEE1NG1",
    source: "bonfire_data_social_block"

  alias Bonfire.Data.Edges.Edge

  virtual_schema do
    has_one :edge, Edge, foreign_key: :id
  end
end
```

It should look quite similar to a mixin definition, except that we `use` `Needle.Virtual` this time (passing an additional `table_id` argument) and we call the `virtual_schema` macro.

The primary limitation of a virtual is that you cannot put extra fields on it. This also means that `belongs_to` is not generally permitted because it results in adding a field, while `has_one` and `has_many` work just fine as they do not cause the creation of fields in the schema.

This is not usually a problem, as extra fields can be put into [mixins](mixins-storing-data-about-objects) or [multimixins](#multimixins) as appropriate.

In all other respects, they behave like Pointables. You can have changesets over them and select and insert as usual.

> Under the hood, a virtual has a writable view (in the above example, called `bonfire_data_social_block`). It looks like a table with just an id, but it's populated with all the ids of blocks that have not been deleted. When the view is inserted into, a record is created in the `pointers` table for you transparently. When you delete from the view, the corresponding `pointers` entry is marked deleted for you.

> Before introducing Virtuals, we noticed it was very common to create Pointables with no extra fields just so we could use the Needle system. Virtuals are alternative for this case that requires less typing and provides a reduced overhead vs pointable (as they save the cost of maintaining a primary key in that table and the associated disk space).


### Pointables

The other, lesser used, type of object is called the `Needle.Pointable`. The major difference is that unlike the simple case of virtuals, pointables are not backed by views, but by tables.

> When a record is inserted into a pointable table, a copy is made in the `pointers` table for you transparently. When you delete from the table, the the corresponding `pointers` entry is marked deleted for you. In these ways, they behave very much like virtuals. By having a table, however, we are free to add new fields.

Pointables pay for this flexibility by being slightly more expensive than virtuals:

* Records must be inserted into/deleted from two tables (the pointable's table and the `pointers` table).
* The pointable table needs its own primary key index.

The choice of using a pointable instead of a virtual combined with one or more mixins is ultimately up to you.

Here is a definition of a pointable type (indicating an ActivityPub activity whose type we don't recognise, stored as a JSON blob):

```elixir
defmodule Bonfire.Data.Social.APActivity do

  use Needle.Pointable,
    otp_app: :bonfire_data_social,
    table_id: "30NF1REAPACTTAB1ENVMBER0NE",
    source: "bonfire_data_social_apactivity"

  pointable_schema do
    field :json, :map
  end
end
```


> As you can see, to declare a pointable schema, we start by using `Needle.Pointable`, providing the name of our otp application, the source table's name in the database and our chosen sentinel ULID.

> We then call `pointable_schema` and define any fields we wish to put directly in the table. For the most part, `pointable_schema` is like Ecto's `schema` macro, except you do not provide the table name and let it handle the primary key.

> If for some reason you wished to turn ID autogeneration off, you could pass `autogenerate: false` to the options provided when using `Needle.Pointable`.


## Adding re-usable fields

### Mixins - storing data about objects

Mixins are tables which contain extra information on behalf of objects. Each object can choose to
record or not record information for each mixin. Sample mixins include:

* user profile (containing a name, location and summary)
* post content (containing the title, summary, and/or html body of a post or message)
* created (containing the id of the object creator)

In this way, they are reusable across different object types. One mixin may (or may not) be used by any number of objects. This is mostly driven by the type of the object we are storing, but can also be driven by user input.

Mixins are just tables too! The only requirement is they have a `ULID` primary key which references `Needle.Pointer`. The developer of the mixin is free to put whatever other fields they want in the table, so long as they have that primary-key-as-reference (which will be automatically added for you by the `mixin_schema` macro). 

Here is a sample mixin definition for a user profile:

```elixir
defmodule Bonfire.Data.Social.Profile do

  use Needle.Mixin,
    otp_app: :bonfire_data_social,
    source: "bonfire_data_social_profile"

  mixin_schema do
    field :name, :string
    field :summary, :string
    field :website, :string
    field :location, :string
  end
end
```

> Mixin tables are not themselves pointable, so there is no need to specify a table id as when defining a pointable schema.

Aside from `use`ing `Needle.Mixin` instead of `Ecto.Schema` and calling `mixin_schema` instead of
`schema`, pretty similar to a standard Ecto schema, right? 

The arguments to `use Needle.Mixin` are:

* `otp_app`: the OTP app name to use when loading dynamic configuration, e.g. the current extension or app (required)
* `source`: the underlying table name to use in the database

We will cover dynamic configuration later. For now, you can use the OTP app that includes the module.

### Multimixins

Multimixins are like mixins, except that where an object may have 0 or 1 of a particular mixins, an object may have any number of a particular multimixin.

For this to work, a multimixin must have a *compound primary key* which must contain an `id` column referencing `Needle.Pointer` and at least one other field which will collectively be unique.

An example multimixin is used for publishing an item to feeds:

```elixir
defmodule Bonfire.Data.Social.FeedPublish do

  use Needle.Mixin,
    otp_app: :bonfire_data_social,
    source: "bonfire_data_social_feed_publish"

  alias Needle.Pointer

  mixin_schema do
    belongs_to :feed, Pointer, primary_key: true
  end
end
```

Notice that this looks very similar to defining a mixin. Indeed, the only difference is the `primary_key: true` in this line, which adds a second field to the compound primary key.
This results in ecto recording a compound primary key of `(id, feed_id)` for the schema (the id is added for you as with regular mixins).




## Writing Migrations

Migrations are typically included along with the schemas as public APIs you can call within your project's migrations.

### Virtuals

Most virtuals are incredibly simple to migrate for:

```elixir
defmodule Bonfire.Data.Social.Post.Migration do

  import Needle.Migration
  alias Bonfire.Data.Social.Post

  def migrate_post(), do: migrate_virtual(Post)

end
```

If you need to do more work, it can be a little trickier. Here's an example for `block`, which also creates a unique index on another table:

```elixir
defmodule Bonfire.Data.Social.Block.Migration do

  import Ecto.Migration
  import Needle.Migration
  import Bonfire.Data.Edges.Edge.Migration
  alias Bonfire.Data.Social.Block

  def migrate_block_view(), do: migrate_virtual(Block)

  def migrate_block_unique_index(), do: migrate_type_unique_index(Block)

  def migrate_block(dir \\ direction())

  def migrate_block(:up) do
    migrate_block_view()
    migrate_block_unique_index()
  end

  def migrate_block(:down) do
    migrate_block_unique_index()
    migrate_block_view()
  end

end
```

Notice how we have to write our `up` and `down` versions separately to get the correct ordering of operations. 

### Pointables

Migration example for a `Pointable`:

```elixir
defmodule Bonfire.Data.Social.APActivity.Migration do
  @moduledoc false
  use Ecto.Migration
  import Needle.Migration
  alias Bonfire.Data.Social.APActivity

  defp make_apactivity_table(exprs) do
    quote do
      require Needle.Migration
      Needle.Migration.create_pointable_table(Bonfire.Data.Social.APActivity) do
        Ecto.Migration.add :json, :jsonb
        unquote_splicing(exprs)
      end
    end
  end

  defmacro create_apactivity_table, do: make_apactivity_table([])
  defmacro create_apactivity_table([do: body]), do: make_apactivity_table(body)

  def drop_apactivity_table(), do: drop_pointable_table(APActivity)

  defp maa(:up), do: make_apactivity_table([])
  defp maa(:down) do
    quote do: Bonfire.Data.Social.APActivity.Migration.drop_apactivity_table()
  end

  defmacro migrate_apactivity() do
    quote do
      if Ecto.Migration.direction() == :up,
        do: unquote(maa(:up)),
        else: unquote(maa(:down))
    end
  end

end
```

As you can see, this `Pointable` migration a little trickier to define than a `Virtual` because we wanted to preserve the ability for the user to define extra fields in config. There are some questions about how useful this is in practice, so you could also go for a simpler option:

```elixir
defmodule MyApp.Repo.Migrations.Greeting do
  @moduledoc false
  use Ecto.Migration
  import Needle.Migration

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

> As you can see, it's pretty similar to defining a regular migration, except you use `create_pointable_table` and
`drop_pointable_table`. Notice that our sentinel ULID makes an appearance again here. It's *very* important that these match what we declared in the schema.

### Mixins

Mixins look much like pointables:

```elixir
defmodule Bonfire.Data.Social.Profile.Migration do

  import Needle.Migration
  alias Bonfire.Data.Social.Profile

  # create_profile_table/{0,1}

  defp make_profile_table(exprs) do
    quote do
      require Needle.Migration
      Needle.Migration.create_mixin_table(Bonfire.Data.Social.Profile) do
        Ecto.Migration.add :name, :text
        Ecto.Migration.add :summary, :text
        Ecto.Migration.add :website, :text
        Ecto.Migration.add :location, :text
        Ecto.Migration.add :icon_id, strong_pointer(Bonfire.Files.Media)
        Ecto.Migration.add :image_id, strong_pointer(Bonfire.Files.Media)
        unquote_splicing(exprs)
      end
    end
  end

  defmacro create_profile_table(), do: make_profile_table([])
  defmacro create_profile_table([do: {_, _, body}]), do: make_profile_table(body)

  # drop_profile_table/0

  def drop_profile_table(), do: drop_mixin_table(Profile)

  # migrate_profile/{0,1}

  defp mp(:up), do: make_profile_table([])

  defp mp(:down) do
    quote do
      Bonfire.Data.Social.Profile.Migration.drop_profile_table()
    end
  end

  defmacro migrate_profile() do
    quote do
      if Ecto.Migration.direction() == :up,
        do: unquote(mp(:up)),
        else: unquote(mp(:down))
    end
  end

end
```

### Multimixins

Similar to mixins:

```elixir
defmodule Bonfire.Data.Social.FeedPublish.Migration do

  import Ecto.Migration
  import Needle.Migration
  alias Bonfire.Data.Social.FeedPublish

  @feed_publish_table FeedPublish.__schema__(:source)

  # create_feed_publish_table/{0,1}

  defp make_feed_publish_table(exprs) do
    quote do
      require Needle.Migration
      Needle.Migration.create_mixin_table(Bonfire.Data.Social.FeedPublish) do
        Ecto.Migration.add :feed_id,
          Needle.Migration.strong_pointer(), primary_key: true
        unquote_splicing(exprs)
      end
    end
  end

  defmacro create_feed_publish_table(), do: make_feed_publish_table([])
  defmacro create_feed_publish_table([do: {_, _, body}]), do: make_feed_publish_table(body)

  def drop_feed_publish_table(), do: drop_pointable_table(FeedPublish)

  def migrate_feed_publish_feed_index(dir \\ direction(), opts \\ [])
  def migrate_feed_publish_feed_index(:up, opts),
    do: create_if_not_exists(index(@feed_publish_table, [:feed_id], opts))
  def migrate_feed_publish_feed_index(:down, opts),
    do: drop_if_exists(index(@feed_publish_table, [:feed_id], opts))

  defp mf(:up) do
    quote do
      Bonfire.Data.Social.FeedPublish.Migration.create_feed_publish_table()
      Bonfire.Data.Social.FeedPublish.Migration.migrate_feed_publish_feed_index()
    end
  end

  defp mf(:down) do
    quote do
      Bonfire.Data.Social.FeedPublish.Migration.migrate_feed_publish_feed_index()
      Bonfire.Data.Social.FeedPublish.Migration.drop_feed_publish_table()
    end
  end

  defmacro migrate_feed_publish() do
    quote do
      if Ecto.Migration.direction() == :up,
        do: unquote(mf(:up)),
        else: unquote(mf(:down))
    end
  end

  defmacro migrate_feed_publish(dir), do: mf(dir)

end
```

### More examples

Take a look at a few of the migrations in our data libraries. Between them, they cover most
scenarios by now:

* [bonfire_data_social](https://github.com/bonfire-networks/bonfire_data_social/)
* [bonfire_data_access_control](https://github.com/bonfire-networks/bonfire_data_access_control/)
* [bonfire_data_identity](https://github.com/bonfire-networks/bonfire_data_identity/)
* [bonfire_data_edges](https://github.com/bonfire-networks/bonfire_data_edges/) (feat. bonus triggers)

If you want to know exactly what's happening, you may want to read the code for
[Needle.Migration](https://github.com/bonfire-networks/needle/blob/main/lib/migration.ex).


## Configuration and overrides

Every pointable or mixin schema is overrideable with configuration
during compilation (this is why using them requires an `:otp_app` to
be specified). For example, we could override `Needle.Table` (which
is a pointable table) thus:

```elixir
config :needle, Needle.Table, source: "my_pointers_table"
```

The `table_id` is also configurable, but we don't recommend you change it.

In addition, all pointable and mixin schemas permit extension with [Exto](https://github.com/bonfire-networks/exto). See the `Exto`'s docs for more information about how to extend schemas via configuration. You will probably at the very least want to insert some `has_one` for mixins off your pointables.


## Referencing Pointables

Ecto does not know anything about our scheme, so unless we specifically want something to reference one of the pointed tables, we typically `belongs_to` with `Needle.Pointer`. The table in which we do this does not itself need to necessarily be a `Pointable`.

```elixir
defmodule MyApp.Foo do

  use Ecto.Schema

  # regular ecto table, not pointable!
  schema "hello" do
    belongs_to :pointer, Needle.Pointer # who knows what it points to?
  end
end
```

You may choose to reference a specific schema rather than Pointer if it
will only point to a single table. If you do this, you must ensure
that the referenced record exists in that table in the normal
way. There may be some performance benefit, we didn't benchmark it.

The migration is slightly more complex, we have to decide what type of
a pointer it is. Needle come in three categories:

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
  @moduledoc false
  use Ecto.Migration
  import Needle.Migration

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
(`strong_pointer/0` calls this with `Needle.Pointer`).

## Dereferencing Pointables

It is common that even though you have a universal foreign key, you
will want to issue different queries based upon the type that is being
pointed to. For this reason, it is up to you to decide how to perform
an onward query.

`Needle.Pointers.schema/1` turns a `Pointer` into an Ecto schema module name
you can switch against. `Needle.Pointers.plan` breaks down a list of Needle
into a map of ids keyed by schema module. It is handy to define some
functions in your (non-library) application that can load any type of
pointer in given contexts.


## Inserting data

### Elixir-based logic

The practical result of needle is that it pushes a certain amount of
validation and consistency logic back into elixir land. It is
therefore your elixir code's responsibility to ensure that data is
inserted into the appropriate mixin tables when inserting a pointable
object and to manage deletions as appropriate.

When assembling queries with mixin tables, pay careful attention to
the type of join you are performing. An inner join is explicitly
asking not to be shown objects that do not have a record for that
mixin. You quite possibly wanted to left join.

## Querying Needle

Since `Pointer` has a table, you can use its `table_id` field to
filter by pointed type. `Needle.Tables.id!/1` (or `ids!/1` for a
list) can be used to obtain the IDs for a table or tables.


## Tradeoffs

All solutions to the universal primary key problem have tradeofs. Here
are what we see as the deficiencies in our approach:

1. It forces a ULID on you. This is great for us, but not
   everyone. ULID exposes a timestamp with millisecond precision. If
   the time of creation of a resource is sensitive information for
   your purposes, ULIDs are not going to be suitable for you.
2. Ecto has no knowledge of the specialty of `Pointer`,
   e.g. `Repo.preload` does not work and you need to specify a join
   condition to join through a pointer. Use our functions or add extra
   associations with exto configuration.
3. Dereferencing a list of needle requires a select query per table
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



## Copyright and License

Copyright (c) 2020 needle Contributors

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
