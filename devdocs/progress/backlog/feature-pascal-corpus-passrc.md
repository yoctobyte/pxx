---
prio: 45
blocked-by: [feature-pascal-corpus-fpcunit, feature-pascal-corpus-fpjson]
---

# Pascal corpus: fcl-passrc — ENDGAME. Deep class hierarchy + resolver (60k src, 40k tests)

- **Type:** feature (Pascal frontend validation)
- **Track:** P — tag: compat
- **Status:** backlog — **endgame, do LAST**. Opened 2026-07-12.
- **Owner:** —
- **Parent:** [[feature-pascal-corpus-oop]]
- **Blocked-by:** feature-pascal-corpus-fpcunit feature-pascal-corpus-fpjson

## Sequencing (user call, 2026-07-12)
**Not the first candidate.** At 60k LOC of source over a 200-class hierarchy, bring-up would
hit a dozen unrelated walls simultaneously and give no clean bisect signal — you cannot tell
a metaclass bug from a refcount bug from an RTL gap when they all fire in the same build.
Land the small ones first ([[feature-pascal-corpus-fpcunit]], then
[[feature-pascal-corpus-fpjson]]) so the OOP surface is already shaken out, then come here
for the depth. Re-rate `prio:` upward once those are green.

## What it is (verified 2026-07-12, do not re-derive)
`fcl-passrc` is **NOT** the FPC compiler's internal parser. It is a **standalone library**
(`packages/fcl-passrc`) that parses Pascal source into an AST and resolves it — used by
fpdoc, pas2js (it is pas2js's actual frontend), and conversion tools. The compiler proper
has its own separate scanner/parser under `compiler/`. So passrc has **no coupling to
compiler internals** — it is a consumable library, text in, AST out.

Local checkouts: `/home/rene/src/fpc-source/packages/fcl-passrc` and
`/usr/share/fpcsrc/3.2.2/packages/fcl-passrc`.

Sizes (`src/`, 60,696 LOC total):

| unit | LOC | what |
| --- | --- | --- |
| `pasresolver.pp` | 29,660 | name/type resolution — the monster |
| `pparser.pp` | 7,823 | recursive-descent parser |
| `pasresolveeval.pas` | 6,004 | const evaluation |
| `pastree.pp` | 5,947 | **the AST class hierarchy** (~200 classes, refcounted) |
| `pscanner.pp` | 5,333 | lexer + directives |
| `pasuseanalyzer.pas` | 3,296 | reachability analysis |
| `paswrite.pp` | 1,584 | AST → source (roundtrip oracle!) |
| `pastounittest.pp`, `passrcutil.pp` | 1,049 | extras |

Its own suite (`tests/`, **40,477 LOC**, fpcunit, driver `testpassrc.lpr`):
`tcresolver.pas` (18,649) · `tctypeparser` (3,681) · `tcuseanalyzer` (3,478) ·
`tcresolvegenerics` (2,889) · `tcclasstype` (2,143) · `tcstatements` (1,903) ·
`tcscanner` (1,825) · `tcprocfunc` (1,399) · `tcexprparser` (1,323) · `tcbaseparser` (925) ·
`tconstparser` (679) · `tcpassrcutil` (422) · `tcmoduleparser` (408) · `tcvarparser` (388) ·
`tcgenerics.pp` (365). Assertion-based — **oracle is built in, no FPC needed at run time**.

## Why this one first
Densest OOP-per-line in the survey and structurally the *right* kind: deep inheritance
(`TPasElement` → everything), abstract + virtual dispatch on every node, manual refcounting
(`AddRef`/`Release`) on an object graph, visitor traversal, class-typed maps/lists,
`class of` metaclass construction. It is also **deterministic and text-shaped**: parse a
file, `paswrite` it back, diff → a cheap end-to-end oracle independent of the test suite.

## Plan
1. Vendor pinned `fcl-passrc` src + tests (PROVENANCE.md w/ FPC tag/commit) via
   `tools/install_lib_candidates.sh`. Read-only vendor; never fork the source.
2. Compile `src/` with `$(PXX_STABLE)`. Bring-up in dependency order:
   `pscanner` → `pastree` → `pparser` → `pasresolveeval` → `pasresolver`.
   Expect walls in: class-hierarchy breadth, `class of` / virtual class methods, refcounted
   object graphs, `TFPList`/`TStringList` breadth, sets of enums, nested types.
3. First runnable milestone (before the suite): a ~40-line host that parses a Pascal file
   and `paswrite`s it back. Feed it **our own compiler sources** and diff the roundtrip —
   self-referential and free.
4. Then `make test-passrc`: build `testpassrc` against our fpcunit and run the suite.
   Start with `tcscanner` + `tcbaseparser`, widen to `tctypeparser`/`tcclasstype`, and treat
   `tcresolver` + `tcresolvegenerics` as the endgame.
5. Each failure → minimal repro vs FPC → fix ONE in the owning lane → `bXXX` regression →
   land green.

## Acceptance
`make test-passrc` green on scanner + parser + classtype + typeparser groups; roundtrip host
reproduces its input on our own sources. Resolver groups tracked as a follow-up if they
cascade.

## Gate
Frontend/IR changed → `make test` + self-host byte-identical → `make stabilize && make pin`.

## Log
- 2026-07-12 — opened, split out of [[feature-pascal-corpus-oop]]. Sizes + shape verified
  against the local FPC checkout.
