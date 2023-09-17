defmodule Pointers.Changesets do
  require Logger

  alias Pointers.{ULID, Util}
  alias Ecto.Association.{BelongsTo, Has, NotLoaded}
  alias Ecto.{Changeset, Schema.Metadata}

  @doc "Returns the schema object's current state."
  def state(thing), do: thing.__meta__.state

  @doc "True if the schema object's current state is `:built`"
  def built?(%_{__meta__: %{state: :built}}), do: true
  def built?(_), do: false

  @doc "True if the schema object's current state is `:loaded`"
  def loaded?(%_{__meta__: %{state: :loaded}}), do: true
  def loaded?(_), do: false

  @doc "True if the schema object's current state is `:deleted`"
  def deleted?(%_{__meta__: %{state: :deleted}}), do: true
  def deleted?(_), do: false

  @doc "true if the provided changeset or list of changesets is valid."
  def valid?(%Changeset{valid?: v}), do: v
  def valid?(cs) when is_list(cs), do: Enum.all?(cs, &valid?/1)

  def insert_verb(%_{} = thing),
    do: if(built?(thing), do: :insert, else: :update)

  # here be dragons
  @doc false
  def set_state(%_{__meta__: meta} = orig, to),
    do: Map.put(orig, :__meta__, set_state(meta, to))

  def set_state(%Metadata{state: _} = orig, to), do: Map.put(orig, :state, to)

  @doc """
  Like `Ecto.Changeset.cast` but for Pointables, Virtuals and Mixins.

  If a pointable or virtual, Generates an ID if one is not present.
  """
  def cast(changeset, params, cols) do
    case changeset do
      # for :loaded things, we just cast them as their ids already exist
      %{__meta__: %{state: :loaded}} ->
        Changeset.cast(changeset, params, cols)

      %Changeset{data: %{__meta__: %{state: :loaded}}} ->
        Changeset.cast(changeset, params, cols)

      # for :built things, we should autogenerate an id if one is not
      # present and it is a pointable or virtual type
      %Changeset{data: %schema{__meta__: %{state: :built}}} ->
        if Util.role(schema) not in [:pointable, :virtual] or
             is_binary(get_field(changeset, :id)) do
          Changeset.cast(changeset, params, cols)
        else
          changeset
          |> Changeset.cast(params, cols)
          |> put_new_id()
        end

      %schema{__meta__: %{state: :built}} ->
        if Util.role(schema) in [:pointable, :virtual] do
          changeset
          |> Changeset.cast(params, cols)
          |> put_new_id()
        else
          Changeset.cast(changeset, params, cols)
        end
    end
  end

  def put_new_id(changeset) do
    if is_binary(get_field(changeset, :id)) do
      changeset
    else
      changeset
      |> Changeset.put_change(:id, ULID.generate())
    end
  end

  @doc """
  Like `Ecto.Changeset.put_assoc/3` but for Pointables, Virtuals and Mixins.

  Copies across keys where possible.
  """
  def put_assoc!(changeset, assoc_key, rels) do
    with {:error, e} <- maybe_put_assoc(changeset, assoc_key, rels) do
      raise RuntimeError, message: e
    end
  end

  @doc """
  Like `put_assoc!/3` but doesn't raise if the association doesn't exist
  """
  def put_assoc(changeset, assoc_key, rels) do
    with {:error, e} <- maybe_put_assoc(changeset, assoc_key, rels) do
      Logger.error(e)
      changeset
    end

    # rescue
    #   e in ArgumentError -> 
    #     IO.warn("Pointers.Changeset: Could not put_assoc #{inspect assoc_key}")
    #     Logger.error(e)
    #     changeset
  end

  defp maybe_put_assoc(
         %Changeset{data: %schema{}} = changeset,
         assoc_key,
         rels
       ) do
    do_maybe_put_assoc(
      schema,
      changeset,
      assoc_key,
      rels
    )
  end

  defp maybe_put_assoc(
         %{__struct__: schema} = object,
         assoc_key,
         rels
       ) do
    do_maybe_put_assoc(
      schema,
      Changeset.cast(object, %{}, []),
      assoc_key,
      rels
    )
  end

  defp do_maybe_put_assoc(
         schema,
         changeset_or_object,
         assoc_key,
         rels
       ) do
    assoc = schema.__schema__(:association, assoc_key)

    case assoc do
      %Has{cardinality: :one} ->
        put_has_one(changeset_or_object, assoc_key, rels, assoc)

      %Has{cardinality: :many} ->
        put_has_many(changeset_or_object, assoc_key, rels, assoc)

      %BelongsTo{} ->
        put_belongs_to(changeset_or_object, assoc_key, rels, assoc)

      _ ->
        {:error, "Cannot put unknown association :#{assoc_key} on %#{schema}{}"}
    end
  end

  # put_assoc for a has_one. copies the owner's key across if one is present
  defp put_has_one(changeset, assoc_key, rel, assoc) do
    case get_field(changeset, assoc.owner_key) do
      nil ->
        Changeset.put_assoc(changeset, assoc_key, rel)

      owner_key ->
        rel = Map.put(rel, assoc.related_key, owner_key)
        Changeset.put_assoc(changeset, assoc_key, rel)
    end
  end

  # put_assoc for a has_many. copies the owner's key across if one is present
  defp put_has_many(changeset, assoc_key, rels, assoc) do
    case get_field(changeset, assoc.owner_key) do
      nil ->
        # Logger.info("put_assoc/put_has_many - assoc has no related key: #{assoc_key}")
        Changeset.put_assoc(changeset, assoc_key, rels)

      owner_key ->
        # Logger.info("put_assoc/put_has_many - assoc related key - #{assoc_key}.#{assoc.related_key}: #{inspect owner_key}")
        rels = Enum.map(rels, &Map.put(&1, assoc.related_key, owner_key))
        # Logger.info("#{assoc_key}: #{inspect rels}")
        Changeset.put_assoc(changeset, assoc_key, rels)
    end
  end

  # put_assoc for a belongs to.
  #
  # * if the rel does not have the related key and that's the :id column, we generate it.
  # * if the rel (now) has the related key, copies it to the parent changeset
  defp put_belongs_to(changeset, assoc_key, rel, assoc) do
    case Map.get(rel, assoc.related_key) do
      nil ->
        if Util.role(assoc.related) && assoc.related_key == :id do
          # Autogenerate the id for them and copy it back
          rel = Map.put(rel, assoc.related_key, ULID.generate())

          changeset
          |> Changeset.put_assoc(assoc_key, rel)
          |> Changeset.put_change(
            assoc.owner_key,
            Map.get(rel, assoc.related_key)
          )
        else
          # Not much we can do but leave it to ecto
          Changeset.put_assoc(changeset, assoc_key, rel)
        end

      # copy it back
      _related_key ->
        Changeset.put_assoc(changeset, assoc_key, rel)
    end
  end

  @doc "Like Ecto.build_assoc/3, but can work with a Changeset"
  def build_assoc(%Changeset{data: %owner{}} = changeset, assoc_key, rel) do
    assoc = owner.__schema__(:association, assoc_key)

    case assoc do
      %Has{cardinality: :one} ->
        case Changeset.apply_action(changeset, :insert) do
          {:ok, data} -> Ecto.build_assoc(data, assoc_key, rel)
          _ -> nil
        end

      %Has{cardinality: :many} ->
        case Changeset.apply_action(changeset, :insert) do
          {:ok, data} -> Enum.map(rel, &Ecto.build_assoc(data, assoc_key, &1))
          _ -> nil
        end

      %BelongsTo{} ->
        raise RuntimeError,
          message: "Expected `has` association in :#{assoc_key} on %#{owner}{}"

      _ ->
        raise RuntimeError,
          message: "Unknown association :#{assoc_key} on %#{owner}{}"
    end
  end

  def build_assoc(%_{} = schema, assoc_key, rel),
    do: Ecto.build_assoc(schema, assoc_key, rel)

  # cast_assoc but does the right thing over a put_assoc
  def cast_assoc(%Changeset{data: %owner{}} = changeset, assoc_key, opts \\ []) do
    assoc = owner.__schema__(:association, assoc_key)

    case assoc do
      %Has{cardinality: :one} ->
        cast_has_one(changeset, assoc_key, assoc, opts)

      %Has{cardinality: :many} ->
        cast_has_many(changeset, assoc_key, assoc, opts)

      %BelongsTo{} ->
        cast_belongs_to(changeset, assoc_key, assoc, opts)

      _ ->
        raise RuntimeError,
          message: "Unknown association :#{assoc_key} on %#{owner}{}"
    end
  end

  def cast_has_one(changeset, assoc_key, _assoc, opts) do
    case Changeset.get_change(changeset, assoc_key) do
      %Changeset{} ->
        # Update the existing changeset
        Changeset.update_change(changeset, assoc_key, fn change ->
          attrs = Map.get(changeset.params, to_string(assoc_key), %{})
          with_ = get_with(changeset, opts)
          with_.(change, attrs)
        end)

      nil ->
        changeset
        |> Changeset.cast_assoc(assoc_key)
    end
  end

  def cast_has_many(changeset, assoc_key, _assoc, opts) do
    Changeset.cast_assoc(changeset, assoc_key, opts)
  end

  def cast_belongs_to(changeset, assoc_key, _assoc, opts) do
    Changeset.cast_assoc(changeset, assoc_key, opts)
  end

  defp get_with(changeset, opts) do
    case Keyword.get(opts, :with) do
      nil -> Function.capture(changeset.data.__struct__, :changeset, 2)
      other -> other
    end
  end

  @doc false
  def assoc_changeset(changeset, key, params, opts \\ [])

  def assoc_changeset(%Changeset{data: %schema{} = data}, key, params, opts) do
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

  defp ac(:update, %_{} = data, key, related, params, opts) do
    case Map.get(data, key) do
      %NotLoaded{} ->
        raise ArgumentError,
          message:
            "You must preload an assoc before casting to it (or set it to nil or the empty list depending on cardinality)."

      %_{} = other ->
        ac_call(related, [other, params], opts)

      # [other | _] -> acc_call(related, [other, params]) # TODO
      [] ->
        ac_call(related, [struct(related), params], opts)

      nil ->
        ac_call(related, [struct(related), params], opts)
    end
  end

  defp ac_call(schema, args, []), do: call(schema, :changeset, args)

  defp ac_call(schema, args, opts),
    do: call_extra(schema, :changeset, args, [opts])

  # @doc "Like `Ecto.Changeset.put_assoc` but copies keys properly"
  # def put_assoc(%Changeset{data: %struct{}}=changeset, key, value_or_values) do
  #   case struct.__schema__(
  # end

  # def put_assoc(%Changeset{}=cs, key, %Changeset{valid?: true}=mixin),
  #   do: Changeset.put_assoc(cs, key, mixin)

  # def put_assoc(%Changeset{}=cs, _, %Changeset{valid?: false}=mixin),
  #   do: %{ cs | valid?: false, errors: cs.errors ++ mixin.errors }

  # def cast_assoc(%Changeset{}=cs, key, params, opts \\ []),
  #   do: put_assoc(cs, key, assoc_changeset(cs, key, params, opts))

  defp call_extra(module, func, args, extra) when is_list(extra) do
    Code.ensure_loaded(module)
    size = Enum.count(args)

    function_exported?(module, func, size + Enum.count(extra))
    |> ce(module, func, args, extra, size)
  end

  defp ce(true, module, func, args, extra, _),
    do: apply(module, func, args ++ extra)

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

  @doc false
  def rewrite_errors(%Changeset{errors: errors} = cs, options, config) do
    errs = Keyword.get(options ++ config, :rename_params, [])
    %{cs | errors: Util.rename(errors, Util.flip(errs))}
  end

  @doc false
  def rewrite_child_errors(%Changeset{data: %what{}} = cs) do
    rewrite_errors(cs, [], config_for(what))
  end

  @doc false
  def rewrite_constraint_errors(%Changeset{} = c) do
    changes = Enum.reduce(c.changes, c.changes, &rce_changes/2)
    errors = c.errors ++ Enum.flat_map(changes, &rce_errors/1)
    {:error, %{c | changes: changes, errors: errors}}
  end

  defp rce_changes({k, %Changeset{valid?: false} = v}, acc),
    do: Map.put(acc, k, rewrite_child_errors(v))

  defp rce_changes(_, acc), do: acc

  defp rce_errors({_, %Changeset{valid?: false, errors: e}}), do: e
  defp rce_errors(_), do: []

  def merge_child_errors(%Changeset{} = cs),
    do: Enum.reduce(cs.changes, cs, &merge_child_errors/2)

  defp merge_child_errors({_k, %Changeset{} = cs}, acc), do: cs.errors ++ acc
  defp merge_child_errors(_, acc), do: acc

  @doc false
  def default_id(changeset) do
    case get_field(changeset, :id) do
      id when is_binary(id) -> changeset
      _ -> Changeset.put_change(changeset, :id, ULID.generate())
    end
  end

  @doc false
  def replicate_map_change(changeset, source_key, target_key, xform) do
    case Changeset.fetch_change(changeset, source_key) do
      {:ok, change} ->
        Changeset.put_change(changeset, target_key, xform.(change))

      _ ->
        changeset
    end
  end

  @doc false
  def replicate_map_valid_change(
        %Changeset{valid?: true} = changeset,
        source_key,
        target_key,
        xform
      ) do
    case Changeset.fetch_change(changeset, source_key) do
      {:ok, change} ->
        Changeset.put_change(changeset, target_key, xform.(change))

      _ ->
        changeset
    end
  end

  def replicate_map_valid_change(changeset, _, _, _), do: changeset

  @doc false
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

  def update_data(%Changeset{data: data} = changeset, fun),
    do: Map.put(changeset, :data, fun.(data))

  # def update_change_in(data, path, transform)
  # def update_change_in(data, [], transform), do: transform.(data)
  # def update_change_in(%Changeset{}=data, [p | path], transform),
  #   do: Changeset.update_change(data, path, &update_change_in(&1, path, transform))
  # def update_change_in(%{}=data, [p | path], transform),
  #   do: Map.update(data, p, nil, &update_change_in(&1, path, transform))
  # def update_change_in(other), do: other

  def put_id_on_mixins(attrs, mixin_names, %{id: pointable}) do
    do_mixin_attrs(mixin_names, attrs, pointable)
  end

  def put_id_on_mixins(attrs, mixin_names, pointable) do
    do_mixin_attrs(mixin_names, attrs, pointable)
  end

  defp do_mixin_attrs(mixin_names, attrs, id) when is_list(mixin_names) do
    Enum.reduce(mixin_names, attrs, &do_mixin_attrs(&1, &2, id))
  end

  defp do_mixin_attrs(mixin_name, attrs, id) when is_atom(mixin_name) do
    Map.update(attrs, mixin_name, nil, &Map.put(&1, :id, id))
  end

  def get_field(%Changeset{} = cs, key), do: Changeset.get_field(cs, key)
  def get_field(%{} = map, key), do: Map.get(map, key)
  def get_field(other, key), do: other[key]
end
