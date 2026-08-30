---
track: P
prio: 50
type: bug
blocked-by: []
summary: "`type TA = array of Integer; TB = TA;` — indexing a TB is `error: this value cannot be indexed`, while indexing a TA is fine. One extra level of naming loses the array-ness. Six-line repro, same file, no generics and no units involved; it is not about TArray, which is only how it was found. SetLength on the alias is accepted, so the type is array enough to resize and not array enough to read."
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
