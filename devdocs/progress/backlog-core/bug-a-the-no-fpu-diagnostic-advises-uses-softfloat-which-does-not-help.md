---
track: A
prio: 35
type: bug
status: open
found: 2026-08-30
found-by: claude-A
---

# The "no FPU" diagnostic tells you to `uses softfloat`, and doing so changes nothing

On a bare ESP target the compiler refuses a float operation with:

```
this target has no FPU and the soft-float kernel __pxx_d2i_rne is not linked;
add `uses softfloat` to the program
```

**Following that advice does not work.** Measured on both bare ESP targets:

| program | bare xtensa | bare riscv32 |
| --- | --- | --- |
| `uses builtin;` | fails (two undefined names) | same, line for line |
| `uses softfloat, builtin;` | **same kernel error, same line** | same |

`softfloat` is **found** — no unit-not-found diagnostic appears — and the check
still refuses.

## Why this is worth a ticket rather than a shrug

A diagnostic that names a remedy is stronger than silence, and a *wrong* remedy
is weaker than silence: it costs the reader a real attempt and then leaves them
unsure whether they did it wrong. Two sessions have now hit this line while
chasing something else.

## The two candidate causes, deliberately not guessed between

1. The kernel-presence check does not see `softfloat`'s kernels (wrong predicate,
   wrong point in the pipeline, or the unit's symbols are not registered under
   the names the check looks for).
2. The advice is stale — `softfloat` no longer provides these kernels, or never
   provided them for the bare ESP profile — and the message should say something
   else, or nothing.

These have opposite fixes. Whoever takes it should determine which **before**
editing the string, since fixing the message when the check is broken would hide
a real defect behind a more honest-sounding sentence.

## Provenance

Found while working
[[bug-a-builtin-pas-calls-a-declaration-that-esp-compiles-out]]; the kernel
errors are the queue that appears once that unit's guards are made to work. Not
chased there because it is a separate defect with a separate cause.

---

## 2026-08-30 (frankB) — it is cause 1, and the repro is 15 lines

Amending at the coordinator's request with a concrete consumer, a minimal
repro, and an answer to this ticket's own open question. Measured at
`c781fc84f` with pin v396 (`pinned` abece5150983); every row is from a run.

### The answer to "the two candidate causes, deliberately not guessed between"

**Cause 1, sharpened — and the sharpening matters more than the verdict.** The
kernel-presence check is not wrong about what it sees: on a program that names
`softfloat`, the kernel genuinely **is not linked**. What is wrong is that
nothing links it. Kernel linking is driven by a scan of the **program**'s
tokens, so a float need that arises inside a **unit** is invisible to it, and
`uses softfloat` puts the unit in scope without triggering the link.

Cause 2 is out: `softfloat` does provide these kernels —
`compiler/builtin/softfloat.pas` defines `__pxx_ul2d` — so the advice is not
stale, it is simply not the lever.

### Minimal repro — no library involved

```pascal
unit mimic_fneed;
{$MODE PXX}
interface
function AsDouble(u: UInt64): Double;   { needs __pxx_ul2d }
implementation
function AsDouble(u: UInt64): Double;
begin
  AsDouble := Double(u);
end;
end.
```

Three programs over that one unit, on `--platform=esp --esp-profile=bare`:

| the program | bare xtensa | bare riscv32 |
| --- | --- | --- |
| **A** — no float anywhere in the program | FAIL `__pxx_ul2d` | FAIL `__pxx_l2d` |
| **B** — A **plus `uses softfloat`**, the advice | **FAIL, identically** | **FAIL, identically** |
| **C** — A plus `d := 1.5; d := d * 2.0` in the program | **BUILDS** | **BUILDS** |

Control: all three build on aarch64, which has an FPU — so this is not "bare
ESP refuses float". Ordering is irrelevant: `uses softfloat, mimic_fneed` and
`uses mimic_fneed, softfloat` both fail.

**Row C is the whole finding.** A float the program does not need, added purely
to be *seen*, fixes a failure caused by a float the program never mentions. The
remedy that works is the one nobody would guess, and the remedy the diagnostic
names does nothing.

Incidental, worth knowing when grepping: the two targets name **different**
kernels for the same source line — `__pxx_ul2d` on xtensa, `__pxx_l2d` on
riscv32.

### Why fixing the pull may RETIRE this ticket rather than fix the sentence

This ticket's own instruction — *"determine which before editing the string,
since fixing the message when the check is broken would hide a real defect
behind a more honest-sounding sentence"* — was right, and the answer points
away from the string entirely. **The advice failing is a symptom, not the
defect.** If unit-internal float needs drove the pull, `uses softfloat` would
be unnecessary rather than ineffective, and the diagnostic would stop firing on
correct programs. Editing the message first would have made a real bug polite.

**This is the same defect as
[[bug-a-the-hw-entropy-intrinsics-are-unreachable-on-every-esp-target]], in a
second place — which makes it a property of the pull mechanism rather than two
bugs.** There, `__pxxCpuHasHwRandom` was pulled by a token scan of the program
(`pasparser_prog.inc`), so `lib/rtl/random.pas` naming it was invisible and the
name did not resolve. Same shape, same file's mechanism, different symbol.

**And the fix already has a landed template**: `ba14f5f56` solved it for the
intrinsics by moving them into an on-demand unit (`compiler/builtin/
builtinentropy.pas`, which `uses` nothing so it is pullable on a bare boot) and
having the library file `uses` it explicitly. Whether the soft-float kernels
can take the same treatment is the first question to ask, and it is a much
smaller question than the general one.

### Concrete consumer

`lib/rtl/random.pas` is **unbuildable on both bare ESP targets** because of
this. It fails at `random.pas:460`, inside `RandomDouble`
(`Double(XoshiroNext shr 11) * 1.1102230246251565e-16`) — **including for
programs that only call `Random64` and never touch a float**, since the unit is
compiled whole. Recorded as a real `blocked-by` edge on
[[feature-random-esp-hw-tier]].

That consumer is why row C matters practically rather than curiously: the
workaround available to a caller today is to add a float they do not want to a
program that does not need one, in order to use an integer RNG.

### Provenance note

Found while re-verifying [[feature-random-library]]'s blockers. An earlier pass
from this session reported **seven** float shapes building fine on bare ESP and
concluded no wall existed. Every one of those seven was a program containing
float code, so each pulled the kernel by the very mechanism that is broken —
they were testing the working path while trying to test the broken one. That
table is still true and still bounds the failure (generic float on bare ESP is
fine); it simply could not see this. Recorded because the same confound will
catch the next person: **to test this, the program must contain no float at
all.**
