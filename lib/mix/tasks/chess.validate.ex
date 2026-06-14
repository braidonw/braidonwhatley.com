defmodule Mix.Tasks.Chess.Validate do
  @shortdoc "Verify every curated chess puzzle is a genuine forced mate"

  @moduledoc """
  Confirms each puzzle in `App.Chess` is a real forced mate in its advertised
  number of moves — so the contact gate is always winnable.

      mix chess.validate

  Two independent checks per puzzle:

    * **engine** — an exhaustive search through the Rust move generator
      (`App.Chess.forced_mate?/2`). This is authoritative: the task fails if any
      puzzle is not a forced mate in its `mate_in`.
    * **stockfish** — a sanity cross-check (`go movetime`) reporting the mate
      distance Stockfish sees. Informational only, and skipped if the binary
      isn't installed.
  """
  use Mix.Task

  @sf_movetime_ms 2000

  @impl true
  def run(_args) do
    Mix.Task.run("app.start")

    results = Enum.map(App.Chess.puzzles(), &check/1)

    IO.puts("\n  puzzle                mate_in   engine    stockfish")
    IO.puts("  " <> String.duplicate("─", 54))
    Enum.each(results, &print_row/1)

    failures = Enum.reject(results, & &1.engine_ok)

    if failures == [] do
      IO.puts("\n  ✓ all #{length(results)} puzzles are genuine forced mates\n")
    else
      ids = Enum.map_join(failures, ", ", & &1.id)
      Mix.raise("#{length(failures)} puzzle(s) failed engine validation: #{ids}")
    end
  end

  defp check(puzzle) do
    %{
      id: puzzle.id,
      mate_in: puzzle.mate_in,
      engine_ok: App.Chess.forced_mate?(puzzle.fen, puzzle.mate_in),
      stockfish: stockfish_mate(puzzle.fen)
    }
  end

  defp print_row(r) do
    engine = if r.engine_ok, do: "PASS", else: "FAIL"

    sf =
      case r.stockfish do
        {:mate, n} -> "mate in #{n}"
        :no_mate -> "no mate"
        :unavailable -> "—"
      end

    IO.puts([
      "  ",
      String.pad_trailing(r.id, 22),
      String.pad_trailing("#{r.mate_in}", 10),
      String.pad_trailing(engine, 10),
      sf
    ])
  end

  # One-shot Stockfish probe over its own port (independent of the running
  # GenServer). Returns the mate distance the engine reports, if any.
  defp stockfish_mate(fen) do
    case System.find_executable("stockfish") do
      nil ->
        :unavailable

      path ->
        port =
          Port.open(
            {:spawn_executable, path},
            [:binary, :exit_status, :use_stdio, :stderr_to_stdout, args: []]
          )

        Port.command(port, "uci\nisready\nposition fen #{fen}\ngo movetime #{@sf_movetime_ms}\n")
        result = read_until_bestmove(port, "", nil)
        Port.command(port, "quit\n")
        result
    end
  end

  defp read_until_bestmove(port, buffer, mate) do
    receive do
      {^port, {:data, data}} ->
        {lines, rest} = split_lines(buffer <> data)

        case Enum.reduce(lines, {:cont, mate}, &scan_line/2) do
          {:done, score} -> done(score)
          {:cont, score} -> read_until_bestmove(port, rest, score)
        end

      {^port, {:exit_status, _}} ->
        done(mate)
    after
      @sf_movetime_ms + 4000 -> done(mate)
    end
  end

  defp scan_line(_line, {:done, _} = acc), do: acc

  defp scan_line("bestmove " <> _, {:cont, mate}), do: {:done, mate}

  defp scan_line("info " <> _ = line, {:cont, mate}) do
    case Regex.run(~r/score mate (-?\d+)/, line) do
      [_, n] -> {:cont, String.to_integer(n)}
      _ -> {:cont, mate}
    end
  end

  defp scan_line(_line, acc), do: acc

  defp done(nil), do: :no_mate
  defp done(n) when n > 0, do: {:mate, n}
  defp done(_), do: :no_mate

  defp split_lines(data) do
    parts = String.split(data, "\n")
    {complete, [rest]} = Enum.split(parts, -1)
    {complete, rest}
  end
end
