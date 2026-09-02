---
track: A
prio: 35
type: bug
status: done
found: 2026-08-30
found-by: claude-T
owner: frankC
---

# Storing a `char` into a `string[N]` through a pointer compiles on x86-64 only

Ten lines. x86-64 compiles it and prints `X`; **i386, aarch64 and arm32 all
refuse it**:

```pascal
program m2;
{$mode objfpc}
type TS = string[8];
var s: TS; p: ^TS; c: char;
begin
  c := 'X';
  p := @s;
  p^ := c;          { <-- char stored into an inline string, through a pointer }
  writeln(s);
end.
```

```
x86-64             ok: [code=65360B ...]        and runs, printing "X"
--target=aarch64   error: target aarch64: char-to-inline-string store through pointer not yet supported
--target=arm32     error: target arm32: ...
--target=i386      error: target i386: ...
```

Measured at `5944ee686`, binary `1ff8acbe123b` (self-host fixedpoint converged).

## Where

`IR_STORE_MEM` with dest `tk = tyString` and value `tyChar`. All three backends
raise deliberately at that exact arm, and the x86-64 arm right next to them is
a **one-line call**:

| backend | line | what it does |
| --- | --- | --- |
| x86-64 | `ir_codegen.inc:7509` | `IREmitStoreCharAsString`  { rsi = char ordinal -> [len=1][char] } |
| i386 | `ir_codegen386.inc:4466` | `Error('... not yet supported')` |
| aarch64 | `ir_codegen_aarch64.inc:3994` | `Error('... not yet supported')` |
| arm32 | `ir_codegen_arm32.inc:3778` | `Error('... not yet supported')` |

The two neighbouring arms (`tyAnsiString` source, and the general inline->inline
copy) ARE implemented on all four backends, so this is one missing case in an
otherwise-complete lowering, not a missing feature. Write the length word as 1,
then the char byte, at the destination the arm has already computed — the
aarch64 arm has the dest in `x6` and the source in `x5` before it raises.

**Line numbers re-measured 2026-09-02 at `f74d2f851`** — the four filed on
08-30 had each drifted 400-460 lines and none of them errored; they pointed
somewhere. Anchor on the diagnostic string, which is unique:
`grep -rn 'char-to-inline-string store through pointer' compiler/*.inc`.

## The reference to copy is in the SAME FILE, not on riscv32

Each of the three refusing backends **already emits this exact sequence** for
the `IR_STORE_SYM` form (plain `s := c`), with the destination and source in
the same registers the refusing arm has already loaded:

| backend | working arm (`s := c`) | refusing arm (`p^ := c`) |
| --- | --- | --- |
| i386 | `ir_codegen386.inc:1900` | `:4466` |
| aarch64 | `ir_codegen_aarch64.inc:1918` | `:3994` |
| arm32 | `ir_codegen_arm32.inc:1671` | `:3778` |

i386's working arm is six `EmitB` lines writing `[len=1][0][char]` to `edi`
from `esi`; the refusal site two thousand lines below has already done
`mov edi, eax` / `pop esi`. So this is a same-file, same-target, same-register
transplant per backend — not new codegen against a foreign reference.

**x86-64 has the `tyChar` arm in BOTH paths** (`IR_STORE_SYM` at
`ir_codegen.inc:7010`, `IR_STORE_MEM` at `:7509`); the other three have it in
`IR_STORE_SYM` only. That asymmetry is the whole bug, and it is the
`normalise-dont-special-case` shape: one concept, two lowering sites, the
second one left behind. Confirm `p^.s := ch` (record field through a pointer,
the unrecorded sibling) lands on this same `IR_STORE_MEM` arm before closing —
if it does, one edit per backend covers both; if it takes a third path, that
path needs the same transplant and the ticket is not done without it.

Verified by inspection only (grep + read at `f74d2f851`); no build was run for
this note.

## Why this is worth the ~4 instructions per backend

Not because the construct is everyday Pascal — `p^ := c` on a `^string[N]` is
not. Two other reasons:

1. **It is a cross-target-only refusal of code that works natively.** Anything
   written and tested on x86-64 that happens to contain it stops compiling for
   ESP/ARM with no warning until the port. That is the failure mode the cross
   targets exist to surface early.
2. **It blocks the cross-target fuzz slice at seed 1.** The `--wide` grammar
   emits it readily (via the `--shorts` rung), so every cross slice stops here
   before reaching any other rung. Track T will work around it the way
   `--intfs` is worked around today — an explicit opt-out with this ticket
   cited — but that workaround hides every OTHER `--shorts` cross bug behind
   it for as long as it stands.

## Good failure mode, to be clear

This is a **loud refusal**, not silent wrong code. The guards are doing their
job and the diagnostic names the construct precisely — which is why this ticket
took ten minutes to write instead of a day. Filed at prio 35 rather than higher
for exactly that reason.

## Provenance

Found by the Track T cross-target fuzz slice (`pasmith_run --wide --cross`),
first seed, signature `pxx-cross_target-aarch-char-inline`. Track T owns the
tool, never the bug.

Gate: per CLAUDE.md's per-fix loop — `make compiler/pascal26` plus the repro
above on all four targets. Cross breadth comes back from Track T against the
pushed sha.

## Drop the dodge in the SAME pass as the fix

Track T is currently running its cross slices with `--shorts 0` to get past this
— the same dodge the 2026-07-14 note prescribed for its sibling. That is how a
fuzzer stays productive, and it is also how a fuzzer stops being able to find a
family of bugs; the only thing distinguishing the two is this paragraph.

**Whoever fixes the lowering removes the dodge in the same commit**, and re-runs
one cross slice with `--shorts 2` to confirm the rung is live again. Do not file
a follow-up to remove it: a ticket whose entire content is "stop working around
a thing that now works" is exactly the ticket nobody picks up, and the dodge
then becomes permanent by default.

Until then, every OTHER `--shorts` cross bug is hidden behind this one.

### What the dodged slice already covered, so the cost is bounded

Run at `5944ee686`, binary `1ff8acbe123b`, `--wide --shorts 0 --cross`:

> **294 programs, 0 divergences**, across 8 oracles — fpc-O0, fpc-O2, pxx-O0,
> pxx-O2, pxx-O3, pxx-i386, pxx-aarch64, pxx-arm32.

Two things that says, and one it does not.

It **bounds what the dodge costs**: with `--shorts` off, every other widened
rung — records, arrays, enums, exceptions, var/const/out params, classes,
hierarchies, properties, class methods, destructors — agrees across all three
cross targets and both FPC levels. So this dodge is not sitting on top of a pile
of other cross bugs; it is hiding the `--shorts` rung specifically.

It also says the **cross dimension is not trivially productive** at this grammar
once the one blocking refusal is dodged. That is a real fact about where the
next fuzzing effort should go — widening the grammar, or adding an oracle
dimension that is not behavioural at all
([[feature-t-a-second-oracle-dimension-section-alignment]]) — rather than
running more seeds of the same shape.

It does **not** show there are no cross bugs in those rungs. 294 seeds is 294
seeds; a clean run is evidence about the rate, not proof of absence.


## Re-measured 2026-09-02 (frankC), during the shortstring cluster census

Still open, on `0c487458fa67`. **riscv32 now PASSES** — this ticket predates
that, and it matters because it means a non-x86-64 reference implementation
already exists to copy from.

Six shapes, five targets:

| | shape | x86-64 | i386 | aarch64 | arm32 | riscv32 |
| --- | --- | --- | --- | --- | --- | --- |
| a | `p^ := c` (this ticket) | ok | REFUSED | REFUSED | REFUSED | ok |
| b | `p^ := 'abc'` literal via pointer | ok | ok | ok | ok | ok |
| c | `p^.a := 1`, string field present | ok | ok | ok | ok | ok |
| d | `p^.s := 'abc'` string field via pointer | ok | ok | ok | ok | ok |
| e | **`p^.s := ch` char into a string FIELD** | ok | REFUSED | REFUSED | REFUSED | ok |
| f | `s := ch` char into string, NO pointer | ok | ok | ok | ok | ok |

**Row e is this ticket's sibling and was not recorded here**: the same defect
reached through a record field rather than a bare pointer. Row f shows it is not
the char-to-string conversion; row b shows it is not the pointer store. The
refusal is exactly `char VALUE + string DEST + POINTER store`.

Note rows c and d are [[bug-cross-pointer-store-record-with-shortstring-field]],
which is DONE (`7716bd2a`) — so the record spelling of the pointer store was
fixed and this spelling was not. `normalise-dont-special-case`: one arm of a
double case, and the sibling only becomes visible with both on one page. **Fix
both arms, and check row e as well as row a.**

## Not blocked by the byte-prefix layout

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]] would change
`[len:8][char]` to `[len:1][char]`, which makes each emitter marginally simpler
and removes none of them. This does not need to wait for it, and it does not
close if that lands.

## FIXED 2026-09-02 (frankC) — three transplants, both rows, executed on five targets

The `IR_STORE_MEM` arm on i386, aarch64 and arm32 now emits what the
`IR_STORE_SYM` arm **in the same file** already emitted for `s := c`. At the
refusal point each backend had already loaded dest and char into the registers
that arm expects, so this is a transplant and not a port:

| backend | emitted | note |
| --- | --- | --- |
| i386 | 6 `EmitB` lines | `mov eax, esi` is not convention — 32-bit mode has no `sil` |
| aarch64 | 3 | one 64-bit `str x9, [x6]` covers both halves of the length word |
| arm32 | 5 | two 32-bit stores for the length word, as its `IR_STORE_SYM` twin does |

**Row e rides the same arm — confirmed, not assumed.** `pr^.s := c` in a file
containing nothing else is refused by the PINNED compiler on all three targets
with the same diagnostic, and compiles and runs on x86-64. There is no third
path; one edit per backend closed both rows.

### Verified by EXECUTION, not by compiling

"It compiles" would have been the weak claim here — wrong bytes assemble fine.
All five targets **run** `test/test_char_into_shortstring_via_pointer.pas` under
qemu and produce byte-identical output, at **every level `-O0` through `-O3`**
(20 cells, all green).

**Positive control:** the pinned compiler still refuses that exact test file on
i386/aarch64/arm32. That is what proves the test reaches the arm rather than
passing for free. The pin/`lib/` precondition was checked — `git diff HEAD --
lib/` was empty when the control was taken.

**Aimed so it cannot pass by accident:** every string is pre-loaded with a
5-char value before the store under test, so a store that does nothing prints
`5 abcde` rather than reading back as a plausible pass. Rows c and d are the
ticket's own isolating controls (no pointer; string source through the pointer),
and row b checks the neighbouring `LongInt` field, which a wrong length word or
a stray byte would land on.

### Where the test is wired, and which row is the guard

`test-i386`, `test-aarch64`, `test-arm32`, `test-riscv32`, plus the native
suite. **The native row is marked in the Makefile as one that CANNOT FAIL for
this bug** — x86-64 was correct throughout, so a native-only test would be a
guard that cannot fail for the defect it is named after. The cross rows are the
guard. riscv32's row is labelled as the control that these three transplants
changed nothing on the backend that was already right.

### The `--shorts 0` dodge is NOT in this repo

Removing it in the same commit was the instruction and it cannot be followed
here: the only `--shorts 0` in the tree is a comment in `pasmith_run.py`
describing the **historic** dodge as fixed, and no invocation in `tools/`,
`Makefile` or `tstate/` passes it. Track T's dodge lives in how its daemon
invokes the slice on `seven` — T's own infra.

So this ticket cannot close that loop, and per the section above a follow-up
ticket is the one nobody picks up. **What is provided instead is the evidence
that removes the need to trust anyone's say-so**: a cross slice run here with
the rung LIVE against the fixed compiler, recorded below. Whoever holds Track T
drops the dodge against that.

### The rung, live: `--wide --shorts 2 --cross`, seeds 1-60

> **60 programs, 0 divergences** — 0 FPC-rejected/generator bugs, 0 known
> signatures, 0 NEW. Oracles: fpc-O0, fpc-O2, pxx-O0, pxx-O2, pxx-O3, pxx-i386,
> pxx-aarch64, pxx-arm32.

Run here against the fixed compiler, with the `--shorts` rung ON. Before this
fix the same invocation stopped at the first seed on all three cross oracles.

Two things it says. The rung is **live again** — the refusal that gated it is
gone and the generator's shortstring shapes now reach every oracle. And 60 seeds
of a rung that previously produced nothing at all is a **rate**, not a proof of
absence: the earlier `--shorts 0` run was 294 programs and 0 divergences, so a
clean 60 here is consistent with the cross dimension simply not being very
productive at this grammar, which is the ticket's own reading.

**Track T: this is the evidence to drop the dodge on.** It is not removable from
this repo (see above), so it needs whoever holds the daemon invocation.

## Log
- 2026-09-02 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit e4cba526a.
