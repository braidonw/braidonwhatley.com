//! Legal move generation.
//!
//! The approach is the simplest one that's easy to verify: generate
//! *pseudo-legal* moves (everything that respects how a piece moves and doesn't
//! land on a friendly piece), then keep only those that don't leave our own
//! king in check, by trying each on a copy of the board. It's not the fastest
//! scheme — that comes later, when search needs it — but it's correct, and
//! perft tests prove it.
//!
//! Sliding attacks (bishop/rook/queen) are computed by walking rays out from
//! the square until they hit a blocker. Knight and king attacks are looked up
//! from tables built once at startup.

use crate::bitboard::Bitboard;
use crate::board::{Board, CastlingRights};
use crate::moves::{Move, MoveFlag};
use crate::types::{Color, PieceType, Square};
use std::sync::LazyLock;

/// Knight destination squares, precomputed per origin square.
static KNIGHT_ATTACKS: LazyLock<[Bitboard; 64]> = LazyLock::new(|| {
    build_offset_table(&[
        (1, 2),
        (2, 1),
        (2, -1),
        (1, -2),
        (-1, -2),
        (-2, -1),
        (-2, 1),
        (-1, 2),
    ])
});

/// King destination squares (one step in any direction), precomputed.
static KING_ATTACKS: LazyLock<[Bitboard; 64]> = LazyLock::new(|| {
    build_offset_table(&[
        (1, 0),
        (1, 1),
        (0, 1),
        (-1, 1),
        (-1, 0),
        (-1, -1),
        (0, -1),
        (1, -1),
    ])
});

/// Build a 64-entry attack table from a fixed set of (file, rank) offsets,
/// dropping any that fall off the board.
fn build_offset_table(offsets: &[(i8, i8)]) -> [Bitboard; 64] {
    let mut table = [Bitboard::EMPTY; 64];
    for (sq_index, entry) in table.iter_mut().enumerate() {
        let f0 = (sq_index & 7) as i8;
        let r0 = (sq_index >> 3) as i8;
        for &(df, dr) in offsets {
            let (f, r) = (f0 + df, r0 + dr);
            if (0..8).contains(&f) && (0..8).contains(&r) {
                entry.set(Square::from_file_rank(f as u8, r as u8));
            }
        }
    }
    table
}

const BISHOP_DIRS: [(i8, i8); 4] = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
const ROOK_DIRS: [(i8, i8); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

/// Squares a sliding piece attacks given the current occupancy: walk each
/// direction, marking squares until (and including) the first blocker.
fn sliding_attacks(sq: Square, occupied: Bitboard, dirs: &[(i8, i8)]) -> Bitboard {
    let mut attacks = Bitboard::EMPTY;
    let f0 = sq.file() as i8;
    let r0 = sq.rank() as i8;
    for &(df, dr) in dirs {
        let (mut f, mut r) = (f0 + df, r0 + dr);
        while (0..8).contains(&f) && (0..8).contains(&r) {
            let target = Square::from_file_rank(f as u8, r as u8);
            attacks.set(target);
            if occupied.contains(target) {
                break; // the blocker square is attackable; nothing beyond it is.
            }
            f += df;
            r += dr;
        }
    }
    attacks
}

#[inline]
pub fn bishop_attacks(sq: Square, occupied: Bitboard) -> Bitboard {
    sliding_attacks(sq, occupied, &BISHOP_DIRS)
}

#[inline]
pub fn rook_attacks(sq: Square, occupied: Bitboard) -> Bitboard {
    sliding_attacks(sq, occupied, &ROOK_DIRS)
}

#[inline]
pub fn queen_attacks(sq: Square, occupied: Bitboard) -> Bitboard {
    bishop_attacks(sq, occupied) | rook_attacks(sq, occupied)
}

/// The squares a single pawn of `color` on `square` attacks (diagonally).
pub fn pawn_attacks(color: Color, square: Square) -> Bitboard {
    let bb = Bitboard::from_square(square);
    match color {
        // Shift NW/NE, masking the edge file so the board doesn't wrap around.
        Color::White => ((bb & !Bitboard::FILE_A) << 7) | ((bb & !Bitboard::FILE_H) << 9),
        Color::Black => ((bb & !Bitboard::FILE_H) >> 7) | ((bb & !Bitboard::FILE_A) >> 9),
    }
}

/// Is `square` attacked by any piece of `by`? Used for check detection and to
/// validate castling transit squares.
pub fn is_square_attacked(board: &Board, square: Square, by: Color) -> bool {
    // Knights and king: direct table lookups.
    if (KNIGHT_ATTACKS[square.index() as usize] & board.pieces(by, PieceType::Knight)).any() {
        return true;
    }
    if (KING_ATTACKS[square.index() as usize] & board.pieces(by, PieceType::King)).any() {
        return true;
    }

    // Pawns: a `by` pawn attacks `square` exactly when an opposite-color pawn
    // placed on `square` would attack that pawn (attacks are symmetric).
    if (pawn_attacks(by.flip(), square) & board.pieces(by, PieceType::Pawn)).any() {
        return true;
    }

    // Sliding pieces: trace rays from the target and see if a relevant slider
    // sits at the end.
    let occupied = board.occupied();
    let diagonal = board.pieces(by, PieceType::Bishop) | board.pieces(by, PieceType::Queen);
    if (bishop_attacks(square, occupied) & diagonal).any() {
        return true;
    }
    let orthogonal = board.pieces(by, PieceType::Rook) | board.pieces(by, PieceType::Queen);
    if (rook_attacks(square, occupied) & orthogonal).any() {
        return true;
    }

    false
}

/// Is the side to move currently in check?
pub fn in_check(board: &Board) -> bool {
    let us = board.side_to_move;
    is_square_attacked(board, board.king_square(us), us.flip())
}

/// All fully legal moves for the side to move.
pub fn legal_moves(board: &Board) -> Vec<Move> {
    let us = board.side_to_move;
    let them = us.flip();
    let mut pseudo = Vec::with_capacity(48);

    generate_pawn_moves(board, &mut pseudo);
    generate_knight_moves(board, &mut pseudo);
    generate_king_moves(board, &mut pseudo);
    generate_slider_moves(board, &mut pseudo);

    // A pseudo-legal move is legal iff it doesn't leave our king attacked.
    // Castling transit squares are already vetted in generate_king_moves, so
    // here we only need to check the king's final resting square.
    pseudo.retain(|&mv| {
        let mut next = *board;
        next.make_move(mv);
        !is_square_attacked(&next, next.king_square(us), them)
    });
    pseudo
}

fn generate_knight_moves(board: &Board, out: &mut Vec<Move>) {
    let us = board.side_to_move;
    let own = board.color(us);
    for from in board.pieces(us, PieceType::Knight) {
        let targets = KNIGHT_ATTACKS[from.index() as usize] & !own;
        for to in targets {
            out.push(Move::normal(from, to));
        }
    }
}

fn generate_slider_moves(board: &Board, out: &mut Vec<Move>) {
    let us = board.side_to_move;
    let own = board.color(us);
    let occupied = board.occupied();

    for from in board.pieces(us, PieceType::Bishop) {
        push_targets(out, from, bishop_attacks(from, occupied) & !own);
    }
    for from in board.pieces(us, PieceType::Rook) {
        push_targets(out, from, rook_attacks(from, occupied) & !own);
    }
    for from in board.pieces(us, PieceType::Queen) {
        push_targets(out, from, queen_attacks(from, occupied) & !own);
    }
}

#[inline]
fn push_targets(out: &mut Vec<Move>, from: Square, targets: Bitboard) {
    for to in targets {
        out.push(Move::normal(from, to));
    }
}

fn generate_king_moves(board: &Board, out: &mut Vec<Move>) {
    let us = board.side_to_move;
    let them = us.flip();
    let own = board.color(us);
    let from = board.king_square(us);

    for to in KING_ATTACKS[from.index() as usize] & !own {
        out.push(Move::normal(from, to));
    }

    // Castling: the king must not be in check, and the squares it passes
    // through (and lands on) must be unattacked, with the path clear.
    let occupied = board.occupied();
    let rank = from.rank();
    let in_check_now = is_square_attacked(board, from, them);
    if in_check_now {
        return;
    }

    let unattacked = |sq: Square| !is_square_attacked(board, sq, them);
    let empty = |sq: Square| !occupied.contains(sq);

    if board.castling.has(board.castling.king_side(us)) {
        let f = Square::from_file_rank(5, rank);
        let g = Square::from_file_rank(6, rank);
        if empty(f) && empty(g) && unattacked(f) && unattacked(g) {
            out.push(Move::new(from, g, MoveFlag::CastleKing));
        }
    }
    if board.castling.has(board.castling.queen_side(us)) {
        let d = Square::from_file_rank(3, rank);
        let c = Square::from_file_rank(2, rank);
        let b = Square::from_file_rank(1, rank);
        // b-file only needs to be empty (the rook crosses it); the king stops at c.
        if empty(d) && empty(c) && empty(b) && unattacked(d) && unattacked(c) {
            out.push(Move::new(from, c, MoveFlag::CastleQueen));
        }
    }
    let _ = CastlingRights::WHITE_KING; // keep the constants module-visible
}

fn generate_pawn_moves(board: &Board, out: &mut Vec<Move>) {
    let us = board.side_to_move;
    let them = us.flip();
    let occupied = board.occupied();
    let enemies = board.color(them);
    let push_dir = us.pawn_push();

    // Rank from which a pawn may double-push, and the rank it promotes on.
    let (start_rank, promo_rank) = match us {
        Color::White => (1, 7),
        Color::Black => (6, 0),
    };

    for from in board.pieces(us, PieceType::Pawn) {
        let from_idx = from.index() as i8;

        // Single push.
        let one = from_idx + push_dir;
        if let Some(one_sq) = Square::new(one as u8) {
            if !occupied.contains(one_sq) {
                emit_pawn_move(out, from, one_sq, one_sq.rank() == promo_rank);

                // Double push, only from the home rank and only if both squares are clear.
                if from.rank() == start_rank {
                    let two_sq = Square::from_index((from_idx + 2 * push_dir) as u8);
                    if !occupied.contains(two_sq) {
                        out.push(Move::new(from, two_sq, MoveFlag::DoublePawnPush));
                    }
                }
            }
        }

        // Captures (including promotions).
        for to in pawn_attacks(us, from) & enemies {
            emit_pawn_move(out, from, to, to.rank() == promo_rank);
        }

        // En passant: the target square is empty, but a pawn sits beside it.
        if let Some(ep) = board.en_passant {
            if (pawn_attacks(us, from) & Bitboard::from_square(ep)).any() {
                out.push(Move::new(from, ep, MoveFlag::EnPassant));
            }
        }
    }
}

/// Push a pawn move, expanding to the four promotion choices on the last rank.
fn emit_pawn_move(out: &mut Vec<Move>, from: Square, to: Square, is_promotion: bool) {
    if is_promotion {
        for kind in [
            PieceType::Queen,
            PieceType::Rook,
            PieceType::Bishop,
            PieceType::Knight,
        ] {
            out.push(Move::new(from, to, MoveFlag::Promotion(kind)));
        }
    } else {
        out.push(Move::normal(from, to));
    }
}
