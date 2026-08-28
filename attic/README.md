# Attic

Superseded work, kept because this directory is not a git repository and there
is no undo. Nothing here is read by a session and nothing depends on it.

- `tunnel.lua`, `test_tunnel.lua`, `tunnel.state` — the earlier working mining
  program, from before the claim design. Phase 2 of `quarry.lua` copied its
  `clear`/`step` shape and its deny-list handling; that is the whole of its
  remaining value. Moved here 2026-08-28.

`cloudcat.py` was deliberately NOT moved: it is a headless cloud-catcher client
that can push a file straight to an in-game computer, which would remove the
paste.rs round trip entirely if the user has cloud-catcher running. Unused so
far, but not superseded.
