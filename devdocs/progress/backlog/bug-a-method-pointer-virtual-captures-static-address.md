---
summary: "@baseref.VirtualMethod binds the STATIC base method address, not the virtual override — a method pointer to a virtual method via a base-typed ref calls the wrong method (silent), and contradicts pxx's own direct virtual dispatch"
type: bug
prio: 45
track: A
---

# Method pointer to a virtual method via a base ref captures the static address

- **Type:** bug (correctness — `procedure of object` / method-pointer lowering of a
  virtual method address). **Silent.**
- **Track:** A (codegen of `@obj.VirtualMethod`).
- **Found by:** the pasmith fuzzer's `--mptrs` rung ([[feature-pasmith-deep-oop]]);
  the tool is owned by testing infra, which files findings into the owning lane.
- **Found:** 2026-07-15.

## Symptom — airtight minimal repro

```pascal
program mvirt;
{$mode objfpc}{$H+}
type
  TB = class function M(a: longint): longint; virtual; end;
  TD = class(TB) function M(a: longint): longint; override; end;
  TFn = function(a: longint): longint of object;
function TB.M(a: longint): longint; begin M := a + 1; end;
function TD.M(a: longint): longint; begin M := a + 1000; end;
var b: TB; fn: TFn;
begin
  b := TD.Create;              { base-typed ref, DERIVED instance }
  fn := @b.M;                  { method pointer to a VIRTUAL method via the base ref }
  writeln('via ptr: ', fn(5)); { should call TD.M -> 1005 }
  writeln('direct : ', b.M(5));{ virtual dispatch -> 1005 }
  b.Free;
end.
```

| compiler | via ptr | direct |
| --- | --- | --- |
| **FPC 3.2.2** | `1005` | `1005` |
| **pxx** (`-O0`/`-O2`/`-O3`) | **`6`** | `1005` |

pxx binds `@b.M` to the **static, declared** `TB.M` (returns `a+1 = 6`) instead of
the runtime type's override `TD.M` (`a+1000 = 1005`). The tell is that pxx
**contradicts itself**: the method pointer taken from `b` calls a different method
than `b.M(...)` called directly on the same object. A method pointer to a virtual
method must dispatch on the object's actual type (Delphi/FPC semantics — this is how
event handlers, `TThread.Synchronize`, `for..in` enumerators via method pointers, and
every `TNotifyEvent` work). pxx silently calls the wrong method: the program runs and
produces a plausible-but-wrong number.

## How the fuzzer sees it

`tools/pasmith.py --mptrs N` declares a base + derived class with N virtual methods,
holds objects through the base type (some instantiated derived), and calls random
`@obj.Mm` pairings through a var and an array. On FPC each pointer dispatches like the
direct call; on pxx it binds the base method, so the folded checksum differs. FPC and
pxx are each self-consistent across `-O`; they diverge only with each other — one
systematic bug. Reproduce:

```
tools/pasmith_run.py --seeds 4-33 --mptrs 3 --classes 0 --stmts 6
```

## Scope / what to check

- `@obj.Method` for a virtual method must emit the *virtual* address load (resolve
  through Self's vtable), not the static symbol. Check the IR lowering of the address-of
  a virtual method (vs a non-virtual one — non-virtual method pointers already work:
  a hand test with non-virtual `M` agrees with FPC).
- Verify the fix also covers `procedure of object` assigned to fields, array elements,
  and passed as parameters (the fuzzer exercises var + array).
- Related: [[project_operator_overloading_exists_syntax_limits]],
  [[project_procedural_types_arc]] (procedural/method types groundwork).

## Acceptance

The minimal repro prints `via ptr: 1005` under pxx at every `-O` level; the pasmith
`--mptrs` rung stops diverging (its ledger signature clears on `--recheck`); a
`test/test_*.pas` regression that calls a virtual method through a method pointer and
folds the result matches FPC.
