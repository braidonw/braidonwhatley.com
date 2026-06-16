defmodule App.Chess.Native do
  @moduledoc """
  Rustler NIF over the vendored `chess-core` engine (`native/chess_nif`).

  Stateless and string-based: every call takes a FEN (and a UCI move where
  relevant) and returns plain data. Both functions return `{:ok, map}` on
  success or `{:error, reason}` on bad input — an invalid FEN or illegal move
  is an error tuple, never a crash.

  Returned maps use atom keys:

    * `analyze/1` → `%{status: status, side_to_move: "white" | "black",
      legal_moves: [%{uci:, san:, from:, to:}]}`
    * `apply_move/2` → `%{fen:, status:, side_to_move:, last_san:}`

  where `status` is one of `"ongoing"`, `"check"`, `"checkmate"`, `"stalemate"`.
  """
  use Rustler, otp_app: :braidonwhatley, crate: "chess_nif"

  @doc "Read a position: status, side to move, and every legal move."
  @spec analyze(String.t()) :: {:ok, map()} | {:error, String.t()}
  def analyze(_fen), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Apply a UCI move if it is legal in the given FEN."
  @spec apply_move(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def apply_move(_fen, _uci), do: :erlang.nif_error(:nif_not_loaded)
end
