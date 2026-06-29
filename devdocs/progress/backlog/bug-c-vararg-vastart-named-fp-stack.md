# C: `va_start` ignores named FP and stack-spilled parameters

- **Type:** bug (Track A / C frontend + x86-64 SysV variadic ABI)
- **Status:** backlog (partially fixed 2026-06-29 — register-class case closed)
- **Owner:** unassigned
- **Found / Opened:** 2026-06-29, while lifting the C vararg argument-count cap.

## Progress — 2026-06-29 (register-class case fixed)

The **named-FP-in-register** case is fixed. `ParseCSubroutine` now classifies
named params by SysV class (`ProcNamedGP` = int/ptr count, new `ProcNamedFP` =
float count), and `__pxx_va_start_impl` takes `nfp` and seeds
`fp_offset = 48 + nfp*16` (was hardcoded 48). So `double f(double scale, int n,
...)` now reads its variadic doubles correctly (`sumv(2.0,3,1,2,3)` → 12.0, was
10.0; gcc-matched). Guard: `test/cvararg_named_fp.c` (in `make`). Self-host
fixedpoint byte-identical; lua green.

**Still open — stack-spilled named params** (the harder half). When a variadic
function has more than 6 named GP or 8 named FP params, the surplus named params
spill to the caller stack, and:
  - reading those *named* params is itself wrong (e.g. 10 named doubles: the 9th/
    10th read as 0 — a prologue issue, not just va), and
  - `overflow_arg_area` must start past the stack-spilled named params, else the
    variadic tail is misaligned (7 named ints + variadic: tail summed 20 vs 60).
Repros: scratchpad `v2_many_double.c`, `v3_many_gp.c`. These need the prologue /
overflow-area accounting, separate from the register-class fix above.

## Symptom

The current C variadic support seeds `va_list` with only `ProcNamedGP`, and
`__pxx_va_start_impl` always initializes:

- `gp_offset = named_gp * 8`
- `fp_offset = 48`
- `overflow_arg_area = __va_overflow`

That is correct for common shapes like `printf(const char *fmt, ...)`, where the
only named parameter is a GP argument and no named parameter has spilled to the
caller stack.

It is not correct for legal C variadic functions with named floating-point
parameters or enough named parameters to consume/spill ABI argument slots, e.g.:

```c
double f(double scale, int n, ...);
int g(int a, int b, int c, int d, int e, int f, int g, ...);
```

In those cases, `va_arg(ap, double)` can reread a named FP register slot, and
overflow-area reads can start at the wrong caller stack slot.

## Cause

`ParseCSubroutine` records only `ProcNamedGP[procIdx] := nparams`, treating all
named parameters as GP-register parameters. The x86-64 SysV ABI classifies named
parameters independently:

- up to 6 integer/pointer-class parameters in GP registers,
- up to 8 floating-class parameters in SSE registers,
- remaining named parameters in the caller stack overflow area.

`va_start` needs all three offsets: initial GP offset, initial FP offset, and the
first variadic stack slot after any named stack-spilled parameters.

## Acceptance

- Track named GP, named FP, and named stack-spilled parameter counts for C
  variadic functions.
- Seed `va_list` with the correct `gp_offset`, `fp_offset`, and
  `overflow_arg_area`.
- Add focused C tests for:
  - named `double` before `...`, followed by `va_arg(double)`;
  - named parameters that spill to the stack before `...`;
  - mixed named GP/FP parameters before variadic GP/FP arguments.
- Existing `printf` and many-argument vararg tests remain green.
