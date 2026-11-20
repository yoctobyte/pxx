---
slug: bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type
track: N
prio: 55
type: bug
status: done
owner: rd
created: 2026-09-09
found-by: frankB
tags: [nilpy, overload, constructor, silent-wrong-value]
blocked-by: []
summary: "A NilPy construction `C(x)` on a class with several same-arity constructors runs the FIRST one declared, whatever x is. Measured 2026-09-09: one class with `Create(TPyBytes)` and `Create(TPyList)`, one unit with `which(TPyBytes)`/`which(TPyList)` -- the FUNCTIONS resolve correctly (list->2, bytes->1) and the CONSTRUCTORS both answer 1. Silent: the wrong body runs and whatever it does to the wrong argument type is what the program gets. PyClassCreate picks with FindUMeth(ci,'create'), a by-NAME first match; the type-aware picker FindUMethOverloadAhead exists and is already NilPy-aware, but it works by parsing the arguments speculatively and rewinding, and at PyClassCreate's pick site the arguments are ALREADY parsed -- so the fix is a selector over parsed argument NODES, not a call to the existing one. Blocks writing any shim class whose CPython constructor is type-overloaded; lib/rtl/mimic_array.pas carries a one-ctor + runtime `is` workaround with a revert-when-fixed note."
---

# A NilPy overloaded constructor is picked by name, ignoring argument type

## Repro (measured 2026-09-09, compiler b60efad9e381)

`lib/rtl/mimic_ovprobe.pas`:

```pascal
unit mimic_ovprobe;
{$MODE PXX}
interface
uses pylib;
type
  K = class
  public
    tag: Integer;
    constructor Create(b: TPyBytes); overload;
    constructor Create(l: TPyList); overload;
  end;
function which(b: TPyBytes): Integer; overload;
function which(l: TPyList): Integer; overload;
implementation
constructor K.Create(b: TPyBytes); begin tag := 1; end;
constructor K.Create(l: TPyList);  begin tag := 2; end;
function which(b: TPyBytes): Integer; begin Result := 1; end;
function which(l: TPyList): Integer;  begin Result := 2; end;
end.
```

```python
import ovprobe
print("func list ->", ovprobe.which([1, 2]))     # 2  correct
print("func bytes->", ovprobe.which(b"ab"))      # 1  correct
print("ctor list ->", ovprobe.K([1, 2]).tag)     # 1  WRONG, expected 2
print("ctor bytes->", ovprobe.K(b"ab").tag)      # 1  correct by luck
```

**The function half is the control.** It is correct, and it is correct because
`bug-a-overload-resolution-ignores-class-identity` was fixed for calls. The
constructor path never inherited that.

## Mechanism

`PyClassCreate` (compiler/pyparser.inc) picks the constructor with

```pascal
ctorMi := FindUMeth(ci, 'create');
```

which is a by-NAME first match up the parent chain. Arity is checked afterwards
(the `ParamCount - 1` guards below it), so two constructors of DIFFERENT arity
are separated correctly; two of the SAME arity are not looked at again.

`FindUMethOverloadAhead` (compiler/pasparser_call.inc:3442) is the type-aware
selector and already handles `isNilPy`. It is **not** a drop-in here: it learns
the argument types by parsing them SPECULATIVELY and rewinding the token stream,
and at PyClassCreate's pick site the arguments have already been parsed into an
AST chain. So the fix is a selector that scores candidates against
already-parsed argument nodes (`ResolveNodeRec` gives a node's class id), not a
call to the existing function.

## Why it is worth more than its prio suggests

It is the SILENT class. Nothing is refused; the wrong constructor body simply
runs. In the case that found it, a `TPyList` argument bound to a `TPyBytes`
parameter and the body raised "bytes length not a multiple of item size" — a
message about bytes from a call that passed no bytes, which sends the reader
into the wrong function entirely.

## Workaround in the tree, with a lifecycle

`lib/rtl/mimic_array.pas` declares ONE two-argument constructor taking
`TPyBytes` and dispatches on `TObject(init) is TPyList` inside it. That is the
same shape pylib's own `bytes(b: TPyBytes)` carries for the function-side
version of this bug, and it is marked REVERT TO TWO OVERLOADS in place.
Track B's revert-when-fixed pattern (devdocs/dev/track-b-workarounds.md), not a
compiler-appeasement reshape of compiler code.

## Resolution (2026-11-20, rd)

**The mechanism above was half right.** PyClassCreate's `FindUMeth(ci,
'create')` is a by-name pick, but the call is not lowered with it: IR lowering
re-picks through `FindUCtorOverloadArgs` (pasparser_call.inc), which already
scores the ALREADY-PARSED argument nodes, as this ticket proposed. The bug was
inside that selector: it ranked by type KIND only, so two `tyClass` parameters
tied at rank 0 and the first-declared won. It lacked the class-identity
refinement its twin `FindUMethOverloadAhead` carries (exact class rank 0,
ancestor up-cast rank 2, unrelated class rank 3).

**Fix:** the same refinement in `FindUCtorOverloadArgs`, reading the argument's
class through `ResolveNodeRec`.

**Pascal had the same bug.** That selector is shared:

```
K.Create(b: TB) / K.Create(a: TA), called with b, a, TA2(a descendant):
  fpc 3.2.2   1 2 2      pxx before   1 1 1      pxx after   1 2 2
KR.Create(a: TA) / KR.Create(a2: TA2), called with a, a2:
  fpc 3.2.2   1 2        pxx before   1 1        pxx after   1 2
```

**Tests:**
- test-nilpy: `test_nilpy_an_overloaded_constructor_picks_by_argument_class.py`
  (fixture `test/nilpy_ctorov/mimic_ovprobe.pas`, the repro above).
- test-core: `test_a_a_same_arity_ctor_overload_picks_by_class.pas`.

Both fail on the compiler before the fix.

**mimic_array is NOT reverted to two overloads, on purpose.** Measured: with
two overloads, `def mk(x): return array.array("h", x)` passes a variant, the
bytes overload wins, and `mk([4, 5])` raises "array index out of range: 1".
An untyped argument can only be dispatched at run time, so the single
constructor with its `is TPyList` check is the right design, not a workaround.
Its comment now says so.
