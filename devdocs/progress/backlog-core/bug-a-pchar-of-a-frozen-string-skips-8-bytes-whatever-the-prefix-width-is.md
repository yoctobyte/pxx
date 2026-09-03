---
prio: 65
track: A
type: bug
status: open
summary: "`PChar(s)` for a `string[N]` adds a hardcoded 8 to skip the length prefix, so under -dPXX_SHORTSTRING (1-byte prefix) it points 7 bytes past the characters and the callee sees an empty or garbage string. Measured on x86-64: `Show(PChar(s))` and `Show(PChar(arr[0]))` print nothing under the flag and are correct without it. Four sites in ir.inc spell the 8 as a literal beside a `= tyString` guard that also misses the specific frozen kinds."
---

# PChar of a frozen string skips 8 bytes whatever the prefix width is

```pascal
type TS = string[8];
var s: TS; arr: array[0..1] of TS; r: record f: TS; end;
begin
  s := 'abcde'; arr[0] := 'abcde'; r.f := 'abcde';
  Show(PChar(s));       { default: [abcde]   -dPXX_SHORTSTRING: []      }
  Show(PChar(arr[0]));  { default: [abcde]   -dPXX_SHORTSTRING: []      }
  Show(PChar(r.f));     { correct in both — a different path            }
end.
```

Measured 2026-09-03 on x86-64. It is not a regression: the pin cannot show it,
because `-dPXX_SHORTSTRING` is a no-op in a compiler that predates the layout —
**check `SizeOf` beside any pinned measurement of byte-prefix behaviour**, the
pin prints 16 where the flag mode must print 9.

## Where

Four sites in `compiler/ir.inc` (the auto-`char*` marshalling for a Pointer
parameter, the same for a variadic slot, the function-pointer path and the
virtual-call path) share one shape:

```pascal
if (not isRefArg) and (cpi >= 0) and
   (IntToTypeKind(IRTk[value]) = tyString) and
   ... Params[pathIdx].TypeKind = tyPointer ...
then
  aval := IRAppend(IR_BINOP, aval, IRAppend(IR_CONST_INT, ..., 8, ...), Ord(tkPlus), ...)
```

Two defects in one expression and they need fixing together:

1. **The literal 8** must be `FrozenStrPrefixSize(IRStrTkOf(value))`. That is
   the whole bug in the flag mode.
2. **The guard** is `= tyString`, so it also misses a value already tagged
   tyFixedString or tyShortString — which is what an array element and a record
   field now carry. `TypeIsAnyString` / `TypeIsFrozenString` is the question
   being asked.

`FrozenStrPrefixSize` exists precisely so a literal 8 on a string-ish line is a
countable worklist; these four are on it.

## Why it matters past the flag

`PChar(s)` is how every C binding takes a Pascal string. Under phase 4 this is
the default layout, and the failure is silent: the callee sees an empty string,
not a crash.

[[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]]
