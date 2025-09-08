defmodule Gremlex.Client do
  @moduledoc """
  A Mint-based WebSocket client for Gremlin Server.

  This module is a GenServer that connects to a Gremlin Server using the WebSocket protocol.
  It sends queries to the server and receives responses. It also handles pings and pongs to keep the connection alive.

  ## Example

  ```
  iex> Gremlex.Client.start_link({host: "localhost", port: 8182, path: "/gremlin", secure: false})
  {:ok, #PID<0.123.0>}
  iex> Gremlex.Client.query(%Gremlex.Graph{vertices: [%Gremlex.Vertex{id: "1", label: "person"}]})
  {:ok, [%Gremlex.Vertex{id: "1", label: "person"}]}
  ```
  """
  use GenServer, restart: :transient

  alias Gremlex.Deserializer
  alias Mint.HTTP
  alias Mint.WebSocket

  require Logger

  @ping_interval 5 * 60_000
  @reconnect_interval 1_000

  @mname "#{inspect(__MODULE__)}"

  @type error_code ::
          :UNAUTHORIZED
          | :MALFORMED_REQUEST
          | :INVALID_REQUEST_ARGUMENTS
          | :SERVER_ERROR
          | :SCRIPT_EVALUATION_ERROR
          | :SERVER_TIMEOUT
          | :SERVER_SERIALIZATION_ERROR
          | :CONNECTION_UNAVAILABLE

  @type response :: {:ok, list()} | {:error, error_code(), reason :: String.t()}

  # Internal state
  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            conn: HTTP.t(),
            request_ref: Mint.Types.request_ref(),
            request_id: String.t() | nil,
            caller: pid(),
            websocket: WebSocket.t(),
            status: Mint.Types.status(),
            resp_headers: Mint.Types.headers(),
            closing?: boolean(),
            mode: :active | :passive,
            connection_opts: Keyword.t()
          }

    defstruct conn: nil,
              websocket: nil,
              request_ref: nil,
              request_id: nil,
              caller: nil,
              status: nil,
              resp_headers: [],
              closing?: false,
              mode: :active,
              connection_opts: []
  end

  # Public APIs
  @doc """
  Accepts a graph which it converts into a query and queries the database.

  Params:
  * query - A `Gremlex.Graph.t` or raw String query
  * timeout (Default: 30000ms) - Timeout in milliseconds to pass to GenServer and Task.await call
  """
  @spec query(Gremlex.Graph.t() | String.t(), number() | :infinity) :: response
  def query(query, timeout \\ 30_000) do
    :poolboy.transaction(
      :gremlex,
      fn worker_pid -> GenServer.call(worker_pid, {:query, query, timeout}, timeout) end,
      timeout
    )
  end

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  # Callbacks
  @impl GenServer
  def init(args) do
    host = Keyword.fetch!(args, :host)
    port = Keyword.fetch!(args, :port)
    path = Keyword.fetch!(args, :path)
    secure = Keyword.fetch!(args, :secure)
    opts = Keyword.fetch!(args, :opts)

    Logger.info("[#{@mname}] Initializing ...")

    connection_opts = [host: host, port: port, path: path, secure: secure, opts: opts]
    {:ok, %State{connection_opts: connection_opts}, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, %State{} = state) do
    case connect_websocket(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[#{@mname}] Failed to connect: #{inspect(reason)}")

        reconnect()
        {:noreply, %State{state | conn: nil, websocket: nil}}
    end
  end

  @impl GenServer
  def handle_call({:query, _query, _timeout}, _from, %State{websocket: websocket} = state)
      when is_nil(websocket) do
    {:reply, {:error, :CONNECTION_UNAVAILABLE}, state}
  end

  def handle_call({:query, query, timeout}, _from, %State{} = state) do
    # Create the request payload
    %Gremlex.Request{requestId: request_id} = request = Gremlex.Request.new(query)
    payload = Jason.encode!(request)

    # Switch to passive mode to synchronously recv responses
    with {:ok, state} <- change_mode(state, :passive),
         {:ok, state} <- send_frame(put_in(state.request_id, request_id), {:text, payload}) do
      reply = recv(state, timeout)

      Process.send_after(self(), {:change_mode, :active}, 0)
      schedule_ping()

      {:reply, reply, put_in(state.request_id, nil)}
    else
      {:error, reason} ->
        Logger.error("[#{@mname}] Failed to query: #{inspect(reason)}")

        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_info(:connect, %State{} = state) do
    case connect_websocket(state) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.warning("[#{@mname}] Failed to connect: #{inspect(reason)}")

        reconnect()
        {:noreply, %State{state | conn: nil, websocket: nil}}
    end
  end

  def handle_info({:change_mode, new_mode}, %State{} = state) do
    case change_mode(state, new_mode) do
      {:ok, state} ->
        {:noreply, state}

      {:error, reason} ->
        Logger.error("[#{@mname}] Failed to change mode #{new_mode}: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  def handle_info(:ping, %State{} = state) do
    {:ok, state} = send_frame(state, {:ping, ""})

    schedule_ping()

    {:noreply, state}
  end

  def handle_info(message, %State{} = state) do
    case WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = put_in(state.conn, conn)
        state = Enum.reduce(responses, state, &handle_response/2)

        state =
          if state.closing? do
            reconnect()
            %State{state | conn: nil, websocket: nil}
          else
            state
          end

        {:noreply, state}

      {:error, _conn, %Mint.TransportError{reason: :closed}, responses} ->
        Logger.metadata(responses: responses)
        Logger.warning("[#{@mname}] WebSocket connection closed!")

        reconnect()
        {:noreply, %State{state | conn: nil, websocket: nil}}

      {:error, _conn, reason, responses} ->
        Logger.metadata(responses: responses)
        Logger.info("[#{@mname}] Failed to process websocket message: #{inspect(reason)}")

        {:noreply, state}

      :unknown ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(reason, %State{} = state) do
    Logger.warning("[#{@mname}] Terminating Client with reason: #{inspect(reason)}")
    do_close(state)

    :ok
  end

  defp connect_websocket(%State{connection_opts: connect_opts} = state) do
    [host: host, port: port, path: ws_path, secure: secure, opts: opts] = connect_opts
    {http_scheme, ws_scheme} = if secure, do: {:https, :wss}, else: {:http, :ws}

    with {:ok, conn} <- HTTP.connect(http_scheme, host, port, opts),
         {:ok, conn, ref} <-
           WebSocket.upgrade(ws_scheme, conn, ws_path, [],
             extensions: [WebSocket.PerMessageDeflate]
           ) do
      {:ok, %{state | conn: conn, request_ref: ref}}
    else
      {:error, reason} ->
        {:error, Exception.message(reason)}

      {:error, conn, reason} ->
        Mint.HTTP.close(conn)
        {:error, Exception.message(reason)}
    end
  end

  defp change_mode(%State{mode: mode} = state, mode), do: {:ok, state}

  defp change_mode(%State{conn: conn} = state, new_mode) do
    case HTTP.set_mode(conn, new_mode) do
      {:ok, conn} -> {:ok, %{state | conn: conn, mode: new_mode}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Internal functions
  defp handle_response({:close, _code, reason} = _response, %State{} = state) do
    Logger.warning("[#{@mname}] Received close connection: #{inspect(reason)}")

    do_close(state)
    %{state | closing?: true, websocket: nil, conn: nil}
  end

  defp handle_response({:status, ref, status} = _response, %State{request_ref: ref} = state) do
    put_in(state.status, status)
  end

  defp handle_response({:headers, ref, resp_headers}, %State{request_ref: ref} = state) do
    put_in(state.resp_headers, resp_headers)
  end

  defp handle_response({:done, ref} = _response, %State{request_ref: ref} = state) do
    # Upgrade websocket
    case WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
      {:ok, conn, websocket} ->
        Logger.info("[#{@mname}] Websocket upgraded successfully!")

        schedule_ping()
        %{state | conn: conn, websocket: websocket, status: nil, resp_headers: []}

      {:error, _conn, _reason} ->
        reconnect()

        %State{state | conn: nil, websocket: nil}
    end
  end

  defp handle_response(
         {:data, ref, data} = _response,
         %State{request_ref: ref, websocket: websocket} = state
       )
       when not is_nil(websocket) do
    case WebSocket.decode(websocket, data) do
      {:ok, _websocket, [pong: ""]} ->
        state

      {:ok, _websocket, _frames} ->
        put_in(state.websocket, websocket)

      {:error, websocket, _reason} ->
        put_in(state.websocket, websocket)
    end
  end

  defp send_frame(%State{conn: conn, websocket: websocket, request_ref: ref} = state, frame) do
    with {:ok, websocket, data} <- WebSocket.encode(websocket, frame),
         {:ok, conn} <- WebSocket.stream_request_body(conn, ref, data) do
      {:ok, %{state | conn: conn, websocket: websocket}}
    else
      {:error, _websocket, reason} -> {:error, reason}
    end
  end

  defp do_close(%State{} = state) do
    # Streaming a close frame may fail if the server has already closed
    # for writing.
    try do
      _ = send_frame(state, :close)
      HTTP.close(state.conn)
    rescue
      _ -> :ok
    end
  end

  defp recv(
         %State{conn: conn, websocket: websocket, request_ref: ref} = state,
         timeout,
         acc \\ []
       ) do
    with {:ok, conn2, [{:data, ^ref, data}]} <- WebSocket.recv(conn, 0, timeout),
         {:ok, _websocket, result} <- WebSocket.decode(websocket, data) do
      handle_decoded_response(state, result, conn2, timeout, acc)
    end
  end

  # Handle single or multiple text block responses
  # In some cases we can receive a single response containing multiple 206 blocks and a final 200 block
  def handle_decoded_response(
        %State{request_id: request_id} = state,
        [{:text, _} | _] = responses,
        conn,
        timeout,
        acc
      ) do
    # Filter responses by requestId
    {responses, unexpected_responses} =
      responses
      |> Keyword.get_values(:text)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.split_with(fn resp -> resp["requestId"] == request_id end)

    :ok = log_unexpected_responses(unexpected_responses)

    handle_filtered_responses(state, responses, conn, timeout, acc)
  end

  # No need to schedule ping message again since they are periodically scheduled
  # Keep the connection alive
  def handle_decoded_response(state, [{:pong, _}], _conn, timeout, acc) do
    recv(state, timeout, acc)
  end

  def handle_decoded_response(state, [{:ping, _}], _conn, timeout, acc) do
    recv(state, timeout, acc)
  end

  # Unhandled response
  def handle_decoded_response(state, _response, _conn, timeout, acc) do
    recv(state, timeout, acc)
  end

  defp handle_filtered_responses(state, [], conn, timeout, acc) do
    # No matching responses, just continue waiting
    recv(put_in(state.conn, conn), timeout, acc)
  end

  defp handle_filtered_responses(state, responses, conn, timeout, acc) do
    results =
      Enum.flat_map(responses, fn response ->
        case Deserializer.deserialize(response) do
          nil -> []
          value when is_list(value) -> value
        end
      end)

    statuses = MapSet.new(responses, & &1["status"]["code"])

    error_message =
      Enum.map_join(responses, ", ", &(&1["status"]["message"] || &1["status"]["error_message"]))

    cond do
      200 in statuses -> {:ok, acc ++ results}
      204 in statuses -> {:ok, []}
      206 in statuses -> recv(put_in(state.conn, conn), timeout, acc ++ results)
      401 in statuses -> {:error, :UNAUTHORIZED, error_message}
      409 in statuses -> {:error, :MALFORMED_REQUEST, error_message}
      499 in statuses -> {:error, :INVALID_REQUEST_ARGUMENTS, error_message}
      500 in statuses -> {:error, :SERVER_ERROR, error_message}
      597 in statuses -> {:error, :SCRIPT_EVALUATION_ERROR, error_message}
      598 in statuses -> {:error, :SERVER_TIMEOUT, error_message}
      599 in statuses -> {:error, :SERVER_SERIALIZATION_ERROR, error_message}
    end
  end

  defp log_unexpected_responses(responses) do
    responses
    |> Enum.reject(&(&1 in [:ping, :pong]))
    |> Enum.each(fn response ->
      Logger.warning("[#{@mname}] Received unexpected response: #{inspect(response)}")
    end)
  end

  defp schedule_ping, do: Process.send_after(self(), :ping, @ping_interval)
  defp reconnect, do: Process.send_after(self(), :connect, @reconnect_interval)
end
