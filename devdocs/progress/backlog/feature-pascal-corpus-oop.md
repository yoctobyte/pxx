---
prio: 60
---

# Pascal OOP corpus — real libraries that hammer classes/interfaces/generics

- **Type:** feature (umbrella — Pascal frontend validation)
- **Track:** P — tag: compat (FPC-parity on real OO code; see parallel-tracks.md)
- **Status:** backlog — opened 2026-07-12 (user request).
- **Owner:** —
- **Unblocks:** the whole OO surface's credibility (RTTI, streaming, generics×classes)

## Why
The self-host gate compiles the compiler, and the compiler is written in a **thin,
deliberately procedural Pascal subset** — records, arrays, plain procedures. It exercises
almost **zero OOP**: no deep inheritance chains, no virtual/abstract dispatch storms, no
interfaces, no generic classes, no RTTI, no `TPersistent`/streaming. So the class system
(pinned features from v175's class-system batch onward) is currently guarded only by our
own small tests. A real, non-GUI, OOP-dense corpus is the missing gate.

Requirements for a candidate: **non-GUI**, self-contained (no DB/X11/network), OOP-dense,
and ideally **ships its own test suite** so the oracle is built in (the duktape/tcc shape —
see [[feature-c-corpus-duktape]]).

## Sizing rule (user call 2026-07-12)
**Climb the ladder by size, smallest first.** A 60k-LOC library hits a dozen unrelated walls
in the same build and you cannot tell a metaclass bug from a refcount bug from an RTL gap.
Small library = walls arrive one at a time = clean bisect signal. Depth comes last, once the
OOP surface is already shaken out.

## Candidates (sizes MEASURED 2026-07-12 against the local FPC checkout)

| lib | src LOC | own tests | ticket |
| --- | ---: | --- | --- |
| **fcl-fpcunit** | 5,089 | `tests/` + `exampletests/` | [[feature-pascal-corpus-fpcunit]] |
| **fcl-json** | 9,769 | 12,261 LOC, fpcunit | [[feature-pascal-corpus-fpjson]] |
| fcl-xml (DOM/SAX) | 21,753 | yes | — not filed yet |
| rtl-generics | — | — | — not filed yet |
| **fcl-passrc** | 60,696 | 40,477 LOC, fpcunit | [[feature-pascal-corpus-passrc]] (ENDGAME) |

Rung 1 — **fpcunit** (5k). Test framework = OOP by construction: `TTestCase` inheritance,
`TTestSuite` composite, `ITestListener` interfaces, exception classes, and **RTTI method
enumeration** to discover `Test*` methods. It is also the *harness* every other FPC library's
suite is written against → landing it unlocks every rung above it. Cheapest, highest leverage.

Rung 2 — **fpjson** (10k src / 12k tests). Abstract base + polymorphic descendants
(`TJSONData` → number/string/bool/null/array/object), `class of` factory dispatch, owned-child
lifetimes — plus `fpjsonrtti.pp`, object ⇄ JSON **streaming through RTTI**, which is the same
machinery [[project RTTI→streaming→LFM]] needs. Byte-exact roundtrip oracle.

Rung 3 — reassess. Likely **rtl-generics** (`Generics.Collections`: generic classes +
`IComparer<T>`/`IEqualityComparer<T>` + class constraints — the generics × classes ×
interfaces intersection nothing else touches) or **fcl-xml DOM** (22k, `TDOMNode` tree,
roundtrip oracle). Also on the shelf: `TPersistent`/`TCollection`/`TStream` from `classes` +
`contnrs`.

Rung 4 (endgame) — **fcl-passrc**. The deep structural workout: ~200-class `TPasElement`
hierarchy, abstract/virtual dispatch on every node, manual refcounted object graph, visitors,
metaclass construction; `paswrite` gives a source-roundtrip oracle. Only after 1–3 are green.

Not now:
- **BESEN** (ECMAScript engine, Object Pascal, non-GUI): enormous class/interface use, a GC,
  virtual dispatch in hot loops, Delphi-ish dialect. Real prize, but same too-many-walls
  problem as passrc — revisit after the ladder.
- **DWScript** core: huge OOP + generics + interfaces, has a suite. Later.
- **mORMot 2**: enormous OOP/RTTI but asm-laden and Delphi-first → high pain, low signal.
- **Spring4D**: DI container, extreme interfaces/generics/attributes; Delphi-only idioms —
  likely a wall, not a test.

## Plan
Climb rungs 1 → 4 in order, one at a time. Each library follows the corpus loop: vendor
pinned source (PROVENANCE.md), compile with `$(PXX_STABLE)`, run its own suite, reduce each
failure to a minimal repro vs FPC, fix ONE in the owning lane, add a `bXXX` regression, land
green. Re-rate the next rung's `prio:` upward when the current one goes green.

## Gate
Per sub-ticket. Frontend/IR changed → `make test` + self-host byte-identical →
`make stabilize && make pin`.

## Log
- 2026-07-12 — opened. Candidate survey done; passrc + fpcunit picked as the first landing.
