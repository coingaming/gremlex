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
            caller: pid(),
            websocket: Mint.WebSocket.t(),
            status: Mint.Types.status(),
            resp_headers: Mint.Types.headers(),
            closing?: boolean()
          }
    defstruct [:conn, :websocket, :request_ref, :caller, :status, :resp_headers, :closing?]
  end

  # Public APIs
  @doc """
  Accepts a graph which it converts into a query and queries the database.

  Params:
  * query - A `Gremlex.Graph.t` or raw String query
  * timeout (Default: 5000ms) - Timeout in milliseconds to pass to GenServer and Task.await call
  """
  @spec query(Gremlex.Graph.t() | String.t(), number() | :infinity) :: response
  def query(query, timeout \\ 5000) do
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
  def init({host, port, path, secure}) do
    Logger.info("Initializing Client...")

    {:ok, %State{}, {:continue, {:connect, host, port, [path: path, secure: secure]}}}
  end

  @impl true
  def handle_continue({:connect, host, port, options}, %State{} = state) do
    http_scheme = if options[:secure], do: :https, else: :http
    ws_scheme = if options[:secure], do: :wss, else: :ws

    transport_opts = [
      versions: [:"tlsv1.2"]
    ]

    ws_path = options[:path] || "/"

    Logger.info("Connecting to: #{http_scheme}://#{host}:#{port} ...")

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, host, port, transport_opts),
         :ok <- Logger.info("Connecting to ws: #{ws_scheme}://#{host}:#{port}/#{ws_path} ..."),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(ws_scheme, conn, ws_path, [],
             extensions: [Mint.WebSocket.PerMessageDeflate]
           ) do
      Logger.info("Connected to: #{http_scheme}://#{host}:#{port} successfully!")

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
    Logger.info("Processing query: #{inspect(query)}")

    {:ok, conn_p} = Mint.HTTP.set_mode(conn, :passive)
    state = put_in(state.conn, conn_p)

    ## Send the query
    payload = query |> Gremlex.Request.new() |> Jason.encode!()

    {result, state} =
      case send_frame(state, {:text, payload}) do
        {:ok, state} ->
          Logger.debug("Sent query: #{inspect(query)}")

          # Wait for the response
          # task = Task.async(fn -> recv(state, timeout) end)
          # result = Task.await(task, timeout)
          {recv(state, timeout), state}

        {:error, state, reason} ->
          {{:error, reason}, state}
      end

    Logger.info("Query result: #{inspect(result)}")

    {:ok, conn_a} = Mint.HTTP.set_mode(conn, :active)

    {:reply, result, %{state | conn: conn_a}}
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
        state = put_in(state.conn, conn) |> handle_responses(responses)

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
  defp handle_responses(%State{request_ref: ref, websocket: websocket} = state, responses) do
    Enum.reduce(responses, state, fn response, state ->
      Logger.debug("Handling response: #{inspect(response)}")

      case response do
        # reply to pings with pongs
        {:ping, data} ->
          {:ok, state} = send_frame(state, {:pong, data})
          state

        {:pong, data} ->
          {:ok, state} = send_frame(state, {:ping, data})
          state

        {:close, _code, reason} ->
          Logger.debug("Closing connection: #{inspect(reason)}")
          %{state | closing?: true}

        {:status, ^ref, status} ->
          put_in(state.status, status)

        {:headers, ^ref, resp_headers} ->
          put_in(state.resp_headers, resp_headers)

        {:done, ^ref} ->
          # create a new websocket for the next request
          case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers) do
            {:ok, conn, websocket} ->
              Logger.debug("New connection created!")
              %{state | conn: conn, websocket: websocket, status: nil, resp_headers: nil}

            {:error, conn, reason} ->
              Logger.debug("Received error new: #{inspect(reason)}")
              put_in(state.conn, conn)
          end

        {:data, ^ref, data} when not is_nil(websocket) ->
          case Mint.WebSocket.decode(state.websocket, data) do
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

        {:text, _text} ->
          state

        frame ->
          Logger.debug("Unexpected frame received: #{inspect(frame)}")
          state
      end
    end)
  end

  defp send_frame(%State{conn: conn, websocket: websocket, request_ref: ref} = state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(websocket, frame),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(conn, ref, data) do
      Logger.debug("Sending frame: #{inspect(frame)}")

      {:ok, %{state | conn: conn, websocket: websocket}}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        {:error, put_in(state.websocket, websocket), reason}

      {:error, conn, reason} ->
        {:error, put_in(state.conn, conn), reason}
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
    with {:ok, conn, [{:data, ^ref, data}]} <- Mint.WebSocket.recv(conn, 0, timeout),
         {:ok, _websocket, result} <- Mint.WebSocket.decode(websocket, data) do
      case result do
        [{:text, query_result}] ->
          response = Jason.decode!(query_result)
          result = Deserializer.deserialize(response)
          status = response["status"]["code"]
          error_message = response["status"]["message"]
          # Continue to block until we receive a 200 status code
          case status do
            200 ->
              {:ok, acc ++ result}

            204 ->
              {:ok, []}

            206 ->
              recv(conn, timeout, acc ++ result)

            401 ->
              {:error, :UNAUTHORIZED, error_message}

            409 ->
              {:error, :MALFORMED_REQUEST, error_message}

            499 ->
              {:error, :INVALID_REQUEST_ARGUMENTS, error_message}

            500 ->
              {:error, :SERVER_ERROR, error_message}

            597 ->
              {:error, :SCRIPT_EVALUATION_ERROR, error_message}

            598 ->
              {:error, :SERVER_TIMEOUT, error_message}

            599 ->
              {:error, :SERVER_SERIALIZATION_ERROR, error_message}
          end

        [{:ping, _}] ->
          # Keep the connection alive
          send_frame(state, {:pong, ""})
          :ok
      end
    end
  end

  defp schedule_ping do
    Process.send_after(self(), :ping, 30_000)
  end
end
