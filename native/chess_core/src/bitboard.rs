//! A 64-bit set of squares.
//!
//! Each bit position corresponds to a [`Square`] index (bit 0 = a1, bit 63 =
//! h8). Treating the board as an integer lets us compute attacks, moves, and
//! masks with single CPU instructions instead of loops.

use crate::types::Square;
use std::ops::{BitAnd, BitAndAssign, BitOr, BitOrAssign, BitXor, BitXorAssign, Not, Shl, Shr};

#[derive(Clone, Copy, PartialEq, Eq, Default, Hash)]
pub struct Bitboard(pub u64);

impl Bitboard {
    pub const EMPTY: Bitboard = Bitboard(0);
    pub const FULL: Bitboard = Bitboard(!0);

    /// File masks, indexed `0..8` (a-file..h-file).
    pub const FILE_A: Bitboard = Bitboard(0x0101_0101_0101_0101);
    pub const FILE_H: Bitboard = Bitboard(0x8080_8080_8080_8080);

    /// Rank masks for the two pawn-relevant home ranks.
    pub const RANK_1: Bitboard = Bitboard(0x0000_0000_0000_00FF);
    pub const RANK_8: Bitboard = Bitboard(0xFF00_0000_0000_0000);

    /// A board with only `square` set.
    #[inline]
    pub const fn from_square(square: Square) -> Bitboard {
        Bitboard(1u64 << square.index())
    }

    #[inline]
    pub const fn is_empty(self) -> bool {
        self.0 == 0
    }

    #[inline]
    pub const fn any(self) -> bool {
        self.0 != 0
    }

    /// Number of set squares.
    #[inline]
    pub const fn count(self) -> u32 {
        self.0.count_ones()
    }

    #[inline]
    pub const fn contains(self, square: Square) -> bool {
        self.0 & (1u64 << square.index()) != 0
    }

    #[inline]
    pub fn set(&mut self, square: Square) {
        self.0 |= 1u64 << square.index();
    }

    #[inline]
    pub fn clear(&mut self, square: Square) {
        self.0 &= !(1u64 << square.index());
    }

    /// The least-significant set square, or `None` if empty.
    #[inline]
    pub const fn lsb(self) -> Option<Square> {
        if self.0 == 0 {
            None
        } else {
            Some(Square::from_index(self.0.trailing_zeros() as u8))
        }
    }

    /// Pop the least-significant set square, returning it and clearing the bit.
    #[inline]
    pub fn pop_lsb(&mut self) -> Option<Square> {
        let sq = self.lsb()?;
        self.0 &= self.0 - 1;
        Some(sq)
    }
}

/// Iterate the set squares from a1 upward, consuming the board.
impl Iterator for Bitboard {
    type Item = Square;

    #[inline]
    fn next(&mut self) -> Option<Square> {
        self.pop_lsb()
    }
}

// --- Operator overloads so bitboards read like sets -------------------------

macro_rules! bitwise_op {
    ($trait:ident, $method:ident, $op:tt) => {
        impl $trait for Bitboard {
            type Output = Bitboard;
            #[inline]
            fn $method(self, rhs: Bitboard) -> Bitboard {
                Bitboard(self.0 $op rhs.0)
            }
        }
    };
}

bitwise_op!(BitAnd, bitand, &);
bitwise_op!(BitOr, bitor, |);
bitwise_op!(BitXor, bitxor, ^);

impl Not for Bitboard {
    type Output = Bitboard;
    #[inline]
    fn not(self) -> Bitboard {
        Bitboard(!self.0)
    }
}

impl BitAndAssign for Bitboard {
    #[inline]
    fn bitand_assign(&mut self, rhs: Bitboard) {
        self.0 &= rhs.0;
    }
}

impl BitOrAssign for Bitboard {
    #[inline]
    fn bitor_assign(&mut self, rhs: Bitboard) {
        self.0 |= rhs.0;
    }
}

impl BitXorAssign for Bitboard {
    #[inline]
    fn bitxor_assign(&mut self, rhs: Bitboard) {
        self.0 ^= rhs.0;
    }
}

impl Shl<u32> for Bitboard {
    type Output = Bitboard;
    #[inline]
    fn shl(self, rhs: u32) -> Bitboard {
        Bitboard(self.0 << rhs)
    }
}

impl Shr<u32> for Bitboard {
    type Output = Bitboard;
    #[inline]
    fn shr(self, rhs: u32) -> Bitboard {
        Bitboard(self.0 >> rhs)
    }
}

impl std::fmt::Debug for Bitboard {
    /// Render as an 8x8 grid (rank 8 at the top) for readable test failures.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        writeln!(f, "Bitboard(0x{:016X})", self.0)?;
        for rank in (0..8).rev() {
            write!(f, "  ")?;
            for file in 0..8 {
                let sq = Square::from_file_rank(file, rank);
                f.write_str(if self.contains(sq) { "X " } else { ". " })?;
            }
            writeln!(f)?;
        }
        Ok(())
    }
}
