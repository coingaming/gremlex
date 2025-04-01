defmodule Gremlex.Vertex do
  alias Gremlex.Vertex
  alias Gremlex.Deserializer

  @derive Jason.Encoder

  @enforce_keys [:label, :id]
  defstruct [:label, :id, :properties]

  @type t :: %__MODULE__{}

  def add_properties(%Vertex{properties: nil} = vertex, properties) do
    Map.put(vertex, :properties, properties)
  end

  def add_properties(%Vertex{properties: this} = vertex, that) do
    properties = Map.merge(this, that)
    Map.put(vertex, :properties, properties)
  end

  def from_response(%{"id" => json_id, "label" => label} = result) do
    id =
      case json_id do
        %{"@type" => id_type, "@value" => id_value} ->
          Deserializer.deserialize(id_type, id_value)

        id ->
          id
      end

    properties = Map.get(result, "properties", %{})

    vertex = %Vertex{id: id, label: label}

    serialized_properties =
      Enum.reduce(properties, %{}, fn {label, property}, acc ->
        values =
          Enum.map(property, fn
            %{"@value" => %{"value" => %{"@type" => type, "@value" => value}}} ->
              Deserializer.deserialize(type, value)

            %{"@value" => %{"value" => value}} ->
              value
          end)

        Map.put(acc, String.to_atom(label), values)
      end)

    Vertex.add_properties(vertex, serialized_properties)
  end
end
