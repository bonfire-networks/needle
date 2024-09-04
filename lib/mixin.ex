defmodule Needle.Mixin do
  @moduledoc """
  If a Pointer represents an object, mixins represent data about the object. Mixins collate optional
  additional information about an object. Different types of object will typically make use of
  different mixins. You can see these as aspects of the data if you like.

  A mixin table starts with an `id` column which references `Pointer` and forms the default primary
  key. It is up to the user to choose which other fields go in the table, and thus what the mixin is for.

  Use of a mixin is typically through `has_one`:

  ```
  has_one :my_mixin, MyMixin, foreign_key: :id, references: :id
  ```

  Sometimes, the user may wish to add fields to the primary key by using the `primary_key: true`
  option to `add` in their migrations. This is permitted and in such case we call the resulting
  mixin a `multimixin`. Use becomes `has_many`:

  ```
  has_many :my_mixin, MyMixin, foreign_key: :id, references: :id
  ```

  Thus the choice of single or multi comes down to how many times you want to store that data for
  the object. A user's profile naturally lends itself to a regular `single` mixin, whereas an
  object's appearance in a feed would naturally lend itself to being a multimixin since the object
  may appear in many feeds.

  ### Declaring a mixin table type

  ```
  defmodule My.Mixin do

    use Needle.Mixin,
      otp_app: :my_app,
      source: "postgres_table_name"

    mixin_schema do
      field :is_awesome, :boolean
    end
  end
  ```
  """

  # alias Ecto.Changeset
  alias Needle.{UID, Util}

  defmacro __using__(options), do: using(__CALLER__.module, options)

  @must_be_in_module "Needle.Mixin may only be used inside a defmodule!"

  def using(nil, _options),
    do: raise(RuntimeError, description: @must_be_in_module)

  def using(module, options) do
    otp_app = Util.get_otp_app(options)
    Util.get_source(options)
    config = Application.get_env(otp_app, module, [])
    Module.put_attribute(module, __MODULE__, options)
    pointers = emit_pointers(config ++ options)

    quote do
      use Ecto.Schema
      require Needle.Changesets
      use Exto
      import Needle.Mixin

      # this is an attempt to help mix notice that we are using the configuration at compile
      # time. In exto, for reasons, we already had to use Application.get_env
      _dummy_compile_env = Application.compile_env(unquote(otp_app), unquote(module))

      unquote_splicing(pointers)
    end
  end

  @must_use "You must use Needle.Mixin before calling mixin_schema/1"

  defmacro mixin_schema(do: body) do
    module = __CALLER__.module
    schema_check_attr(Module.get_attribute(module, __MODULE__), module, body)
  end

  @timestamps_opts [type: :utc_datetime_usec]
  @foreign_key_type UID

  defp schema_check_attr(options, module, body) when is_list(options) do
    otp_app = Util.get_otp_app(options)
    config = Application.get_env(otp_app, module, [])
    source = Util.get_source(config ++ options)

    foreign_key = Module.get_attribute(module, :foreign_key_type, @foreign_key_type)

    timestamps_opts = Module.get_attribute(module, :timestamps_opts, @timestamps_opts)

    quote do
      @primary_key false
      @foreign_key_type unquote(foreign_key)
      @timestamps_opts unquote(timestamps_opts)
      schema(unquote(source)) do
        belongs_to(:pointer, Needle.Pointer,
          foreign_key: :id,
          on_replace: :update,
          primary_key: true,
          type: Needle.UID
        )

        unquote(body)
        Exto.flex_schema(unquote(otp_app))
      end
    end
  end

  defp schema_check_attr(_, _, _), do: raise(ArgumentError, message: @must_use)

  # defines __pointers__
  defp emit_pointers(config) do
    otp_app = Keyword.fetch!(config, :otp_app)

    [
      Util.pointers_clause(:role, :mixin),
      Util.pointers_clause(:otp_app, otp_app)
    ]
  end
end
