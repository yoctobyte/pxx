---
slug: bug-a-hand-written-literal-short-jumps-span-emitters-that-can-grow
title: "Hand-written literal short jumps span emitters that can grow, and land mid-sequence when they do"
track: A
prio: 70
type: bug
status: working
created: 2026-09-01
found-by: frankA
owner: frankA
blocked-by: []
summary: "Short jumps in the backends carry a hand-counted literal displacement over a span emitted by other code; when that span changes size the jump stays IN RANGE and lands mid-sequence, so nothing errors. THREE converted so far and TWO of them were ALREADY WRONG on master, both silent wrong values on x86-64: `Write(s:w)` on a ShortString with w <= Length(s) printed a truncated string (`WriteLn(s:2)` for 'abcdef' printed nothing; FPC prints abcdef), and LoadFile into a ShortString returned an EMPTY string for every successful read. Both jumps overshot by exactly 8 bytes. Fixed with PatchRel8, tests test_write_shortstring_field_width_narrower and test_loadfile_shortstring (both verified to FAIL on the pre-fix binary). The third site (the x86-64 clone stub) was byte-identical. ~41 literal sites remain; the census is NOT ~25 -- that number and an earlier 142 both came from a grep that matches ModRM and second opcode bytes. CheckRel8 covers the 172 computed sites and hard-errors, so the OVERFLOW class cannot ship; this is the other class and no instrument sees it."
---

# A literal displacement is a claim about code someone else emits

Two failure classes, and only one of them is guarded.

- **Too large.** `CheckRel8` hard-errors, 172 sites go through it, and
  [[feature-t-track-the-rel8-displacement-budget-so-a-tight-jump-is-visible-before-it-breaks]]
  warns before it happens. Cannot ship.
- **In range, wrong target.** The span between the jump and its intended
  landing place grew, the displacement is still a legal rel8, and it now points
  into the middle of an instruction sequence. Assembles, links, runs, and
  corrupts. Nothing measures it.

The second one is not hypothetical: it happened, in the shape most likely to
recur — a hand-counted jump over a global store, and `--emit-obj` on i386 later
wrapped every global store in `push`/anchor/`lea`/`pop` to make it position
independent. The wrapper is correct, the store is correct, and the jump that
had counted the old bytes landed on the wrapper's `pop`. It took a
disassembly assertion to see, because no symbol, relocation or size number
moves.

## The job

Enumerate the literal short jumps — frankC's census puts them at roughly 25,
against 172 computed — and convert each to `EmitRel8`/`PatchRel8`, which
computes the displacement from the actual emitted positions and range-checks
it. Enumerate from the EMITTED artifact where possible rather than by grepping
one spelling of the byte-emitting idiom.

The unlock-stub fix also deleted a "this block must be exactly 16 bytes"
assertion, which was the same claim in comment form: a hand-counted constant
standing in for what an emitter will produce. Any sibling assertion of that
shape belongs in this sweep.

## Why it is worth doing rather than watching

A budget row is blind to this class by construction, so the remedy is
structural: make the displacement computed everywhere and the class stops
existing. Until then each one is a correctness bug waiting for an unrelated
emitter to grow — and the growth is normal work, done by someone who has no
reason to look for a jump that spans their edit.

## Measured 2026-09-01 — the first three conversions, two live bugs

Method: build the control artefacts with the compiler at the tree BEFORE the
change, convert, rebuild, byte-compare. Since every displacement is supposed to
be correct today, the expected result is byte-identity and **any differing byte
is a bug that was shipping**. Two of the three differed.

| site | before | after | verdict |
| --- | --- | --- | --- |
| `ir_codegen.inc` string-width pad (`jle`) | 35 | 27 | **8 bytes past the target** |
| `symtab.inc` `EmitLoadFile` clamp (`jns`) | 10 | 2 | **8 bytes past the target** |
| `thread_emit.inc` x86-64 clone stub (`jnz`) | 30 | 30 | correct, byte-identical |

Both overshoots land inside the *next* emitter rather than off the end, which is
why they corrupt a value instead of crashing:

- `WriteLn(s:2, '|')` for `s = 'abcdef'` printed `|`, and `WriteLn(s:6, '|')`
  printed `a|`. FPC prints `abcdef|` for both — a field width is a MINIMUM and
  never truncates. The jump landed 8 bytes into `EmitwriteStrVar`, so the write
  went out with a wrong length; what came out depended on the surrounding call
  shape, which is why the rows differ from each other.
- `LoadFile(p, s)` into a ShortString reported `Length(s) = 0` for a 21-byte
  file. `jns` is taken on every SUCCESSFUL read, so the 8 bytes it also skipped
  — the start of `EmitStoreStrLen` — meant no LoadFile into a ShortString has
  ever stored a length.

**Neither had a test, and both had a near-miss.** `test_write_char_field_width`
carries a row written for exactly this question (`s:1`, "narrower than the
value: no truncation") and it passed, because `var s: string` is an ANSISTRING
here and the AnsiString arm forty lines below already computed its displacement.
`test_loadfile_into_element_and_field` and `test_cross_loadfile` both declare
AnsiString destinations, which route to `EmitLoadFileManaged` — a different
emitter. Both are the double-case shape from `normalise-dont-special-case.md`,
with the fix in one arm.

`MovRaxImm(0)` emitting two bytes (`xor eax,eax`) rather than ten is the change
that broke the LoadFile site, and it is exactly the "normal work by someone with
no reason to look for a jump spanning their edit" this ticket predicts.

## The census is not ~25, and not 142

Both numbers came from the same broken instrument. `EmitB($7x); EmitB(...)`
matches ModRM bytes and the second byte of two-byte opcodes:
`EmitB($0F); EmitB($7E); EmitB($C0)` is `movq rax, xmm0`, and
`EmitB($4C); EmitB($89); EmitB($77); EmitB($20)` is `mov [rdi+32], r14`. Neither
is a jump. A filter that reads the trailing `{ mnemonic }` comment instead finds
**36 `jcc` sites + 8 `$EB` short-jmp sites**, and that instrument can only
UNDERCOUNT — it misses any site whose comment does not name the mnemonic. Three
are now converted; treat ~41 as a floor, not a count.

Enumerating from the emitted artifact, as the job section says, is still the
right instrument and has not been built.

## Not in scope, found on the way

`--target=i386` ignores a field width on strings entirely: `WriteLn(s:9)` for
`s = 'abcdef'` prints `abcdef` where x86-64 and FPC print `   abcdef`. Verified
pre-existing (the i386 artefacts are byte-identical across this change), so it
is a separate defect and not a regression here.
