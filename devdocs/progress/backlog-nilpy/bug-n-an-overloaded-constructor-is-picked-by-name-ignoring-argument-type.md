---
slug: bug-n-an-overloaded-constructor-is-picked-by-name-ignoring-argument-type
track: N
prio: 55
type: bug
status: backlog
owner: ""
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
