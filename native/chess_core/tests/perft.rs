//! Perft regression tests against the published reference node counts.
//!
//! These positions and numbers are the chess-programming community's standard
//! move-generation test suite (see the Chess Programming Wiki "Perft Results").
//! If any count is off, the move generator has a bug — a missed move, an
//! illegal move allowed, or a botched en passant / castling / promotion.
//!
//! The fast set (under ~200k nodes each) runs with `cargo test`. The deeper
//! checks are `#[ignore]`d; run them with `cargo test --release -- --ignored`.

use chess_core::{perft, Board};

fn check(fen: &str, depth: u32, expected: u64) {
    let board = Board::from_fen(fen).expect("test FEN should parse");
    let nodes = perft(&board, depth);
    assert_eq!(
        nodes, expected,
        "perft({depth}) for `{fen}` was {nodes}, expected {expected}",
    );
}

const STARTPOS: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
const KIWIPETE: &str = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
const POS3: &str = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1";
const POS4: &str = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1";
const POS5: &str = "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8";
const POS6: &str = "r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10";

#[test]
fn startpos_shallow() {
    check(STARTPOS, 1, 20);
    check(STARTPOS, 2, 400);
    check(STARTPOS, 3, 8902);
    check(STARTPOS, 4, 197281);
}

#[test]
fn kiwipete_shallow() {
    // Castling, pins, and en passant all in play — the classic bug-finder.
    check(KIWIPETE, 1, 48);
    check(KIWIPETE, 2, 2039);
    check(KIWIPETE, 3, 97862);
}

#[test]
fn position3_shallow() {
    // Sparse position rich in pawn pushes and rook checks.
    check(POS3, 1, 14);
    check(POS3, 2, 191);
    check(POS3, 3, 2812);
    check(POS3, 4, 43238);
}

#[test]
fn position4_shallow() {
    // Promotions and an awkward pinned mess.
    check(POS4, 1, 6);
    check(POS4, 2, 264);
    check(POS4, 3, 9467);
}

#[test]
fn position5_shallow() {
    check(POS5, 1, 44);
    check(POS5, 2, 1486);
    check(POS5, 3, 62379);
}

#[test]
fn position6_shallow() {
    check(POS6, 1, 46);
    check(POS6, 2, 2079);
    check(POS6, 3, 89890);
}

// --- Deeper checks: slower, run explicitly with --release -- --ignored ------

#[test]
#[ignore = "slow; run with --release"]
fn startpos_deep() {
    check(STARTPOS, 5, 4865609);
    check(STARTPOS, 6, 119060324);
}

#[test]
#[ignore = "slow; run with --release"]
fn kiwipete_deep() {
    check(KIWIPETE, 4, 4085603);
}

#[test]
#[ignore = "slow; run with --release"]
fn position3_deep() {
    check(POS3, 5, 674624);
    check(POS3, 6, 11030083);
}
