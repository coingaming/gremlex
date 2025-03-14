defmodule Gremlex.ClientTests do
  use Gremlex
  use ExUnit.Case

  setup do
    # Cleanup DB
    {:ok, _} = query("g.V().drop()")
    :ok
  end

  describe "query/1" do
    test "that it can return a successful query" do
      person_id = System.unique_integer([:positive])
      vertex_id = "person#{person_id}"

      assert {:ok, [%{label: ^vertex_id}]} =
               g() |> add_v(vertex_id) |> property("name", "John Doe") |> query()

      assert {:ok, [%{label: ^vertex_id}]} = g() |> v() |> query()
    end

    test "returns an error :SCRIPT_EVALUATION_ERROR for a bad request" do
      {result, response, error_message} = g() |> to(1) |> query()
      assert result == :error
      assert response == :SCRIPT_EVALUATION_ERROR
      assert error_message != ""
    end

    test "allows you to create a new vertex" do
      {result, response} = g() |> add_v("person") |> property("name", "jasper") |> query()
      assert Enum.count(response) == 1
      assert result == :ok
      [vertex] = response
      assert vertex.label == "person"
      assert vertex.properties == %{name: ["jasper"]}
    end

    test "allows you to create a new vertex with multiline property" do
      address = "23480 Park Sorrento, Suite 100 Calabasas, CA 91302"

      {result, response} =
        g()
        |> add_v("person")
        |> property("name", "jasper")
        |> property("address", address)
        |> query()

      assert Enum.count(response) == 1
      assert result == :ok
      [vertex] = response
      assert vertex.label == "person"

      assert vertex.properties ==
               %{
                 name: ["jasper"],
                 address: [address]
               }
    end

    test "allows you to create a new vertex without a property" do
      {result, response} = g() |> add_v("person") |> query()
      assert Enum.count(response) == 1
      assert result == :ok
      [vertex] = response
      assert vertex.label == "person"
    end

    test "allows you to create a new vertex with a namespace" do
      {_, [s]} = g() |> add_v("foo") |> add_namespace() |> query()
      {_, [t]} = g() |> add_v("bar") |> add_namespace("baz") |> query()
      assert s.properties.namespace == ["gremlex"]
      assert t.properties.namespace == ["baz"]
    end

    test "allows you to create a relationship between two vertices" do
      {_, [s]} = g() |> add_v("foo") |> property("name", "bar") |> query()
      {_, [t]} = g() |> add_v("bar") |> property("name", "baz") |> query()
      {result, response} = g() |> v(s.id) |> add_e("isfriend") |> to(t) |> query()
      assert result == :ok
      [edge] = response
      assert edge.label == "isfriend"
    end

    test "allows you to get all edges" do
      v1_id = System.unique_integer([:positive])
      v2_id = System.unique_integer([:positive])
      {_, [s]} = g() |> add_v("vertex_#{v1_id}") |> property("name", "vertex#{v1_id}") |> query()
      {_, [t]} = g() |> add_v("vertex_#{v2_id}") |> property("name", "vertex#{v2_id}") |> query()

      {:ok, [%{label: "isfriend"}]} = g() |> v(s.id) |> add_e("isfriend") |> to(t) |> query()
    end

    test "returns empty list when there is no content retrieved" do
      {_, response} =
        g() |> v() |> has_label("person") |> has("doesntExist", "doesntExist") |> query()

      assert(response == [])
    end

    test "allow to execute plain query" do
      {result, response} = query("g.addV('person').property('name', 'jasper')")
      assert Enum.count(response) == 1
      assert result == :ok
      [vertex] = response
      assert vertex.label == "person"
      assert vertex.properties == %{name: ["jasper"]}
    end
  end
end
