---
track: A
prio: 45
type: bug
blocked-by: []
summary: "The MAX_IR / MAX_TOKENS / MAX_UFIELD tables were converted to dynamic arrays, but four things derived from those caps were not: two fixed-size local scratch arrays indexed by a now-unbounded count (IRVerify writes past its 256 KB stack local), the MAX_TOKENS-as-infinity sentinel for MainProgramTokCount / DbgMainTokEnd, and two dead MAX_UFIELD guards in cparser one of which silently degrades a C struct to an opaque pointer."
---

# Dynamic tables left their fixed-size shadows behind

- **Type:** bug (compiler core; memory safety at the sharp end)
- **Status:** done
- **Owner:** agent-A
- **Opened:** 2026-08-21
- **Found:** reading [[feature-dynamic-compiler-tables]]'s remaining-work list —
  which is itself stale: the Tokens and Syms families it lists as TODO are
  already converted, and so is UField.

## The shape

`feature-dynamic-compiler-tables` converted the IR, AST, token, symbol and
field pools from `array[0..MAX_X-1]` to `array of T` + `EnsureXCapacity`. The
tables grew correctly. What did not move is everything that had quietly taken
`MAX_X` to mean *"a number the count can never reach"*:

1. **`IRVerify` (`ir.inc`) writes past a fixed-size stack local.**
   ```pascal
   seenLabel: array[0..MAX_IR-1] of Boolean;   { 256 KB stack local }
   ...
   for i := 0 to IRLabelCount - 1 do seenLabel[i] := False;   { UNGUARDED }
   ```
   `IRNewLabel` hands out ids by `Inc(IRLabelCount)` with no cap, and IR nodes
   are dynamic, so a single body with >= 262144 labels smashes the stack. The
   later `lblId >= MAX_IR` check errors *after* that clear loop has run — and it
   tests the wrong bound anyway (`IRLabelCount` is the real one). IRVerify runs
   on **every body** by default (`StrictIR`).
2. **`IRDump` (`ir.inc`)** has the same `array[0..MAX_IR-1] of Boolean` local,
   indexed by IR NODE index this time, and clears all `MAX_IR` entries even when
   the body has ten. Diagnostic path (`--dump-ir`), same overflow when
   `IRCount > MAX_IR`.
3. **`MAX_TOKENS` used as an infinity sentinel.** `MainProgramTokCount :=
   MAX_TOKENS` and `DbgMainTokEnd := MAX_TOKENS` mean "not set yet / no bound",
   and ~150 sites read `i < MainProgramTokCount` as "unbounded". Tokens are now
   dynamic, and sqlite's amalgamation ALREADY hit 2 M tokens — the value that is
   supposed to be unreachable is one large translation unit away. Above it,
   `DbgMainTokEnd` silently marks main-file tokens as belonging to units (wrong
   `-g` line info), and the `= MAX_TOKENS` "still unset" tests can read a real
   count as unset.
4. **Two dead `MAX_UFIELD` guards in `cparser.inc`.** `AddUField` calls
   `EnsureUFieldCapacity`, so the pool grows; but the C struct parser still
   hard-errors at `UFldCount >= MAX_UFIELD - 1` ("raise the cap" — there is no
   cap to raise), and — worse — still treats `UFldCount >= MAX_UFIELD - 128` as
   "record-table headroom low" and **silently degrades the struct to an opaque
   pointer**. A silent layout loss is the failure mode this repo pays most for.

## Why one ticket

They are one bug wearing four hats: *a cap was deleted and its shadows were
left*. Fixing one and not the others leaves the same reasoning error in place —
[[devdocs/dev/normalise-dont-special-case.md]], "if you fix one arm of a double
case, grep for the sibling".

## Fix

- One growable scratch flag array in `defs.inc` (`IRScratchFlag` +
  `EnsureIRScratch`), used by both `IRVerify` and `IRDump`, sized to the real
  bound (`IRLabelCount` / `IRCount`) and cleared only over that range.
- Bounds-check label ids against `IRLabelCount`, not `MAX_IR`.
- A named `TOK_UNBOUNDED` sentinel that a token count cannot reach, replacing
  `MAX_TOKENS` in that role.
- Delete the dead `MAX_UFIELD` error and drop the `UFldCount` term from the
  headroom test (`MAX_UCLASS` stays — `UCls*` really is still fixed).

## Gate

Track A's: `make compiler/pascal26` (byte-identical fixedpoint) + `tools/gate.sh
quick`.

## Fixed 2026-08-21

- `IRScratchFlag` + `EnsureIRScratch` (`defs.inc` / `ir.inc`): one growable
  flag-per-index scratch, doubling from 4096, replacing BOTH 256 KB stack
  locals. Each user clears only the range it reads (`IRLabelCount` in
  `IRVerify`, `IRCount` in `IRDump`); they are never live at once, which the
  declaration states as the contract.
- All five `lblId >= MAX_IR` bounds checks now test `IRLabelCount` — the bound
  the ids actually come from.
- `TOK_UNBOUNDED = 2147483647` replaces `MAX_TOKENS` as the "not set / no
  bound" sentinel for `MainProgramTokCount` and `DbgMainTokEnd`.
- The dead `MAX_UFIELD` hard error is gone, and the `UFldCount` term is out of
  both opaque-pointer headroom tests. `MAX_UCLASS` stays: `UCls*` is still a
  fixed table, so that half of the test is real.

### What was measured, and what could not be

Against a build of the parent commit: 10 Pascal tests and the C canary emit
**byte-identical binaries**, and a 13883-line `--dump-ir` is identical apart
from the output path in its own final `ok:` line. Self-host fixedpoint converges
in one round; `gate.sh quick` green.

**No test reproduces the overflow, and that is worth stating plainly.** Reaching
262144 labels in one body means a body with ~262144 branches, and the recursive
AST/IR tree walk SIGSEGVs at roughly 3500 chained statements — a separate
stack-depth limit noted in [[feature-dynamic-compiler-tables]]. So the front
door is blocked by a different wall today. That is exactly how the shadow
survived the conversion unnoticed, and it is why the fix is a bound rather than
a bigger array: the next person to lift the walker's depth limit should not
inherit a stack smash.

## Log
- 2026-08-21 — resolved, commit PENDING-COMMIT.
