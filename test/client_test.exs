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

    test "allows you to update a vertex property" do
      {_, [vertex]} = g() |> add_v("person") |> property("name", "jasper") |> query()
      {result, response} = g() |> v(vertex.id) |> property("name", "john") |> query()
      assert result == :ok
      [updated_vertex] = response
      assert updated_vertex.properties.name == ["john"]
    end

    test "allows you to delete a vertex" do
      {_, [vertex]} = g() |> add_v("person") |> property("name", "jasper") |> query()
      {result, _} = g() |> v(vertex.id) |> drop() |> query()
      assert result == :ok
      {_, response} = g() |> v(vertex.id) |> query()
      assert response == []
    end

    test "allows you to delete an edge" do
      {_, [s]} = g() |> add_v("foo") |> property("name", "bar") |> query()
      {_, [t]} = g() |> add_v("bar") |> property("name", "baz") |> query()
      {_, [edge]} = g() |> v(s.id) |> add_e("isfriend") |> to(t) |> query()
      {result, _} = g() |> e(edge.id) |> drop() |> query()
      assert result == :ok
      {_, response} = g() |> e(edge.id) |> query()
      assert response == []
    end

    test "returns an error for invalid Gremlin syntax" do
      {result, response, error_message} = query("g.addV('person').property('name', )")
      assert result == :error
      assert response == :SCRIPT_EVALUATION_ERROR

      assert error_message ==
               "No signature of method: org.apache.tinkerpop.gremlin.process.traversal.dsl.graph.DefaultGraphTraversal.property() is applicable for argument types: (String) values: [name]\nPossible solutions: hasProperty(java.lang.String)"
    end
  end

  describe "side_effect/2" do
    test "allows you to set a side effect on vertex" do
      {_, [_tshirt]} = g() |> add_v("tshirt") |> property("price", 60) |> query()
      {_, [_hat]} = g() |> add_v("hat") |> property("price", 70) |> query()
      {_, [_socks]} = g() |> add_v("socks") |> property("price", 20) |> query()
      {_, [hoodie]} = g() |> add_v("hoodie") |> property("price", 200) |> query()
      {_, [bag]} = g() |> add_v("bag") |> property("price", 101) |> query()

      # """
      # g.V()
      # .has('price', gt(#{@price_threshold}))
      # .sideEffect(__.property('discounted', true))
      # .fold()
      # .as('discounted')
      # .project('count', 'ids')
      #   .by(__.unfold().count())
      #   .by(__.unfold().id().fold())
      # .toList()
      # """

      {:ok, [%{"count" => count, "products" => products}] = _response} =
        g()
        |> v()
        |> has("price", gt(g(), 100))
        |> side_effect(anonymous() |> property("discounted", "true"))
        |> fold()
        |> as("discounted")
        |> project(["count", "products"])
        |> by(anonymous() |> unfold() |> count())
        |> by(anonymous() |> unfold() |> fold())
        |> to_list()
        |> query()

      assert count == 2
      assert Enum.count(products) == 2

      assert Enum.all?(products, fn x ->
               x.id in [bag.id, hoodie.id] and
                 x.properties.price in [[200], [101]] &&
                 x.properties.discounted == ["true"]
             end)
    end
  end

  describe "handle_decoded_response/5" do
    setup do
      %{state: %Gremlex.Client.State{request_id: Gremlex.Request.Id.generate()}}
    end

    test "returns error tuple for 4xx and 5xx responses", %{state: state} do
      timeout = 5_000
      conn = nil
      acc = []

      assert {:error, "Invalid request"} ==
               Gremlex.Client.handle_decoded_response(
                 state,
                 [error: "Invalid request"],
                 conn,
                 timeout,
                 acc
               )
    end

    test "handle pong message in query response", %{state: state} do
      timeout = 5_000
      conn = nil
      acc = []

      text_response =
        "{\"requestId\":\"#{state.request_id}\",\"status\":{\"message\":\"\",\"code\":200,\"attributes\":{\"@type\":\"g:Map\",\"@value\":[\"host\",\"/192.168.0.1:12345\"]}},\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[\"0\"]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}}}"

      response1 = [pong: " ", text: text_response]

      assert {:ok, ["0"]} ==
               Gremlex.Client.handle_decoded_response(
                 state,
                 response1,
                 conn,
                 timeout,
                 acc
               )

      response2 = [pong: " ", pong: " ", text: text_response]

      assert {:ok, ["0"]} ==
               Gremlex.Client.handle_decoded_response(
                 state,
                 response2,
                 conn,
                 timeout,
                 acc
               )

      response3 = [text: text_response, pong: " ", pong: " ", pong: " "]

      assert {:ok, ["0"]} ==
               Gremlex.Client.handle_decoded_response(
                 state,
                 response3,
                 conn,
                 timeout,
                 acc
               )
    end

    test "returns empty list for 204 response", %{state: state} do
      timeout = 5_000
      conn = nil
      acc = []

      response =
        "{\"requestId\":\"#{state.request_id}\",\"status\":{\"message\":\"\",\"code\":204,\"attributes\":{\"@type\":\"g:Map\",\"@value\":[\"host\",\"/192.168.0.1:12345\"]}},\"result\":{\"data\":null,\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}}}"

      assert {:ok, []} ==
               Gremlex.Client.handle_decoded_response(
                 state,
                 [text: response],
                 conn,
                 timeout,
                 acc
               )
    end

    test "returns decoded response for 200 status", %{state: state} do
      timeout = 5_000
      conn = nil
      acc = []

      response =
        "{\"requestId\":\"#{state.request_id}\",\"status\":{\"message\":\"\",\"code\":200,\"attributes\":{\"@type\":\"g:Map\",\"@value\":[\"host\",\"/192.168.0.1:12345\"]}},\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[\"0\"]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}}}"

      assert {:ok, ["0"]} ==
               Gremlex.Client.handle_decoded_response(
                 state,
                 [text: response],
                 conn,
                 timeout,
                 acc
               )
    end

    test "returns single list for multipart response", %{state: state} do
      timeout = 5_000
      conn = nil
      acc = []

      response =
        [
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id1\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id2\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":206,\"message\":\"\"}}",
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id2\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id1\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":200,\"message\":\"\"}}"
        ]

      assert {:ok,
              [
                %{"id" => "id1", "linked" => ["id2"], "label" => "VERTEX"},
                %{"id" => "id2", "linked" => ["id1"], "label" => "VERTEX"}
              ]} ==
               Gremlex.Client.handle_decoded_response(state, response, conn, timeout, acc)
    end

    test "returns single list for multipart response with handling pong messages", %{
      state: state
    } do
      timeout = 5_000
      conn = nil
      acc = []

      response =
        [
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id1\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id6\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":206,\"message\":\"\"}}",
          pong: " ",
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id2\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id5\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":206,\"message\":\"\"}}",
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id3\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id4\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":206,\"message\":\"\"}}",
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id4\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id3\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":206,\"message\":\"\"}}",
          pong: " ",
          close: " ",
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id5\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id2\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":206,\"message\":\"\"}}",
          text:
            "{\"requestId\":\"#{state.request_id}\",\"result\":{\"data\":{\"@type\":\"g:List\",\"@value\":[{\"@type\":\"g:Map\",\"@value\":[\"id\",\"id6\",\"linked\",{\"@type\":\"g:List\",\"@value\":[\"id1\"]},\"label\",\"VERTEX\"]}]},\"meta\":{\"@type\":\"g:Map\",\"@value\":[]}},\"status\":{\"attributes\":{\"@type\":\"g:Map\",\"@value\":[]},\"code\":200,\"message\":\"\"}}"
        ]

      assert {:ok,
              [
                %{"id" => "id1", "linked" => ["id6"], "label" => "VERTEX"},
                %{"id" => "id2", "linked" => ["id5"], "label" => "VERTEX"},
                %{"id" => "id3", "linked" => ["id4"], "label" => "VERTEX"},
                %{"id" => "id4", "linked" => ["id3"], "label" => "VERTEX"},
                %{"id" => "id5", "linked" => ["id2"], "label" => "VERTEX"},
                %{"id" => "id6", "linked" => ["id1"], "label" => "VERTEX"}
              ]} ==
               Gremlex.Client.handle_decoded_response(state, response, conn, timeout, acc)
    end
  end
end
