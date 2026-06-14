//! Fundamental chess value types: colors, piece kinds, and board squares.
//!
//! Squares use the *little-endian rank-file* (LERF) mapping, the convention
//! almost every bitboard engine uses:
//!
//! ```text
//!   8 | 56 57 58 59 60 61 62 63
//!   7 | 48 49 50 51 52 53 54 55
//!   6 | 40 41 42 43 44 45 46 47
//!   5 | 32 33 34 35 36 37 38 39
//!   4 | 24 25 26 27 28 29 30 31
//!   3 | 16 17 18 19 20 21 22 23
//!   2 |  8  9 10 11 12 13 14 15
//!   1 |  0  1  2  3  4  5  6  7
//!     +------------------------
//!        a  b  c  d  e  f  g  h
//! ```
//!
//! So `square = rank * 8 + file`, `file = square & 7`, `rank = square >> 3`.

/// The side to move / piece owner.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum Color {
    White,
    Black,
}

impl Color {
    /// The opposing color.
    #[inline]
    pub const fn flip(self) -> Color {
        match self {
            Color::White => Color::Black,
            Color::Black => Color::White,
        }
    }

    /// Index into color-keyed arrays (`White = 0`, `Black = 1`).
    #[inline]
    pub const fn index(self) -> usize {
        self as usize
    }

    /// The direction a pawn of this color advances, as a square-index delta.
    #[inline]
    pub const fn pawn_push(self) -> i8 {
        match self {
            Color::White => 8,
            Color::Black => -8,
        }
    }
}

/// The six kinds of chess piece, independent of color.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub enum PieceType {
    Pawn,
    Knight,
    Bishop,
    Rook,
    Queen,
    King,
}

impl PieceType {
    pub const ALL: [PieceType; 6] = [
        PieceType::Pawn,
        PieceType::Knight,
        PieceType::Bishop,
        PieceType::Rook,
        PieceType::Queen,
        PieceType::King,
    ];

    #[inline]
    pub const fn index(self) -> usize {
        self as usize
    }

    /// The lowercase letter used in FEN/PGN for this piece kind.
    pub const fn to_char(self) -> char {
        match self {
            PieceType::Pawn => 'p',
            PieceType::Knight => 'n',
            PieceType::Bishop => 'b',
            PieceType::Rook => 'r',
            PieceType::Queen => 'q',
            PieceType::King => 'k',
        }
    }
}

/// A colored piece, e.g. a white knight.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
pub struct Piece {
    pub color: Color,
    pub kind: PieceType,
}

impl Piece {
    #[inline]
    pub const fn new(color: Color, kind: PieceType) -> Piece {
        Piece { color, kind }
    }

    /// FEN letter: uppercase for white, lowercase for black.
    pub const fn to_fen_char(self) -> char {
        let c = self.kind.to_char();
        match self.color {
            Color::White => c.to_ascii_uppercase(),
            Color::Black => c,
        }
    }

    /// Parse a FEN piece letter, e.g. `'N'` -> white knight.
    pub fn from_fen_char(c: char) -> Option<Piece> {
        let color = if c.is_ascii_uppercase() {
            Color::White
        } else {
            Color::Black
        };
        let kind = match c.to_ascii_lowercase() {
            'p' => PieceType::Pawn,
            'n' => PieceType::Knight,
            'b' => PieceType::Bishop,
            'r' => PieceType::Rook,
            'q' => PieceType::Queen,
            'k' => PieceType::King,
            _ => return None,
        };
        Some(Piece::new(color, kind))
    }
}

/// A board square, `0..64` in LERF order.
///
/// Stored as a `u8` but always in range; construct via [`Square::new`] or the
/// file/rank helpers so the invariant holds.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash, PartialOrd, Ord)]
pub struct Square(u8);

impl Square {
    /// Create a square from a raw index. Returns `None` if `index >= 64`.
    #[inline]
    pub const fn new(index: u8) -> Option<Square> {
        if index < 64 {
            Some(Square(index))
        } else {
            None
        }
    }

    /// Create a square from a raw index without bounds checking.
    ///
    /// # Safety contract
    /// `index` must be `< 64`. This is a logic precondition, not memory safety,
    /// but violating it produces nonsense board state.
    #[inline]
    pub const fn from_index(index: u8) -> Square {
        debug_assert!(index < 64);
        Square(index)
    }

    /// Build from file (`0..8`, a–h) and rank (`0..8`, 1–8).
    #[inline]
    pub const fn from_file_rank(file: u8, rank: u8) -> Square {
        debug_assert!(file < 8 && rank < 8);
        Square(rank * 8 + file)
    }

    #[inline]
    pub const fn index(self) -> u8 {
        self.0
    }

    #[inline]
    pub const fn file(self) -> u8 {
        self.0 & 7
    }

    #[inline]
    pub const fn rank(self) -> u8 {
        self.0 >> 3
    }

    /// Parse algebraic coordinates like `"e4"`.
    pub fn from_algebraic(s: &str) -> Option<Square> {
        let bytes = s.as_bytes();
        if bytes.len() != 2 {
            return None;
        }
        let file = bytes[0].checked_sub(b'a')?;
        let rank = bytes[1].checked_sub(b'1')?;
        if file < 8 && rank < 8 {
            Some(Square::from_file_rank(file, rank))
        } else {
            None
        }
    }

    /// Render as algebraic coordinates, e.g. `"e4"`.
    pub fn to_algebraic(self) -> String {
        let file = (b'a' + self.file()) as char;
        let rank = (b'1' + self.rank()) as char;
        format!("{file}{rank}")
    }
}

impl std::fmt::Display for Square {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.to_algebraic())
    }
}
