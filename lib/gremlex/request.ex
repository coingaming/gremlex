defmodule Gremlex.Request do
  alias Gremlex.Graph
  alias Gremlex.Request.Id
  @derive Jason.Encoder
  @op "eval"
  @processor ""
  @enforce_keys [:op, :processor, :requestId, :args]
  defstruct [:op, :processor, :requestId, :args]

  @type t :: %__MODULE__{}

  @doc """
  Accepts plain query or a graph and returns a Request.
  """
  @spec new(String.t()) :: t()
  def new(query) when is_binary(query) do
    args = %{gremlin: query, language: "gremlin-groovy"}
    %Gremlex.Request{requestId: Id.generate(), args: args, op: @op, processor: @processor}
  end

  @spec new(Gremlex.Graph.t()) :: t()
  def new(query) do
    new(Graph.encode(query))
  end
end
