---
prio: 75
owner: frank-rust
---

# Pascal OOP corpus — real libraries that hammer classes/interfaces/generics

- **Type:** feature (umbrella — Pascal frontend validation)
- **Track:** P — tag: compat (FPC-parity on real OO code; see parallel-tracks.md)
- **Status:** working
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
| rtl-generics | — | — | [[feature-pascal-corpus-generics]] (rung 3, in `blocked/` on [[feature-pascal-builtin-tobject-class]]) |
| **fcl-passrc** | 60,696 | 40,477 LOC, fpcunit | [[feature-pascal-corpus-passrc]] (ENDGAME) |

> **Keep this column current.** The rtl-generics row said "not filed yet" for weeks
> while [[feature-pascal-corpus-generics]] existed and had already cleared 17 walls.
> It sat in `unfinished/`, which `ready`/`next` do not scan by design, so the ticket
> was invisible to the ranker AND to this index at the same time -- the two switches
> that normally cover for each other were both off, and a dispatch went out to file a
> duplicate. Update the row when a rung's ticket is filed, not when it is done.

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
- 2026-08-20 — rungs 1 (fpcunit) and 2 (fpjson) are GREEN and in `done/`. Rung 3
  (rtl-generics) is in `blocked/` on [[feature-pascal-builtin-tobject-class]]; that
  blocker is the actionable item, not this umbrella. Returned to `backlog/` — an
  umbrella has no work of its own, and holding it in `working/` takes the ranker's
  top slot away from the rung that does.
- 2026-08-20 — the ladder is STALLED, not merely blocked: rung 3's default pick
  (rtl-generics) waits on [[decide-tobject-root-methods-dispatch-model]] and rung 4
  is gated on rung 3. The one rung available without that answer is the **fcl-xml
  DOM** alternative this ticket already names (22k, roundtrip oracle) — but opening
  a 22k-LOC campaign to route around a pending decision is a scope call for the
  user, not something an agent should start on its own. Until either lands, this
  umbrella has no work despite ranking at 65.
- 2026-08-28 — **the 2026-08-20 stall note above is STALE in both of its clauses,
  and this umbrella has been heading Track P's ranked queue at p75 while its own
  body says it has no work.** Corrected by the coordinator:
  - [[decide-tobject-root-methods-dispatch-model]] was **answered by the user on
    2026-08-21** and is in `decided/`. It has not blocked anything for a week.
  - [[feature-pascal-builtin-tobject-class]] records itself *"unblocked
    2026-08-22 (the decide is answered and implemented)"*; only `UnitName` and
    `ClassInfo` remain.
  - Rung 3 [[feature-pascal-corpus-generics]] has moved to `unfinished/` and its
    remaining `blocked-by`, `gap-b-typinfo-ptypedata-has-no-ordtype-and-is-just-ptypeinfo`,
    **is in `done/`.** So rung 3 is fully unblocked and is the actionable item —
    the ladder is not stalled and has not been for days.
  - The fcl-xml route-around, opened as a scope call for the user, is therefore
    **moot** and should not be raised again on this ticket's authority.

  > **A stalled-because note ages into a false claim, and it ages invisibly.**
  > Every clause here was true when written. Nothing re-reads a stall note when
  > its blocker resolves, because resolving a blocker is an event on the
  > *blocker*, and the note lives on the dependent. This is the same missing-edge
  > family as a `blocked-by` pointing at a closed ticket — sixth instance found
  > on 2026-08-28 — except that prose is invisible to `progress.sh check`, which
  > only reads frontmatter. An umbrella that ranks above every rung it contains
  > and then tells the reader it has no work is the worst shape of it: the
  > ranker promotes it, and only a human who opens it learns it is empty.

## The "local FPC checkout" premise expired (coordinator, 2026-08-30)

**Every candidate in the table above is unbuildable on this box right now, and the
table is what hides it.** The sizes were "MEASURED 2026-07-12 against the local FPC
checkout"; that checkout is gone. Verified rather than assumed:

- `fpc` 3.2.2 and `ppcx64` are installed and working — the seed compiler is fine.
- `fp-units-fcl-3.2.2` is installed, so the fcl units exist as **compiled `.ppu`/`.o`**.
- **`fpc-source-3.2.2` is NOT installed**, so no `.pas` sources are on disk at all.
  `find / -type d -name fcl-xml` returns nothing.

So the corpus rungs need **source**, and the installed package ships **objects**. A
compiled unit is exactly the thing a corpus build cannot consume, and the distinction
is invisible from "FPC is installed", which is the check anyone would run.

This is why the top of the global ranked queue has sat at p75 with nothing moving:
`ready` correctly reports it unblocked, because the blocker is a host package rather
than a `blocked-by:` edge, and nothing in the ticket system can see a missing apt
package. Same class as
[[chore-b-no-cross-loader-on-this-host-blocks-the-dynlib-arm-run]] — host
provisioning, owner-only, no agent in any lane can close it.

**Unblock:** `apt install fpc-source-3.2.2` (20 MB download, 211 MB installed).
Surfaced to the owner 2026-08-30 together with the cross-gcc and cross-libc requests,
which are the same category.

Rungs 1-2 (`fpcunit`, `fpjson`) are in `done/` and were built when the checkout
existed, so their results stand — this does not retro-invalidate them. Rung 3
(`generics`) is in `unfinished/` owned by frankA with 17 walls cleared; rung 4
(`passrc`) is p30. The unfiled `fcl-xml` row remains unfiled **deliberately**: filing
a rung that cannot be built would put a fourth unactionable ticket into a queue whose
problem is already that its top is unactionable.

## RETRACTION: the FPC sources ARE on this box. My search was truncated. (coordinator, 2026-08-30)

**The section above is wrong and the apt package is not needed.** A complete FPC
source tree — 672 MB, `fcl-xml` included — is at:

```
/data/borg-rescue/home-rene/src/fpc-source/packages/
```

and per-clone corpora already exist at `~/pxx/library_candidates/` and
`~/frankB/library_candidates/` (absent from `~/frank-coordinator/`, which is why
this looked empty from here too). frankB and frank-rust have been compiling
`rtl-generics` out of them all afternoon, which is what exposed this.

**How the wrong conclusion was reached, because the mechanism is the point.** The
command actually run was:

```
find / -maxdepth 6 -type d -name fcl-xml      # returns nothing
```

The real path is **depth 7**. And the section above records it as
`find / -type d -name fcl-xml`, dropping the `-maxdepth` — **so the ticket states
a stronger claim than the command supports.** The search was truncated, its
silence was read as absence, and the truncation was then edited out of the record
without anyone intending to.

That is the exact error this session spent the afternoon correcting in five other
places — a `head` that hid the first error name, a float probe that only tested
the working path, a grep whose frame excluded the real allocator. **"Ask what your
instrument truncates" was written into the roster by the person who then failed to
ask it.** A depth limit is a truncation that returns success.

**What stands and what falls:**

- **FALLS:** "the corpus rungs are unbuildable on this box", "`apt install
  fpc-source-3.2.2` is the unblock", and the framing of this as host provisioning
  in the same class as [[chore-b-no-cross-loader-on-this-host-blocks-the-dynlib-arm-run]].
- **STANDS:** `fpc-source-3.2.2` is genuinely not installed as a package, and
  `fp-units-fcl` genuinely ships compiled `.ppu`/`.o` rather than `.pas`. Both true,
  both irrelevant — the sources arrive by another route.
- **STANDS:** the table's "MEASURED 2026-07-12 against the local FPC checkout"
  should still be re-measured against the tree named above rather than trusted.

**The `fcl-xml` rung is filable and buildable now.** Whoever takes it: point at
`/data/borg-rescue/home-rene/src/fpc-source/packages/fcl-xml`, or copy it into a
`library_candidates/` beside the other rungs as the existing corpora do.

---

## Rung 3 (fcl-xml DOM) — first wall cleared, second wall measured (frank-rust, 2026-08-30)

Source: `/data/borg-rescue/home-rene/src/fpc-source/packages/fcl-xml/src`, per
the coordinator's retraction above. Probe is `uses dom;` with a one-line body,
which pulls `xmlutils` and therefore `names.inc`.

| wall | status |
| --- | --- |
| 1. `property` in an `interface` (`IXmlLineInfo`) | **CLEARED** — [[bug-p-a-property-in-an-interface-declaration-is-rejected]], `0f0fd6642`. Two defects: the parse, and eleven copies of accessor dispatch that did not know an interface receiver needs `AN_INTF_CALL`. The parse fix alone compiles and then segfaults, so "the corpus got further" would have been a false green here. |
| 2. `const namingBitmap: array[0..$0C] of TSetOfByte` | **CLEARED** — [[bug-p-a-const-array-of-sets-is-rejected-as-too-many-elements]]. |
| 3. `PWideChar(Value)` cast, `xmlutils.pp:285` | **CLEARED under `PXX_WIDE_PAYLOAD`, deliberately REFUSED without it** — `5b31f4647`. Not a missing type: `var p: PWideChar` always declared fine, only the cast was absent. It is refused by default because on the UTF-8 payload it steps two bytes and yields packed byte pairs on plain ASCII (26984 for `PWideChar('hi')[0]` where FPC gives 104) — a NEW divergence, not an inherited one. |
| 4. `AllocMem`, `xmlutils.pp:478` (also `:589`, `:922`) | **CLEARED** — frankB, `3decbf0c4`, in `lib/rtl/sysutils.pas`. |
| 5. `"List": no such member`, `xmlutils.pp:760` | **OPEN**, not filed — `TList.List`, the internal pointer array. RTL gap, Track B. Reached only under `PXX_WIDE_PAYLOAD`. |

**The wide-payload gate is the real rung-3 blocker, and it is now measurable.**
Under `{$define PXX_WIDE_PAYLOAD}` this probe goes from `:285` to `:760` — 475
lines further — so the define is buying reach and costing nothing here. Getting
that number required fixing a bug that blocked the gate's own blast-radius
measurement: `builtinwide` is pulled by a token scan over the PROGRAM's tokens
only, so `{$define PXX_WIDE_PAYLOAD}` + `uses SysUtils` was a hard compiler
error from a four-line program. Fixed, and both measurements are recorded on
[[chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload]],
which is where the decision lives.

**I sized wall 2 wrong in this very table an hour earlier and the correction is
worth more than the entry.** It said the fix was "not a parser arm's worth of
work" because an array's static store had no element-init kind for a baked set
blob. Four lines of measurement said otherwise: `arr[i] := <set>` was already a
working assignment, so the whole fix was one arm plus one init kind. The estimate
came from grepping the init-kind table and seeing no set among {ordinal, string,
procaddr, classref, float} — a correct answer to "which kinds exist", read as an
answer to "what would this cost". Reading the mechanism tells you what is absent;
running it tells you what is needed, and here those differed.

Method note for whoever takes rung 3 next: probe with `uses <unit>;` and a
one-line body, and read the FIRST error only. Each wall's error names the include
file it is in (`in: names.inc`), which is the fastest handle on a 22k-line
package -- and do not treat a compile as a rung cleared, per wall 1.
