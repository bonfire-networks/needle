defmodule Pointers.Changesets do

  alias Pointers.{ULID, Util}
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

  def insert_verb(%_{}=thing), do: if(is_built?(thing), do: :insert, else: :update)

  defp cast(thing, _, nil), do: Changeset.cast(thing, %{}, [])
  defp cast(thing, params, cast) when is_list(cast),
    do: Changeset.cast(thing, Map.delete(params, :cast), cast)

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
        ac(insert_verb(data), data, key, related, params, opts)
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

  def default_id(changeset) do
    case Changeset.get_field(changeset, :id) do
      nil -> Changeset.put_change(changeset, :id, ULID.generate())
      _ -> changeset
    end
  end

end
