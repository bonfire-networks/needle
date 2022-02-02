# defmodule Pointers.Queries do

#   defmacro frum({:in, _, [{name, [], mod}, _]}=orig, args)
#   when is_atom(name) and is_atom(mod) and is_list(args) do
#     env = __CALLER__
#     quote do: from(unquote(orig), unquote_splicing([{:as, name} | compile(args, env) ]))
#   end

#   defp compile([], _env), do: []
#   defp compile([{:join, j} | rest], env), do: join(j, :join, rest, env)
#   defp compile([{:left_join, j} | rest], env), do: join(j, :left_join, rest, env)
#   defp compile([{:right_join, j} | rest], env), do: join(j, :right_join, rest, env)

# # {:in, [context: Elixir, import: Kernel],
# #  [{:a, [], Elixir}, {{:., [], [{:b, [], Elixir}, :c]}, [no_parens: true], []}]}

#   @doc """
#   ```
#   frum foo in Foo,
#     join: bar in foo.bar,
#     join: foo.bar,
#   ```
#   """
#   defp join(j, kind, rest, env) do
#     case j do
#       # l.r
#       %Sin.Op{
#         name: :.,
#         lhs: %Sin.Var{} = l,
#         rhs: %Sin.Var{} = r,
#       } -> :ok

#       # l in m.r
#       %Sin.Op{
#         name: :in,
#         lhs: %Sin.Var{} = l,
#         rhs: %Sin.Op{
#           name: :.,
#           lhs: %Sin.Var{} = m,
#           rhs: %Sin.Var{} = r,
#         },
#       } -> :ok
#     end
#   end

#   # defp expand_alias({:__aliases__, _, _}=a), do: Code.eval_quoted(a)
#   # defp expand_alias(other), do: other
    
#   # defmacro mix_in(query, source, mixins, opts \\ []),
#   #   do: join_mixins(query, source, :inner, mixins, opts)

#   # defmacro left_mix_in(query, source, mixins, opts \\ []),
#   #   do: join_mixins(query, source, :left, mixins, opts)

#   # def join_mixins(query, source, qual, mixins, opts),
#   #   do: Enum.reduce(mixins, query, &join_mixin(&2, &1, qual, source, opts))  

#   # defp join_mixin(query, {rel, as}, qual, source, opts) do
#   #   prefix = Keyword.get(opts, :prefix, "")
#   #   join_as(query, qual, source, rel, prefix(prefix, as))
#   # end

#   # defp join_mixin(query, rel, qual, source, opts) do
#   #   prefix = Keyword.get(opts, :prefix, "")
#   #   join_as(query, qual, source, rel, prefix(prefix, rel))
#   # end

#   # defmacro join_as(query, source, rel, as),
#   #   do: join_as(query, :inner, source, rel, as)

#   # defmacro left_join_as(query, source, rel, as),
#   #   do: join_as(query, :left, source, rel, as)

#   # defmacro right_join_as(query, source, rel, as),
#   #   do: join_as(query, :right, source, rel, as)

#   # def join_as(query, qual, source, rel, as) do
#   #   quote do
#   #     Ecto.Query.join unquote(query), unquote(qual),
#   #       x in assoc(as(unquote(source)), unquote(rel)),
#   #       as: unquote(as)
#   #   end
#   # end

#   defp prefix(x, y) when is_atom(x), do: prefix(Atom.to_string(x) <> "_", y)
#   defp prefix(x, y) when is_atom(y), do: prefix(x, Atom.to_string(y))
#   defp prefix(x, y) when is_binary(x) and is_binary(y), do: String.to_atom(x <> y)

# end
