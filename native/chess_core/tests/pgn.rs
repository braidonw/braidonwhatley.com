//! PGN parsing tests: headers, comments, move numbers, multiple games, and
//! that the replayed moves round-trip back to the same SAN.

use chess_core::{parse_pgn, san, Board};

const SCHOLARS_MATE: &str = r#"[Event "Casual Game"]
[Site "?"]
[White "Alice"]
[Black "Bob"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0
"#;

#[test]
fn parses_headers_moves_and_result() {
    let games = parse_pgn(SCHOLARS_MATE).expect("should parse");
    assert_eq!(games.len(), 1);
    let game = &games[0];
    assert_eq!(game.white(), "Alice");
    assert_eq!(game.black(), "Bob");
    assert_eq!(game.result, "1-0");
    assert_eq!(game.moves.len(), 7);
}

#[test]
fn replayed_moves_round_trip_to_san() {
    let game = &parse_pgn(SCHOLARS_MATE).unwrap()[0];
    let mut board = Board::starting_position();
    let mut sans = Vec::new();
    for &mv in &game.moves {
        sans.push(san(&board, mv));
        board.make_move(mv);
    }
    assert_eq!(sans, ["e4", "e5", "Bc4", "Nc6", "Qh5", "Nf6", "Qxf7#"]);
}

#[test]
fn skips_clock_comments_and_unspaced_move_numbers() {
    // Chess.com-style export: inline {[%clk ...]} comments, and a dialect with
    // move numbers stuck to the move ("1.e4").
    let pgn = r#"[White "X"]
[Black "Y"]
[Result "1/2-1/2"]

1.e4 {[%clk 0:03:00]} e5 {[%clk 0:02:58]} 2.Nf3 Nc6 1/2-1/2
"#;
    let game = &parse_pgn(pgn).unwrap()[0];
    assert_eq!(game.result, "1/2-1/2");
    assert_eq!(game.moves.len(), 4);
}

#[test]
fn parses_multiple_games_in_one_file() {
    let two = format!("{SCHOLARS_MATE}\n{SCHOLARS_MATE}");
    let games = parse_pgn(&two).expect("should parse both");
    assert_eq!(games.len(), 2);
    assert_eq!(games[1].moves.len(), 7);
}

#[test]
fn skips_variations_and_nags() {
    let pgn = r#"[Result "*"]

1. e4 e5 2. Nf3 (2. Bc4 Bc5) 2... Nc6 $1 3. Bb5 *
"#;
    let game = &parse_pgn(pgn).unwrap()[0];
    // The variation (2. Bc4 Bc5) and the $1 NAG are ignored; mainline is 5 plies.
    assert_eq!(game.moves.len(), 5);
}
