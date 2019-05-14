defmodule Grmelex.DeserializerTests do
  import Gremlex.Deserializer
  alias Gremlex.{Edge, Vertex, VertexProperty, Path}
  alias Gremlex.Test.Mocks
  use ExUnit.Case
  use ExUnitProperties

  describe "deserialize/2" do
    test "should deserialize integers" do
      check all n <- integer() do
        assert deserialize("g:Int64", n) == n
        assert deserialize("g:Int32", n) == n
        assert deserialize("g:Float", n) == n
      end
    end

    test "should deserialize floats and doubles" do
      check all f <- float() do
        assert deserialize("g:Float", f) == f
        assert deserialize("g:Double", f) == f
      end
    end

    test "should deserialize timestamps" do
      dt = DateTime.utc_now()
      timestamp = DateTime.to_unix(dt, :microsecond)
      assert deserialize("g:Date", timestamp) == dt
      assert deserialize("g:Timestamp", timestamp) == dt
    end

    test "should deserialize sets with different types" do
      set = [%{"@type" => "g:Int32", "@value" => 1}, "person", true]
      expected_set = MapSet.new([1, "person", true])
      actual_set = deserialize("g:Set", set)
      assert MapSet.equal?(expected_set, actual_set) == true
    end

    test "should deserialize uuids" do
      assert deserialize("g:UUID", "uuid") == "uuid"
    end

    test "should deseiralize lists" do
      list = [
        %{
          "@type" => "g:Int32",
          "@value" => 1
        },
        "person",
        true
      ]

      expected_list = [1, "person", true]
      assert deserialize("g:List", list) == expected_list
    end

    test "should deserialize edges" do
      edge = %{
        "id" => %{
          "@type" => "g =>Int32",
          "@value" => 13
        },
        "label" => "develops",
        "inVLabel" => "software",
        "outVLabel" => "person",
        "inV" => %{
          "@type" => "g:Int32",
          "@value" => 10
        },
        "outV" => %{
          "@type" => "g:Int32",
          "@value" => 1
        },
        "properties" => %{
          "since" => %{
            "@type" => "g:Int32",
            "@value" => 2009
          }
        }
      }

      expected_edge = %Edge{
        label: "develops",
        id: 13,
        in_vertex: %Vertex{id: 10, label: "software"},
        out_vertex: %Vertex{id: 1, label: "person"},
        properties: %{since: 2009}
      }

      assert deserialize("g:Edge", edge) == expected_edge
    end

    test "should deserialize vertices" do
      vertex = Mocks.vertex()

      expected_vertex = %Vertex{
        id: 1,
        label: "person",
        properties: %{
          name: ["marko"],
          location: ["san diego", "santa cruz", "brussels", "santa fe"]
        }
      }

      assert deserialize("g:Vertex", vertex) == expected_vertex
    end

    test "should deserialize vertex properties" do
      vertex_property = Mocks.vertex_property()
      expected_property = %VertexProperty{id: 0, value: "marko", label: "name", vertex: 1}

      assert deserialize("g:VertexProperty", vertex_property) == expected_property
    end

    test "should deserialize vertex properties without a vertex" do
      vertex_property = Mocks.vertex_property_no_vertex()
      expected_property = %VertexProperty{id: 0, value: "marko", label: "name", vertex: nil}

      assert deserialize("g:VertexProperty", vertex_property) == expected_property
    end

    test "should deserialize map" do
      map = Mocks.map()

      expected_map = %{
        "label" => "LABEL_1",
        "created_at" => [DateTime.from_unix!(1_557_753_523_490, :microsecond)],
        "id" => "VERTEX_1",
        "prop1" => [false]
      }

      assert deserialize("g:Map", map) == expected_map
    end

    test "should deserialize path" do
      path = Mocks.path()

      expected_path = %Path{
        labels: [MapSet.new(), MapSet.new()],
        objects: [
          %Vertex{id: "VERTEX_1", label: "LABEL_1", properties: %{}},
          %Vertex{id: "VERTEX_2", label: "LABEL_1", properties: %{}}
        ]
      }

      assert deserialize("g:Path", path) == expected_path
    end
  end
end
