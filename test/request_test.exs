defmodule Gremlex.RequestTests do
  use ExUnit.Case
  alias Gremlex.Request
  import Gremlex.Graph

  describe "new/1" do
    test "construct the proper payload for a gremlin graph query" do
      query = g() |> v()
      payload = "g.V()"
      args = %{gremlin: payload, language: "gremlin-groovy"}
      assert %Request{args: ^args, op: "eval", processor: ""} = Request.new(query)
    end

    test "construct the proper payload for a gremlin plain query" do
      payload = "g.V()"
      args = %{gremlin: payload, language: "gremlin-groovy"}
      assert %Request{args: ^args, op: "eval", processor: ""} = Request.new(payload)
    end
  end
end
