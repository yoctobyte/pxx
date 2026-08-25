---
track: P
prio: 55
type: feature
blocked-by: []
summary: "Pascal corpus rung 2 — real FPC 3.2.2 `fgl.pp` (the reference RTL's generic-container unit) as a wired, oracle-checked corpus target. Landed 2026-08-25: fetcher, runner, 7 drivers, skip list. Baseline 3 pass / 4 known-fail. Replaces a check that had silently printed `SKIP (no fpcsrc)` on every box without a system FPC source tree."
status: backlog
owner: —
---

# Pascal corpus rung 2 — fgl (real FPC generic containers)

- **Type:** feature (frontend corpus rung) — tag: compat
- **Track:** P (frontend walls); the wiring itself is Track B-shaped (build with
  the compiler, assert output) but the burn-down is all Pascal frontend.
- **Parent:** [[feature-pascal-corpus-expansion]]
- **Landed:** 2026-08-25

## What this rung is

`rtl/objpas/fgl.pp` is FPC's generic-container unit — `TFPSList`,
`TFPGList<T>`, `TFPGObjectList<T>`, `TFPGInterfacedObjectList<T>`,
`TFPGMap<K,V>`, `TFPGMapObject<K,V>`, plus their enumerators. ~2,000 lines of
real, widely-used library source that leans on generics × classes ×
interfaces × pointer-level container plumbing all at once. It is the smallest
piece of real Object Pascal that exercises that intersection, which is why it
sits directly above the FPC conformance sweep on the ladder.

## Why it needed doing (the inversion)

fgl was already named as a compat target and there was already a driver,
`test/test_fgl_use.pas`, wired into `test-core`. But its guard was:

```make
@if [ -d /usr/share/fpcsrc/3.2.2/rtl/objpas ]; then ... \
else echo "fgl(real FPC source): SKIP (no fpcsrc)"; fi
```

`/usr/share/fpcsrc` is a distro FPC-source package that is **not installed on
the dev box, the watcher box, or in a fresh clone**. So the flagship
FPC-compatibility check had been printing `SKIP (no fpcsrc)` and passing —
green, and measuring nothing. Nothing fetched the FPC RTL sources either; the
installer fetched FPC's *test suite* from a pinned commit but not its *RTL*.

## What landed

1. **Fetcher** — `tools/install_lib_candidates.sh fpc-rtl`: sparse
   `rtl/objpas` + `rtl/inc` + `LICENSE` from the **same pinned FPC commit** the
   testsuite fetch already used (`0d122c49…`, `release_3_2_2`), into the
   gitignored `library_candidates/fpc-rtl/`, with `PROVENANCE.md`. Also added to
   `all`.
2. **Drivers** — `test/fgl/*.pas`, one per container:
   `fpslist`, `list_int`, `list_str`, `map_int`, `map_str`, `objectlist`,
   `ifclist`.
3. **Oracle** — `test/fgl/*.expected`, produced by compiling **those same
   drivers against that same `fgl.pp` with FPC 3.2.2 itself**. All seven build
   and run correctly under FPC, so every red below is a pxx gap and never a bad
   driver. Note the exact claim: this is *behavioural* parity with the reference
   compiler on real library code. It says nothing about the machine code we
   emit — see the claims-discipline section of `CLAUDE.md`.
4. **Runner** — `tools/run_fgl_corpus.sh [compiler] [objpas-dir]`, modelled on
   `tools/run_c_conformance.sh`: self-skips loudly when the tree is absent
   (falling back to a system `fpcsrc` if one happens to exist), honours
   `test/fgl/pxx.skip` (`name.pas<TAB>reason`, every entry naming its ticket),
   prints `test-fgl: PASS/FAIL/SKIP`.
5. **Make target** — `test-fgl`, spelling out `library_candidates/fpc-rtl` so
   testmgr's `CORPUS_RE` sees it and the job self-skips loudly rather than
   silently greening. `test-core`'s inline check now prefers the fetched tree,
   so it runs everywhere instead of skipping.

## Baseline 2026-08-25 (pxx VERSION 374 / self-hosted HEAD): 3 pass, 4 known-fail

| driver | state | wall |
| --- | --- | --- |
| `fpslist` | **PASS** | — |
| `list_int` | **PASS** | — |
| `map_int` | **PASS** | — |
| `list_str` | red | [[bug-p-a-string-typecast-is-a-conversion-and-not-a-cast]] (fgl.pp:892) |
| `map_str` | red | same ticket (fgl.pp:1602) |
| `objectlist` | red | [[bug-p-inherited-ignores-the-parents-default-parameter-values]] (fgl.pp:1061) |
| `ifclist` | red | [[bug-p-a-cast-as-lvalue-does-not-accept-a-builtin-type-name]] (fgl.pp:1189) |

**Three tickets unlock four of the seven drivers**, and each is a narrow
double-case defect where the sibling path already works — the shape
`devdocs/dev/normalise-dont-special-case.md` describes. Two of them
(`String(…)` as a cast, `inherited` + defaults) are between them what stops
*string-keyed containers* and *the standard owning-container constructor
idiom* — i.e. most of what real Object Pascal code does with fgl.

Also found while bringing this up, filed separately because it is not an fgl
wall: [[bug-p-stray-tokens-in-a-unit-declaration-section-are-silently-skipped]]
and [[bug-p-a-diagnostic-in-a-used-unit-names-the-wrong-source-file]].

## Not done here

- **testmgr / twatch enrolment** — `test-fgl` is not in any tier and `fpc-rtl`
  is not in `twatch.py`'s `CORPUS_EXPECTED`. Those are Track T files; filed as
  [[task-t-enrol-the-fgl-corpus-rung]].
- The burn-down: remove a `pxx.skip` line as each ticket lands and the runner
  starts enforcing that driver.

## Gate
`make compiler/pascal26` (self-host fixedpoint) + `tools/run_fgl_corpus.sh
./compiler/pascal26` + `tools/gate.sh quick`.

## Links
Parent: [[feature-pascal-corpus-expansion]] · mechanism copied from
[[feature-c-corpus-expansion]] / `tools/run_c_conformance.sh`
