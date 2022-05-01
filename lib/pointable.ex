defmodule Pointers.Pointable do
  @moduledoc """
  Sets up an Ecto Schema for a Pointable table.

  ## Sample Usage

  ```
  use Pointers.Pointable,
    otp_app: :my_app,   # your OTP application's name
    source: "my_table", # default name of table in database
    table_id: "01EBTVSZJ6X02J01R1XWWPWGZW" # unique ULID to identify table

  pointable_schema do
    # ... fields go here, if any
  end
  ```

  ## Overriding with configuration

  During `use` (i.e. compilation time), we will attempt to load
  configuration from the provided `:otp_app` under the key of the
  current module. Any values provided here will override the defaults
  provided to `use`. This allows you to configure them after the fact.

  Additionally, pointables use `Flexto`'s `flex_schema()`, so you can
  provide additional configuration for those in the same place.

  I shall say it again because it's important: This happens at
  *compile time*. You must rebuild the app containing the pointable
  whenever the configuration changes.

  ## Introspection

  Defines a function `__pointers__/1` to introspect data. Recognised
  parameters:

  `:role` - `:pointable`
  `:table_id` - retrieves the ULID id of the pointable table.
  `:otp_app` - retrieves the OTP application to which this belongs.
  """

  alias Pointers.Util

  defmacro __using__(options), do: using(__CALLER__.module, options)

  @must_be_in_module "Pointers.Pointable may only be used inside a defmodule!"

  defp using(nil, _options), do: raise RuntimeError, description: @must_be_in_module
  defp using(module, options) do
    # raise early if not present
    Util.get_source(options)
    get_table_id(options)
    app = Util.get_otp_app(options)
    Module.put_attribute(module, __MODULE__, options)
    config = Application.get_env(app, module, [])
    pointers = emit_pointers(config ++ options)
    quote do
      use Ecto.Schema
      require Flexto
      require Pointers.Changesets
      import Pointers.Pointable
      # this is an attempt to help mix notice that we are using the configuration at compile
      # time. In flexto, for reasons, we already had to use Application.get_env
      _dummy_compile_env = Application.compile_env(unquote(app), unquote(module))
      unquote_splicing(pointers)
    end
  end

  @bad_table_id "You must provide a ULID-formatted binary :table_id option."
  @must_use "You must use Pointers.Pointable before calling pointable_schema/1."

  defp get_table_id(opts), do: check_table_id(Keyword.get(opts, :table_id))

  defp check_table_id(x) when is_binary(x), do: check_table_id_valid(x, Pointers.ULID.cast(x))
  defp check_table_id(_), do: raise ArgumentError, message: @bad_table_id

  defp check_table_id_valid(x, {:ok, x}), do: x
  defp check_table_id_valid(_, _), do: raise ArgumentError, message: @bad_table_id

  defmacro pointable_schema(body)
  defmacro pointable_schema([do: body]) do
    module = __CALLER__.module
    schema_check_attr(Module.get_attribute(module, __MODULE__), module, body)
  end

  @default_timestamps_opts [type: :utc_datetime_usec]

  # verifies that the module was `use`d and generates a new schema
  defp schema_check_attr(options, module, body) when is_list(options) do
    otp_app = Keyword.fetch!(options, :otp_app)
    config = Application.get_env(otp_app, module, [])
    source = Util.get_source(config ++ options)
    quote do
      unquote(Util.schema_primary_key(module, options))
      unquote(Util.schema_foreign_key_type(module))
      unquote(Util.put_new_attribute(module, :timestamps_opts, @default_timestamps_opts))
      schema unquote(source) do
        unquote(body)
        Flexto.flex_schema(unquote(otp_app))
      end
    end
  end

  defp schema_check_attr(_, _, _), do: raise RuntimeError, message: @must_use

  # defines __pointers__
  defp emit_pointers(config) do
    table_id = Pointers.ULID.cast!(Keyword.fetch!(config, :table_id))
    otp_app = Keyword.fetch!(config, :otp_app)
    [ Util.pointers_clause(:role, :pointable),
      Util.pointers_clause(:table_id, table_id),
      Util.pointers_clause(:otp_app, otp_app),
    ]
  end

end
