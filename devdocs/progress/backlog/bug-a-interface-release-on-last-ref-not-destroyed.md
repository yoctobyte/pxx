---
summary: "COM interface: dropping the last interface reference (:= nil) does NOT run the destructor — pxx defers/skips Release, breaking interface RAII (silent)"
type: bug
prio: 40
track: A
---

# COM interface refcount: last-reference release does not destroy the object

- **Type:** bug (correctness — interface lifetime / RTL Release lowering). **Silent.**
- **Track:** A (IR / RTL lowering of interface `_Release`).
- **Found by:** the pasmith fuzzer's `--intfs` rung; the tool is owned by testing
  infra, which files findings into the owning lane.
- **Found:** 2026-07-15 by the pasmith interface rung ([[feature-pasmith-deep-oop]])
  on its first run — every interface seed diverges pxx-vs-FPC with both compilers
  self-consistent across `-O` levels (the single-real-bug signature).
- **Context:** COM/ARC interface polish is on the user's "delayed" list
  ([[feedback_rtti_layout_mostly_irrelevant_facade]]), hence the modest prio — but
  it is a *silent* correctness bug (RAII destructors never fire), so it is filed as
  a `bug-`, not hidden. Bump if interface RAII becomes load-bearing for a corpus.

## Symptom — airtight minimal repro

```pascal
program minrel;
{$mode objfpc}{$H+}
type
  IThing = interface ['{B0000000-0000-0000-0000-000000000001}'] procedure Go; end;
  TThing = class(TInterfacedObject, IThing)
    destructor Destroy; override;
    procedure Go;
  end;
destructor TThing.Destroy; begin writeln('DTOR ran'); inherited Destroy; end;
procedure TThing.Go; begin end;
var it: IThing;
begin
  it := TThing.Create;
  writeln('before nil');
  it := nil;                { last interface ref dropped -> destructor MUST run HERE }
  writeln('after nil');
end.
```

| compiler | output |
| --- | --- |
| **FPC 3.2.2** (`-O2` and `-O-`) | `before nil` / **`DTOR ran`** / `after nil` |
| **pxx** (`-O0`/`-O2`/`-O3`) | `before nil` / `after nil` — **destructor never runs** |

## Superseded by the full COM-lifetime arc (2026-07-15)

User authorized the full route: this bug (destructor not firing on last ref) is one
symptom of incomplete COM managed lifetime. The fix lives in
[[feature-com-interface-managed-lifetime]] — item 1 (scope-exit release) resolves
this repro; the rest (param/result/field release + default flip) rounds it out.
Keep this ticket as the correctness anchor; resolve it when item 1 lands.

## Recon (2026-07-15, agent-A — root found; fix is a dialect-default decision, parked)

Root: the ARC assign paths in `ir.inc` (retain-new / release-old around an
interface store, and the `_Release` on `it := nil`) are all gated on `isComIntf`
= `UClsIsComInterface[iface]`. That flag is set at the interface declaration
(`parser.inc` ~17837) from the global `InterfacesComMode`, which **defaults to
CORBA (off)** (`lexer.inc:679`) and only flips under `{$interfaces com}`. So a
plain objfpc interface is CORBA → no refcount → no `_Release` → destructor never
fires. The IR *emits* the release for `it := nil`, but only inside `if isComIntf`,
which is False. Confirmed by `--dump-ir`: `it := TThing.Create` is a plain
store (no `PXXIntfAddRefRaw`), `it := nil` is a bare `default_mem` (no
`PXXIntfRelease`).

**FPC defaults interfaces to COM**; pxx's CORBA default is the divergence.

Measured two candidate fixes (both built + self-host byte-identical):
1. **Flip the global default to COM** (FPC-faithful). Fixes the repro, but breaks
   the 7 GUID-less CORBA-style interface tests (`test_interfaces`,
   `_as`/`_is`/`_inherit`/`_param`/`_multi_secondary`) — they implement GUID-less
   interfaces on non-refcounted classes, which under COM require the reserved
   QI/_AddRef/_Release slots. Under real FPC those tests would themselves need
   `{$interfaces corba}`, so the "fix" is: flip default + add `{$interfaces corba}`
   to the CORBA-lenient tests.
2. **GUID ⇒ COM heuristic** (rejected). Fixed the repro and kept the 6 GUID-less
   tests, but broke `test_getinterface_guid_b257`: it uses `class(TObject, IFoo)`
   — a GUID interface implemented by a NON-refcounted TObject (a valid pxx
   CORBA-lenient pattern). A GUID appears on both COM and CORBA interfaces, so it
   is not the distinguishing signal; the `{$interfaces}` mode is.

Recommendation: this is a **dialect-default decision** (COM vs CORBA), which the
user has flagged as delayed ([[feedback_rtti_layout_mostly_irrelevant_facade]]).
The FPC-faithful move is option 1 (default COM + `{$interfaces corba}` on the
lenient tests). Needs the user's call before flipping, plus the full interface +
OOP corpus gate. Left broken until that decision.

---

Dropping the last reference to a COM (refcounted) interface must call `_Release`,
which at refcount 0 destroys the object **synchronously**, before the next
statement. pxx does not: the destructor's side effect (`writeln`) never appears, so
the object is either leaked or its destruction is deferred past program-observable
points. This is core Delphi/FPC interface semantics and the basis of interface RAII
(lock guards, scoped handles, `try/finally`-free cleanup) — pxx silently skips it.

## How the fuzzer sees it

`tools/pasmith.py --intfs N` holds each object only through an interface reference,
nils them at the end, and folds each destructor into the checksum. On FPC the dtors
fire on the nils (checksum reflects them); on pxx they do not, so the checksum
differs. Every interface seed diverges, FPC self-consistent, pxx self-consistent —
one systematic bug. Reproduce:

```
tools/pasmith_run.py --seeds 3-55 --intfs 3 --classes 0 --stmts 8
```

## Scope / what to check

- Does pxx implement `TInterfacedObject._Release` decrementing refcount and calling
  `Destroy` at zero? The refcount may never reach the destroy path, or the
  `iface := nil` assignment may not lower to a `_Release` call at all.
- Related landmarks: [[project_interface_arc_com_done]], [[project_interface_single_pointer_abi_b337]]
  (interface value = one pointer), the b349-b352 real-`TInterfacedObject` work
  ([[project_session_2026_07_14_tio_csmith_b349_b352]]). This bug is specifically the
  RELEASE side: AddRef on assignment may work while Release-on-nil / Release-on-scope
  does not.
- Also verify Release fires at end-of-scope (a local interface var going out of
  scope), and on reassignment (`it := other`), not just `:= nil`.

## Acceptance

The minimal repro above prints `DTOR ran` between the two lines under pxx at every
`-O` level; a `test/test_*.pas` regression that folds an interface destructor into a
checksum matches FPC; the pasmith `--intfs` rung stops diverging (its ledger
signature clears on `--recheck`).
