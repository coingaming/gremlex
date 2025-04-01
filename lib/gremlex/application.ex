defmodule Gremlex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    # List all child processes to be supervised
    host = Application.get_env(:gremlex, :host)
    port = Application.get_env(:gremlex, :port) |> parse_port()
    path = Application.get_env(:gremlex, :path) || "/"
    pool_size = Application.get_env(:gremlex, :pool_size) || 10
    max_overflow = Application.get_env(:gremlex, :max_overflow) || 10
    secure = Application.get_env(:gremlex, :secure) || false
    opts = Application.get_env(:gremlex, :opts) || []

    children = build_app_worker(host, port, path, pool_size, max_overflow, secure, opts)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gremlex.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp parse_port(nil), do: nil

  defp parse_port(port) when is_number(port), do: port

  defp parse_port(port_string) when is_binary(port_string) do
    case Integer.parse(port_string) do
      {port, ""} ->
        port

      _ ->
        raise ArgumentError, message: "Invalid Port: #{port_string}"
    end
  end

  defp build_app_worker(host, port, _, _, _, _, _) when is_nil(host) or is_nil(port) do
    []
  end

  defp build_app_worker(host, port, path, pool_size, max_overflow, secure, opts) do
    pool_options = [
      name: {:local, :gremlex},
      worker_module: Gremlex.Client,
      size: pool_size,
      max_overflow: max_overflow
    ]

    worker_args = [host: host, port: port, path: path, secure: secure, opts: opts]
    [:poolboy.child_spec(:gremlex, pool_options, worker_args)]
  end
end
