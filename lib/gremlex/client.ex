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

  require Logger

  @type error_code ::
          :UNAUTHORIZED
          | :MALFORMED_REQUEST
          | :INVALID_REQUEST_ARGUMENTS
          | :SERVER_ERROR
          | :SCRIPT_EVALUATION_ERROR
          | :SERVER_TIMEOUT
          | :SERVER_SERIALIZATION_ERROR

  @type response :: {:ok, list()} | {:error, error_code(), reason :: String.t()}

  # Internal state
  defmodule State do
    @moduledoc false
    @type t :: %__MODULE__{
            conn: Mint.HTTP.t(),
            request_ref: Mint.Types.request_ref(),
            request_id: String.t() | nil,
            caller: pid(),
            websocket: Mint.WebSocket.t(),
            status: Mint.Types.status(),
            resp_headers: Mint.Types.headers(),
            closing?: boolean()
          }

    defstruct [
      :conn,
      :websocket,
      :request_ref,
      :request_id,
      :caller,
      :status,
      :resp_headers,
      :closing?
    ]
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

    Logger.info("Initializing Client...")

    {:ok, %State{}, {:continue, {:connect, host, port, path, secure, opts}}}
  end

  @impl true
  def handle_continue({:connect, host, port, ws_path, secure, opts}, %State{} = state) do
    {http_scheme, ws_scheme} = if secure, do: {:https, :wss}, else: {:http, :ws}

    # Default http mode is active
    with {:ok, conn} <-
           Mint.HTTP.connect(http_scheme, host, port, opts),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(ws_scheme, conn, ws_path, [],
             extensions: [{Mint.WebSocket.PerMessageDeflate, [:client_max_window_bits]}]
           ) do
      Logger.info("Websocket connected successfully!")

      schedule_ping()
      {:noreply, %{state | conn: conn, request_ref: ref}}
    else
      {:error, reason} ->
        {:stop, reason, state}

      {:error, _conn, reason} ->
        {:stop, reason, state}
    end
  end

  @impl GenServer
  def handle_call({:query, query, timeout}, _from, %State{conn: conn} = state) do
    Logger.debug("Processing query: #{inspect(query)}")

    # Create the request payload
    %Gremlex.Request{requestId: request_id} = request = Gremlex.Request.new(query)
    payload = Jason.encode!(request)

    # Switch to passive mode to manually recv responses
    # This allows us to manually handle the responses
    {:ok, conn_p} = Mint.HTTP.set_mode(conn, :passive)
    state = %{state | conn: conn_p, request_id: request_id}

    Logger.info("request: #{inspect(request)}")

    {result, state} =
      case send_frame(state, {:text, payload}) do
        {:ok, state} ->
          Logger.debug("Sent query: #{inspect(query)}")

          # Wait for the response
          {recv(state, timeout), state}

        {:error, state, reason} ->
          {{:error, reason}, state}
      end

    Logger.debug("Query result: #{inspect(result)}")

    # Switch again to active mode so GenServer can asynchronously
    # handle ping/pong and other messages from websocket.
    {:ok, conn_a} = Mint.HTTP.set_mode(conn, :active)

    {:reply, result, %{state | conn: conn_a, request_id: nil}}
  end

  def handle_call(message, _from, %State{} = state) do
    Logger.debug("Received unhandled call: #{inspect(message)}")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info(:ping, %State{} = state) do
    send_frame(state, {:ping, ""})

    Logger.debug("Sent ping!")
    schedule_ping()

    {:noreply, state}
  end

  def handle_info(message, %State{} = state) do
    Logger.debug("Received info: #{inspect(message)}")

    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = put_in(state.conn, conn)
        state = Enum.reduce(responses, state, &handle_response/2)

        if state.closing? do
          do_close(state)
          {:stop, :normal, state}
        else
          {:noreply, state}
        end

      {:error, conn, reason, responses} ->
        Logger.error("Received error: #{inspect(reason)}", responses: responses)
        {:noreply, put_in(state.conn, conn)}

      :unknown ->
        {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(reason, %State{} = state) do
    Logger.info("Terminating Client with reason: #{inspect(reason)}")
    do_close(state)

    :ok
  end

  # Internal functions
  defp handle_response({:ping, data} = _response, %State{} = state) do
    # reply to pings with pongs
    {:ok, state} = send_frame(state, {:pong, data})
    state
  end

  defp handle_response({:pong, data} = _response, %State{} = state) do
    # reply to pongs with pings
    {:ok, state} = send_frame(state, {:ping, data})
    state
  end

  defp handle_response({:close, _code, reason} = _response, %State{} = state) do
    Logger.debug("Closing connection: #{inspect(reason)}")
    %{state | closing?: true}
  end

  defp handle_response({:status, ref, status} = _response, %State{request_ref: ref} = state) do
    put_in(state.status, status)
  end

  defp handle_response({:headers, ref, resp_headers}, %State{request_ref: ref} = state) do
    put_in(state.resp_headers, resp_headers)
  end

  defp handle_response({:done, ref} = _response, %State{request_ref: ref} = state) do
    # create a new websocket for the next request
    case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
      {:ok, conn, websocket} ->
        Logger.debug("New connection created!")
        %{state | conn: conn, websocket: websocket, status: nil, resp_headers: nil}

      {:error, conn, reason} ->
        Logger.debug("Received error new: #{inspect(reason)}")
        put_in(state.conn, conn)
    end
  end

  defp handle_response(
         {:data, ref, data} = _response,
         %State{request_ref: ref, websocket: websocket} = state
       )
       when not is_nil(websocket) do
    case Mint.WebSocket.decode(websocket, data) do
      {:ok, _websocket, [pong: ""]} ->
        Logger.debug("Received pong!")
        state

      {:ok, _websocket, frames} ->
        Logger.debug("Decoded data: #{inspect(frames)}")
        put_in(state.websocket, websocket)

      {:error, websocket, reason} ->
        Logger.debug("Decode error: #{inspect(reason)}")
        put_in(state.websocket, websocket)
    end
  end

  defp handle_response({:text, _text} = _response, %State{} = state) do
    state
  end

  defp handle_response(frame = _response, %State{} = state) do
    Logger.debug("Unexpected frame received: #{inspect(frame)}")
    state
  end

  defp send_frame(%State{conn: conn, websocket: websocket, request_ref: ref} = state, frame) do
    with {:ws, {:ok, websocket, data}} <- {:ws, Mint.WebSocket.encode(websocket, frame)},
         {:conn, {:ok, conn}} <- {:conn, Mint.WebSocket.stream_request_body(conn, ref, data)} do
      Logger.debug("Sending frame: #{inspect(frame)}")

      {:ok, %{state | conn: conn, websocket: websocket}}
    else
      {:ws, {:error, websocket, reason}} -> {:error, put_in(state.websocket, websocket), reason}
      {:conn, {:error, conn, reason}} -> {:error, put_in(state.conn, conn), reason}
    end
  end

  defp do_close(%State{} = state) do
    # Streaming a close frame may fail if the server has already closed
    # for writing.
    try do
      _ = send_frame(state, :close)
      Mint.HTTP.close(state.conn)
    rescue
      _ -> :ok
    end
  end

  defp recv(
         %State{conn: conn, websocket: websocket, request_ref: ref} = state,
         timeout,
         acc \\ []
       ) do
    with {:ok, conn2, [{:data, ^ref, data}]} <- Mint.WebSocket.recv(conn, 0, timeout),
         {:ok, _websocket, result} <- Mint.WebSocket.decode(websocket, data) do
      handle_decoded_response(state, result, conn2, timeout, acc)
    end
  end

  # No need to schedule ping message again since they are periodically scheduled
  def handle_decoded_response(state, [{:pong, _}], _conn, timeout, acc) do
    recv(state, timeout, acc)
  end

  # Keep the connection alive
  def handle_decoded_response(state, [{:ping, _}], _conn, timeout, acc) do
    {:ok, state} = send_frame(state, {:pong, ""})
    recv(state, timeout, acc)
  end

  # Single block response
  def handle_decoded_response(
        %State{request_id: request_id} = state,
        [{:text, query_result}],
        conn,
        timeout,
        acc
      ) do
    %{"requestId" => ^request_id, "status" => %{"code" => status, "message" => error_message}} =
      response = Jason.decode!(query_result)

    result = Deserializer.deserialize(response)

    # Continue to block until we receive a 200 status code
    case status do
      200 -> {:ok, acc ++ result}
      204 -> {:ok, []}
      206 -> recv(Map.put(state, :conn, conn), timeout, acc ++ result)
      401 -> {:error, :UNAUTHORIZED, error_message}
      409 -> {:error, :MALFORMED_REQUEST, error_message}
      499 -> {:error, :INVALID_REQUEST_ARGUMENTS, error_message}
      500 -> {:error, :SERVER_ERROR, error_message}
      597 -> {:error, :SCRIPT_EVALUATION_ERROR, error_message}
      598 -> {:error, :SERVER_TIMEOUT, error_message}
      599 -> {:error, :SERVER_SERIALIZATION_ERROR, error_message}
    end
  end

  # Multiple block response. In some cases we can receive a single response
  # containing multiple 206 blocks and a final 200 block
  def handle_decoded_response(
        %State{request_id: request_id} = state,
        [{:text, _} | _rest] = response,
        conn,
        timeout,
        acc
      ) do
    responses =
      response
      |> Keyword.get_values(:text)
      |> Enum.map(&Jason.decode!/1)
      |> Enum.filter(fn %{"requestId" => id} -> id == request_id end)

    statuses = MapSet.new(responses, & &1["status"]["code"])
    results = Enum.flat_map(responses, &Deserializer.deserialize/1)
    error_message = Enum.map_join(responses, ", ", & &1["status"]["error_message"])

    cond do
      200 in statuses -> {:ok, acc ++ results}
      204 in statuses -> {:ok, []}
      206 in statuses -> recv(Map.put(state, :conn, conn), timeout, acc ++ results)
      401 in statuses -> {:error, :UNAUTHORIZED, error_message}
      409 in statuses -> {:error, :MALFORMED_REQUEST, error_message}
      499 in statuses -> {:error, :INVALID_REQUEST_ARGUMENTS, error_message}
      500 in statuses -> {:error, :SERVER_ERROR, error_message}
      597 in statuses -> {:error, :SCRIPT_EVALUATION_ERROR, error_message}
      598 in statuses -> {:error, :SERVER_TIMEOUT, error_message}
      599 in statuses -> {:error, :SERVER_SERIALIZATION_ERROR, error_message}
    end
  end

  defp schedule_ping do
    # TODO: Revert once tested on test envs
    Process.send_after(self(), :ping, 500)
  end
end
