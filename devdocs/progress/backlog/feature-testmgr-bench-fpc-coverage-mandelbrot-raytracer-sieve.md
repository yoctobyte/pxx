---
prio: 25
---

# Track T: bench.tsv has no `fpc` column for mandelbrot / raytracer / sieve

- **Track:** T (test infra — `tools/testmgr.py --bench`)
- **Found:** 2026-07-15, wiring the pxx-vs-FPC ratio into the website's
  benchmarks table (Track W). The "vs FPC" column is blank for three of the
  six benchmark workloads because `bench.tsv` carries no `fpc`-level row for
  them. This ticket records *why* each one is missing and which is fixable.

## Where it comes from

`BENCH_SUITE` in `tools/testmgr.py` (~line 1421) tags each workload with an
`fpc_ok` flag; only `fpc_ok=True` workloads are also compiled+timed under
`fpc -O2` for the `fpc` level:

```
("mandelbrot", ..., False),   # float compute (pxx units)
("raytracer",  ..., False),   # call-heavy float
("sieve",      ..., False),   # memory-bound int
("nbody",      ..., True),    # float, FPC-comparable
("fib",        ..., True),    # call-heavy int, FPC-comparable
```

FPC flags used: `-O2 -Tlinux -Px86_64` (no `-M` mode), mirroring the Makefile
`FPCFLAGS`.

## Findings — two distinct causes, verified with `fpc 3.2.2`

**mandelbrot — pxx-only unit (structural, `fpc_ok=False` is correct).**
```
mandelbrot.pas(31,26) Fatal: Can't find unit ansiterm used by Mandelbrot
```
`uses sysutils, baseunix, ansiterm;` — `ansiterm` is a pxx RTL unit with no FPC
equivalent. Not FPC-comparable without an FPC shim.

**raytracer — pxx-only units (structural, `fpc_ok=False` is correct).**
```
raytracer.pas(25,22) Fatal: Can't find unit image used by RayTracer
```
`uses sysutils, math, image, png, hashing, platform;` — `image`, `png`,
`hashing`, `platform` are pxx lib units. Same story as mandelbrot.

**sieve — NOT structural; it is a dialect/mode gap and IS fixable.**
```
sieve.pas(87,5) Error: range check error while evaluating constants
                       (1000000 must be between -32768 and 32767)
```
`uses sysutils;` only — no pxx-only unit. The failure is that FPC's *default*
mode types `Integer` as 16-bit `smallint`, so the `for n := 2 to LIMIT do`
loop (`LIMIT = 1000000`) overflows the loop variable's range. pxx defaults
`Integer` to ≥32-bit, so it compiles as-is. Adding `-Mobjfpc` (32-bit Integer)
makes FPC compile it clean:
```
$ fpc -Mobjfpc -O2 examples/primes/sieve.pas
102 lines compiled, 0.1 sec
```

## Suggested fixes (Track T's call)

- **sieve:** give it an `fpc` column. Either add `{$mode objfpc}` to
  `examples/primes/sieve.pas`, or add `-Mobjfpc` to the harness `FPC_FLAGS`
  (arguably more correct — it makes the reference compiler's integer width
  match pxx's default, which is the point of the comparison). Then flip
  `sieve`'s `fpc_ok` to `True`. Note the Makefile bootstrap gets away without
  `-Mobjfpc` only because `compiler.pas` carries its own mode directive.
- **mandelbrot / raytracer:** leave `fpc_ok=False` — they genuinely depend on
  pxx-only units. Optionally record the reason in a one-word column or a
  companion note so the dashboard can render "n/a (pxx units)" instead of a
  bare "—", making "no FPC number" visibly deliberate rather than missing data.

## Why it matters

Low priority — the dashboard is honest today (blank = no data). But a reader
sees three blanks and can't tell "FPC can't build this" from "we forgot to
measure it". sieve in particular is a *free* extra FPC comparison being left on
the table over a one-flag mode mismatch.
