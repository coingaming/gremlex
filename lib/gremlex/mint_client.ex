defmodule Gremlex.MintClient do
  use GenServer, restart: :transient

  require Logger
  require Mint.HTTP

  @type response ::
          {:ok, list()}
          | {:error, :unauthorized, String.t()}
          | {:error, :malformed_request, String.t()}
          | {:error, :invalid_request_arguments, String.t()}
          | {:error, :server_error, String.t()}
          | {:error, :script_evaluation_error, String.t()}
          | {:error, :server_timeout, String.t()}
          | {:error, :server_serialization_error, String.t()}

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
  @spec start_link(any()) :: pid()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

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

  @impl GenServer
  def init({host, port, path, secure}) do
    {:ok, %State{}, {:continue, {:connect, host, port, [path: path, secure: secure]}}}
  end

  @impl true
  def handle_continue({:connect, host, port, options}, %State{} = state) do
    http_scheme =
      case options[:secure] do
        false -> :http
        true -> :https
      end

    # TODO: configure to :ws or :wss
    ws_scheme = options[:scheme] || :ws
    ws_path = options[:path] || "/"

    with {:ok, conn} <- Mint.HTTP.connect(http_scheme, host, port, []),
         {:ok, conn, ref} <-
           Mint.WebSocket.upgrade(ws_scheme, conn, ws_path, [],
             extensions: [Mint.WebSocket.PerMessageDeflate]
           ) do
      {:noreply, %{state | conn: conn, request_ref: ref}}
    else
      {:error, reason} ->
        {:stop, reason, state}

      {:error, _conn, reason} ->
        {:stop, reason, state}
    end
  end

  @impl GenServer
  def handle_call(
        {:query, query, _timeout},
        from,
        %State{conn: conn, websocket: websocket} = state
      ) do
    Logger.info("Querying: #{inspect(query)}")

    payload =
      query
      |> Gremlex.Request.new()
      |> Jason.encode!()

    {:ok, websocket, data} = Mint.WebSocket.encode(websocket, {:text, payload})
    state = put_in(state.websocket, websocket)

    {:ok, conn} = Mint.WebSocket.stream_request_body(conn, state.request_ref, data)

    {:ok, _conn, [{:data, _ref, data}]} = Mint.WebSocket.recv(conn, 0, 5_000)

    Logger.info("Received data: #{inspect(data)}")

    result2 =
      case Mint.WebSocket.decode(websocket, data) do
        {:ok, _websocket, result} -> result
        {:error, _websocket, reason} -> {:error, reason}
      end

    Logger.info("Received response: #{inspect(result2)}")

    {:reply, result2, %{state | caller: from}}
  end

  def handle_call(message, _from, state) do
    Logger.info("Received unhandled call: #{inspect(message)}")
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:tcp, conn, _data} = message, %{conn: conn} = state) do
    Logger.info("Received info tcp: #{inspect(message)}")

    case Mint.WebSocket.recv(conn, 0, 5_000) do
      {:ok, conn, responses} ->
        # {conn, pending} = process_frames(conn, frames, pending)
        # {:noreply, %{state | conn: conn, pending_queries: pending}}
        state = put_in(state.conn, conn) |> handle_responses(responses)
        if state.closing?, do: do_close(state), else: {:noreply, state}

      {:error, conn, reason} ->
        {:stop, reason, put_in(state.conn, conn)}
    end
  end

  def handle_info(message, state) do
    Logger.info("Received info: #{inspect(message)}")

    case Mint.WebSocket.stream(state.conn, message) do
      {:ok, conn, responses} ->
        state = put_in(state.conn, conn) |> handle_responses(responses)
        if state.closing?, do: do_close(state), else: {:noreply, state}

      {:error, conn, reason, _responses} ->
        state = put_in(state.conn, conn) |> reply({:error, reason})
        {:noreply, state}

      :unknown ->
        {:noreply, state}
    end
  end

  defp handle_responses(%{request_ref: ref, websocket: websocket} = state, responses) do
    Enum.reduce(responses, state, fn
      # reply to pings with pongs
      {:ping, data}, state ->
        {:ok, state} = send_frame(state, {:pong, data})
        state

      {:close, _code, reason}, state ->
        Logger.info("Closing connection: #{inspect(reason)}")
        %{state | closing?: true}

      {:status, ^ref, status}, state ->
        Logger.info("Received status: #{inspect(status)}")
        put_in(state.status, status)

      {:headers, ^ref, resp_headers}, state ->
        Logger.info("Received headers: #{inspect(resp_headers)}")
        put_in(state.resp_headers, resp_headers)

      {:done, ^ref}, state ->
        Logger.info("Received done")

        case Mint.WebSocket.new(state.conn, ref, state.status, state.resp_headers, mode: :passive) do
          {:ok, conn, websocket} ->
            Logger.info("Received new: #{inspect(websocket)}")
            %{state | conn: conn, websocket: websocket, status: nil, resp_headers: nil}

          {:error, conn, reason} ->
            Logger.info("Received error new: #{inspect(reason)}")
            put_in(state.conn, conn)
        end

      {:data, ^ref, data}, state when not is_nil(websocket) ->
        Logger.info("Received data: #{inspect(data)}")

        case Mint.WebSocket.decode(state.websocket, data) do
          {:ok, websocket, frames} ->
            Logger.info("Received decode: #{inspect(frames)}")

            put_in(state.websocket, websocket)
            |> handle_frames(frames)

          {:error, websocket, reason} ->
            Logger.info("Received error decode: #{inspect(reason)}")
            reply(state, {:error, reason})
            put_in(state.websocket, websocket)
        end

      {:text, text}, state ->
        Logger.info("Received: #{inspect(text)}, sending back the reverse")
        {:ok, state} = send_frame(state, {:text, String.reverse(text)})
        state

      frame, state ->
        Logger.info("Unexpected frame received: #{inspect(frame)}")
        state
    end)
  end

  defp send_frame(state, frame) do
    with {:ok, websocket, data} <- Mint.WebSocket.encode(state.websocket, frame),
         state = put_in(state.websocket, websocket),
         {:ok, conn} <- Mint.WebSocket.stream_request_body(state.conn, state.request_ref, data) do
      Logger.info("Sending frame: #{inspect(frame)}")

      {:ok, put_in(state.conn, conn)}
    else
      {:error, %Mint.WebSocket{} = websocket, reason} ->
        {:error, put_in(state.websocket, websocket), reason}

      {:error, conn, reason} ->
        {:error, put_in(state.conn, conn), reason}
    end
  end

  def handle_frames(state, frames) do
    Enum.reduce(frames, state, fn
      # reply to pings with pongs
      {:ping, data}, state ->
        {:ok, state} = send_frame(state, {:pong, data})
        state

      {:close, _code, reason}, state ->
        Logger.info("Closing connection: #{inspect(reason)}")
        %{state | closing?: true}

      {:text, text}, state ->
        Logger.info("Received: #{inspect(text)}, sending back the reverse")
        # {:ok, state} = send_frame(state, {:text, String.reverse(text)})
        reply(state, text)

      frame, state ->
        Logger.info("Unexpected frame received: #{inspect(frame)}")
        state
    end)
  end

  defp do_close(state) do
    # Streaming a close frame may fail if the server has already closed
    # for writing.
    _ = send_frame(state, :close)
    Mint.HTTP.close(state.conn)
    {:stop, :normal, state}
  end

  defp reply(state, response) do
    if state.caller, do: GenServer.reply(state.caller, response)
    put_in(state.caller, nil)
  end
end
