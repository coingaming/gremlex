defmodule Gremlex.Long do
  @moduledoc """
  A module for handling long integers. Relevant for quering gremlin-groovy long values like
  g.E(123L). 
  """

  @type t :: %__MODULE__{
          value: integer()
        }

  @enforce_keys [:value]
  defstruct [:value]

  @doc """
  Creates a new Long struct from an integer.
  """
  @spec new(integer()) :: t()
  def new(value) when is_integer(value) do
    %Gremlex.Long{value: value}
  end
end
