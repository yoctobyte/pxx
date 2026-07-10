# nilsh — the portable-userland shell (NilPy)

Phase 1 of [feature-demo-portable-userland]: a busybox-style applet shell in
Nil-Python — one binary, commands are built-in applet functions dispatched by
name, no fork/exec, so the same source can run as a Linux process, Linux PID 1,
or an ESP32/FreeRTOS task set (swap the PAL backend, not the app).

## Status: BLOCKED (deliberately committed non-compiling)

`shell0.npy` is the phase-0 skeleton: tokenizer → dispatch → applets
(`echo wc upper rev help`) over a canned session. It is idiomatic NilPy with no
workarounds, and it does not compile today — writing it was the point: phase 1's
job is to surface the NilPy frontend gaps with concrete programs. Found so far
(2026-07-10):

- **bug-nilpy-str-param-length-index** (Track A, hard blocker): a `str`
  parameter isn't a working string inside a function — `Length(param)` returns
  garbage, `param[i]` segfaults, and the tokenizer loop trips an
  `Unsupported linear node in IR codegen` ICE.
- **feature-nilpy-collections-and-string-methods** (Track A, pre-existing):
  no `list`/`dict`/`split` — hence the fixed-token `tok(line, n)` helper and
  the canned session.
- No stdin read surface yet (`input()`/readline) — interactive loop needs it,
  or a `PalRead`→str marshalling story (raw `PalRead` imports fine, but there
  is no bytes→str path).
- `import sysutils` fails with "array of const requires the builtinheap unit"
  (probably the str-param bug's sibling; re-check after that fix).
- NilPy string indexing is 1-based (`"hello"[1] = 'h'`) — Pascal semantics
  leaking through; decide dialect policy before the shell relies on it.

When the blocker ticket lands, `shell0.npy` should compile unchanged and print
the canned session; then phase 1 continues (stdin loop, more applets, pipes).
