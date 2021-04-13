defmodule Pointers.Changesets do

  alias Pointers.Util
  alias Ecto.Changeset
  alias Ecto.Association.{NotLoaded}

  @doc "Returns the schema object's current state."
  def state(thing), do: thing.__meta__.state

  @doc "True if the schema object's current state is `:built`"
  def is_built?(%_{__meta__: %{state: :built}}), do: true
  def is_built?(_), do: false

  @doc "True if the schema object's current state is `:loaded`"
  def is_loaded?(%_{__meta__: %{state: :loaded}}), do: true
  def is_loaded?(_), do: false

  @doc "True if the schema object's current state is `:deleted`"
  def is_deleted?(%_{__meta__: %{state: :deleted}}), do: true
  def is_deleted?(_), do: false

  def verb(%_{}=thing), do: if(is_built?(thing), do: :insert, else: :update)

  defmacro auto(thing, params, options, defaults) do
    module = __CALLER__.module
    quote bind_quoted: [
      module: module,
      thing: thing,
      params: params,
      options: options,
      defaults: defaults,
    ] do
      Pointers.Changesets.auto(
        thing, params, options, defaults,
        Pointers.Changesets.config_for(module, Pointers.Changesets.verb(thing))
      )
    end
  end

  def auto(thing, params, options, defaults, config) do
    opts = options ++ config ++ defaults
    thing
    |> auto_cast(params, opts)
    |> auto_required(opts[:required])
    |> auto_fields(options, defaults, config) # individual for merge
    |> rewrite_errors(options, config)
  end

  defp auto_cast(thing, params, opts) do
    params = Util.rename(params, Util.add_binaries(Keyword.get(opts, :rename_params, [])))
    cast(thing, params, opts[:cast])
  end

  defp cast(thing, _, nil), do: Changeset.cast(thing, %{}, [])
  defp cast(thing, params, cast) when is_list(cast),
    do: Changeset.cast(thing, Map.delete(params, :cast), cast)

  defp auto_required(changeset, nil), do: changeset
  defp auto_required(changeset, []), do: changeset
  defp auto_required(changeset, req) when is_list(req),
    do: Changeset.validate_required(changeset, req)

  defp auto_fields(%Changeset{data: %what{}}=cs, options, defaults, config) do
    fields = what.__schema__(:fields) -- [:id]
    Enum.reduce(fields, cs, fn field, cs ->
      opts =
        Keyword.get(options, field, []) ++ # last moment overrides
        Keyword.get(config, field, []) ++ # configuration overrides
        Keyword.get(defaults, field, []) # vendor values
      cs
      |> auto_acceptance(field, opts[:acceptance])
      |> auto_exclusion(field,  opts[:exclusion])
      |> auto_format(field,     opts[:format])
      |> auto_inclusion(field,  opts[:inclusion])
      |> auto_length(field,     opts[:length])
      |> auto_number(field,     opts[:number])
      |> auto_subset(field,     opts[:subset])
    end)
  end

  defp auto_acceptance(changeset, field, true),
    do: Changeset.validate_acceptance(changeset, field)
  defp auto_acceptance(changeset, _field, _), do: changeset

  defp auto_exclusion(changeset, _field, nil), do: changeset
  defp auto_exclusion(changeset, field, excl),
    do: Changeset.validate_exclusion(changeset, field, excl)

  defp auto_format(changeset, _key, nil), do: changeset
  defp auto_format(changeset, _key, []), do: changeset
  defp auto_format(changeset, key, %Regex{}=format),
    do: Changeset.validate_format(changeset, key, format)

  defp auto_format(_changeset, key, invalid),
      do: throw {:invalid_format_regexp, regexp: invalid, key: key}


  defp auto_inclusion(changeset, _field, nil), do: changeset

  defp auto_inclusion(changeset, field, incl) when is_list(incl),
    do: Changeset.validate_inclusion(changeset, field, incl)

  defp auto_inclusion(_changeset, key, invalid),
    do: throw {:invalid_inclusion_list, value: invalid, key: key}


  defp auto_length(changeset, _key, nil), do: changeset
  defp auto_length(changeset, _key, []), do: changeset
  defp auto_length(changeset, key, opts),
    do: Changeset.validate_length(changeset, key, opts)

  defp auto_number(changeset, _key, nil), do: changeset
  defp auto_number(changeset, _key, []), do: changeset
  defp auto_number(changeset, key, opts),
    do: Changeset.validate_number(changeset, key, opts)

  defp auto_subset(changeset, _key, nil), do: changeset
  defp auto_subset(changeset, _key, []), do: changeset
  defp auto_subset(changeset, key, opts),
    do: Changeset.validate_subset(changeset, key, opts)

  def replicate_map_change(changeset, source_key, target_key, xform) do
    case Changeset.fetch_change(changeset, source_key) do
      {:ok, change} ->
        Changeset.put_change(changeset, target_key, xform.(change))
      _ -> changeset
    end
  end

  def replicate_map_valid_change(%Changeset{valid?: true}=changeset, source_key, target_key, xform) do
    case Changeset.fetch_change(changeset, source_key) do
      {:ok, change} ->
        Changeset.put_change(changeset, target_key, xform.(change))
      _ -> changeset
    end
  end
  def replicate_map_valid_change(changeset, _, _, _), do: changeset

  def config_for(module) do
    otp_app = module.__pointers__(:otp_app)
    conf = Application.get_env(otp_app, module, [])
    conf
  end

  def config_for(module, key, default \\ []) do
    conf = config_for(module)
    val = Keyword.get(conf, key, default)
    if is_list(conf) and is_list(val), do: val ++ conf, else: val
  end

  @doc "true if the provided changeset or list of changesets is valid."
  def valid?(%Changeset{valid?: v}), do: v
  def valid?(cs) when is_list(cs), do: Enum.all?(cs, &valid?/1)

  @doc """
  """
  def assoc_changeset(changeset, key, params, opts \\ [])
  def assoc_changeset(%Changeset{data: %schema{}=data}, key, params, opts) do
    case schema.__schema__(:association, key) do
      %{related: related} ->
        ac(verb(data), data, key, related, params, opts)
      _ ->
        raise ArgumentError,
          message: "Invalid relation: #{key} on #{schema}"
    end
  end

  defp ac(:create, %_{}, _, related, params, opts),
    do: ac_call(related, [struct(related), params], opts)

  defp ac(:update, %_{}=data, key, related, params, opts) do
    case Map.get(data, key) do
      %NotLoaded{} ->
        raise ArgumentError,
          message: "You must preload an assoc before casting to it (or set it to nil or the empty list depending on cardinality)."

      %_{}=other -> ac_call(related, [other, params], opts)
      # [other | _] -> acc_call(related, [other, params]) # TODO
      [] -> ac_call(related, [struct(related), params], opts)
      nil -> ac_call(related, [struct(related), params], opts)
    end
  end

  defp ac_call(schema, args, []), do: call(schema, :changeset, args)
  defp ac_call(schema, args, opts), do: call_extra(schema, :changeset, args, [opts])

  def put_assoc(changeset, key, mixin_changeset)

  def put_assoc(%Changeset{}=cs, key, %Changeset{valid?: true}=mixin),
    do: Changeset.put_assoc(cs, key, mixin)

  def put_assoc(%Changeset{}=cs, _, %Changeset{valid?: false}=mixin),
    do: %{ cs | valid?: false, errors: cs.errors ++ mixin.errors }

  def cast_assoc(%Changeset{}=cs, key, params, opts \\ []),
    do: put_assoc(cs, key, assoc_changeset(cs, key, params, opts))

  defp call_extra(module, func, args, extra) when is_list(extra) do
    Code.ensure_loaded(module)
    size = Enum.count(args)
    function_exported?(module, func, size + Enum.count(extra))
    |> ce(module, func, args, extra, size)
  end

  defp ce(true, module, func, args, extra, _), do: apply(module, func, args ++ extra)
  defp ce(false, module, func, args, _, size),
    do: c2(function_exported?(module, func, size), module, func, args)

  defp call(module, func, args) when is_list(args) do
    Code.ensure_loaded(module)
    size = Enum.count(args)
    c2(function_exported?(module, func, size), module, func, args)
  end

  defp c2(true, module, func, args), do: apply(module, func, args)
  defp c2(false, module, func, args) do
    raise ArgumentError,
      message: "Function not found: #{module}.#{func}, args: #{inspect(args)}"
  end

  def rewrite_errors(%Changeset{errors: errors}=cs, options, config) do
    errs = Keyword.get(options ++ config, :rename_params, [])
    %{ cs | errors: Util.rename(errors, Util.flip(errs)) }
  end

  def rewrite_child_errors(%Changeset{data: %what{}}=cs) do
    rewrite_errors(cs, [], config_for(what))
  end

  def rewrite_constraint_errors(%Changeset{}=c) do
    changes = Enum.reduce(c.changes, c.changes, &rce_changes/2)
    errors = c.errors ++ Enum.flat_map(changes, &rce_errors/1)
    {:error, %{ c | changes: changes, errors: errors }}
  end

  defp rce_changes({k, %Changeset{valid?: false}=v}, acc), do: Map.put(acc, k, rewrite_child_errors(v))
  defp rce_changes(_, acc), do: acc

  defp rce_errors({_, %Changeset{valid?: false, errors: e}}), do: e
  defp rce_errors(_), do: []

  def merge_child_errors(%Changeset{}=cs),
    do: Enum.reduce(cs.changes, cs, &merge_child_errors/2)

  defp merge_child_errors({_k, %Changeset{}=cs}, acc), do: cs.errors ++ acc
  defp merge_child_errors(_, acc), do: acc

end
