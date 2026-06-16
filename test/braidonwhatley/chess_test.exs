defmodule App.ChessTest do
  use ExUnit.Case, async: true

  alias App.Chess

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
  @back_rank "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"

  describe "board_rows/1" do
    test "returns 8 ranks of 8 cells, rank 8 first" do
      rows = Chess.board_rows(@start)
      assert length(rows) == 8
      assert Enum.all?(rows, &(length(&1) == 8))

      [rank8 | _] = rows
      assert hd(rank8).square == "a8"
      assert List.last(rows) |> hd() |> Map.get(:square) == "a1"
    end

    test "parses pieces with color, type and glyph" do
      rows = Chess.board_rows(@back_rank)
      cells = List.flatten(rows)

      a1 = Enum.find(cells, &(&1.square == "a1"))
      assert a1.piece.color == :white
      assert a1.piece.type == :rook

      g8 = Enum.find(cells, &(&1.square == "g8"))
      assert g8.piece.color == :black
      assert g8.piece.type == :king

      assert Enum.find(cells, &(&1.square == "d4")).piece == nil
    end

    test "a1 is a dark square, h1 is light" do
      cells = @start |> Chess.board_rows() |> List.flatten()
      assert Enum.find(cells, &(&1.square == "a1")).shade == :dark
      assert Enum.find(cells, &(&1.square == "h1")).shade == :light
    end
  end

  describe "analyze/1" do
    test "reports the side to move and legal move count for the start position" do
      assert {:ok, %{status: :ongoing, side_to_move: :white, moves: moves}} =
               Chess.analyze(@start)

      assert length(moves) == 20
    end

    test "detects checkmate" do
      # The back-rank position after Ra8#.
      assert {:ok, %{status: :checkmate}} = Chess.analyze("R5k1/5ppp/8/8/8/8/5PPP/6K1 b - - 1 1")
    end

    test "detects stalemate" do
      # Black to move, no legal move, not in check.
      assert {:ok, %{status: :stalemate}} = Chess.analyze("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    end

    test "errors on an invalid FEN" do
      assert {:error, _} = Chess.analyze("not a fen")
    end
  end

  describe "targets_from/2" do
    test "lists a rook's legal destinations" do
      targets = Chess.targets_from(@back_rank, "a1")
      assert Map.has_key?(targets, "a8")
      assert targets["a8"] == "a1a8"
      # Up the a-file and along the first rank.
      assert "a5" in Map.keys(targets)
      assert "f1" in Map.keys(targets)
    end

    test "prefers the queen for a promotion destination" do
      # White pawn on b7, promote on b8.
      targets = Chess.targets_from("6k1/1P6/8/8/8/8/6K1/8 w - - 0 1", "b7")
      assert targets["b8"] == "b7b8q"
    end
  end

  describe "play/2 — the gate" do
    test "a mating move solves the puzzle" do
      res = Chess.play(state(@back_rank, 1, 0), "a1a8")
      assert res.result == :solved
      assert res.moves == ["Ra8#"]
    end

    test "a legal non-mating move on a mate-in-1 fails (resets)" do
      res = Chess.play(state(@back_rank, 1, 0), "a1a7")
      assert res.result == :failed
    end

    test "an illegal move is rejected, not applied" do
      res = Chess.play(state(@back_rank, 1, 0), "a1b3")
      assert res.result == :illegal
    end

    test "the key move of a mate-in-2 continues with a legal bot reply" do
      kq = "6k1/8/5K2/8/8/8/8/5Q2 w - - 0 1"
      res = Chess.play(state(kq, 2, 0), "f1g2")
      assert res.result == :continue
      assert [player_san, bot_san] = res.moves
      assert player_san =~ "Q"
      assert is_binary(bot_san) and bot_san != ""
      # After the bot's reply it's the player's move again, still not mate.
      assert {:ok, %{side_to_move: :white}} = Chess.analyze(res.fen)
    end
  end

  describe "forced_mate?/2 — every curated puzzle is a genuine forced mate" do
    for puzzle <- Chess.puzzles() do
      @puzzle puzzle
      test "#{puzzle.id} is mate in #{puzzle.mate_in}" do
        assert Chess.forced_mate?(@puzzle.fen, @puzzle.mate_in),
               "#{@puzzle.id} should be a forced mate in #{@puzzle.mate_in}"
      end

      if puzzle.mate_in > 1 do
        test "#{puzzle.id} is not a faster mate in #{puzzle.mate_in - 1}" do
          refute Chess.forced_mate?(@puzzle.fen, @puzzle.mate_in - 1),
                 "#{@puzzle.id} should not be solvable faster than #{@puzzle.mate_in}"
        end
      end
    end

    test "every puzzle is white to move with legal moves" do
      for p <- Chess.puzzles() do
        assert {:ok, %{side_to_move: :white, moves: moves}} = Chess.analyze(p.fen)
        assert moves != []
      end
    end
  end

  describe "puzzle navigation" do
    test "next_puzzle wraps around" do
      ids = Enum.map(Chess.puzzles(), & &1.id)
      last = List.last(ids)
      assert Chess.next_puzzle(last).id == hd(ids)
    end
  end

  defp state(fen, mate_in, moves_made),
    do: %{fen: fen, mate_in: mate_in, moves_made: moves_made}
end
