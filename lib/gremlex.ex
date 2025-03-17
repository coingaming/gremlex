defmodule Gremlex do
  defmacro __using__(_) do
    quote do
      import Gremlex.Graph
      import Gremlex.Client
    end
  end
end
