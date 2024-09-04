defmodule Needle.Virtual do
  @moduledoc """
  Sets up an Ecto Schema for a Virtual Pointable

  Virtual Pointables (or just `virtuals`) are like pointables with no
  additional columns, except instead of being backed by a table they
  are backed by a view. This is more efficient of resources but only
  works when there are no additional columns to add.

  If you need to add columns to the schema, you should use a pointable.

  ## Sample Usage

  ```
  use Needle.Virtual,
    otp_app: :my_app,   # your OTP application's name
    source: "my_table", # default name of view in database
    table_id: "01EBTVSZJ6X02J01R1XWWPWGZW" # valid UID to identify virtual

  virtual_schema do
    # ... `has_one`, `has_many`, or *virtual* fields ONLY go here.
  end
  ```

  ## Overriding with configuration

  During `use` (i.e. compilation time), we will attempt to load
  configuration from the provided `:otp_app` under the key of the
  current module. Any values provided here will override the defaults
  provided to `use`. This allows you to configure them after the fact.

  Additionally, pointables use `Exto`'s `flex_schema()`, so you can
  provide additional configuration for those in the same place. Unlike
  a regular pointable, you should not add additional
  (non-virtual) fields, but it is permitted to add `has_one` /
  `has_many` associations.

  I shall say it again because it's important: This happens at
  *compile time*. You must rebuild the app containing the pointable
  whenever the configuration changes.

  ## Introspection

  Defines a function `__pointers__/1` to introspect data. Recognised
  parameters:

  `:role` - `:virtual`.
  `:table_id` - retrieves the UID id of the virtual.
  `:otp_app` - retrieves the OTP application to which this belongs.
  """

  alias Needle.Util

  defmacro __using__(options), do: using(__CALLER__.module, options)

  @must_be_in_module "Needle.Virtual may only be used inside a defmodule!"

  defp using(nil, _options),
    do: raise(RuntimeError, description: @must_be_in_module)

  defp using(module, options) do
    # raise early if not present
    get_table_id(options)
    Util.get_source(options)
    app = Util.get_otp_app(options)
    Module.put_attribute(module, __MODULE__, options)
    config = Application.get_env(app, module, [])
    pointers = emit_pointers(config ++ options)

    quote do
      use Ecto.Schema
      use Exto
      require Needle.Changesets
      import Needle.Virtual

      # this is an attempt to help mix notice that we are using the configuration at compile
      # time. In exto, for reasons, we already had to use Application.get_env
      _dummy_compile_env = Application.compile_env(unquote(app), unquote(module))

      unquote_splicing(pointers)
    end
  end

  @bad_table_id "You must provide a UID-formatted binary :table_id option."
  @must_use "You must use Needle.Virtual before calling virtual_schema/1."

  defp get_table_id(opts), do: check_table_id(Keyword.get(opts, :table_id))

  defp check_table_id(x) when is_binary(x),
    do: check_table_id_valid(x, Needle.UID.cast(x))

  defp check_table_id(_), do: raise(ArgumentError, message: @bad_table_id)

  defp check_table_id_valid(x, {:ok, x}), do: x

  defp check_table_id_valid(_, _),
    do: raise(ArgumentError, message: @bad_table_id)

  defmacro virtual_schema(body)

  defmacro virtual_schema(do: body) do
    module = __CALLER__.module
    schema_check_attr(Module.get_attribute(module, __MODULE__), module, body)
  end

  # verifies that the module was `use`d and generates a new schema
  defp schema_check_attr(options, module, body) when is_list(options) do
    otp_app = Keyword.fetch!(options, :otp_app)
    config = Application.get_env(otp_app, module, [])
    source = Util.get_source(config ++ options)

    quote do
      unquote(Util.schema_primary_key(module, options))
      unquote(Util.schema_foreign_key_type(module))

      schema unquote(source) do
        Exto.flex_schema(unquote(otp_app))
        unquote(body)
      end
    end
  end

  defp schema_check_attr(_, _, _), do: raise(RuntimeError, message: @must_use)

  # defines __pointers__
  defp emit_pointers(config) do
    table_id = get_table_id(config)
    otp_app = Util.get_otp_app(config)

    [
      Util.pointers_clause(:role, :virtual),
      Util.pointers_clause(:table_id, table_id),
      Util.pointers_clause(:otp_app, otp_app)
    ]
  end
end
