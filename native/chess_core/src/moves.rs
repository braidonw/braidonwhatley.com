//! Move representation.
//!
//! A [`Move`] is just origin + destination + a [`MoveFlag`] describing anything
//! that isn't a plain "pick up here, put down there." The flag is what lets
//! `make_move` know to also remove an en-passant pawn, shuffle a rook during
//! castling, or swap a pawn for a queen.

use crate::types::{PieceType, Square};

/// What kind of move this is, beyond the from/to squares.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum MoveFlag {
    /// Ordinary move or capture (capture is inferred from the board).
    Normal,
    /// Pawn advancing two squares from its home rank (sets the en-passant target).
    DoublePawnPush,
    /// Capturing en passant; the captured pawn is not on the destination square.
    EnPassant,
    /// King-side castle (O-O).
    CastleKing,
    /// Queen-side castle (O-O-O).
    CastleQueen,
    /// Pawn promotion to the given piece kind.
    Promotion(PieceType),
}

/// A single chess move.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub struct Move {
    pub from: Square,
    pub to: Square,
    pub flag: MoveFlag,
}

impl Move {
    #[inline]
    pub const fn new(from: Square, to: Square, flag: MoveFlag) -> Move {
        Move { from, to, flag }
    }

    #[inline]
    pub const fn normal(from: Square, to: Square) -> Move {
        Move::new(from, to, MoveFlag::Normal)
    }

    /// The promotion piece, if this move is a promotion.
    #[inline]
    pub const fn promotion(self) -> Option<PieceType> {
        match self.flag {
            MoveFlag::Promotion(kind) => Some(kind),
            _ => None,
        }
    }

    /// Long algebraic / UCI notation, e.g. `"e2e4"` or `"e7e8q"`.
    pub fn to_uci(self) -> String {
        let mut s = format!("{}{}", self.from.to_algebraic(), self.to.to_algebraic());
        if let Some(kind) = self.promotion() {
            s.push(kind.to_char());
        }
        s
    }
}

impl std::fmt::Display for Move {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.to_uci())
    }
}
