---
prio: 58
blocked-by: [feature-pascal-corpus-fpcunit]
---

# Pascal corpus: fcl-json — polymorphic TJSONData hierarchy + RTTI streaming

- **Type:** feature (Pascal frontend validation)
- **Track:** P — tag: compat
- **Status:** backlog — opened 2026-07-12.
- **Owner:** —
- **Parent:** [[feature-pascal-corpus-oop]]
- **Blocked-by:** feature-pascal-corpus-fpcunit

## Why this is the second landing (not passrc)
Right size to *converge*: **9,769 LOC src, 12,261 LOC of fpcunit tests** (measured
2026-07-12 against the local FPC checkout). Big enough to be real OOP, small enough that
walls arrive one at a time instead of ten at once.

OOP surface it forces:
- **Abstract base + polymorphic descendants** — `TJSONData` → `TJSONNumber` (int/int64/
  float) / `TJSONString` / `TJSONBoolean` / `TJSONNull` / `TJSONArray` / `TJSONObject`.
  Abstract methods, virtual property getters, `class of` factory dispatch, enumerators.
- **`fpjsonrtti.pp`** — object ⇄ JSON streaming **through RTTI** on published properties.
  This is the same machinery [[project RTTI→streaming→LFM]] needs, so the ticket doubles as
  a real-code gate on our RTTI.
- Owned-object lifetimes (containers freeing children), exception classes, `TFPList`/
  `TStringList` breadth.

And the **oracle is trivial and byte-exact**: parse → re-serialize → compare, on top of the
library's own assertion suite.

## Shape (verified 2026-07-12; local checkouts under /home/rene/src/fpc-source/packages and
/usr/share/fpcsrc/3.2.2/packages)
- `src/`: `fpjson.pp` (the hierarchy), `jsonscanner.pp`, `jsonparser.pp`, `jsonreader.pp`,
  `fpjsonrtti.pp` (streaming), plus `jsonconf`/`jsonini`/`json2yaml` (skip initially).
- `tests/`: `testjsondata.pp`, `testjsonparser.pp`, `testjson.pp` (driver), `testcomps.pp`,
  `tcjsonini.pp` — fpcunit suites.

## Plan
1. Vendor pinned fcl-json src + tests (PROVENANCE.md w/ FPC tag) via
   `tools/install_lib_candidates.sh`. Read-only vendor.
2. Compile `fpjson` + `jsonscanner` + `jsonparser` with `$(PXX_STABLE)`. Bring up the
   **hierarchy first, RTTI streaming second** — `fpjsonrtti` is a separate wall, park it if
   it cascades.
3. `make test-fpjson`: build `testjson` against our fpcunit, run `testjsondata` then
   `testjsonparser`. Add our own roundtrip host (parse a corpus of .json → re-emit → diff).
4. Each failure → minimal repro vs FPC → fix ONE in the owning lane → `bXXX` regression →
   land green.

## Acceptance
`make test-fpjson` green on `testjsondata` + `testjsonparser`; roundtrip host byte-exact on
a JSON corpus. `fpjsonrtti` streaming green, or split to a follow-up if it opens its own
RTTI cascade.

## Gate
Frontend/IR changed → `make test` + self-host byte-identical → `make stabilize && make pin`.

## Log
- 2026-07-12 — opened. Promoted ahead of [[feature-pascal-corpus-passrc]] (user call): passrc
  at 60k LOC would bang our head against too many walls at once.
