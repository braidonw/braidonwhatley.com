defmodule App.Chess.Stockfish do
  @moduledoc """
  A thin GenServer wrapper around a Stockfish UCI engine, spoken to over a
  `Port`.

  Used to pick the bot's **most stubborn legal defense** while a visitor works
  through a mate-in-N puzzle, so beating it feels earned. It is never required:
  if the `stockfish` binary is missing (a dev box without it, or an image that
  didn't install it) the server starts in an `unavailable` state and
  `best_move/2` returns `:unavailable`, letting callers fall back to a
  deterministic legal move from the core engine.

  The binary is located via, in order:

    1. `config :braidonwhatley, #{inspect(__MODULE__)}, path: "..."`
    2. the `STOCKFISH_PATH` environment variable
    3. `stockfish` on `$PATH`

  Requests are serialized by the GenServer — one search at a time — which is
  plenty for a single-puzzle gate.
  """
  use GenServer
  require Logger

  @default_movetime_ms 150
  # Hard ceiling so a wedged engine can never hang a LiveView process.
  @call_timeout_ms 5_000

  # ─── Public API ───────────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Best move for `fen` as a UCI string, or `:unavailable` when Stockfish can't
  answer (binary absent, engine crashed, or it reported no move). Callers
  should treat `:unavailable` as "use your own fallback", not as an error.

  Options:

    * `:movetime` — search time in milliseconds (default `#{@default_movetime_ms}`).
  """
  @spec best_move(String.t(), keyword()) :: {:ok, String.t()} | :unavailable
  def best_move(fen, opts \\ []) do
    movetime = Keyword.get(opts, :movetime, @default_movetime_ms)

    try do
      GenServer.call(__MODULE__, {:best_move, fen, movetime}, @call_timeout_ms)
    catch
      # Server not started, or it timed out — degrade gracefully.
      :exit, _ -> :unavailable
    end
  end

  @doc "Whether a Stockfish engine is actually running."
  @spec available?() :: boolean()
  def available? do
    try do
      GenServer.call(__MODULE__, :available?)
    catch
      :exit, _ -> false
    end
  end

  # ─── Server ───────────────────────────────────────────────────────

  @impl true
  def init(opts) do
    state = %{port: nil, buffer: "", pending: nil, available?: false}

    case find_binary(opts) do
      nil ->
        Logger.info("[Stockfish] binary not found; bot will use the fallback engine")
        {:ok, state}

      path ->
        port =
          Port.open(
            {:spawn_executable, path},
            [:binary, :exit_status, :use_stdio, :stderr_to_stdout, args: []]
          )

        Port.command(port, "uci\nisready\n")
        Logger.info("[Stockfish] started: #{path}")
        {:ok, %{state | port: port, available?: true}}
    end
  end

  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, state.available?, state}
  end

  def handle_call({:best_move, _fen, _movetime}, _from, %{available?: false} = state) do
    {:reply, :unavailable, state}
  end

  def handle_call({:best_move, fen, movetime}, from, state) do
    Port.command(state.port, "ucinewgame\nposition fen #{fen}\ngo movetime #{movetime}\n")
    {:noreply, %{state | pending: from}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {lines, buffer} = split_lines(state.buffer <> data)
    {:noreply, Enum.reduce(lines, %{state | buffer: buffer}, &handle_line/2)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("[Stockfish] engine exited (#{status}); falling back")
    state = reply_pending(state, :unavailable)
    {:noreply, %{state | port: nil, available?: false}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ─── Internals ────────────────────────────────────────────────────

  # A `bestmove` line resolves the in-flight request. `(none)` means the engine
  # had no move (mate/stalemate) — treat as unavailable so the caller falls back.
  defp handle_line("bestmove " <> rest, state) do
    case String.split(rest, " ", trim: true) do
      ["(none)" | _] -> reply_pending(state, :unavailable)
      [uci | _] -> reply_pending(state, {:ok, uci})
      [] -> reply_pending(state, :unavailable)
    end
  end

  defp handle_line(_other, state), do: state

  defp reply_pending(%{pending: nil} = state, _reply), do: state

  defp reply_pending(%{pending: from} = state, reply) do
    GenServer.reply(from, reply)
    %{state | pending: nil}
  end

  # Split a binary into complete lines, keeping any trailing partial in the buffer.
  defp split_lines(data) do
    parts = String.split(data, "\n")
    {complete, [rest]} = Enum.split(parts, -1)
    {complete, rest}
  end

  defp find_binary(opts) do
    configured =
      opts[:path] ||
        Application.get_env(:braidonwhatley, __MODULE__, [])[:path] ||
        System.get_env("STOCKFISH_PATH")

    cond do
      is_binary(configured) and File.regular?(configured) -> configured
      is_binary(configured) -> System.find_executable(configured)
      true -> System.find_executable("stockfish")
    end
  end
end
