---
track: A
prio: 55
type: bug
status: new
blocked-by: []
owner: ""
summary: "A csmith program compiles clean and then HANGS at runtime under pxx at -O0/-O1/-O2/-O3 alike, where a gcc-built binary of the same source runs and prints its checksum. Localized to func_58 by entry instrumentation: gcc enters all 10 generated functions, pxx enters 8 and spins in the 8th. Not an optimizer bug (every level hangs) and not a wrong builtin (all 15 verified equal to gcc individually). Repro preserved verbatim at test/csmith/hang_builtins_700082.c -- found via the --builtins axis, which csmith disables by default and no run in this repo had ever enabled."
---

# A csmith program hangs under pxx at every `-O` level, and runs under gcc

- **Found:** 2026-08-30 by frankC, first run of the csmith `--builtins` axis.
- **Repro:** `test/csmith/hang_builtins_700082.c` (kept verbatim — see that
  directory's README for why a seed is not enough).
- **Compiler:** self-host fixedpoint `883476f0abaf`, `converged after 1 round(s)`.

## The measurement

```
gcc  -w -I/usr/include/csmith          -> runs, prints "checksum = 5ABA20EA", exit 0
pxx  -I/usr/include/csmith ...         -> compiles clean (exit 0), binary HANGS
```

The compile is fine — `ok: ... [code=585496B data=14648B bss=69192B procs=829]`,
exit 0. The failure is entirely at runtime.

## What has been ruled out, by measuring rather than reasoning

**1. It is not an optimizer bug.** Every level hangs, including `-O0`:

| `-O0` | `-O1` | `-O2` | `-O3` |
| --- | --- | --- | --- |
| hang | hang | hang | hang |

This matters for where to look: a pass cannot be the culprit if the level with
no passes also hangs. (It also means the CLAUDE.md caveat about the self-host
gate proving only the default `-O` is not the story here.)

**2. It is not a wrong builtin, despite being found on the `--builtins` axis.**
The program uses 15 distinct builtins. I tested every one of them directly
against gcc over `{0, 1, 2, MSB-set, all-ones, 0x0123456789ABCDEF}`:

```
__builtin_clz clzl clzll ctz ctzl ctzll popcount popcountl
parity parityl parityll ffsl ffsll bswap32 bswap64
```

**All agree with gcc, every value.** So `--builtins` found this bug by
generating a program shape, not by exercising a broken builtin — worth stating
plainly so nobody re-runs that comparison.

**3. Two specific loop hypotheses, both refuted.** `func_58` contains loops
whose termination depends on exact integer typing, and the obvious suspects are
wrong:

- `for (g_195 = -27; g_195 > 14; g_195 = safe_add_func_uint64_t_u_u(g_195,4))`
  — `g_195` is `int32_t`, so gcc never enters. A minimal version agrees with gcc
  (`iterations=0 g=-27`). **Not it.**
- `for (l_671 = 25; l_671 != 19; l_671 = safe_sub_func_uint16_t_u_u(l_671,2))`
  — `!=` termination driven by a `uint16_t` subtraction, the most fragile shape
  in the function. Minimal version agrees (`n=3 l=19`), as do `l_817`'s `!=`
  counter and `p_63`'s unsigned-wrap guard. **Not it either.**

Recording these because they are the two anyone would try first, and both cost a
measurement to eliminate.

## Where it is

Entry instrumentation (a one-shot `printf` at the top of each generated
function, applied to both compilers' builds of the SAME instrumented source):

```
gcc:  enters all 10 functions, ends "checksum = 5ABA20EA"
pxx:  enters 8, last is  ENTER func_58,  then spins
```

So the defect is inside `func_58` (definition at line 1012 of the repro, ~349
lines) or something it calls. It is not reached-and-returned: the 9th and 10th
functions gcc enters are never entered.

## What is NOT established — read before assuming a lane

**The lane is a guess.** Filed **A** because a runtime hang that survives `-O0`
and does not reduce to a small loop shape is most likely IR lowering or codegen,
which is A's — the fuzz-routing convention (`IR/codegen -> A, dialect/frontend
-> P, RTL -> B`). But nothing here proves it is not the C frontend's lowering,
and `func_58` has not been reduced to a minimal case. **If reduction lands it in
`cparser.inc`, re-file it to C rather than arguing the letter** — the evidence
above is lane-neutral.

No reducer is installed on this box (`creduce`/`cvise` both absent), which is
the single thing that would most speed this up; a `--builtins` finding that
survives reduction is a much smaller ticket than 1939 lines.

## Frequency

3 hits over 120 iterations, **1 distinct** (seeds 700082, 700093, 700106 all
reduce to the same finding). The other 117: 40 agreed with the gcc oracle, 77
were skipped because the native validity filter could not build them — see the
campaign ticket for why that skip rate is a property of the axis, not a fault.

## Related

- Campaign: `feature-c-csmith-differential-fuzzing`
- Why the program and not the seed: `bug-t-a-fuzz-finding-cited-by-seed-alone-cannot-prove-a-fix`
