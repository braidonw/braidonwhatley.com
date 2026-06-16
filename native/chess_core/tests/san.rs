//! SAN notation tests covering the context-sensitive cases: captures,
//! disambiguation, promotion, castling, en passant, check, and mate.

use chess_core::{legal_moves, san, Board};

/// Find the legal move matching a UCI string and render its SAN.
fn san_of(fen: &str, uci: &str) -> String {
    let board = Board::from_fen(fen).expect("test FEN should parse");
    let mv = legal_moves(&board)
        .into_iter()
        .find(|m| m.to_uci() == uci)
        .unwrap_or_else(|| panic!("{uci} is not legal in {fen}"));
    san(&board, mv)
}

const STARTPOS: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

#[test]
fn simple_pawn_and_piece_moves() {
    assert_eq!(san_of(STARTPOS, "e2e4"), "e4");
    assert_eq!(san_of(STARTPOS, "g1f3"), "Nf3");
}

#[test]
fn pawn_capture_names_origin_file() {
    // White e4 pawn takes a black d5 pawn.
    let fen = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2";
    assert_eq!(san_of(fen, "e4d5"), "exd5");
}

#[test]
fn en_passant_capture() {
    // White e5 pawn captures the just-moved black d-pawn en passant.
    let fen = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3";
    assert_eq!(san_of(fen, "e5d6"), "exd6");
}

#[test]
fn castling_uses_o_notation() {
    let fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1";
    assert_eq!(san_of(fen, "e1g1"), "O-O");
    assert_eq!(san_of(fen, "e1c1"), "O-O-O");
}

#[test]
fn promotion_with_equals() {
    // Kings tucked in corners so the promotion gives no check.
    let fen = "8/4P3/8/8/8/8/8/k6K w - - 0 1";
    assert_eq!(san_of(fen, "e7e8q"), "e8=Q");
    assert_eq!(san_of(fen, "e7e8n"), "e8=N");
}

#[test]
fn knight_disambiguation_by_file() {
    // Knights on a1 and e1 can both reach c2; SAN names the origin file.
    let fen = "7k/8/8/8/8/8/8/N3N1K1 w - - 0 1";
    assert_eq!(san_of(fen, "a1c2"), "Nac2");
    assert_eq!(san_of(fen, "e1c2"), "Nec2");
}

#[test]
fn check_and_mate_suffixes() {
    // Scholar's-mate position: Qxf7 is checkmate.
    let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5Q2/PPPP1PPP/RNB1K1NR w KQkq - 0 1";
    assert_eq!(san_of(fen, "f3f7"), "Qxf7#");

    // A rook check that is not mate: Rh8+ along the 8th rank.
    let fen2 = "4k3/8/8/8/8/8/8/K6R w - - 0 1";
    assert_eq!(san_of(fen2, "h1h8"), "Rh8+");
}
