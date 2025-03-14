defmodule Gremlex do
  defmacro __using__(_) do
    quote do
      import Gremlex.Graph
      import Gremlex.MintClient
    end
  end
end
