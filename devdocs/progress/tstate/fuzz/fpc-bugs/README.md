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
