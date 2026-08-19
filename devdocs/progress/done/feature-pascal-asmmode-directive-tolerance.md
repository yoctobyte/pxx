---
prio: 50
---

# Accept `{$asmMode default}` (and other non-intel asmmode values)

- **Type:** feature (Pascal frontend — Track P; directive lives in the shared
  lexer = A gate applies)
- **Status:** done
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

---

## RESOLVED 2026-08-19 — `frankonpiler-an` (Track A/P, sole-A confirmed)

Parse-and-tolerate, exactly the fix shape this ticket proposed. `{$asmMode}`
now accepts the whole FPC set — `intel`, `default`, `att`, `direct` — and the
refusal moved to where it can be justified: the point an `asm` block actually
arrives under a syntax we cannot read.

```
{$asmMode default}  no asm  -> compiled       (FPC: compiled)
{$asmMode intel}    no asm  -> compiled
{$asmMode att}      no asm  -> compiled
{$asmMode direct}   no asm  -> compiled
{$asmMode bogus}            -> unknown {$asmMode} value (intel, default, att and direct are the FPC set)
{$asmMode att}      + asm   -> {$asmMode att} is accepted, but this asm block cannot be read:
                               inline asm (asm...end) is Intel syntax only
```

Regression: `test/test_asmmode_tolerance.pas`, in `test-core`, differential
against FPC.

**The check lives in the LEXER, not the parser**, and that is the one design
call worth recording. The mode is per-FILE and the directive takes effect at the
point it is scanned; a parser-time global would hold whichever file was lexed
last, so a unit with `{$asmMode att}` and no asm could poison a later unit's asm
block or vice versa. The lexer sees the directive and the `asm` keyword in
source order, which is exactly the ordering the semantics need — so the flag is
set in `ProcessPasDirective` and read where `tkAsm` is produced.

Unblocks the first wall in [[goal-compile-fpc-compiler]]: `cutils.pas:26` opens
with `{$asmMode default}` and every FPC compiler unit follows it. That does not
mean the next wall is far away — it means this one is gone.

Gate: `make compiler/pascal26` fixedpoint + `tools/gate.sh quick`, green.

## Log
- 2026-08-19 — resolved, commit PENDING-COMMIT.
