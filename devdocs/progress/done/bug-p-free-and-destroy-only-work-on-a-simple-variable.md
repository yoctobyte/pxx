---
summary: "`.Free` is only accepted on a plain variable — `a[0].Free`, `r.f.Free`, `h.f.Free` are all `\"Free\": no such member on this record/class`, and `v.Destroy` fails even on a plain variable"
type: bug
track: P
prio: 60
owner: claude-b-night2
---

# `.Free` / `.Destroy` off anything but a simple variable

- **Type:** bug — Track P (Pascal frontend; the code is in the shared
  `compiler/parser.inc`)
- **Status:** done
- **Opened:** 2026-08-05
- **Found by:** `tools/fpc_diff_probe.sh` thread cases — three of them freed an
  array of workers with `t[k].Free` and every one failed to compile.

## Repro

```pascal
program af;
uses SysUtils;
type
  TFoo = class n: Integer; end;
  TBox = record f: TFoo; end;
  THolder = class f: TFoo; end;
var r: TBox; h: THolder; a: array[0..1] of TFoo; d: array of TFoo; v: TFoo;
begin
  ...
end.
```

| expression | pxx |
| --- | --- |
| `v.Free` | **ok** |
| `v.Destroy` | `error: "Destroy": no such member on this record/class` |
| `r.f.Free` (record field) | `error: "Free": no such member ...` |
| `h.f.Free` (class field) | `error: "Free": no such member ...` |
| `a[0].Free` (static array) | `error: "Free": no such member ...` |
| `d[0].Free` (dynamic array) | `error: "Free": no such member ...` |
| `FreeAndNil(r.f)` | **ok** — the workaround |
| `a[0].ClassName` | **ok** — other TObject members are fine on any designator |

FPC compiles all of them.

## Why this shape matters

`FList[i].Free`, `Workers[k].Free`, `FOwner.Child.Free` are everyday Pascal.
The failure is at least loud — a compile error, never a wrong value or a
missed destructor — but it forces `FreeAndNil` or a temporary at every site,
which is exactly the kind of reshaping `CLAUDE.md`'s platonic-code rule says
not to do quietly.

That `a[0].ClassName` works while `a[0].Free` does not is the tell: this is not
about member lookup on an indexed base in general.

## Root cause (FIXED, except `Destroy`)

`Free` is not a member of any class the frontend knows; it was recognised by
ad-hoc token-shape special cases in `compiler/parser.inc` — the load-bearing
one being an identifier followed *literally* by `. Free ;`. Any base with a
selector in front of it — an index, a field, an `as`-cast — misses that shape,
falls through to ordinary member lookup, and there is no `Free` to find.

The fix adds the desugar at the two general member-access fall-throughs, right
before the `RequireRecMember` call that would reject it: one in
`ParseLValueAST` (which is where `a[0].Free`, `d[0].Free`, `r.f.Free`,
`h.f.Free` land) and one in `ParseClassRecordSelectors` (where a `(`-led
statement like `(o as T).Free;` lands). Both route into the existing
`GenMakeFreeObjectExpr`, the same generator `TClass(expr).Free` already used.

Two predicates carry the conditions:

- `BuiltinFreeHere` — a user class (not a record), no user-declared `Free`
  (a real `Free` method still wins), and the token after the name ends a
  statement, which is the same guard the old bare-identifier case used.
- `PureDesignator` — `GenMakeFreeObjectExpr` CloneASTs its operand up to three
  times (nil test, `Destroy`, `FreeMem`), so the base must be re-evaluable:
  ident / field / index / deref, or a cast **whose operand recurses to one of
  those**. `(f() as T).Free` is deliberately still refused — accepting the cast
  outright would call `f()` three times.

## Still open: `Destroy`

`v.Destroy` on a class with no declared destructor is still an error. It is not
folded in on purpose: `Free` is the nil-guarded wrapper, and desugaring a direct
`.Destroy` to the same thing would change what it means. Filed nowhere yet —
raise it if real code wants it.

## Verification

`test/test_free_designator.pas`, wired into `make test`, asserts the
**semantics** and not just that it compiles: five objects freed through five
different designator shapes each log from their destructor (`d1d2d3d4d5`), a
user-declared `Free` wins (`U`), and `nil.Free` stays a no-op.

- self-host fixedpoint converged in one round
- `tools/gate.sh quick` GREEN with the FPC seed canary, `tools/gate.sh lib` GREEN
- `make demos` 34/34 with the changed compiler
- three `tools/fpc_diff_probe.sh` thread cases were blocked on this and are now
  untagged and passing — **and one of them then exposed
  [[bug-b-criticalsection-was-a-no-op-stub]]**, a silent lost-update bug that
  the compile failure had been hiding

## Gate

Track P: `make test` + self-host fixedpoint (byte-identical).

## Log
- 2026-08-05 — resolved, commit 503f1e94b.
