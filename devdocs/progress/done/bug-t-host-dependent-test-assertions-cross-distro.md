---
summary: "Watcher and dev boxes run different distros, so tests that bake in host state (library versions, allocator behaviour, the host CPython) go permanently RED on the watcher while passing locally — and read as watcher bugs"
type: bug
track: T
prio: 70
status: done
owner: claude@xeon
---

# Host-coupled test assertions produce permanent, misleading REDs

- **Type:** bug (Track T triage + an audit) — **Track T**
- **Opened:** 2026-08-01, immediately after one instance of this cost three
  wrong diagnoses.
- **T owns the TRIAGE RULE and the audit; each individual test fix is filed
  into the owning lane** (the precedent below was a Track N fix). This ticket is
  not a licence for T to edit other lanes' tests.

## The setup that makes this bite

| box | distro |
| --- | --- |
| dev | Ubuntu 24.04 |
| `xeon` (watcher) | Ubuntu 26.04 |
| arm32/arm64 rPis (planned) | Raspberry Pi OS |

Different distro ⇒ different system library versions, different **glibc**
(so different malloc behaviour), different system CPython. Any assertion coupled
to those is green on the box it was written on and red forever elsewhere.

## Proven instance (fixed, e867b9af6)

`test_nilpy_import_sqlite` asserted `= "3045001"` — that is sqlite **3.45.1**,
the authoring box's version, since the test prints
`major*1000000 + minor*1000 + patch` of the *host's* libsqlite3.

It was the single STILL-RED entry in xeon's reports across many shas, and it was
diagnosed as a **phantom twice** (first as the full-tier job-status eviction
bug, then as generic watcher noise) before the distro difference was guessed.
Fixed by asserting the SHAPE (any well-formed `3.x.y`) rather than the value —
what the test exists to prove is that `import sqlite3` resolves the C header,
links `libsqlite3.so.0` and calls it.

## The triage rule this should install

**Green on the dev box, red on the watcher ⇒ suspect HOST COUPLING FIRST**, ahead
of "watcher bug" and well ahead of "compiler bug". The failure looks exactly
like a watcher fault, which is why it survived so long.

The tell, and it is cheap to check: **read the log tail.** If the compile line
is `ok: ...`, the build succeeded and the failure is the OUTPUT COMPARISON — so
the question is what the expected value depends on, not what the compiler did.
In the sqlite case that `ok:` was visible in every single report and was walked
past each time.

## Audit — flagged, NOT yet verified

A scan for the same family found no other hard-coded host *version* literals and
no `/usr`/`/lib` paths in assertions. `sqlite3` appears to have been the only
test importing a genuine system shared library. Two residual risks remain, both
**hypotheses to check, not known breakage**:

1. **Allocator-behaviour assertions.** `Makefile` asserts exact values
   `= "640000"`, `= "396000"`, `= "770000"` for leak/RSS-shaped tests. These are
   malloc-behaviour numbers and 24.04 → 26.04 is a glibc bump. If they red on
   xeon they want tolerance bands, not exact equality — same treatment as
   sqlite, same reason.
2. **cpyext tests versus the host CPython.** `test_cpyext_markupsafe.npy` and
   siblings verify byte-identical output against the box's *actual* CPython.
   That coupling is deliberate and is the strength of those tests, but it is
   host-version-dependent by construction and will diverge across distros.

Good existing pattern to copy: the Tk test (`Makefile:6608`) guards with
`command -v xvfb-run` and an `[ -e ... ]` check before running at all.

## Why this is worth doing before the rPis land

Each new distro multiplies this surface, and the planned arm boxes add a third
(see [[feature-t-host-roles-native-vs-qemu-topology]]). In the fast-loop model a
permanent RED is worse than a missing test: it is noise that masks real
regressions and burns triage time on every cycle.

## Gate

The two flagged families are checked on xeon (not reasoned about). Anything
host-coupled is either made shape-based/tolerant or explicitly gated on the
dependency being present, and the triage rule lands in the Track T notes.

## Log
- 2026-08-03 (`claude@xeon`) — audit done ON xeon (26.04), not reasoned about;
  the triage rule landed in `devdocs/dev/track-t.md`. Both flagged families are
  **false alarms**, and the ticket's own framing of them was wrong in an
  instructive way.

  **Family 1 — "allocator-behaviour assertions".** `= "396000"` and
  `= "770000"` are not malloc numbers: the recipes generate a Pascal program of
  180 and 350 statements summing 2200 per statement, so the assertions are the
  program's own arithmetic. `= "640000"` is a raise count the NilPy program
  prints. Compiled and run here at HEAD: 396000, 770000, 640000 — exact, and
  host-independent by construction. The one genuine memory assertion sits
  beside 640000 and was already both tolerant (`RSS > 90000` KB) and guarded
  (`[ -x /usr/bin/time ]`); measured 75308 KB on 26.04, comfortably inside the
  band the ticket quotes as ~75 MB fixed / ~105 MB pre-fix.

  **Family 2 — "cpyext vs the host CPython".** No host CPython is involved at
  all. The tests compile vendored, unmodified extension sources (MarkupSafe
  3.0.3, Cython 3.2.9 output) against pxx's OWN `lib/cpyext/include/Python.h`
  and `lib/cpyext/src/pyruntime.c`, with `Py_LIMITED_API` pinned in the recipe.
  `ldd` on the built `test_cpyext_markupsafe` binary says *not a dynamic
  executable* — it links nothing, let alone libpython. Output matches byte for
  byte here. The coupling the ticket feared exists only at AUTHORING time, in
  the vendored sources, which are in-tree and versioned.

  **What the audit changes about the rule.** "Looks like a host version
  literal" is a weak oracle — it is what produced both false alarms. The strong
  one is `ldd` (or, equivalently: does the test reach outside the repo at
  runtime?). The proven instance passes that test — `test_nilpy_import_sqlite`
  really does link `libsqlite3.so.0` — and both suspects fail it. The rule as
  written now leads with the log tail and the compile line, then `ldd`, then
  shape-vs-exact.

  **Corroborating evidence, not just inspection:** xeon's last full tier
  (1c8df90, 2026-08-03) is GREEN with all five cpyext jobs and
  `test_nilpy_exception_no_leak` passing, and a fresh scan for host version
  literals and `/usr`/`/lib` paths in assertions found nothing beyond the
  already-fixed sqlite one (only its explanatory comment remains).

  Nothing to change in the tests, so no lane fixes are filed. The residual risk
  the ticket names — each new distro multiplies the surface — is real but
  belongs to [[feature-t-host-roles-native-vs-qemu-topology]] when the rPis
  land; the rule above is what makes that cheap.
- 2026-08-03 — resolved, commit PENDING-COMMIT.
