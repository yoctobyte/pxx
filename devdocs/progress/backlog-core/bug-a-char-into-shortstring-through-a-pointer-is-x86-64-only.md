---
track: A
prio: 35
type: bug
status: open
found: 2026-08-30
found-by: claude-T
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
| x86-64 | `ir_codegen.inc:6076` | `IREmitStoreCharAsString`  { rsi = char ordinal -> [len=1][char] } |
| i386 | `ir_codegen386.inc:4066` | `Error('... not yet supported')` |
| aarch64 | `ir_codegen_aarch64.inc:3537` | `Error('... not yet supported')` |
| arm32 | `ir_codegen_arm32.inc:3467` | `Error('... not yet supported')` |

The two neighbouring arms (`tyAnsiString` source, and the general inline->inline
copy) ARE implemented on all four backends, so this is one missing case in an
otherwise-complete lowering, not a missing feature. Write the length word as 1,
then the char byte, at the destination the arm has already computed — the
aarch64 arm has the dest in `x6` and the source in `x5` before it raises.

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
