defmodule App.Chess do
  @moduledoc """
  The contact-gate chess domain.

  A visitor is shown a curated **forced mate-in-N** position and must deliver
  checkmate within `mate_in` moves. The bot defends with its most stubborn legal
  reply (`App.Chess.Stockfish`, falling back to a deterministic legal move from
  the core engine). All legality and mate detection comes from the Rust engine
  via `App.Chess.Native`, so *any* valid mate is accepted — not just one scripted
  line.

  Every curated puzzle is a genuine forced mate, so the bot can never wriggle
  out: the gate is hard but always winnable. Run `mix chess.validate` to
  re-confirm the whole set against Stockfish.
  """
  alias App.Chess.{Native, Stockfish}

  @typedoc "Outcome of a single player move (see `play/2`)."
  @type outcome :: :solved | :failed | :continue | :illegal

  # Both colors use the *solid* glyphs; the board CSS distinguishes white pieces
  # (paper fill + ink stroke) from black (solid ink) via `.is-white`/`.is-black`.
  # Solid glyphs stay crisp on both light and dark squares.
  @glyphs %{
    "K" => "♚",
    "Q" => "♛",
    "R" => "♜",
    "B" => "♝",
    "N" => "♞",
    "P" => "♟",
    "k" => "♚",
    "q" => "♛",
    "r" => "♜",
    "b" => "♝",
    "n" => "♞",
    "p" => "♟"
  }
  @types %{
    "k" => :king,
    "q" => :queen,
    "r" => :rook,
    "b" => :bishop,
    "n" => :knight,
    "p" => :pawn
  }

  # Curated forced mates, each validated against Stockfish (`mix chess.validate`).
  # `mate_in` counts the visitor's own moves; the bot replies in between.
  @puzzles [
    %{
      id: "back-rank",
      fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1",
      mate_in: 1,
      title: "The back rank",
      blurb: "White to move. The king is boxed in by its own pawns. One move.",
      hint:
        "It's a back-rank mate. The king built his own cell with those f-, g- and h-pawns — bring the rook all the way home down the open a-file."
    },
    %{
      id: "queen-sac-luft",
      fen: "6k1/5ppp/8/8/8/8/5PPP/3Q2K1 w - - 0 1",
      mate_in: 1,
      title: "Heavy piece, light work",
      blurb: "White to move. Same cage, a different key. Mate in one.",
      hint:
        "The queen does what the rook did — but she can land right on the back rank next to the king. Slide her home along the d-file and across."
    },
    %{
      id: "king-and-queen",
      fen: "6k1/8/5K2/8/8/8/8/5Q2 w - - 0 1",
      mate_in: 2,
      title: "King and queen",
      blurb: "White to move. The bare essentials. Drive the king into the net — mate in two.",
      hint:
        "Don't check yet — box him in. Use the queen a knight's-move away to take squares, let your king do the cornering, then deliver mate."
    },
    %{
      id: "battery",
      fen: "r5rk/5p1p/5R2/4Q3/8/8/7P/7K w - - 0 1",
      mate_in: 2,
      title: "The battery",
      blurb: "White to move. Rook and queen, working together. Mate in two.",
      hint:
        "Rook and queen are stacked on the same line for a reason. Sacrifice the front piece to crack open the king, then the one behind it finishes."
    }
  ]

  # ─── Puzzles ──────────────────────────────────────────────────────

  @doc "All curated puzzles, in order."
  @spec puzzles() :: [map()]
  def puzzles, do: @puzzles

  @doc "The first puzzle (the one a fresh visitor starts on)."
  @spec first_puzzle() :: map()
  def first_puzzle, do: hd(@puzzles)

  @doc "Look up a puzzle by id, or `nil`."
  @spec get_puzzle(String.t()) :: map() | nil
  def get_puzzle(id), do: Enum.find(@puzzles, &(&1.id == id))

  @doc "The next puzzle after `id`, wrapping around to the first."
  @spec next_puzzle(String.t()) :: map()
  def next_puzzle(id) do
    ids = Enum.map(@puzzles, & &1.id)
    idx = Enum.find_index(ids, &(&1 == id)) || -1
    Enum.at(@puzzles, rem(idx + 1, length(@puzzles)))
  end

  # ─── Position reading ─────────────────────────────────────────────

  @doc """
  Parse a FEN into 8 ranks (rank 8 first) of cells for rendering. Each cell is
  `%{square: "e4", shade: :light | :dark, piece: nil | piece}` where a piece is
  `%{color:, type:, glyph:, char:}`.
  """
  @spec board_rows(String.t()) :: [[map()]]
  def board_rows(fen) do
    [placement | _] = String.split(fen, " ")

    placement
    |> String.split("/")
    |> Enum.with_index()
    |> Enum.map(fn {row, ridx} -> expand_row(row, 8 - ridx) end)
  end

  defp expand_row(row, rank) do
    row
    |> String.graphemes()
    |> Enum.reduce({0, []}, fn ch, {file, cells} ->
      case Integer.parse(ch) do
        {n, ""} ->
          empties = for f <- file..(file + n - 1), do: cell(f, rank, nil)
          {file + n, cells ++ empties}

        :error ->
          {file + 1, cells ++ [cell(file, rank, ch)]}
      end
    end)
    |> elem(1)
  end

  defp cell(file, rank, ch) do
    %{
      square: <<?a + file>> <> Integer.to_string(rank),
      # a1 is dark; a square is dark when file+rank is odd.
      shade: if(rem(file + rank, 2) == 1, do: :dark, else: :light),
      piece: piece_from_char(ch)
    }
  end

  defp piece_from_char(nil), do: nil

  defp piece_from_char(ch) do
    color = if ch == String.upcase(ch), do: :white, else: :black
    %{color: color, type: @types[String.downcase(ch)], glyph: @glyphs[ch], char: ch}
  end

  @doc """
  Analyze a position: `%{status:, side_to_move:, moves:}` with atom `status`
  (`:ongoing | :check | :checkmate | :stalemate`) and `side_to_move`
  (`:white | :black`). `moves` is the list of legal moves (`%{uci, san, from, to}`).
  """
  @spec analyze(String.t()) :: {:ok, map()} | {:error, term()}
  def analyze(fen) do
    with {:ok, a} <- Native.analyze(fen) do
      {:ok,
       %{
         status: String.to_atom(a.status),
         side_to_move: String.to_atom(a.side_to_move),
         moves: a.legal_moves
       }}
    end
  end

  @doc "The legal destination squares for a piece on `from` (UCI `to` strings)."
  @spec legal_targets(String.t(), String.t()) :: [String.t()]
  def legal_targets(fen, from) do
    case analyze(fen) do
      {:ok, %{moves: moves}} ->
        moves |> Enum.filter(&(&1.from == from)) |> Enum.map(& &1.to)

      _ ->
        []
    end
  end

  @doc "The set of squares the side to move can pick a piece up from."
  @spec movable_squares(String.t()) :: MapSet.t()
  def movable_squares(fen) do
    case analyze(fen) do
      {:ok, %{moves: moves}} -> MapSet.new(moves, & &1.from)
      _ -> MapSet.new()
    end
  end

  @doc """
  A `%{to_square => uci}` map of every legal move from `from`. Promotions
  collapse to a single entry per destination, defaulting to the queen — enough
  for click-to-move where the UI only sends the destination square.
  """
  @spec targets_from(String.t(), String.t()) :: %{String.t() => String.t()}
  def targets_from(fen, from) do
    case analyze(fen) do
      {:ok, %{moves: moves}} ->
        moves
        |> Enum.filter(&(&1.from == from))
        |> Enum.reduce(%{}, fn m, acc ->
          Map.update(acc, m.to, m.uci, fn existing ->
            if String.ends_with?(m.uci, "q"), do: m.uci, else: existing
          end)
        end)

      _ ->
        %{}
    end
  end

  # ─── Playing a move ───────────────────────────────────────────────

  @doc """
  Apply the visitor's move (UCI, possibly with a promotion suffix) to a puzzle in
  progress, then — unless the game is already decided — let the bot defend.

  Returns a result map with `:result`:

    * `:solved`   — the visitor delivered checkmate.
    * `:failed`   — the line fizzled: stalemate, or `mate_in` moves used without
      mate. The caller should reset the puzzle.
    * `:continue` — game goes on; `:fen` is the new position (visitor to move),
      `:moves` lists the SAN of the visitor's move then the bot's reply.
    * `:illegal`  — the move wasn't legal (shouldn't happen via the UI).

  `state` carries `:fen`, `:mate_in`, and `:moves_made` (visitor moves so far).
  """
  @spec play(map(), String.t()) :: map()
  def play(%{fen: fen, mate_in: mate_in, moves_made: made}, uci) do
    case Native.apply_move(fen, uci) do
      {:error, reason} ->
        %{result: :illegal, reason: reason}

      {:ok, after_player} ->
        moves_made = made + 1
        resolve(after_player, moves_made, mate_in)
    end
  end

  defp resolve(%{status: "checkmate", fen: fen, last_san: san}, moves_made, _mate_in) do
    %{result: :solved, fen: fen, moves_made: moves_made, moves: [san]}
  end

  defp resolve(%{status: "stalemate"}, _moves_made, _mate_in) do
    %{result: :failed, reason: :stalemate}
  end

  defp resolve(%{}, moves_made, mate_in) when moves_made >= mate_in do
    # Out of moves without mate — this wasn't the mating line.
    %{result: :failed, reason: :out_of_moves}
  end

  defp resolve(%{fen: fen, last_san: player_san}, moves_made, _mate_in) do
    bot_uci = bot_reply(fen)
    {:ok, after_bot} = Native.apply_move(fen, bot_uci)

    %{
      result: :continue,
      fen: after_bot.fen,
      moves_made: moves_made,
      status: String.to_atom(after_bot.status),
      moves: [player_san, after_bot.last_san]
    }
  end

  @doc """
  Can the side to move force checkmate within `n` of its own moves, against
  *every* defense? An exhaustive search through the Rust engine — no Stockfish —
  so it's a definitive proof that a puzzle is a genuine forced mate. Used by the
  test suite and `mix chess.validate`.
  """
  @spec forced_mate?(String.t(), pos_integer()) :: boolean()
  def forced_mate?(fen, n) when n >= 1 do
    {:ok, %{moves: moves}} = analyze(fen)
    Enum.any?(moves, &mates_within?(fen, &1.uci, n))
  end

  defp mates_within?(fen, uci, n) do
    {:ok, after_attacker} = Native.apply_move(fen, uci)

    case after_attacker.status do
      "checkmate" ->
        true

      "stalemate" ->
        false

      _ when n <= 1 ->
        # Needed mate on this move and didn't deliver it.
        false

      _ ->
        # Defender to move: every reply must still leave a forced mate in n-1.
        {:ok, %{moves: replies}} = analyze(after_attacker.fen)

        replies != [] and
          Enum.all?(replies, fn r ->
            {:ok, after_def} = Native.apply_move(after_attacker.fen, r.uci)
            forced_mate?(after_def.fen, n - 1)
          end)
    end
  end

  # The bot's most stubborn legal defense. Stockfish when available; otherwise a
  # deterministic legal pick so behaviour stays reproducible (and testable).
  defp bot_reply(fen) do
    case Stockfish.best_move(fen) do
      {:ok, uci} -> uci
      :unavailable -> fallback_reply(fen)
    end
  end

  defp fallback_reply(fen) do
    {:ok, %{moves: moves}} = analyze(fen)
    moves |> Enum.map(& &1.uci) |> Enum.sort() |> hd()
  end
end
