---
summary: "tstate: xeon's red set is PART missing-corpora and PART a real i386 regression of mine (now reverted) — the corpora half still stands"
type: bug
track: T
prio: 50
---

# xeon's red set looks like missing corpora, not a code regression

- **Type:** bug (test infrastructure — **Track T**, whose host and tstate this is)
- **Opened:** 2026-07-31 by Track B, after `gate.sh check` reported
  `open CASCADE: 17 jobs` and I checked whether my day's `lib/crtl` work caused it.

## What tstate says

`devdocs/progress/tstate/TSTATE.md` reports a **CASCADE of 17 jobs** on xeon,
`bad=110774a14648`, `last good unknown`. Two things make that summary
misleading, and both are worth fixing in the reporting itself:

1. **The blamed commit is a tstate bookkeeping commit** —
   `tstate(borg): opt f2f1a3a9add8 done` — which touches only
   `devdocs/progress/tstate/`. It cannot break code. With `last good unknown`
   the bisect never established a baseline, so the attribution is noise.
2. **The job list in TSTATE.md does not match `xeon.json`.** TSTATE.md lists
   test-core entries (tk `.npy`, `test_c_gtk*`, `sqlite_crud*`,
   `cprintf_ll_b252.c`, …). `xeon.json` lists a different 18. Something is
   summarising a stale or wrong set, which cost me an hour chasing the wrong
   files.

## The actual 18 (from xeon.json: 1629 jobs, 18 failing)

```
fpc-bootstrap#src:compiler/compiler.pas          <- pre-existing, another lane
test-asm#src:test/test_asm_so.asm
test-c-conformance-i386#shard0,1,2/6
test-c-conformance-riscv32#shard0..5/6           <- all six
test-c-conformance-arm32#shard2/6
test-lua-cross#src:test/lua/runner.c
test-sqlite-threads-{x86_64,i386,arm32,aarch64}#src:tools/run_sqlite_thread_test.sh
test-zlib#src:tools/install_lib_candidates.sh
```

## Why this reads as missing corpora rather than a regression

**Every one of those job families needs a GITIGNORED fetched tree**, and the
files tstate blames are the fetch/run SCRIPTS, not any source that changed:

| job | needs |
| --- | --- |
| test-c-conformance-* | `library_candidates/c-testsuite` |
| test-lua-cross | `library_candidates/lua` |
| test-zlib | `library_candidates/zlib` — blamed on `install_lib_candidates.sh` |
| test-sqlite-threads-* | `library_candidates/sqlite` — blamed on `run_sqlite_thread_test.sh` |

`.gitignore` excludes both `external/` and `library_candidates/`, so a fresh
clone has none of them. A host that has never run
`tools/install_lib_candidates.sh` fails exactly this set and passes the other
1611 jobs — which is what xeon shows.

## CORRECTION: NOT ruled out — part of it WAS mine (2026-07-31, same day)

The section below is wrong and is kept so the mistake is visible. Running the
i386 conformance locally, which was still in flight when this was filed, gave
**215 pass, 4 fail** — and an A/B against my own commits was decisive:

| lib/crtl at | 00206 | 00211 | 00212 |
| --- | --- | --- | --- |
| before my crtl work (`4d9bf3f8a`) | 0 | 0 | 0 |
| after `780506d85` (div/ldiv/lldiv/llabs) | — | **92** | — |
| after `ea07b041c` (sscanf widths, %#o) | — | **140** | — |

So I caused a real cross-target regression, and the "my crtl is byte-identical
to gcc on i386" evidence below was true but IRRELEVANT — it tested the new
functions, not their effect on everything else.

The shape is worse than a bug in those functions. `00211.c` never calls any of
them: it is `printf("n+1 = %d\\n", n+1)` with an implicit `return 0`. Its OUTPUT
stays correct and only the EXIT CODE goes wrong (0 -> 60/92/140). And reverting
`stdlib.c` alone did not fix it — the `stdio.c` change triggers it
independently. Two unrelated additions both break it, which says **crtl growing
at all** disturbs something on i386, not that either function is faulty.
That is a latent 32-bit codegen or link bug — filed separately as
[[bug-c-i386-crtl-growth-corrupts-main-exit-code]].

Master is restored: `lib/crtl` and `test/crtl_libc_oracle.c` are back at
`aa3f561a7` (keeping errno.h and strnlen, which are i386-clean), so the four
tests exit 0 again. The reverted work — div/ldiv/lldiv/llabs and the sscanf
width fix — is real and wanted, and goes back in once the i386 bug is fixed.

## Ruled out on the Track B side (WRONG — see the correction above)

I checked whether my 2026-07-31 `lib/crtl` work (errno.h, `strnlen`,
`div`/`ldiv`/`lldiv`/`llabs`, the `vsscanf` width rewrite, `%#o`, `%.0d`) caused
it, because C cross targets are exactly what it would break and `gate.sh lib`
does not cover them:

- I touched **no `compiler/**` file** — every compiler change today is the
  Track N agent's `feat(nilpy)`/`fix(nilpy)` work. So `selfhost-fixedpoint` and
  `fpc-bootstrap` cannot be mine; nothing in `lib/` affects them.
- The additions compiled `--target=i386` and run under `tools/run_target.sh`
  produce output **byte-identical to gcc** — `lldiv` on a near-`INT64_MIN`
  numerator, `div`, `llabs`, `strnlen`, and a `sscanf` with `%3d`/`%4s` widths.
- A full `--target=i386` c-conformance run was still in flight when this was
  filed; if it comes back red the conclusion above changes and this ticket
  should be updated rather than believed.

## What would settle it

On xeon: `tools/install_lib_candidates.sh` for c-testsuite, lua, zlib and
sqlite, then re-run. If the 16 corpus jobs go green, the remaining two
(`fpc-bootstrap`, `test-asm`) are the real signal and deserve their own bisect.

## Worth fixing regardless

A job that cannot run because its corpus is absent should report **SKIP**, not
`fail` — `make test-cjson`/`test-lua` already skip cleanly when the tree is
missing, so the cross jobs are inconsistent with that. Reporting absent-input as
failure is what turned a setup gap into an 18-job "cascade" with a bisect
pointing at a bookkeeping commit.
