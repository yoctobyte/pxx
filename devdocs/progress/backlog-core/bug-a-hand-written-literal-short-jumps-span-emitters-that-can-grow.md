---
slug: bug-a-hand-written-literal-short-jumps-span-emitters-that-can-grow
title: "Hand-written literal short jumps span emitters that can grow, and land mid-sequence when they do"
track: A
prio: 35
type: bug
status: open
created: 2026-09-01
found-by: frankA
owner: ""
blocked-by: []
summary: "Short jumps in the backends carry a hand-counted literal displacement over a span emitted by other code; when that span changes size the jump stays IN RANGE and lands mid-sequence, so nothing errors. FOUR converted, and TWO were ALREADY WRONG on master -- both silent wrong values on x86-64, fixed at 14bc9d218: `Write(s:w)` on a ShortString with w <= Length(s) truncated (`WriteLn(s:2)` for 'abcdef' printed nothing; FPC prints abcdef), and LoadFile into a ShortString returned an EMPTY string for every successful read. Both overshot by exactly 8 bytes. DROPPED 70 -> 35 because the CLASS is now guarded, not because the sweep is finished: gate row 74ed877f2 (tools/rel8_literal_span_check.py) fails any literal displacement spanning non-fixed-size emission, with the pre-fix tree as its positive control, and all 41 remaining sites span EmitB/EmitI32 only. Remaining work is converting those 41 for uniformity -- preventive, low expected yield, and safe to leave. Census settled at 42 (now 41) by a POSITION rule that agreed with the comment rule 108/108; the earlier 'about 25' and 142 both came from a grep matching ModRM bytes."
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

## The class now has a guard: `tools/rel8_literal_span_check.py`

`gate.sh` runs it in every mode, before the mode `case`, in under a second
(landed 74ed877f2). The rule it enforces is the one the three conversions
measured:

> **A literal displacement may only span emissions of FIXED size.**

Spanning `EmitB`/`EmitI32` is fine — the bytes are on the page and a reader
adding one is looking straight at the count, which is why the clone stub's
hand-counted 30 was correct. Spanning `MovRaxImm`, `EmitSyscall`,
`EmitDataRef`, `EmitGlobRef` or anything else that picks an encoding is not.

**Its positive control is the pre-fix tree**, not a fixture: pointed at
`3f9937e6c` it flags `ir_codegen.inc:8903` and `symtab.inc:6922` and nothing
else — the two sites that were actually wrong, and not the one that was right.
`--selftest` additionally asserts it rejects both shapes it was built from,
accepts a fixed-size span, and does not read a ModRM byte as a jump; the accept
row carries its own anti-vacuity assert, because "not flagged" and "not seen at
all" print the same.

Current tree: 42 literal short jumps, every span fixed-size. That is a floor on
future damage, not a claim the 42 are converted — a fixed-size span is correct
until someone inserts a line into it, and the checker will then say so.

## The census is 42, and the discriminator is POSITION, not the comment

"About 25" and an earlier 142 came from the same broken instrument.
`EmitB($7x); EmitB(...)` matches ModRM and SIB bytes and the second byte of
two-byte opcodes: `EmitB($0F); EmitB($7E); EmitB($C0)` is `movq rax, xmm0`, and
`EmitB($4C); EmitB($89); EmitB($77); EmitB($20)` is `mov [rdi+32], r14`. Neither
is a jump, and the naive shape reports ~131 sites of which two thirds are not.

The comment-mnemonic filter (36 `jcc` + 8 `$EB`) was better but still an
undercount, because **23 sites carry no comment at all** and it cannot classify
those. The instrument that settles it is POSITION: these files emit one
instruction per line, so a jump opcode is the FIRST byte emitted on its line and
a ModRM or immediate byte never is.

**Checked against the comment rule over the whole commented population:
108 sites, 108 agreements, 0 disagreements.** The two rules can fail
differently — one reads prose, one reads structure — so the agreement is
corroboration rather than one measurement taken twice. The position rule then
classifies the 23 the comment rule could not: **9 are real jumps, 14 are ModRM
contamination**, including `EmitB($48); EmitB($8D); EmitB($7C); EmitB($24);`
(`lea rdi, [rsp+n]`), which the risk scan had promoted to a suspected third bug
before it was decoded.

**42 literal short jumps** on the tree at `14bc9d218`, in six files
(`ir_codegen386.inc` 21, `ir_codegen.inc` 16, `cparser.inc` 2,
`pasparser_lval.inc` 1, `symtab.inc` 1, `thread_emit.inc` 1). The count is
self-consistent across the change: the pre-fix tree gives the same 42 with the
three converted sites still present and the two uncopied files absent.

Enumerating from the emitted artifact, as the job section says, would be
stronger still and has not been built; the position rule is a source-level
instrument with a measured agreement, not a decode.

## Not in scope, found on the way

Chasing the i386 control turned up a second, unrelated defect, now
[[bug-a-three-backends-drop-the-field-width-on-a-string-variable]]: `WriteLn(s:9)`
for `s = 'abcdef'` prints `abcdef` on i386, aarch64 AND arm32, where x86-64,
riscv32 and FPC print `   abcdef`. Pre-existing here -- the i386 artefacts are
byte-identical across this change -- so it is not a regression from it.

The first reading of that said "i386 only", from an A/B whose cross-target rows
had silently all executed the same stale i386 artefact: the filename was built
by a `$(...)` that failed, so every target wrote to and ran one path. Distinct
output names and qemu gave the real answer, which is three targets.

## Why the priority dropped after the guard landed, 2026-09-02

70 was right while the class could ship a wrong value unseen. It cannot now:
`gate.sh` fails on any literal displacement spanning non-fixed-size emission, in
every mode, and the 41 remaining sites all span `EmitB`/`EmitI32` only. A
fixed-size span is wrong only if someone edits inside it, and that edit trips the
gate row on the same commit.

So the residual job is converting 41 correct jumps for uniformity. Worth doing —
the i386 clone stub at `d63f434b5` is the argument, one leg computed and one
counted is how an arm gets left behind — but it is preventive work with a low
expected yield, and it should not outrank anything that is currently wrong.

**If you take it:** convert per file, and use byte-identity as the control
(build the artefacts with the pre-change compiler, convert, rebuild, compare).
Do not treat identity as a pass on its own — a program that never reaches the
site is byte-identical too, so assert the site is exercised, by searching the
artifact for the opcode and its displacement byte. That is how the two live ones
were found: identity was the expected result, so the differing byte WAS the bug.
