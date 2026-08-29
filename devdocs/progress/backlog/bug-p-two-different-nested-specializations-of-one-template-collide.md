---
prio: 65
track: P
owner: unassigned
---

# Two different nested specializations of ONE template, in one generic, collide

- **Type:** bug — compile error on valid code. FPC accepts and prints `8 / 804`.
- **Track P** (Pascal frontend, generics).
- **Newly reachable:** this shape could not be reached at all until
  [[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]]
  was fixed, so it is not a regression — it is the next layer down, exposed.
- **Binary:** `ba79fbeb2b0c`, verified self-host fixedpoint.

## Symptom

A generic that specializes the **same** inner template on **two different**
enclosing type parameters — `specialize TCmp<T>` and `specialize TCmp<U>` — is
rejected, and the error points at the INNER template's own body rather than at
either use:

```
pascal26:11: error: SizeOf: unknown type or variable
```

Line 11 is `class function TCmp.Size: LongInt; begin Result := SizeOf(T); end;`,
which is correct code and compiles fine when only one of the two
specializations is present. So the diagnostic names a line that is not wrong.

## Repro (16 lines; FPC prints `8` then `804`)

```pascal
program n3;
{$mode objfpc}{$H+}
type
  generic TCmp<T> = class
    class function Size: LongInt; static;
  end;
  generic TOrd<T, U> = class
    class function Get: LongInt; static;
    class function Both: LongInt; static;
  end;
class function TCmp.Size: LongInt; begin Result := SizeOf(T); end;
class function TOrd.Get: LongInt; begin Result := specialize TCmp<T>.Size; end;
class function TOrd.Both: LongInt;
begin Result := specialize TCmp<T>.Size * 100 + specialize TCmp<U>.Size; end;
type TO1 = specialize TOrd<Int64, LongInt>;
begin WriteLn(TO1.Get); WriteLn(TO1.Both); end.
```

## The boundary, measured

| shape | result |
| --- | --- |
| one nested specialization, one method | **8** — fine |
| two DIFFERENT outer specializations (`TOrd<Int64,LongInt>`, `TOrd<LongInt,Byte>`) | **8 / 4** — fine |
| one method specializing `TCmp<T>` **and** `TCmp<U>` | **error** |

So it is not "two specializations" and not "two methods": it is **two distinct
specializations of the SAME inner template from within one enclosing template**.

## Where to start

`ParseSpecialization`'s prerequisite scan now sweeps the class body and every
buffered method body (`gmScan`). It collects nested prerequisites into
`NSpecName[]`/`NSpecTmpl[]` keyed by the minted alias name, so `TCmp$Int64` and
`TCmp$LongInt` should be two distinct rows. The error naming the inner
template's own body suggests the second alias is streamed with the FIRST one's
substitution still loaded (`SpecSub*`), leaving `T` unbound in the second — but
that is a hypothesis from the shape of the message, **not measured**. Trace with
`--debug`, which prints each `SPEC <name> = <template> nested=<n>` and its
`needs` list, before changing anything.

## Not to be confused with

The Delphi-mode ordering defect recorded in
[[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]]
(method bodies not yet buffered when the rewrite's alias is specialized). That
one is about *when* specialization runs; this one happens with the bodies
present and both prerequisites reachable.
