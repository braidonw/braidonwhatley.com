# Vendored: `chess-core`

This crate is a pinned copy of the `chess-core` crate from Braidon's chess
engine project.

- **Source:** `~/developer/chess` — `crates/chess-core`
- **Commit:** `13f72cb780a6b88898d0de32d8f06483fa622bd0`
  (`13f72cb Set control-bar buttons to 30px tall with 12px text`)
- **Why vendored:** the upstream repo has no git remote, so the Phoenix build
  (including Docker) can't pull it via a git dependency. A pinned copy keeps the
  build self-contained.

## Local change vs upstream

`Cargo.toml` no longer inherits `edition`/`license` from a workspace root
(the upstream is a workspace member; this copy stands alone):

```toml
edition = "2021"
license = "MIT OR Apache-2.0"
```

The Rust source under `src/` is otherwise unmodified.

## Refreshing

To pull a newer upstream version, re-copy `src/` and re-apply the `Cargo.toml`
edit above, then bump the commit hash here. Consumed only by
`native/chess_nif`, which is exercised by `test/braidonwhatley/chess_test.exs`
and `cargo test` in this crate.
