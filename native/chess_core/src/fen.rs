//! Forsyth–Edwards Notation: the standard text encoding of a position.
//!
//! Example (the start position):
//! `rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1`
//!
//! The six space-separated fields are: piece placement (rank 8 first),
//! side to move, castling rights, en-passant target, halfmove clock, and
//! fullmove number.

use crate::board::{Board, CastlingRights};
use crate::types::{Color, Piece, Square};

/// Why a FEN string couldn't be parsed.
#[derive(Debug, PartialEq, Eq)]
pub enum FenError {
    /// Fewer than the required fields were present.
    MissingField(&'static str),
    /// The placement field didn't describe exactly 8 ranks of 8 files.
    BadPlacement(String),
    /// A field held a value outside its allowed set.
    BadField(&'static str, String),
}

impl std::fmt::Display for FenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            FenError::MissingField(name) => write!(f, "FEN missing the {name} field"),
            FenError::BadPlacement(s) => write!(f, "FEN piece placement invalid: {s}"),
            FenError::BadField(name, s) => write!(f, "FEN {name} field invalid: {s}"),
        }
    }
}

impl std::error::Error for FenError {}

impl Board {
    /// Parse a full FEN string into a board.
    pub fn from_fen(fen: &str) -> Result<Board, FenError> {
        let mut fields = fen.split_whitespace();
        let placement = fields.next().ok_or(FenError::MissingField("placement"))?;
        let side = fields.next().ok_or(FenError::MissingField("side to move"))?;
        let castling = fields.next().ok_or(FenError::MissingField("castling"))?;
        let en_passant = fields.next().ok_or(FenError::MissingField("en passant"))?;
        // The clock fields are optional in some FEN dialects; default them.
        let halfmove = fields.next().unwrap_or("0");
        let fullmove = fields.next().unwrap_or("1");

        let mut board = Board::empty();
        parse_placement(&mut board, placement)?;

        board.side_to_move = match side {
            "w" => Color::White,
            "b" => Color::Black,
            other => return Err(FenError::BadField("side to move", other.to_string())),
        };

        board.castling = parse_castling(castling)?;

        board.en_passant = if en_passant == "-" {
            None
        } else {
            Some(
                Square::from_algebraic(en_passant)
                    .ok_or_else(|| FenError::BadField("en passant", en_passant.to_string()))?,
            )
        };

        board.halfmove_clock = halfmove
            .parse()
            .map_err(|_| FenError::BadField("halfmove clock", halfmove.to_string()))?;
        board.fullmove_number = fullmove
            .parse()
            .map_err(|_| FenError::BadField("fullmove number", fullmove.to_string()))?;

        Ok(board)
    }

    /// Render this board as a FEN string.
    pub fn to_fen(&self) -> String {
        let mut fen = String::new();

        // Placement: rank 8 down to rank 1, runs of empties collapsed to a digit.
        for rank in (0..8).rev() {
            let mut empties = 0;
            for file in 0..8 {
                let sq = Square::from_file_rank(file, rank);
                match self.piece_at(sq) {
                    Some(piece) => {
                        if empties > 0 {
                            fen.push(char::from_digit(empties, 10).unwrap());
                            empties = 0;
                        }
                        fen.push(piece.to_fen_char());
                    }
                    None => empties += 1,
                }
            }
            if empties > 0 {
                fen.push(char::from_digit(empties, 10).unwrap());
            }
            if rank > 0 {
                fen.push('/');
            }
        }

        fen.push(' ');
        fen.push(match self.side_to_move {
            Color::White => 'w',
            Color::Black => 'b',
        });

        fen.push(' ');
        fen.push_str(&format_castling(self.castling));

        fen.push(' ');
        match self.en_passant {
            Some(sq) => fen.push_str(&sq.to_algebraic()),
            None => fen.push('-'),
        }

        fen.push_str(&format!(" {} {}", self.halfmove_clock, self.fullmove_number));
        fen
    }
}

/// Fill the board from the placement field (rank 8 first, '/'-separated).
fn parse_placement(board: &mut Board, placement: &str) -> Result<(), FenError> {
    let ranks: Vec<&str> = placement.split('/').collect();
    if ranks.len() != 8 {
        return Err(FenError::BadPlacement(placement.to_string()));
    }

    for (i, rank_str) in ranks.iter().enumerate() {
        // The first substring is rank 8, so count ranks down from 7.
        let rank = 7 - i as u8;
        let mut file = 0u8;
        for c in rank_str.chars() {
            if let Some(skip) = c.to_digit(10) {
                file += skip as u8;
            } else {
                let piece = Piece::from_fen_char(c)
                    .ok_or_else(|| FenError::BadPlacement(placement.to_string()))?;
                if file >= 8 {
                    return Err(FenError::BadPlacement(placement.to_string()));
                }
                board.put_piece(Square::from_file_rank(file, rank), piece);
                file += 1;
            }
        }
        if file != 8 {
            return Err(FenError::BadPlacement(placement.to_string()));
        }
    }
    Ok(())
}

fn parse_castling(field: &str) -> Result<CastlingRights, FenError> {
    let mut rights = CastlingRights::empty();
    if field == "-" {
        return Ok(rights);
    }
    for c in field.chars() {
        match c {
            'K' => rights.add(CastlingRights::WHITE_KING),
            'Q' => rights.add(CastlingRights::WHITE_QUEEN),
            'k' => rights.add(CastlingRights::BLACK_KING),
            'q' => rights.add(CastlingRights::BLACK_QUEEN),
            _ => return Err(FenError::BadField("castling", field.to_string())),
        }
    }
    Ok(rights)
}

fn format_castling(rights: CastlingRights) -> String {
    if rights.raw() == 0 {
        return "-".to_string();
    }
    let mut s = String::new();
    if rights.has(CastlingRights::WHITE_KING) {
        s.push('K');
    }
    if rights.has(CastlingRights::WHITE_QUEEN) {
        s.push('Q');
    }
    if rights.has(CastlingRights::BLACK_KING) {
        s.push('k');
    }
    if rights.has(CastlingRights::BLACK_QUEEN) {
        s.push('q');
    }
    s
}
