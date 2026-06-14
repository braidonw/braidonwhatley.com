//! PGN parsing — reading recorded games into positions we can replay.
//!
//! A PGN file is a sequence of games, each a block of `[Key "Value"]` headers
//! followed by movetext: move numbers, SAN moves, `{comments}`, `$NAG`
//! annotations, optional `(variations)`, and a result token. We keep the
//! mainline moves and the headers, and ignore the rest.
//!
//! Moves are resolved by matching each SAN token against the legal moves of the
//! current position (reusing [`crate::san`]), so the same generator validates
//! both directions — anything that doesn't match a legal move is a parse error,
//! not a silently dropped move.

use crate::board::Board;
use crate::movegen::legal_moves;
use crate::moves::Move;

/// A single parsed game: its headers, the mainline moves, and the result token.
pub struct PgnGame {
    pub headers: Vec<(String, String)>,
    pub moves: Vec<Move>,
    /// Result token: `"1-0"`, `"0-1"`, `"1/2-1/2"`, or `"*"` (unknown/ongoing).
    pub result: String,
}

impl PgnGame {
    /// Look up a header value by key (case-sensitive, as PGN keys are).
    pub fn header(&self, key: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
    }

    pub fn white(&self) -> &str {
        self.header("White").unwrap_or("?")
    }

    pub fn black(&self) -> &str {
        self.header("Black").unwrap_or("?")
    }

    /// The starting position for this game (a `FEN` header if present, else the
    /// standard initial position).
    pub fn start_position(&self) -> Result<Board, PgnError> {
        match self.header("FEN") {
            Some(fen) => Board::from_fen(fen).map_err(|e| PgnError::Setup(e.to_string())),
            None => Ok(Board::starting_position()),
        }
    }
}

/// Why a PGN couldn't be parsed.
#[derive(Debug, PartialEq, Eq)]
pub enum PgnError {
    /// A malformed `[Key "Value"]` header line.
    Header(String),
    /// A `FEN` setup header that didn't parse.
    Setup(String),
    /// A move token that matched no legal move in the current position.
    IllegalMove { move_number: usize, token: String },
}

impl std::fmt::Display for PgnError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            PgnError::Header(s) => write!(f, "malformed PGN header: {s}"),
            PgnError::Setup(s) => write!(f, "invalid FEN setup header: {s}"),
            PgnError::IllegalMove { move_number, token } => {
                write!(f, "illegal/unrecognized move `{token}` near move {move_number}")
            }
        }
    }
}

impl std::error::Error for PgnError {}

/// Parse every game in a PGN string.
pub fn parse_pgn(text: &str) -> Result<Vec<PgnGame>, PgnError> {
    let mut scanner = Scanner::new(text);
    let mut games = Vec::new();

    loop {
        scanner.skip_whitespace();
        if scanner.at_end() {
            break;
        }
        let headers = scanner.parse_headers()?;
        let game = scanner.parse_movetext(headers)?;
        // A trailing chunk with neither headers nor moves means we're done.
        if game.headers.is_empty() && game.moves.is_empty() {
            break;
        }
        games.push(game);
    }
    Ok(games)
}

/// A byte cursor over the PGN text.
struct Scanner<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl<'a> Scanner<'a> {
    fn new(text: &'a str) -> Scanner<'a> {
        Scanner {
            bytes: text.as_bytes(),
            pos: 0,
        }
    }

    fn at_end(&self) -> bool {
        self.pos >= self.bytes.len()
    }

    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.pos).copied()
    }

    fn bump(&mut self) -> Option<u8> {
        let b = self.peek();
        if b.is_some() {
            self.pos += 1;
        }
        b
    }

    fn skip_whitespace(&mut self) {
        while matches!(self.peek(), Some(b) if b.is_ascii_whitespace()) {
            self.pos += 1;
        }
    }

    /// Read consecutive `[Key "Value"]` header lines.
    fn parse_headers(&mut self) -> Result<Vec<(String, String)>, PgnError> {
        let mut headers = Vec::new();
        loop {
            self.skip_whitespace();
            if self.peek() != Some(b'[') {
                break;
            }
            self.bump(); // consume '['

            // Key: up to the first space.
            let key_start = self.pos;
            while matches!(self.peek(), Some(b) if b != b' ' && b != b'"' && b != b']') {
                self.pos += 1;
            }
            let key = self.slice(key_start, self.pos);
            self.skip_whitespace();

            // Value: a quoted string.
            if self.peek() != Some(b'"') {
                return Err(PgnError::Header(format!("{key} (missing quoted value)")));
            }
            self.bump(); // opening quote
            let value_start = self.pos;
            while matches!(self.peek(), Some(b) if b != b'"') {
                self.pos += 1;
            }
            let value = self.slice(value_start, self.pos);
            self.bump(); // closing quote

            // Consume up to and including the closing ']'.
            while matches!(self.peek(), Some(b) if b != b']') {
                self.pos += 1;
            }
            self.bump();

            headers.push((key, value));
        }
        Ok(headers)
    }

    /// Read movetext for one game, replaying moves onto a board.
    fn parse_movetext(&mut self, headers: Vec<(String, String)>) -> Result<PgnGame, PgnError> {
        let mut game = PgnGame {
            headers,
            moves: Vec::new(),
            result: "*".to_string(),
        };
        let mut board = game.start_position()?;

        loop {
            self.skip_whitespace();
            match self.peek() {
                None => break,
                Some(b'[') => break, // next game's headers
                Some(b'{') => self.skip_comment(),
                Some(b'(') => self.skip_variation(),
                Some(b'$') => self.skip_token(), // NAG like $1
                Some(_) => {
                    let token = self.read_token();
                    if let Some(result) = result_token(&token) {
                        game.result = result.to_string();
                        break;
                    }
                    // Strip a leading move number ("12." / "12...") if present.
                    let san_token = token.trim_start_matches(|c: char| c.is_ascii_digit() || c == '.');
                    if san_token.is_empty() {
                        continue; // bare move number
                    }
                    let Some(mv) = resolve_san(&board, san_token) else {
                        return Err(PgnError::IllegalMove {
                            move_number: board.fullmove_number as usize,
                            token: san_token.to_string(),
                        });
                    };
                    board.make_move(mv);
                    game.moves.push(mv);
                }
            }
        }
        Ok(game)
    }

    fn slice(&self, start: usize, end: usize) -> String {
        String::from_utf8_lossy(&self.bytes[start..end]).into_owned()
    }

    /// Read a whitespace-delimited token.
    fn read_token(&mut self) -> String {
        let start = self.pos;
        while matches!(self.peek(), Some(b) if !b.is_ascii_whitespace()) {
            self.pos += 1;
        }
        self.slice(start, self.pos)
    }

    fn skip_token(&mut self) {
        let _ = self.read_token();
    }

    /// Skip a `{ ... }` comment.
    fn skip_comment(&mut self) {
        while let Some(b) = self.bump() {
            if b == b'}' {
                break;
            }
        }
    }

    /// Skip a `( ... )` variation, including any nested comments/variations.
    fn skip_variation(&mut self) {
        let mut depth = 0;
        while let Some(b) = self.bump() {
            match b {
                b'(' => depth += 1,
                b')' => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                b'{' => self.skip_comment(),
                _ => {}
            }
        }
    }
}

/// Match a SAN token to a legal move by generating SAN for each candidate.
fn resolve_san(board: &Board, token: &str) -> Option<Move> {
    let want = normalize_san(token);
    legal_moves(board)
        .into_iter()
        .find(|&mv| normalize_san(&crate::san::san(board, mv)) == want)
}

/// Canonicalize SAN for comparison: drop check/annotation marks and treat the
/// digit `0` as the letter `O` (so `0-0` matches `O-O`).
fn normalize_san(s: &str) -> String {
    s.chars()
        .filter(|c| !matches!(c, '+' | '#' | '!' | '?'))
        .map(|c| if c == '0' { 'O' } else { c })
        .collect()
}

fn result_token(token: &str) -> Option<&'static str> {
    match token {
        "1-0" => Some("1-0"),
        "0-1" => Some("0-1"),
        "1/2-1/2" => Some("1/2-1/2"),
        "*" => Some("*"),
        _ => None,
    }
}
