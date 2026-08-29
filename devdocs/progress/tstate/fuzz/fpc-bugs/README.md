# FPC upstream bugs found by the pasmith differential fuzzer

pxx's Object-Pascal fuzzer (`tools/pasmith.py`) runs each random program under
FPC and pxx at several optimization levels. When **FPC contradicts itself**
(O1 vs O2/O3) the divergence is an FPC bug, not a pxx one — pxx agrees with
FPC's own -O1 output at every level. These are reduced and documented here so
they can be filed upstream (gitlab.com/freepascal.org/fpc/source → Issues).

## fpc-o2-cse-rte216.pas — CSE miscompiles a boolean store into a GPF

- **FPC:** 3.2.2, x86_64-linux (ppcx64).
- **Ledger sigs:** `fpc-self_if` (seed 27295), `fpc-self_trace-length` (seed
  27432) — same root cause.

### Summary

At `-O2`/`-O3` the program dies with **Runtime error 216** (general protection
fault) at the statement

```pascal
ar0[2] := longint(ord(((g17 or g17) or (ar0[2] > ar1[0]))));
```

At `-O1`, `-O-`, or `-O2 -OoNOCSE` it runs cleanly and prints `survived`.

### Pass isolated: CSE (common subexpression elimination)

Necessary and sufficient — nothing else matters:

```
fpc -O1              -> survived   (rc 0)
fpc -O1 -OoCSE       -> RTE 216    (CSE alone triggers it)
fpc -O2              -> RTE 216
fpc -O2 -OoNOCSE     -> survived   (rc 0)
fpc -O3 -OoNOCSE     -> survived   (rc 0)
```

Every other `-O2` sub-pass disabled individually (`-OoNODFA`, `-OoNOPEEPHOLE`,
`-OoNOREGVAR`, `-OoNOUNCERTAIN`, …) still crashes; only `-OoNOCSE` fixes it.

### Why it is unambiguously a codegen bug

The reproducer is **memory-safe and warning-free**: every array index is a
compile-time constant in range (`ar0[0..3]`, `ar1[0..3]`, `r0g.r0a[0..3]`),
there are no pointers, every global is explicitly `FillChar`/assigned before
use, and every function sets its result. Identical source; only the `-O`/`-Oo`
level changes the outcome. So the fault is in FPC's CSE pass, not the program.

pxx compiles and runs it correctly at `-O0/-O2/-O3` (prints `survived`).

### Status: FIXED in trunk (do NOT file)

Built FPC **3.3.1** trunk (`ppcx64`, commit `3b5c7beebeff`, 2026-07-15) from
source, bootstrapped off 3.2.2. The reproducer runs **clean at every level** on
trunk — `-O1`, `-O2`, `-O3`, and `-O1 -OoCSE` all print `survived`:

```
trunk 3.3.1  -O2          -> survived (clean)
trunk 3.3.1  -O1 -OoCSE   -> survived (clean)
release 3.2.2 -O2         -> RTE 216
```

So the CSE miscompile is **already fixed upstream** and only affects the aging
3.2.2 release. Not worth a new issue; at most a fixes-3.2 backport candidate, and
even that is marginal given 3.2.2's age. Kept here as a documented fuzzer find
and a regression guard: if pxx ever grows a CSE pass, this is a ready test case.

### Reproduce

```
fpc -O2 -gl fpc-o2-cse-rte216.pas && ./fpc-o2-cse-rte216   # RTE 216 at the marked line
fpc -O2 -OoNOCSE fpc-o2-cse-rte216.pas && ./fpc-o2-cse-rte216   # survived
```

Reduced from a 1156-line random program (pasmith seed 27295) by ddmin + hand
pruning down to 70 lines.

## fpc-o2-asm-byte-value-exceeds.pas — the assembler writer rejects its own output at -O2

- **FPC:** 3.2.2, x86_64-linux (ppcx64).
- **Ledger sig:** `fpc-self_asm-byte-value-exceeds` (seed 362).
- **Found:** 2026-08-29, and it is the first entry here that is a **compile-time**
  self-contradiction rather than a runtime one — see the note at the end.

### Summary

At `-O2` FPC refuses to compile the program:

```
fpc-o2-asm-byte-value-exceeds.pas(274,16) Error: Asm: byte value exceeds bounds 4294967295
fpc-o2-asm-byte-value-exceeds.pas(324,1) Fatal: There were 1 errors compiling module, stopping
```

At `-O-` it compiles clean (`324 lines compiled, 0.1 sec`, 0 errors) and runs.
Line 274 is

```pascal
g1 := byte(qword(longword(g1)));
```

This is FPC's own assembler writer rejecting an operand its own code generator
produced — not a diagnostic about the source.

### Why it is unambiguously FPC's

Identical source; only `-O` changes the outcome. FPC `-O-` compiles it, runs it,
and prints a checksum that **pxx matches at `-O0`, `-O2` and `-O3`**:

```
fpc-O0, pxx-O0, pxx-O2, pxx-O3 : 16544526250867958718
fpc-O2                         : <compile-fail>
```

So four independent builds across two compilers agree on the program's meaning
and the fifth will not build it.

### NOT reduced, deliberately

The obvious candidate does **not** reproduce — this 7-line program compiles clean
at both levels:

```pascal
program min362;
var g1: byte;
begin
  g1 := 7;
  g1 := byte(qword(longword(g1)));
  writeln(g1);
end.
```

So the trigger is context-dependent (register pressure at `-O2` is the obvious
suspect) and a real reduction is a ddmin-scale job, as
`fpc-o2-cse-rte216.pas` above shows. It was not attempted: reducing an upstream
compiler's bug is not this repo's work, and the 324-line case with nearly every
pasmith feature knob at **0** is already a small configuration.

**The `.pas` is committed rather than left as a seed** because `--seed 362` only
reproduces against the pasmith that generated it, and `tools/pasmith.py` changes
often. The file is the durable artifact; the seed is the convenience.

### Status: NOT checked against trunk

Unlike the CSE bug above, this has **not** been tried on FPC 3.3.1 trunk — no
trunk build was available in the session that found it. So it is not known
whether this is already fixed upstream, and that check is the next step before
anyone files it.

### Reproduce

```
fpc -O2 fpc-o2-asm-byte-value-exceeds.pas   # Error: Asm: byte value exceeds bounds
fpc -O-  fpc-o2-asm-byte-value-exceeds.pas && ./fpc-o2-asm-byte-value-exceeds
```

### Why this one nearly did not get here

It was classified `fpc-reject_compile-fail` — *"FPC REJECTED THE PROGRAM,
pasmith contract violation"* — because `classify()` treated **any** FPC arm
failing to compile as the generator emitting invalid Pascal, and returned before
the `fpc-self` check that this directory's opening paragraph describes. So the
model was right, the destination existed, and nothing could route a compile-time
case to it. Fixed in
[[bug-t-pasmith-calls-an-fpc-o2-bug-a-generator-contract-violation]]; both
entries that bucket ever recorded were FPC bugs, and the other one
(`fpc-self_error-while-linking`, seed 85029) is a *different* FPC failure that
had been deduplicated into the same signature.
