//! `chess-core` — board representation, legal move generation, and FEN parsing.
//!
//! This crate is pure chess rules with no UI and no AI. The GUI and the
//! (future) engine both build on it. The public surface is small:
//!
//! - [`Board`] — a position, with [`Board::make_move`] and FEN I/O.
//! - [`legal_moves`] — every legal move in a position.
//! - [`Move`] / [`MoveFlag`] — moves, including castling/en passant/promotion.
//! - [`perft`] — the standard move-generation correctness check.

mod bitboard;
mod board;
mod fen;
mod movegen;
mod moves;
mod pgn;
mod san;
mod types;

pub use bitboard::Bitboard;
pub use board::{Board, CastlingRights};
pub use fen::FenError;
pub use movegen::{in_check, is_square_attacked, legal_moves};
pub use moves::{Move, MoveFlag};
pub use pgn::{parse_pgn, PgnError, PgnGame};
pub use san::san;
pub use types::{Color, Piece, PieceType, Square};

/// Count the leaf nodes of the move tree to a given depth.
///
/// This is *perft*, the standard way to validate a move generator: the node
/// counts for well-known positions are published, so any discrepancy points to
/// a bug (a missed move, an illegal move allowed, a mishandled en passant or
/// castle). Depth 0 is defined as a single node (the position itself).
pub fn perft(board: &Board, depth: u32) -> u64 {
    if depth == 0 {
        return 1;
    }
    let moves = legal_moves(board);
    // At depth 1 the answer is just the number of legal moves — skip the recursion.
    if depth == 1 {
        return moves.len() as u64;
    }
    let mut nodes = 0;
    for mv in moves {
        let mut next = *board;
        next.make_move(mv);
        nodes += perft(&next, depth - 1);
    }
    nodes
}

/// Like [`perft`], but returns the per-move split at the root (move → subtree
/// node count). Indispensable for *locating* a perft bug: compare against a
/// reference engine's split and the move whose count differs is the culprit.
pub fn perft_divide(board: &Board, depth: u32) -> Vec<(Move, u64)> {
    legal_moves(board)
        .into_iter()
        .map(|mv| {
            let mut next = *board;
            next.make_move(mv);
            let count = if depth <= 1 { 1 } else { perft(&next, depth - 1) };
            (mv, count)
        })
        .collect()
}
