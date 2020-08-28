defmodule Pointers.Changesets do

  alias Pointers.{Pointable, Mixin, Util}
  alias Ecto.Changeset

  def state(thing), do: thing.__meta__.state

  def is_built?(%_{__meta__: %{state: :built}}), do: true
  def is_built?(_), do: false

  def is_loaded?(%_{__meta__: %{state: :loaded}}), do: true
  def is_loaded?(_), do: false

  def is_deleted?(%_{__meta__: %{state: :deleted}}), do: true
  def is_deleted?(_), do: false

  def verb(%_{}=thing), do: if(is_built?(thing), do: :create, else: :update)

  def cast(thing, attrs, config, default),
    do: cast(config(config, attrs, :cast, default), thing, attrs)

  defp cast(nil, thing, _), do: Changeset.cast(thing, %{}, [])
  defp cast(cast, thing, attrs), do: Changeset.cast(thing, Map.delete(attrs, :cast), cast)

  def rename_cast(thing, attrs, config, default) do
    attrs = Util.rename(attrs, config(config, attrs, :rename_attrs, []))
    cast(thing, attrs, config, default)
  end

  def validate_required(changeset, attrs, config, default),
    do: vr(config(config, attrs, :required, default), changeset)

  defp vr(nil, changeset), do: changeset
  defp vr(req, changeset), do: Changeset.validate_required(changeset, req)

  def validate_format(changeset, attrs, config, key, format_key, default) do
    if Map.has_key?(changeset.changes, key), 
      do: vf(config(config, attrs, format_key, default), key, changeset),
      else: changeset
  end

  defp vf(nil, _key, changeset), do: changeset
  defp vf(%Regex{}=format, key, changeset), do: Changeset.validate_format(changeset, key, format)
  defp vf(invalid, key, _), do: throw {:invalid_format_regexp, regexp: invalid, key: key}

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

  def validate_length(changeset, attrs, config, key, opts_key, default) do
    if Map.has_key?(changeset.changes, key),
      do: vl(config(config, attrs, opts_key, default), key, changeset),
      else: changeset
  end

  defp vl(nil, _key, changeset), do: changeset
  defp vl([], _key, changeset), do: changeset
  defp vl(opts, key, changeset),do: Changeset.validate_length(changeset, key, opts)

  defp config(config, attrs, key, default),
    do: attrs[key] || Keyword.get(config, key, default)

  defmacro config() do
    cm = __CALLER__.module
    attr =
      Module.get_attribute(cm, Pointable) || Module.get_attribute(cm, Mixin) ||
      throw("Pointers.Changesets.config must only be called from within Pointables or Mixins.")
    otp_app = Keyword.fetch!(attr, :otp_app)
    quote do
      Application.get_env(unquote(otp_app), unquote(cm), [])
    end
  end

  defmacro config(key, default \\ nil) do
    quote do
      Keyword.get(Pointers.Changesets.config(), unquote(key), unquote(default))
    end
  end

  def valid?(%Changeset{valid?: v}), do: v
  def valid?(cs) when is_list(cs), do: Enum.all?(cs, &valid?/1)

end
