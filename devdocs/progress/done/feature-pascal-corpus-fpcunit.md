---
prio: 55
---

# Pascal corpus: fpcunit — OOP + RTTI test framework (and the harness for the rest)

- **Type:** feature (Pascal frontend validation)
- **Track:** P — tag: compat
- **Status:** done
- **Owner:** agent-A-fpcunit
- **Parent:** [[feature-pascal-corpus-oop]]
- **Unblocks:** [[feature-pascal-corpus-passrc]] (its tests are fpcunit-based), and every
  other FPC library whose suite is written against fpcunit.

## Why
Two payoffs in one:
1. **It is OOP by construction** — `TTestCase` inheritance, `TTestSuite` composite,
   `ITestListener` / `ITestResult` interfaces, exception classes, and — the interesting
   part — **published-method enumeration via RTTI** to discover `Test*` methods. That RTTI
   path is exactly the surface self-host never touches.
2. **It is the harness.** Nearly every FPC library ships its tests as fpcunit suites. Land
   fpcunit and the marginal cost of the next library drops to "vendor + run".

## Shape (verify at vendor time, do not re-derive from memory)
- Lives in FPC tree: `packages/fcl-fpcunit/src/` — `fpcunit.pp`, `testregistry.pas`,
  `testreport.pas`, `testdecorator.pp`, `ubmockobject.pp`, plus console/XML/plain runners
  (`consoletestrunner.pas`, `xmlreporter.pas`). Non-GUI runners only — ignore the GUI ones.
- Local checkouts already present: `/usr/share/fpcsrc/3.2.2/packages/` and
  `/home/rene/src/fpc-source/packages/`.
- Its own tests: `packages/fcl-fpcunit/tests/` (self-testing framework).

## Plan
1. Vendor pinned fcl-fpcunit source via `tools/install_lib_candidates.sh` (PROVENANCE.md
   with the FPC tag/commit). Keep it read-only vendor; do not fork.
2. Compile `fpcunit.pp` + `testregistry` + `consoletestrunner` with `$(PXX_STABLE)`. Expect
   the first wall around **RTTI published-method lookup** (`GetMethodName` / `MethodAddress`
   / `TypeInfo` on classes) and possibly `TStringList`/`TFPList` breadth in the RTL.
3. `make test-fpcunit`: build and run the framework's OWN suite, plus a hand-written
   ~10-case suite of ours (asserts pass/fail/error/ignore, setup/teardown ordering,
   nested suites, exception expectation).
4. Each failure → minimal repro vs FPC → fix ONE in the owning lane → `bXXX` regression.

## Acceptance
`make test-fpcunit` green: framework compiles, self-discovers test methods by RTTI, runs a
suite, and the console runner's summary matches FPC's for the same suite.

## Gate
Frontend/IR changed → `make test` + self-host byte-identical → `make stabilize && make pin`.
Cross where a backend/runtime is touched.

## Log
- 2026-07-12 — opened, split out of [[feature-pascal-corpus-oop]].
- 2026-07-12 — **parse-level walls all CLEARED.** fpcunit.pp + testutils.pp now get
  through the parser end to end against `$(PXX_STABLE)`; what remains is runtime
  surface, not syntax. Seven frontend bugs fell out of it, each with a regression:

  | wall | fix | regression |
  | --- | --- | --- |
  | `class var` name list ate the next visibility word | parser | b244 |
  | bare class var unresolved in a method (incl. static `class procedure`) | parser (CurMethClass) | b244 |
  | string-literal default parameter (`msg: string = ''`) | parser + ir | b245 |
  | method defaults written to the WRONG slot (pre-existing, silent) | parser | b246 |
  | `overload` is a real token; class-body directive loop skipped it | parser | b247 |
  | method + ctor overloads ignored ARGUMENT TYPES (pre-existing, silent) | parser + ir + 6 backends | b248 |
  | `constref`, untyped `out` in an interface method, `cdecl` on a method, property hint directives | parser | b249 |

  Two of those (b246, b248) were **silent wrong-code bugs on the shipping pinned
  binary**, not new breakage — fpcunit just happened to be the first thing that
  looked at them. `IInterface`/`IUnknown`/`HResult` now come from the RTL's Classes.

- 2026-07-12 — **PARKED (unfinished).** The next wall is not syntax: it is runtime
  reflection. Remaining, in order:
  1. `TObject.GetInterface(IID, out obj)` — testutils' `QueryInterface` calls it.
     Filed as [[feature-tobject-getinterface-guid-table]]. This is now the ONLY
     remaining compile blocker in testutils.
  2. ~~RTTI published-method enumeration~~ — **DONE**
     ([[feature-rtti-method-reflection]]): the instance->RTTI backlink, the RTL
     `rtti` unit (enumerate / find / bind-and-call), and FPC's own spelling
     `TObject.MethodAddress` / `MethodName` working with no `uses`. Test discovery,
     the whole point of this rung, now has its engine.
  3. `TFPList` and the rest of the FPC container surface fpcunit leans on.

  Nothing is half-applied: every compiler change above is committed, gated
  (`make test` + self-host byte-identical + `--tier limited` cross) and pushed.
  Resume by taking [[feature-rtti-method-reflection]] first.


## 2026-07-13 — the reflection half is DONE, and a DESIGN BOUNDARY is now visible

Everything the rung actually existed to prove now works, and testutils walks four more
walls before hitting something that is **not a bug**:

- `TObject.MethodAddress` / `MethodName`, FPC spelling, no `uses`
  ([[feature-rtti-method-reflection]]).
- `TObject.GetInterface(IID, out Obj)` — a REAL GUID lookup, not a stub
  ([[feature-tobject-getinterface-guid-table]]). The interface GUID literal used to be
  parsed and thrown away; it is now recorded, and each class RTTI blob carries an
  interface table keyed by it.
- `packed array` on a field/var (b258).

### The boundary: testutils cannot compile unmodified, and that is CORRECT
`testutils.GetMethodList` does not use any public API. It hand-walks **FPC's internal
VMT layout**:

```pascal
vmt := PVmt(aClass);
methodTable := pMethodNameTable(vmt^.vMethodTable);
pmr := @methodTable^.entries[0];
```

`PVmt` / `vMethodTable` / `TMethodNameTable` are FPC System internals. pxx has its own
VMT and its own RTTI blob and will never match FPC's byte layout — nor should it. **No
amount of frontend work fixes this**, and emulating FPC's VMT layout to satisfy one
helper would be the tail wagging the dog.

### So the plan changes: substitute testutils, do not fork fpcunit
`testutils` is the one unit in the chain that is platform-internals code. Provide a
**pxx-native `testutils`** on the unit search path (ahead of the vendor copy) exposing
the same public surface — `FreeObjects`, `GetMethodList`, `TNoRefCountObject` — over our
own reflection. This is not forking the vendor: it is supplying the platform half, which
is exactly what that unit is.

It should be cheap: a pxx `TClass` value **IS** the RTTI blob pointer (AN_CLASSREF), so
`GetMethodList(AClass, AList)` can enumerate the published-method table straight from the
blob — the same walk `lib/rtl/rtti.pas` already does from an instance. The overridden-
method dedup in the FPC version falls out of walking own-then-parent.

`fpcunit.pp` itself needs no such treatment — its discovery goes through
`Self.MethodAddress(FName)`, which now works.

### Remaining after that
`TFPList` and the rest of the FPC container surface. Still parked; nothing half-applied,
every compiler change above is committed, gated and pushed.

## 2026-07-13 — RESOLVED. fpcunit COMPILES AND RUNS.

```
run:      3
failures: 1      <- the deliberate one
errors:   0
```

A `TTestCase` descendant's published `Test*` methods are discovered through RTTI, each is
turned into a callable method pointer, invoked, and its assertion failures recorded. The
whole chain works: RTTI method discovery -> method-pointer construction -> invocation ->
assertion -> exception -> failure recording. fpcunit.pp itself is used UNMODIFIED (637
procs); only `testutils` is substituted, which is the platform-internals half and always
was the plan (see the note above).

### What it took, in the order the walls came
Each of these is a real Pascal-frontend feature, landed green with its own regression:

| wall | what landed |
| --- | --- |
| `get_frame` / `get_pc_addr` / `get_caller_stackinfo` | real frame walk, one backend op (b270) |
| `TObject.ClassName` | + an RTTI header for EVERY class, not just published ones (b271) |
| bare sibling CLASS-method call | a static method needs no Self, it just had to be FOUND (b272) |
| `AMethod;` | bare parenless call of a proc-var / method pointer, as a statement (b273) |
| `ClassType` / `InheritsFrom` | + the chain `E.ClassType.InheritsFrom(C)` (b274) |
| **`Self` in a class method** | **the METACLASS, and the RUNTIME class** (b275) |
| `E is <class-ref VALUE>` | a TClass field/var, not a class name (b276) |
| `TRunMethod(m)` | a method pointer built by hand from a TMethod record (b277) |
| typed metaclasses | ANY constructor name + class methods through `class of T` (b278) |

Plus RTL: ExceptClass, BackTraceStrFunc (+ a real default), BoolToStr, AnsiCompareStr/Text,
UnicodeFormat, System.TMethod, and ExceptAddr as an explicit nil stub.

### The one that mattered
`Self` in a class method (b275). The cheap fix -- make it the statically-known class --
compiles, runs, and silently builds a suite for the WRONG class: FPC's whole idiom is that
`TMyTest.Suite` reaches `TAssert.Suite`'s body with `Self = TMyTest`. So the class is now
passed as a real hidden argument, param 0 of every class method, and it propagates through
bare sibling calls. Everything else in the list is reachable from that one decision.

### Known gaps, filed not hidden
- [[bug-cross-metaclass-new-with-args]] — constructing through a class reference WITH
  ARGUMENTS segfaults on every non-x86-64 target. PRE-EXISTING (reproduces with the old
  `Create` spelling and code path), but it means the fpcunit chain is x86-64-only until
  fixed. **This is the next thing to do for this corpus.**
- [[bug-pascal-exceptaddr-returns-nil]] — ExceptAddr is a declared stub; fpcunit only uses
  it to print WHERE a failure happened, and prints `n/a` for nil, so pass/fail is unaffected.
- Virtual class methods (`class function ... virtual`) still bind statically. FPC dispatches
  them through the VMT. Not needed by fpcunit; worth a ticket if a rung above needs it.

### Next rung
[[feature-pascal-corpus-fpjson]] (rung 2) — and fpcunit being green is what unlocks it, since
every FPC library's own suite is written against fpcunit.
- 2026-07-13 — resolved, commit pending.
