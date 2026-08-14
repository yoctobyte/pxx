---
track: T
prio: 80
type: task
blocked-by: []
summary: "Compile-only sweep of test/** with --strict-uses, classified against three known failure shapes. It is the last input bug-pascal-uses-is-transitive needs before the flag becomes the default, and it is a full-corpus run — Track T's kind of job, not a dev-loop one."
status: done
---

# Sweep `test/**` under `--strict-uses` and classify the failures

Track A built the enforcement ([[bug-pascal-uses-is-transitive]]) and measured it
over `examples/**`: **55 programs, 41 compile today, and all 41 compile
IDENTICALLY with `--strict-uses` on.** The remaining unknown is the `test/`
corpus — 923 `.pas` plus the `.npy` suite — and that is a full-corpus run, which
is why it is filed here rather than run in a dev loop.

## What to run

For each file in `test/**` (`.pas`, `.npy`, and the C corpus if cheap), compile
**twice** and compare only the pass/fail verdict:

```
pxx <file> /tmp/out                 # baseline
pxx --strict-uses <file> /tmp/out   # enforced
```

Nothing is executed and no expectation is checked. A file that already fails the
baseline is not a finding — 113 of the 934 are helper `*_unit.pas` files and
`{%FAIL}` cases that never compiled standalone. **The finding is the set that
compiles clean today and fails only with the flag.**

## How to classify each new failure

Three shapes account for every one Track A hit, and each has a different owner:

1. **A compiler-INJECTED unit that is not marked ambient.** The compiler injects
   `builtin`/`builtinheap`, `pylib`/`pyeval` (every `.npy`), and conditionally
   `textfile`/`math`/`promocore`/`softfloat`/`pxxcio`/`palpthread`. Tell:
   the missing name is a runtime helper the source never mentions —
   `pyfloormod_i`, `pystr_of`. Fix is one call site in the compiler
   (`ParseUsesUnitAmbient`).
2. **Two filters that fail to compose.** Tell: *"no overload of X matches these
   arguments"* with an **EMPTY candidate list**, rather than an undefined
   identifier. An out-of-scope candidate was still suppressing an in-scope one.
   Fix is in the compiler.
3. **A genuine missing `uses`.** Tell: the unit really does call another unit's
   routine without naming it. Fix is one clause in the library — or, as often,
   naming the RIGHT unit (pylib's `FloatToStr` came from `builtin`, not the
   `sysutils` it was accidentally reaching).

Report the count per shape, and for shape 3 the (importer, provider, name)
triples. That list is the actual remaining work, and it is expected to be
short.

## Do NOT size this with `--warn-uses-leak`

The warn pass is noise-dominated: it fires on **speculative** lookups
(`FindUClass`/`FindProc` called to ask "is this identifier a class?", answered
yes, answer discarded), so its top rows are things like
`platform -> pylib [class] TPyDict` at 2948 hits in a unit that never mentions
`TPyDict`. Two earlier sizings of the parent ticket were wrong for exactly this
reason. `--strict-uses` changes resolution, so it errors only where a name
really binds — count failures, not warnings.

## Why it is worth the run

`--strict-uses` becomes the default when this comes back short, which deletes
the whole class of bug behind `decide-class-namespace-scoping`, the tkinter /
reportlab `Canvas` collision, and every future "two libraries export the same
name". The parent ticket is parked on this result.

## RESULT 2026-08-14 — 1660 sources, ONE strict-only failure

Compile-only sweep, every `test/*.pas` and `test/*.npy`, twice each (baseline
and `--strict-uses`), comparing only the pass/fail verdict. Nothing executed,
no expectation checked.

| verdict | count | |
|---|---|---|
| both-pass | **1516** | compile clean with and without the flag |
| baseline-fail | 143 | already fail without it — not findings (helper `*_unit.pas`, `{%FAIL}` cases) |
| **STRICT-ONLY-FAIL** | **1** | the finding |

1660 sources (1038 `.pas` + 622 `.npy`).

### Shape 3 — genuine missing `uses`: **NONE**

The list this ticket asked for — `(importer, provider, name)` triples — is
**empty**. No library needs a `uses` clause added. Combined with Track A's
`examples/**` result (41 of 41 identical), the corpus says the enforcement is
essentially already satisfied.

### The one finding, and it is not cleanly any of the three shapes

`test/test_nilpy_dotted_package_import.npy`:

```
pascal26:3928: error: __pxx_pipe2 needs the thread-safe runtime: rebuild with
--threadsafe (<pthread.h> lowers onto the pxx thread PAL, which that flag
selects; without it this would import a pxx-internal symbol from libc and fail
at load)
  near:       >>> unsigned int sleep
```

Closest to **shape 1** (a conditionally-injected ambient unit): `palpthread` is
marked ambient only under `--threadsafe` (`compiler/cparser.inc:8611`), so under
strict the pthread path is entered where the baseline never needed it. But it
surfaces as a **capability diagnostic**, not an undefined name, so it does not
match shape 1's stated tell. Recording that rather than forcing it into a box.

**Under `--strict-uses` this file has no working configuration**, and the reason
is the second finding below rather than anything about `uses`:

| flags | result |
|---|---|
| (baseline) | compiles, runs, prints `dotted imports ok` |
| `--strict-uses` | **compile error** (above) |
| `--strict-uses --threadsafe` | compiles, then `undefined symbol: __pxx_malloc` at load |
| `--threadsafe` | compiles, then **SIGSEGV** |

So the remedy the diagnostic names is itself broken — see
[[bug-a-threadsafe-segfaults-on-every-nilpy-program]]. **That is the actual
blocker, not a uses problem.** Once `--threadsafe` works for NilPy, this file
should be re-checked; it may well pass, or need only the ambient marking.

### Recommendation for [[bug-pascal-uses-is-transitive]]

The sweep came back short, as that ticket hoped. One file, no shape-3 work, no
library changes. The remaining question is whether that one file's shape-1
marking is worth doing before flipping the default, or whether the flip should
wait on the `--threadsafe` fix so the file can be re-measured honestly.
**That is Track A's call** — T's job was the number, and the number is 1.

### Method note

Run detached under `systemd-run --user`, writing each verdict to a TSV as it
lands and skipping what the TSV already holds on restart. The first attempt
buffered everything to the end and was killed by its own 30-minute `timeout`,
losing ~1700 completed compiles for nothing.

## Log
- 2026-08-14 — resolved, commit PENDING-COMMIT.
