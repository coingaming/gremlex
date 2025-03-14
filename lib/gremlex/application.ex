defmodule Gremlex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  defp parse_port(port) when is_number(port), do: port
  defp parse_port(""), do: 8182
  defp parse_port(:not_set), do: :not_set

  defp parse_port(port_string) when is_binary(port_string) do
    case Integer.parse(port_string) do
      {port, ""} ->
        port

      _ ->
        raise ArgumentError, message: "Invalid Port: #{port_string}"
    end
  end

  defp parse_secure(:not_set), do: false
  defp parse_secure(is_secure), do: is_secure

  defp build_app_worker(:not_set, :not_set, :not_set, :not_set, :not_set, _) do
    []
  end

  defp build_app_worker(host, port, path, pool_size, max_overflow, secure) do
    pool_options = [
      name: {:local, :gremlex},
      worker_module: Gremlex.Client,
      size: pool_size,
      max_overflow: max_overflow
    ]

    [:poolboy.child_spec(:gremlex, pool_options, {host, port, path, secure})]
  end

  def start(_type, _args) do
    # List all child processes to be supervised
    host = Application.get_env(:gremlex, :host, :not_set)
    port = Application.get_env(:gremlex, :port, :not_set) |> parse_port()
    path = Application.get_env(:gremlex, :path, :not_set)
    pool_size = Application.get_env(:gremlex, :pool_size, :not_set)
    max_overflow = Application.get_env(:gremlex, :max_overflow, :not_set)
    secure = Application.get_env(:gremlex, :secure, :not_set) |> parse_secure()

    ## TODO: cleanup after testing
    {http_scheme, opts} =
      if secure do
        {:https, [transport_opts: [middlebox_comp_mode: false]]}
      else
        {:http, []}
      end

    response =
      Mint.HTTP.connect(http_scheme, host, port, opts)

    Logger.info("Connection response: #{inspect(response)}")

    children = build_app_worker(host, port, path, pool_size, max_overflow, secure)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gremlex.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
