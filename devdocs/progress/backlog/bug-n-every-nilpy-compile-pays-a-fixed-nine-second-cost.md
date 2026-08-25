---
track: N
prio: 60
type: bug
blocked-by: []
summary: "Measured 2026-08-25 (pin v374, this box): compiling `print(\"hi\")` costs 8.92s; compiling `begin end.` costs 0.25s. The ~8.7s is a FIXED per-invocation constant — it does not scale with program size — and it is pure user CPU, not I/O. It is ~29% of the entire test matrix's CPU (805 .npy jobs x 8.7s ~ 7000 of 24219 cpu-s) and it is 9 seconds on every NilPy user's hello-world."
---

# Every NilPy compile pays a fixed ~9-second cost

Found by Track T while measuring where the test matrix's wall-clock actually
goes, for the "testing overhead is 95% of development time" question. It is by a
wide margin the largest single lever in that number, and unlike every tiering
proposal it costs **no coverage at all** — it is the same tests, faster.

## The measurement

Pinned compiler `stable_linux_amd64/default/pinned` (v374), plexus, otherwise
idle-ish box:

| source | wall |
| --- | --- |
| `print("hi")` (`.npy`) | **8.92s** |
| `begin end.` (`.pas`) | **0.25s** |
| `test/test_nilpy_forin.npy` | 8.79s |
| `test/test_nilpy_c_pointer.npy` | 9.28s |
| `test/test_nilpy_str_format_conversion_and_containers.npy` | 8.88s |

Two things make this a constant rather than a workload:

- **It does not scale with the program.** A one-line `print` and the real test
  files land within half a second of each other. Whatever costs 8.7s is being
  done *before or regardless of* the user's source.
- **It is compute, not I/O.** Sampling `/proc/<pid>/stat` during the compile
  shows `utime` climbing ~100 jiffies/s (100% of one core) for the whole run,
  with `wchan` at 0 throughout. So this is not header hunting or disk.

Per-job means from the watcher's learned metrics agree, over thousands of runs:
`.npy` jobs mean **13.93s** (median 12.56s), `.pas` jobs mean **1.49s** (median
1.08s), `.c` jobs mean 1.62s. The gap is the constant, not a few slow tests.

## Why it is worth a 60

- **~29% of the whole test matrix.** 805 distinct `.npy` job identities x ~8.7s
  of pure overhead is ~7000 cpu-seconds, against 24219 cpu-seconds for every
  measured job identity in the store. Removing it shrinks every tier that
  contains NilPy — including `limited`, which is what a box with no qemu runs.
- **It is why NilPy sits in no fast tier.** `test-nilpy` was kept out of
  `native` because enrolling it took the fast verdict from ~104s to ~235s
  (see `TIERS` in `tools/testmgr.py`). That trade exists *because of this
  constant*: at `.pas` per-test cost the whole NilPy suite would fit in the
  fast verdict, and the frontend would get dense per-push coverage instead of
  a canary.
- **It is a user-facing number too.** Nine seconds to compile hello-world is
  what a person evaluating NilPy measures first, and it is the one benchmark
  they will run before reading any docs.

## Where it probably is (NOT verified — do not take this as the cause)

The obvious hypothesis is that the NilPy runtime / builtins are lowered from
source into **every** compile, where the Pascal path uses something already
built. `uses pyrt` is not a unit (`unit source not found`), so the runtime is
not a Pascal unit a user can name — it is inside the compiler. That is a
hypothesis from two timings and nothing else.

**Measure before you conclude** (`devdocs/dev/debugging-playbook.md`): `perf` is
blocked on this box by `perf_event_paranoid` and `gdb -p` by `ptrace_scope`, so
neither a profile nor a stack sample is in this ticket. That is exactly the gap
the owning lane should close first — a profile of `pxx tiny.npy` will name the
function in one run, and every route from here without one is guessing.

Repro, ~10 seconds:

```
printf 'print("hi")\n' > /tmp/tiny.npy && printf 'begin end.\n' > /tmp/tiny.pas
time stable_linux_amd64/default/pinned /tmp/tiny.npy /tmp/o
time stable_linux_amd64/default/pinned /tmp/tiny.pas /tmp/o
```

## Lane

Filed as **N** because the asymmetry is between frontends and NilPy is the slow
one. If the profile lands in shared unit/builtin compilation rather than in
`pyparser`/Python-to-IR lowering, it is an **A** ticket and should be re-filed —
`T owns the tool, never the bug`, and this ticket does not presume which lane
owns the fix, only that it is not T's.

Gate when fixed: `make test-nilpy` green + self-host byte-identical. Worth
re-measuring the two timings above in the resolve note, since the whole ticket
is a number.

---

## DIAGNOSIS (2026-08-25, diagnosis-only session)

**Binary all numbers came from:** `compiler/pascal26` self-hosted at
`6ac58fa4c` (= `origin/dev` at the time), built here by `make bootstrap`; the
build's own `cmp` fixedpoint check passed, so this is a byte-identical
self-host at that sha, not a stale artifact. Phase timings additionally use
`compiler/pascal26-debug` (`make pxx-debug`, same sha). `perf` is still blocked
(`kernel.perf_event_paranoid = 4`); `gdb` works (`ptrace_scope = 1` allows
debugging one's own children), so the profile below is gdb-based.

### The named cause

**Every `.npy` compile unconditionally compiles the NilPy runtime — `pylib.pas`
(18,768 lines) and `pyeval.pas` (5,692 lines) — from Pascal source, parsing and
code-generating ~2.1 MB of machine code, before the user's program is looked
at.** The injection is unguarded:

```
compiler/pyparser.inc:34707    ParseUsesUnitAmbient('pylib');
compiler/pyparser.inc:34708    ParseUsesUnitAmbient('pyeval');
```

`pylib.pas`'s own header says so plainly: *"Every .npy program pulls this unit
in automatically (see ParsePyProgram)."*

**This is NOT NilPy-frontend cost. It is shared Pascal unit-compilation cost.**
The ticket's own re-file rule therefore fires — see "Lane" below.

### Proof 1 — the constant is fully reproducible with no NilPy involved

A pure-Pascal program naming the same runtime units reproduces the entire
constant, through the Pascal frontend, with the NilPy frontend never entered:

```
program u; uses pylib, pyeval, promocore, pypal; begin end.
  (compiled with -Fustable_linux_amd64/default/builtin)
```

| case | wall (5 runs, s) | median | procs | code |
| --- | --- | --- | --- | --- |
| `empty.npy` (zero bytes of user source) | 8.72 8.80 9.13 8.56 8.98 | **8.80** | 1771 | 2,216,311B |
| `tiny.npy` (`print("hi")`) | 8.17 9.60 9.02 8.50 9.18 | **9.02** | — | — |
| `uses-all.pas` (pure Pascal, above) | 9.28 9.18 8.65 9.13 9.41 | **9.18** | 1761 | 2,123,100B |
| `uses-pylib.pas` (`uses pylib` only) | 4.48 5.01 5.42 5.22 5.11 | **5.11** | 1283 | 1,257,203B |
| `tiny.pas` (`begin end.`) | 0.30 0.27 0.31 0.29 0.22 | **0.29** | 124 | 60,317B |

The Pascal program and the empty `.npy` land within noise of each other and
differ by **10 procedures** (1771 vs 1761) — those 10 are NilPy's own entry
stubs. Everything else is identical work.

Also note the first row: **an EMPTY `.npy` file — zero bytes — costs the full
8.8s.** That alone settles "flat in program size".

### Proof 2 — phase timing names the two units

`gdb` breakpoints on `ParseUsesUnitAmbient` (printing its `name` argument) and
on `writeELF`, wall-clock stamped, on the debug build. Reproduced on both
`empty.npy` and `tiny.npy` with the same shape; `empty.npy` shown:

| span | seconds | share |
| --- | --- | --- |
| start -> `builtinheap` | 0.09 | 0.7% |
| `builtinheap` body | 0.34 | 2.6% |
| `builtin` body | 0.20 | 1.5% |
| **`pylib` body** | **6.67** | **51.7%** |
| **`pyeval` body + nested builtin/textfile + post-parse fixups** | **5.57** | **43.2%** |
| `writeELF` -> exit | 0.03 | 0.2% |
| (gdb-inflated total) | 12.89 | |

gdb inflates the run ~1.5x. Scaled to the native 8.8s: **pylib ~4.5s, pyeval
(+tail) ~3.8s, everything else ~0.5s.** This agrees within ~10% with the
independent by-construction split in Proof 1 (`uses pylib` = 5.11s; adding
pyeval/promocore/pypal = +4.07s).

### Proof 3 — what it is NOT

Ruled out by measurement, so the next reader does not re-hunt these:

- **Not the optimiser.** `empty.npy` at `-O0` 8.78s, `-O2` 8.65s, `-O3` 8.59s —
  flat. (Also rules out an `-O` pass running to exhaustion.)
- **Not ELF writing / linking.** 0.03s, measured at the `writeELF` breakpoint.
- **Not I/O.** Confirms the ticket: `strace` shows each runtime source opened
  once; the cost is between the reads.
- **Not a hotspot or an O(n^2) blowup.** Compile time tracks *emitted code
  volume* at a near-constant rate across a 150x range:

  | case | code emitted | wall | s/MB |
  | --- | --- | --- | --- |
  | `tiny.pas` | 0.060 MB | 0.29 | 4.8 |
  | `uses-pylib.pas` | 1.257 MB | 5.11 | 4.1 |
  | `uses-all.pas` | 2.123 MB | 9.18 | 4.3 |
  | `compiler.pas` (self-compile) | 9.12 MB | 31.61 | 3.5 |

  The compiler compiles the NilPy runtime at the *same* throughput it compiles
  itself. **There is no pathological function to optimise.** The compiler is
  simply being asked to compile 2.1 MB worth of runtime on every invocation.
- **Not proc count per se.** A synthetic program of 800 trivial called
  procedures (928 procs total) compiles in 0.41s. Empty bodies are ~0.1ms
  each; real ones ~4-5ms. It is the code, not the count.

### How much of the ~9s this accounts for

**~8.3s of the ~8.8s constant (~94%).** Split: `pylib` ~4.5s, `pyeval` ~3.8s.

The residual ~0.5s is `builtinheap` + `builtin` (~0.5s) plus process start and
the NilPy lex/parse of the user file (negligible) and ELF write (0.03s) — and
that residual is the **same floor the Pascal path already pays**: `tiny.pas` is
0.29s. So there is no unexplained remainder; nothing else is hiding here.

### Why the existing DCE pass does not fix this (measured — do not reach for it)

`compiler/dce.inc` exists, but three separate things make it the wrong lever:

1. **It refuses on NilPy.** `pascal26 --dce --dce-report empty.npy` prints
   `dce: off: only the Pascal frontend is wired up so far`, and emits the
   identical 1771 procs / 2,216,311B.
2. **It is a POST-pass, so it saves no time.** On the Pascal equivalent, where
   it does run: `dce: bodies 1585  live 651  dead 931 (723,961B)`,
   `code 2,130,872B -> 1,406,911B` — a 34% size cut, and wall clock **8.59s
   with `--dce` vs 8.30s without**, i.e. slightly *slower*. `dce.inc`'s own
   header explains why: *"The compiler emits a routine's code the moment it
   parses it -- `Procs[i].BodyAddr := CodeLen` sits at the prologue"*. The work
   is already done before DCE looks.
3. **Even perfect DCE leaves 1.4 MB live**, because RTTI/vtable method slots are
   roots and pylib is class-heavy.

Wiring DCE into the NilPy frontend is still worth doing — it would cut a
NilPy hello-world binary from 2.2 MB to ~1.4 MB — but it is a **binary-size**
fix and must not be sold as the fix for these 9 seconds.

### Fix sketch and risk

**Fix A — precompiled / cached runtime unit images. The only lever that gets
the constant near zero (~8.3s of 8.8s).** Serialise the compiled result of
`pylib`/`pyeval` (symbol tables + emitted code blob + fixup/RTTI tables), keyed
on a hash of (unit source, target arch, `-O` level, define set incl.
`PXX_MANAGED_STRING`, `--threadsafe`), and load-and-relocate it instead of
re-parsing.
*Risk: high.* The compiler has no unit-image serialisation today, and emission
is fused with parsing into one global `Code[]` buffer plus global `Procs`,
fixup, RTTI and `UCls` tables — serialising and relocating that is a
substantial Track A project, not an afternoon. The sharp edge is **cache
invalidation**: miss a key (a define, the target, an `-O` level) and the
compiler silently emits stale code, which is exactly the class of "plausible
wrong value far from the cause" bug CLAUDE.md warns about. A conservative first
cut could key on the full flag set and refuse the cache on any unrecognised
flag.

**Fix B — split `pylib` so a program pulls only what it uses (incremental).**
`pylib` is one 18,768-line unit pulled unconditionally; the compiler already has
the on-demand precedent right next to it (`math` is pulled only when the token
scan sees `**`).
*Risk: medium, and the win is bounded.* The `**`/math code comments document the
hazard: *"the LAST unit named wins a name"* — pull order changes overload
resolution, and getting it wrong silently changes which `abs`/`min`/`max` a
program resolves to (that exact bug is cited in `pyparser.inc`). The DCE
measurement bounds the payoff: only ~34% of bodies are unreachable for a trivial
program, so a naive split plausibly recovers ~1/3 of the time, not all of it.

**Fix C — lazy emission (buffer unit bodies, compile on demand).** Already
considered and rejected in `dce.inc`'s header (*"means replaying parser state
per routine, per frontend"*). Upper bound on its win is the dead fraction, ~34%
(~2.8s of 8.3s).

**Recommendation: A is the real fix, B is the shippable increment, C is a trap,
and enabling DCE for NilPy is a size fix filed separately.**

### Lane — this should be re-filed as Track A

The ticket pre-authorised this: *"If the profile lands in shared unit/builtin
compilation rather than in `pyparser`/Python-to-IR lowering, it is an A ticket
and should be re-filed."* Proof 1 shows the entire constant reproduces through
the **Pascal** frontend with NilPy never entered, and Proof 2 puts 95% of the
time inside `ParseUsesUnitAmbient` bodies — shared Pascal unit compilation. The
only NilPy-owned part is the two unguarded call sites at
`pyparser.inc:34707-34708`, and Fix A/B/C all land in Track A's shared files
(unit loading, emission, `dce.inc`).

`track:` left at `N` in frontmatter by this session on purpose — flipping it
changes coordinator dispatch, so that call is left to the coordinator.

### Repro of every number above

```
printf 'print("hi")\n' > /tmp/tiny.npy ; : > /tmp/empty.npy
printf 'program u; uses pylib, pyeval, promocore, pypal; begin end.\n' > /tmp/useall.pas
./compiler/pascal26 /tmp/empty.npy /tmp/o                                  # ~8.8s, 1771 procs
./compiler/pascal26 -Fustable_linux_amd64/default/builtin /tmp/useall.pas /tmp/o   # ~9.2s, 1761 procs
./compiler/pascal26 --dce --dce-report /tmp/empty.npy /tmp/o               # "dce: off: only the Pascal frontend..."
make pxx-debug && gdb -batch -ex 'break ParseUsesUnitAmbient' ... --args ./compiler/pascal26-debug /tmp/empty.npy /tmp/o
```
