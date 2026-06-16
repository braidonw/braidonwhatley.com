//! The board: piece placement plus all the state FEN tracks (side to move,
//! castling rights, en-passant target, move clocks), and the logic to apply a
//! move.
//!
//! Pieces are stored as one [`Bitboard`] per (color, kind) plus a per-color
//! occupancy union, so "where are the white rooks" and "what's on e4" are both
//! fast. [`Board`] is `Copy` (~120 bytes), so legality checking can clone,
//! make the move, and inspect king safety without a separate unmake path —
//! we'll add incremental make/unmake later when search needs the speed.

use crate::bitboard::Bitboard;
use crate::moves::{Move, MoveFlag};
use crate::types::{Color, Piece, PieceType, Square};

/// Castling availability, stored as four bits.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default, Hash)]
pub struct CastlingRights(u8);

impl CastlingRights {
    pub const WHITE_KING: u8 = 0b0001;
    pub const WHITE_QUEEN: u8 = 0b0010;
    pub const BLACK_KING: u8 = 0b0100;
    pub const BLACK_QUEEN: u8 = 0b1000;

    #[inline]
    pub const fn empty() -> CastlingRights {
        CastlingRights(0)
    }

    #[inline]
    pub fn has(self, flag: u8) -> bool {
        self.0 & flag != 0
    }

    #[inline]
    pub fn add(&mut self, flag: u8) {
        self.0 |= flag;
    }

    #[inline]
    pub fn remove(&mut self, flag: u8) {
        self.0 &= !flag;
    }

    #[inline]
    pub fn king_side(self, color: Color) -> u8 {
        match color {
            Color::White => Self::WHITE_KING,
            Color::Black => Self::BLACK_KING,
        }
    }

    #[inline]
    pub fn queen_side(self, color: Color) -> u8 {
        match color {
            Color::White => Self::WHITE_QUEEN,
            Color::Black => Self::BLACK_QUEEN,
        }
    }

    #[inline]
    pub fn raw(self) -> u8 {
        self.0
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Board {
    /// `pieces[color][kind]` — the squares holding that exact piece.
    pieces: [[Bitboard; 6]; 2],
    /// Union of all pieces of each color.
    color_bb: [Bitboard; 2],
    pub side_to_move: Color,
    pub castling: CastlingRights,
    /// The square a pawn just skipped over on a double push, capturable en passant.
    pub en_passant: Option<Square>,
    /// Halfmoves since the last pawn move or capture (for the 50-move rule).
    pub halfmove_clock: u16,
    /// Starts at 1, increments after each black move.
    pub fullmove_number: u16,
}

impl Board {
    /// An empty board with white to move and no rights — a blank slate for FEN
    /// parsing or position setup.
    pub fn empty() -> Board {
        Board {
            pieces: [[Bitboard::EMPTY; 6]; 2],
            color_bb: [Bitboard::EMPTY; 2],
            side_to_move: Color::White,
            castling: CastlingRights::empty(),
            en_passant: None,
            halfmove_clock: 0,
            fullmove_number: 1,
        }
    }

    /// The standard chess starting position.
    pub fn starting_position() -> Board {
        // FEN parsing is verified by tests; the start FEN is the canonical source.
        Board::from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
            .expect("the starting FEN is valid")
    }

    // --- Queries ------------------------------------------------------------

    #[inline]
    pub fn pieces(&self, color: Color, kind: PieceType) -> Bitboard {
        self.pieces[color.index()][kind.index()]
    }

    /// All pieces of one color.
    #[inline]
    pub fn color(&self, color: Color) -> Bitboard {
        self.color_bb[color.index()]
    }

    /// Every occupied square.
    #[inline]
    pub fn occupied(&self) -> Bitboard {
        self.color_bb[0] | self.color_bb[1]
    }

    /// All pieces of a given kind, regardless of color.
    #[inline]
    pub fn pieces_of_kind(&self, kind: PieceType) -> Bitboard {
        self.pieces[0][kind.index()] | self.pieces[1][kind.index()]
    }

    /// The piece on a square, if any.
    pub fn piece_at(&self, square: Square) -> Option<Piece> {
        let color = if self.color_bb[Color::White.index()].contains(square) {
            Color::White
        } else if self.color_bb[Color::Black.index()].contains(square) {
            Color::Black
        } else {
            return None;
        };
        for kind in PieceType::ALL {
            if self.pieces[color.index()][kind.index()].contains(square) {
                return Some(Piece::new(color, kind));
            }
        }
        // Color occupancy and piece bitboards are kept in sync, so this is unreachable.
        unreachable!("color occupancy set but no piece kind found at {square}");
    }

    /// The square the given color's king stands on.
    ///
    /// Panics if that king is missing — a malformed position, which legal play
    /// can never produce.
    #[inline]
    pub fn king_square(&self, color: Color) -> Square {
        self.pieces(color, PieceType::King)
            .lsb()
            .expect("every position has a king of each color")
    }

    // --- Mutation -----------------------------------------------------------

    /// Place a piece, updating both the per-kind and per-color bitboards.
    pub fn put_piece(&mut self, square: Square, piece: Piece) {
        self.pieces[piece.color.index()][piece.kind.index()].set(square);
        self.color_bb[piece.color.index()].set(square);
    }

    /// Remove whatever piece sits on `square` (no-op if empty), keeping the
    /// per-color occupancy in sync.
    fn remove_piece(&mut self, square: Square) {
        if let Some(piece) = self.piece_at(square) {
            self.pieces[piece.color.index()][piece.kind.index()].clear(square);
            self.color_bb[piece.color.index()].clear(square);
        }
    }

    /// Move a piece from one square to another, clearing any occupant of `to`.
    fn move_piece(&mut self, from: Square, to: Square) {
        let piece = self
            .piece_at(from)
            .expect("move_piece called with empty origin");
        self.remove_piece(to);
        self.pieces[piece.color.index()][piece.kind.index()].clear(from);
        self.color_bb[piece.color.index()].clear(from);
        self.put_piece(to, piece);
    }

    /// Apply a move, advancing all derived state (clocks, rights, en passant,
    /// side to move). Assumes `mv` is legal for this position.
    pub fn make_move(&mut self, mv: Move) {
        let us = self.side_to_move;
        let them = us.flip();
        let mover = self
            .piece_at(mv.from)
            .expect("make_move called with empty origin square");
        let is_capture = self.color(them).contains(mv.to) || mv.flag == MoveFlag::EnPassant;

        // 50-move clock: reset on pawn moves and captures, else tick up.
        if mover.kind == PieceType::Pawn || is_capture {
            self.halfmove_clock = 0;
        } else {
            self.halfmove_clock += 1;
        }

        // The en-passant target only persists for the single reply after a
        // double push, so clear it now and re-set it below if needed.
        let prev_ep = self.en_passant.take();

        match mv.flag {
            MoveFlag::Normal => self.move_piece(mv.from, mv.to),
            MoveFlag::DoublePawnPush => {
                self.move_piece(mv.from, mv.to);
                // The skipped-over square becomes the capturable target.
                let ep_index = (mv.from.index() as i8 + us.pawn_push()) as u8;
                self.en_passant = Square::new(ep_index);
            }
            MoveFlag::EnPassant => {
                self.move_piece(mv.from, mv.to);
                // The captured pawn sits beside the destination, not on it: it's
                // on the destination file but the moving side's origin rank.
                let captured = Square::from_file_rank(mv.to.file(), mv.from.rank());
                self.remove_piece(captured);
                let _ = prev_ep; // target square is implied by the flag
            }
            MoveFlag::CastleKing => {
                self.move_piece(mv.from, mv.to);
                // King goes e->g; the h-file rook hops to f.
                let rank = mv.from.rank();
                self.move_piece(
                    Square::from_file_rank(7, rank),
                    Square::from_file_rank(5, rank),
                );
            }
            MoveFlag::CastleQueen => {
                self.move_piece(mv.from, mv.to);
                // King goes e->c; the a-file rook hops to d.
                let rank = mv.from.rank();
                self.move_piece(
                    Square::from_file_rank(0, rank),
                    Square::from_file_rank(3, rank),
                );
            }
            MoveFlag::Promotion(kind) => {
                self.remove_piece(mv.from);
                self.remove_piece(mv.to);
                self.put_piece(mv.to, Piece::new(us, kind));
            }
        }

        self.update_castling_rights(mv, mover);

        if us == Color::Black {
            self.fullmove_number += 1;
        }
        self.side_to_move = them;
    }

    /// Strip castling rights affected by this move: the king or a rook leaving
    /// its home square, or a home-square rook being captured.
    fn update_castling_rights(&mut self, mv: Move, mover: Piece) {
        let us = mover.color;
        if mover.kind == PieceType::King {
            self.castling.remove(self.castling.king_side(us));
            self.castling.remove(self.castling.queen_side(us));
        }

        // A rook moving off its home square, or any piece capturing a rook on
        // its home square, kills the matching right. Checking both endpoints
        // against the four corner squares covers both cases uniformly.
        for sq in [mv.from, mv.to] {
            match (sq.file(), sq.rank()) {
                (0, 0) => self.castling.remove(CastlingRights::WHITE_QUEEN),
                (7, 0) => self.castling.remove(CastlingRights::WHITE_KING),
                (0, 7) => self.castling.remove(CastlingRights::BLACK_QUEEN),
                (7, 7) => self.castling.remove(CastlingRights::BLACK_KING),
                _ => {}
            }
        }
    }
}
