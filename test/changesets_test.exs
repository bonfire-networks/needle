defmodule Pointers.ChangesetsTest do
  use ExUnit.Case
  alias Ecto.Changeset
  alias Pointers.{Changesets, ULID}
  alias Pointers.Test.{M, P, V}
  doctest Pointers

  describe "cast" do
    test "generates an id given an empty pointable" do
      cs =
        %P{}
        |> Changesets.cast(%{}, [])

      ULID.cast!(Changeset.get_change(cs, :id))
    end

    test "generates an id given a new virtual" do
      cs =
        %V{}
        |> Changesets.cast(%{}, [])

      ULID.cast!(Changeset.get_change(cs, :id))
    end

    test "does not generate an id given a new mixin" do
      cs =
        %M{}
        |> Changesets.cast(%{}, [])

      assert nil == Changeset.get_change(cs, :id)
    end

    test "generates an id given a changeset over a new pointable" do
      cs =
        %P{}
        |> Changeset.cast(%{}, [])
        |> Changesets.cast(%{}, [])

      ULID.cast!(Changeset.get_change(cs, :id))
    end

    test "generates an id given a changeset over a new virtual " do
      cs =
        %V{}
        |> Changeset.cast(%{}, [])
        |> Changesets.cast(%{}, [])

      ULID.cast!(Changeset.get_change(cs, :id))
    end

    test "does not generate an id given a changeset over a new mixin " do
      cs =
        %M{}
        |> Changeset.cast(%{}, [])
        |> Changesets.cast(%{}, [])

      assert nil == Changeset.get_change(cs, :id)
    end

    test "does not overwrite an existing id given a changeset over a new pointable" do
      cs =
        %P{}
        |> Changeset.cast(%{}, [])
        |> Changesets.cast(%{}, [])

      id = Changeset.get_change(cs, :id)
      cs = Changesets.cast(cs, %{}, [])
      id2 = Changeset.get_change(cs, :id)
      assert id == id2
    end

    test "does not overwrite an existing id given a changeset over a new virtual" do
      cs =
        %V{}
        |> Changeset.cast(%{}, [])
        |> Changesets.cast(%{}, [])

      id = Changeset.get_change(cs, :id)
      cs = Changesets.cast(cs, %{}, [])
      id2 = Changeset.get_change(cs, :id)
      assert id == id2
    end

    test "still does not generate an id given a changeset over a new mixin" do
      cs =
        %M{}
        |> Changeset.cast(%{}, [])
        |> Changesets.cast(%{}, [])

      assert nil == Changeset.get_change(cs, :id)
    end
  end

  describe "put_assoc" do
    test "copies the id from the pointable to the mixin over has_one" do
      cs =
        %P{}
        |> Changesets.cast(%{}, [])

      id = Changeset.get_change(cs, :id)
      cs = Changesets.put_assoc(cs, :m, %{value: 123})
      assert m = %Changeset{} = Changeset.get_change(cs, :m)
      assert Changeset.get_change(m, :id) == id
    end

    test "copies the id from the pointer to the mixin over has_many" do
      cs =
        %P{}
        |> Changesets.cast(%{}, [])

      id = Changeset.get_change(cs, :id)
      cs = Changesets.put_assoc(cs, :mm, [%{value: 123}, %{value: 234}])
      id2 = Changeset.get_change(cs, :id)
      assert id == id2

      assert [mm1 = %Changeset{}, mm2 = %Changeset{}] = Changeset.get_change(cs, :mm)

      assert Changeset.get_change(mm1, :id) == id
      assert Changeset.get_change(mm2, :id) == id
    end

    test "copies the id from the pointable to the mixin over belongs_to" do
      cs =
        %P{}
        |> Changesets.cast(%{}, [])

      id = Changeset.get_change(cs, :id)

      cs =
        cs
        |> Changesets.put_assoc(:m, %{value: 123})
        |> Changeset.update_change(
          :m,
          &Changesets.put_assoc(&1, :p, %{value: 234})
        )

      assert m = %Changeset{} = Changeset.get_change(cs, :m)
      assert Changeset.get_field(m, :id) == id
      assert p2 = %Changeset{} = Changeset.get_change(m, :p)
      assert is_binary(Changeset.get_field(m, :p_id))
      assert Changeset.get_field(m, :p_id) == Changeset.get_field(p2, :id)
    end
  end

  describe "cast_assoc" do
    # test "" do
    # end

    # test "" do
    # end
  end
end
