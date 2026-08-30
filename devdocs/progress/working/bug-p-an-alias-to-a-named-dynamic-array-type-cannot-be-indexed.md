---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`type TA = array of Integer; TB = TA;` — indexing a TB is `error: this value cannot be indexed`, while indexing a TA is fine. One extra level of naming loses the array-ness. Six-line repro, same file, no generics and no units involved; it is not about TArray, which is only how it was found. SetLength on the alias is accepted, so the type is array enough to resize and not array enough to read."
status: working
owner: frankR
---

# An alias to a named dynamic-array type cannot be indexed

- **Type:** bug (Pascal frontend) — **Track P**.
- **Filed:** 2026-08-30 by frankB, found while adding `TArray<T>` to the RTL
  ([[bug-b-rtl-provides-no-tarray-generic-but-pxx-claims-ver3-2-2]]). Not
  related to that work beyond provenance.
- Measured at pin **v396** (`stable_linux_amd64/default/pinned`), `c781fc84f`.

## Repro — six lines, one file, no units, no generics

```pascal
program m;
{$MODE OBJFPC}{$H+}
type
  TA = array of Integer;
  TB = TA;              { one more level of naming }
var x: TA; y: TB;
begin
  SetLength(x, 2); x[0] := 1; x[1] := 2;     { fine }
  SetLength(y, 2); y[0] := 3; y[1] := 4;     { error }
  WriteLn(x[0] + x[1], y[0] + y[1]);
end.
```

```
pascal26:9: error: this value cannot be indexed — only arrays, strings and
                   pointers can (y)
```

`x` and `y` have the same structural type. The only difference is that `TB` is
named via `TA` instead of via `array of Integer`.

## The sharp part: `SetLength` accepts it

`SetLength(y, 2)` is **not** rejected — the error is on the index. So the alias
is array enough to be resized and not array enough to be read, which means the
array-ness survives into at least one builtin and is lost on the indexing path
specifically. That is a narrower fault than "aliases are not resolved", and it
is where to point the first probe.

## What it is NOT

Ruled out by measurement, because each of these was the obvious first guess:

| hypothesis | test | verdict |
| --- | --- | --- |
| it is about generics | non-generic `TA`/`TB` above | **fails identically** — not generics |
| it is about `TArray` | plain `array of Integer` | **fails identically** — not TArray |
| it needs a unit boundary | all in one program, above | **fails identically** — not cross-unit |
| one level is broken too | `x: TA` in the same program | **`x` works** — one level is fine |

It is specifically the **second** level of naming.

## Why it is worth p50

`type TMyList = TStringArray;` is everyday Pascal — giving a domain name to an
RTL array type is one of the commonest things a unit's `type` block does, and
`lib/rtl/sysutils.pas` alone exports four array types that invite exactly that
(`TStringArray`, `TStringDynArray`, `TFileInfoArray`, and now `TArray<T>`). Any
consumer that renames one of them gets a hard compile failure on the first
index.

It is at least **loud** — a compile error naming the variable, not a wrong
value — which is why this is p50 and not higher.

## Provenance, and the one thing it did NOT block

Found while checking whether adding `TArray<T> = array of T` to
`lib/rtl/sysutils.pas` could break code that declares its own `TArray<T>` (the
`{$ifdef VER3_0_0}` idiom). It cannot: the redeclaration case fails **identically
with that change stashed**, and so does a plain non-generic alias, which is what
led here. Direct use — `var a: TArray<Integer>` — works, which is what the
rtl-generics corpus actually does, so this does not block that ticket.

## Gate

`make test` + self-host byte-identical. The six lines above are the regression
test; keep the `x: TA` line in it, because the point of the finding is that one
level works.

## 2026-08-30 (frankR) — diagnosed; the "sharp part" is an artefact, and the fault is wider

Reproduced exactly on `b3c6858bdfbb`. Then varied the shape before reading any
code, and three of the ticket's framings do not survive it.

### 1. It is not about DYNAMIC arrays. It is every array.

| shape | result |
| --- | --- |
| `TA = array of Integer; TB = TA` — index | FAIL |
| **`TA = array[0..3] of Integer; TB = TA` — index** | **FAIL** |
| `TA = array of array of Integer; TB = TA` | FAIL |
| third level `TC = TB` | FAIL |
| `TA = AnsiString; TB = TA` — index | **ok** |
| `PA = ^Integer; PB = PA` — deref | **ok** |
| control: one level `x: TA` | **ok** |

Static arrays fail identically, so the title's "dynamic" is too narrow. Strings
and pointers are unaffected — they have their own alias carriers
(`AliasStrElemTk`, `AliasElemTk`), which is exactly the asymmetry that explains
this.

### 2. It is not the indexing path. The variable is not an array at all.

```pascal
type TA = array of Integer; TB = TA;
var x: TA; y: TB;
begin WriteLn(SizeOf(x), ' ', SizeOf(y)); end.     { prints: 8 4 }
```

**`SizeOf(y)` is 4.** `y` is not a mis-indexed array; `y` is an `Integer`. The
alias resolved to the array's ELEMENT type and dropped the array-ness entirely.
`Length(y)` says so out loud — *"Length needs a string, an array or a PChar,
**not Integer**"* — and that is the diagnostic that names the bug.

So the ticket's "where to point the first probe" (the indexing path) is the one
place the fault is not.

### 3. `SetLength` is NOT accepted — that observation is an artefact

```
$ pascal26 <alias, SetLength only, no indexing anywhere>
pascal26:4: error: SetLength expects a string variable in IR codegen
```

`SetLength` fails too. In the ticket's repro it *looks* accepted because the
four indexing errors are raised during parsing and the compile never reaches IR
codegen, where SetLength's check lives. Remove the indexing and SetLength
reports on its own.

So there is no "array enough to resize, not array enough to read" split; the
type is simply an Integer and every array operation on it fails. **An earlier
error hid a later one** — the same shape as `ugenconstraints.pas:65` masking 35
conformance tests, one ticket over.

### Root cause, and the exact site

`pasparser_decl.inc:6154`, the fallthrough arm of the type-declaration
dispatcher:

```pascal
      else
      begin
        { Named simple type alias: PFoo = BaseType }
        fTk := ParseTypeKind;
        RegisterGeneralAlias(tnOff, tnLen, Ord(fTk), LastTypeRecId);
      end;
```

`TB = TA` lands here. Named ARRAY types do not live in the scalar alias table —
they have their own `ArrType*` rows, as `AliasPtrElemArrAi`'s comment already
records: *"An array alias is not in the scalar alias table, so ParseTypeKind
answers its unknown-name default."* So `ParseTypeKind` hands back the ELEMENT
kind and `RegisterGeneralAlias` files `TB` as a scalar of that kind. One level
works because `var x: TA` consults `FindArrayType`; the second level never gets
the chance, because by then `TB` is an Integer.

### The fix, not written — `pasparser_decl.inc` is not this lane's file

Before that fallthrough, when the RHS is a bare identifier naming an existing
array type, copy the row instead of scalarising it:

```pascal
        srcAi := -1;
        if CurTok.Kind = tkIdent then srcAi := FindArrayType(CurTok.SVal);
        if srcAi >= 0 then  { copy ArrType row srcAi under the new name, Inc(ArrTypeCount), Next }
        else                { ...the existing two lines }
```

`FindArrayType` already exists (`symtab.inc:352`) and already applies the
visibility/latest-unit-wins rule, so nothing new is needed there. The bulk of
the change is copying the ~20 `ArrType*` fields, which wants to be a helper
beside the two existing registration sites (`pasparser_decl.inc:5974`, `:6071`)
rather than a third open-coded copy — and that placement is a reason for the
file's owner to write it rather than a visitor.

Reported to the coordinator rather than taken.

### For the regression test when it is written

Keep the `x: TA` line, as the ticket says — and add `WriteLn(SizeOf(y))`
expecting 8, plus a static-array pair. `SizeOf` is the assertion that fails
*silently* today; the indexing errors are merely the loud symptom.
