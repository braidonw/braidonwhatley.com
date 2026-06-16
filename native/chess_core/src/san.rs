//! Standard Algebraic Notation (SAN) — the human-readable move format you see
//! in books and scoresheets: `e4`, `Nf3`, `exd5`, `O-O`, `Raxd1`, `e8=Q+`.
//!
//! SAN is context-sensitive: whether a move needs a capture `x`, a
//! disambiguation (`Nbd2` when either knight could go to d2), or a check `+` /
//! mate `#` suffix all depend on the position. So [`san`] takes the board the
//! move is played *from*.

use crate::board::Board;
use crate::movegen::{in_check, legal_moves};
use crate::moves::{Move, MoveFlag};
use crate::types::PieceType;

/// Render `mv` (which must be legal in `board`) as SAN.
pub fn san(board: &Board, mv: Move) -> String {
    let mut text = match mv.flag {
        MoveFlag::CastleKing => "O-O".to_string(),
        MoveFlag::CastleQueen => "O-O-O".to_string(),
        _ => san_body(board, mv),
    };

    // Check/checkmate suffix, determined by playing the move out.
    let mut after = *board;
    after.make_move(mv);
    if in_check(&after) {
        text.push(if legal_moves(&after).is_empty() { '#' } else { '+' });
    }
    text
}

/// The piece/capture/destination core, without the check suffix or castling.
fn san_body(board: &Board, mv: Move) -> String {
    let piece = board.piece_at(mv.from).expect("SAN: origin must hold a piece");
    let destination = mv.to.to_algebraic();
    let is_capture = board.piece_at(mv.to).is_some() || mv.flag == MoveFlag::EnPassant;

    if piece.kind == PieceType::Pawn {
        let mut text = String::new();
        if is_capture {
            // Pawn captures name the origin file: "exd5".
            text.push(file_char(mv.from.file()));
            text.push('x');
        }
        text.push_str(&destination);
        if let Some(promotion) = mv.promotion() {
            text.push('=');
            text.push(piece_letter(promotion));
        }
        text
    } else {
        let mut text = String::new();
        text.push(piece_letter(piece.kind));
        text.push_str(&disambiguation(board, mv, piece.kind));
        if is_capture {
            text.push('x');
        }
        text.push_str(&destination);
        text
    }
}

/// The minimal origin qualifier needed when another same-type piece could also
/// reach the destination: a file, a rank, or both.
fn disambiguation(board: &Board, mv: Move, kind: PieceType) -> String {
    let rivals: Vec<Move> = legal_moves(board)
        .into_iter()
        .filter(|m| {
            m.to == mv.to
                && m.from != mv.from
                && board.piece_at(m.from).map(|p| p.kind) == Some(kind)
        })
        .collect();

    if rivals.is_empty() {
        return String::new();
    }

    let file_clashes = rivals.iter().any(|m| m.from.file() == mv.from.file());
    let rank_clashes = rivals.iter().any(|m| m.from.rank() == mv.from.rank());

    // Prefer file, then rank, then both — the standard precedence.
    if !file_clashes {
        file_char(mv.from.file()).to_string()
    } else if !rank_clashes {
        rank_char(mv.from.rank()).to_string()
    } else {
        format!("{}{}", file_char(mv.from.file()), rank_char(mv.from.rank()))
    }
}

fn piece_letter(kind: PieceType) -> char {
    kind.to_char().to_ascii_uppercase()
}

fn file_char(file: u8) -> char {
    (b'a' + file) as char
}

fn rank_char(rank: u8) -> char {
    (b'1' + rank) as char
}
