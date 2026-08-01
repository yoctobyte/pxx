---
summary: "Overload resolution never checks CLASS IDENTITY for a class-typed parameter — it takes the first candidate whose arity fits, so an unrelated class binds silently and the callee reads one class's fields as another's"
type: bug
track: A
prio: 80
---

# Overload resolution binds an unrelated class to a class-typed parameter

- **Type:** bug (Track A, shared overload resolution — SILENT WRONG DISPATCH,
  and a crash wherever the two layouts differ) — **Track A**
- **Opened:** 2026-08-01, found while fixing
  [[bug-nilpy-dict-from-pairs-and-bytes-decode-segfault]]. That ticket's own
  "it is a TYPECAST" diagnosis is wrong; this is the actual cause, and it is far
  bigger than `dict()`.

## Minimal repro — plain PASCAL, no NilPy involved

```pascal
program ov;
type
  TA = class
    x: Integer;
  end;
  TB = class
    y, z: Integer;
  end;
function pick(a: TA): Integer; overload;
begin pick := 1; end;
function pick(b: TB): Integer; overload;
begin pick := 2; end;
var b: TB;
begin
  b := TB.Create;
  WriteLn(pick(b));    { CPython-free, unambiguous: must print 2 }
end.
```

**Prints `1`.** `TA` and `TB` are unrelated — no inheritance, different layouts.
Resolution took the first candidate whose ARITY fits and never compared the
argument's class to the parameter's.

## Why it matters

- **Silent** in the benign case: you get the wrong function, no diagnostic.
- **A segfault** whenever the two classes' layouts differ and the callee touches
  a field or method — the callee is reading one object's memory through another
  class's shape. That is how it surfaced: `dict([("a", 1)])` bound its TPyList
  to `function dict(d: TPyDict)`, whose body calls `d.keylist`.
- **Blast radius is every overload set with class-typed parameters.** `pylib`
  alone has many (`dict`, `list`, `reversed`, `bytes`, the `TPyDict.update`
  pair). Any of them can be handed the wrong class by a caller and bind happily.
- Ordering becomes load-bearing in a way nobody can see: whichever overload is
  DECLARED FIRST wins for every class argument. Reordering to fix one call
  breaks another (measured — see the sibling ticket).

## Where to look

`compiler/parser.inc`, the overload selection around lines ~3253–3415
(`FindUMethArity` / the candidate scan and the "type-match phases"). The comment
on `ProcArityMatches` (`symtab.inc:4689`) says the type-match phases "only check
the supplied args[0..nArgs-1]" — the question is what that check does for a
`tyClass` parameter, and the measured answer is: nothing that distinguishes one
class from another.

## Care required — do NOT simply require exact class equality

The fix must keep the cases that legitimately bind:

- a **descendant** passed to an ancestor-typed parameter (`IsSubclassOf` already
  exists and is used elsewhere in the resolver),
- `nil`,
- a parameter typed `TObject`, which must keep accepting anything,
- interface-typed parameters,
- the pylib paths that pass a class through a `Variant` parameter.

A too-strict rule will reject working code across every track, so this wants the
full gate and probably a staged landing (warn first, then reject) rather than a
single flip.

## Gate

The repro above prints `2`; `make test` + self-host byte-identical + the
frontends' suites green. Add the repro as a regression test. Then re-check
[[bug-nilpy-dict-from-pairs-and-bytes-decode-segfault]], which should start
working with no further change — its `dict(l: TPyList)` overload is already in
`pylib.pas`, deliberately left unselected and waiting for this fix.

## 2026-08-01 — FIXED

The machinery was already there and simply not reached for classes.

`MatchArgRecMismatch` (`symtab.inc:4762`) exists to make overload resolution
record-identity-aware (bug-overload-resolution-record-identity) and **already
implements descendant tolerance** by walking `UClsParent`. But it opened with

```pascal
if (aTk <> tyRecord) or (Procs[i].Params[j].TypeKind <> tyRecord) then Exit;
```

and its own comment said "Records only: class params keep their
inheritance-tolerant matching" — which in practice meant *no* matching at all
for classes. `MatchCallDelphiProcAddr` likewise filled the `MatchArgRec` side
channel only for `tyRecord` arguments, so a class argument's identity never
reached the matcher.

Two changes:

- `parser.inc` — fill `MatchArgRec[i]` for `tyClass` as well as `tyRecord`.
- `symtab.inc` — accept both kinds (and require the arg and param kinds to
  agree), plus an explicit **TObject** carve-out: a `TObject`-typed parameter
  accepts anything, and a user class with no declared parent has
  `UClsParent = -1`, so the ancestor walk alone would not have reached it.

Descendant widening needed no new code — it was the existing walk, finally
reachable.

### Verified

`test/test_overload_class_identity.pas`, wired into `make test`:

| call | result | why |
| --- | --- | --- |
| `pick(a)` with `a: TA` | 1 | exact |
| `pick(b)` with `b: TB` | **2** | was 1 — the bug |
| `pick(d)` with `d: TDerived` | 1 | descendant widens to its ancestor's param |
| `anyobj(a)` / `anyobj(b)` | 9 / 9 | `TObject` param still accepts anything |

Confirmed RED pre-fix (`1 1 1 9 9`). **Self-host reaches a byte-identical
fixedpoint**, which is the meaningful breadth check here: `compiler.pas` plus
its includes is a large Pascal program dense with overloads, and it is compiled
by the changed resolver twice and compared.

### Downstream

- [[bug-nilpy-dict-from-pairs-and-bytes-decode-segfault]] — **now fixed with no
  further change**, exactly as predicted: the platonic `dict(l: TPyList)`
  overload was left in `pylib.pas` deliberately unselected, and correct
  resolution now picks it. `dict([("a",1),("b",2)])` works, and `dict(a_dict)`
  and `dict([])` still do.
- [[bug-nilpy-bool-protocol-ignored-object-always-truthy]] — blocker cleared,
  but **part 2 remains** and behaves as that ticket predicted: with no overload
  matching a user class, `bool(obj)` flipped from always-False to always-True,
  so `__bool__`/`__len__` are still not consulted. It needs its NilPy arm
  routing user classes through `PyMakeTruthy`. Moved back to the backlog.

## Log
- 2026-08-01 — resolved, commit PENDING.

## 2026-08-01 (follow-up) — one legitimate caller depended on the old looseness

Track T reported `test-nilpy#src:test/test_nilpy_bytes_decode.npy` NEW-RED at
`74a925112` (and, in the same report, both of my earlier reds FIXED):

```
error: no overload of bytes matches these arguments
  argument types: (class)
  candidates: bytes(class) / bytes(AnsiString)
```

`bytes([104, 105])` passes a `TPyList`, and pylib declared only
`bytes(b: TPyBytes)` and `bytes(const s: AnsiString)`. It had been WORKING by
relying on exactly the mis-binding this ticket removed — and the source said so
out loud:

```pascal
{ A LIST argument binds to this overload too (class-arg overload resolution
  is not identity-precise): hand it to the from-list builder. }
if TObject(b) is TPyList then ...
```

So this is the predicted cost of correctness, landing on a caller that had been
built around the defect. Fixed properly rather than by loosening the rule: a
real `bytes(l: TPyList): TPyBytes` overload, the same shape as the
`dict(l: TPyList)` one this ticket already unblocked. The runtime `is` rescue is
kept as belt-and-braces with its comment corrected — it is unreachable from
normal code now, and marked for removal once that is confirmed.

**Swept for siblings rather than waiting for them one at a time.** Two sites in
pylib documented this dependency; the other is `TPyBytes.extend(src: TPyBytes)`
taking a list/tuple. That one is a METHOD, and method overload resolution
(`FindUMethOverload`) is a different path this fix did not touch — verified
still working (`out.extend((13, 10))` → `2 13 10`). Left alone deliberately;
if method resolution is ever made identity-precise too, that site needs the
same treatment and this note is the pointer.

Verified: all five `bytes()` forms byte-identical to CPython (list literal, list
variable, str, bytes copy, and `.decode()` off a list-built value), and
`test_nilpy_bytes_decode.npy` matches CPython end to end.
