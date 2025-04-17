defmodule Gremlex.LongType do
  @moduledoc """
  A module for handling long integers. Relevant for quering gremlin-groovy long values.

  Example
    g.e(long.new(123))
    # => g.E(123L)
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
    %__MODULE__{value: value}
  end
end
