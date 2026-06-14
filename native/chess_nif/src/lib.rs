//! Rustler NIF bridging Elixir to `chess-core`.
//!
//! The surface is deliberately tiny and **stateless**: every function takes a
//! FEN string (and a UCI move where relevant) and returns plain data. Nothing
//! here unwraps untrusted input — a bad FEN or an illegal move comes back as an
//! `{:error, reason}` tuple rather than a panic, so a malformed request can
//! never take down the BEAM.

use chess_core::{in_check, legal_moves, san, Board, Color, Move};
use rustler::NifMap;

/// One legal move, described every way the UI might need it.
#[derive(NifMap)]
struct MoveInfo {
    /// Long algebraic / UCI, e.g. `"e2e4"` or `"e7e8q"`.
    uci: String,
    /// Standard algebraic notation, e.g. `"Nf3"`, `"Qxh7#"`.
    san: String,
    /// Origin square, e.g. `"e2"`.
    from: String,
    /// Destination square, e.g. `"e4"`.
    to: String,
}

/// A full read of a position: whose move, game status, and every legal move.
#[derive(NifMap)]
struct Analysis {
    /// `"ongoing"` | `"check"` | `"checkmate"` | `"stalemate"`.
    status: String,
    /// `"white"` | `"black"`.
    side_to_move: String,
    legal_moves: Vec<MoveInfo>,
}

/// The result of applying a move: the new position plus what it produced.
#[derive(NifMap)]
struct ApplyResult {
    fen: String,
    status: String,
    side_to_move: String,
    /// SAN of the move just played (computed on the pre-move board).
    last_san: String,
}

fn color_str(c: Color) -> String {
    match c {
        Color::White => "white",
        Color::Black => "black",
    }
    .to_string()
}

/// Classify a position from the side-to-move's perspective.
///
/// `chess-core`'s `in_check` already refers to the side to move, and an empty
/// legal-move list means the game is over: in check → checkmate, otherwise
/// stalemate.
fn status_str(board: &Board) -> String {
    let has_moves = !legal_moves(board).is_empty();
    let checked = in_check(board);
    match (has_moves, checked) {
        (false, true) => "checkmate",
        (false, false) => "stalemate",
        (true, true) => "check",
        (true, false) => "ongoing",
    }
    .to_string()
}

fn parse_board(fen: &str) -> Result<Board, String> {
    Board::from_fen(fen).map_err(|e| format!("invalid fen: {e:?}"))
}

fn move_info(board: &Board, mv: Move) -> MoveInfo {
    MoveInfo {
        uci: mv.to_uci(),
        san: san(board, mv),
        from: mv.from.to_algebraic(),
        to: mv.to.to_algebraic(),
    }
}

/// Read a position: status, side to move, and all legal moves.
#[rustler::nif]
fn analyze(fen: String) -> Result<Analysis, String> {
    let board = parse_board(&fen)?;
    let moves = legal_moves(&board)
        .into_iter()
        .map(|mv| move_info(&board, mv))
        .collect();
    Ok(Analysis {
        status: status_str(&board),
        side_to_move: color_str(board.side_to_move),
        legal_moves: moves,
    })
}

/// Apply a UCI move if (and only if) it is legal in `fen`.
///
/// Returns the resulting FEN, the new status, the side now to move, and the
/// SAN of the move played. An illegal/unknown UCI string is an error, never a
/// silent no-op.
#[rustler::nif]
fn apply_move(fen: String, uci: String) -> Result<ApplyResult, String> {
    let mut board = parse_board(&fen)?;
    let mv = legal_moves(&board)
        .into_iter()
        .find(|m| m.to_uci() == uci)
        .ok_or_else(|| format!("illegal move: {uci}"))?;

    let last_san = san(&board, mv);
    board.make_move(mv);

    Ok(ApplyResult {
        fen: board.to_fen(),
        status: status_str(&board),
        side_to_move: color_str(board.side_to_move),
        last_san,
    })
}

rustler::init!("Elixir.App.Chess.Native");
