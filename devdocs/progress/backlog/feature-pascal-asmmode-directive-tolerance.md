---
prio: 50
---

# Accept `{$asmMode default}` (and other non-intel asmmode values)

- **Type:** feature (Pascal frontend — Track P; directive lives in the shared
  lexer = A gate applies)
- **Status:** backlog — unclaimed
- **Opened:** 2026-07-18, out of the FPC-compiler gap analysis
- **Blocks:** [[goal-compile-fpc-compiler]] (rainy-day lighthouse) — this is
  literally the first wall: `cutils.pas:26` opens with `{$asmMode default}`
  and every FPC compiler unit follows the same pattern.

## Problem

pxx only accepts `{$asmMode intel}`; any other value is a hard error. FPC
accepts `default`, `att`, `intel`, `direct` and treats the directive as a
per-file assembler-reader selection. Since the affected units contain no
inline asm at all (they just set the mode defensively), rejecting the
directive is pure conformance loss.

## Fix shape

Parse-and-tolerate: accept any known FPC asmmode value. `intel` behaves as
today; other values are recorded and only become an error if an `asm` block
is actually encountered under a mode we can't read (AT&T). One directive
edit in the shared lexer.

## Gate

Track P via shared files: `make test` + self-host byte-identical. Regression:
a unit starting `{$asmMode default}` with no asm body compiles; same unit
with an asm body under `att` gives a clear "AT&T asm not supported" error at
the asm block, not at the directive.
