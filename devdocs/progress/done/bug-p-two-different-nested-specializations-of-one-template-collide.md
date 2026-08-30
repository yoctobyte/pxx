---
prio: 65
track: P
owner: frankA
status: done
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

## RESOLVED 2026-08-30 (frankA) — already fixed, and NOT by anything aimed at it

**Does not reproduce.** The ticket's own repro compiles and prints `8` / `804`,
matching FPC exactly.

Verified on two binaries so the result does not depend on my working tree:

| binary | result |
| --- | --- |
| HEAD self-hosted (`222370c819c9`) | `8` / `804` |
| **pin v394** (`53800fbeb0b66e11`) | `8` / `804` |
| FPC `-Mobjfpc` (oracle) | `8` / `804` |

It was already correct **on the pin**, so the fix predates my session entirely
and none of my in-flight work is involved.

### Which commit fixed it is NOT established

The ticket records this shape as newly reachable after
[[bug-p-a-generic-class-method-call-is-undefined-inside-another-generics-body]],
and three ordering defects fell around that work. One of them closed this too.
**I did not bisect to find which**, and I am saying so rather than picking the
plausible candidate: the diagnosis in this ticket ("the second alias is streamed
with the FIRST one's substitution still loaded") was explicitly flagged by its
author as a hypothesis from the error's shape and never measured, so attributing
the fix to a commit would be a second unmeasured claim stacked on the first.

What matters for anyone touching the prerequisite scan is in the test file, not
in a sha.

### The durable part: it is now guarded

An incidentally-fixed defect has nothing protecting it, and the next change to
`ParseSpecialization`'s prerequisite scan would have no way to know this shape
was ever hard. Filed as
`test/test_generic_two_nested_specializations_of_one_template.pas`, wired beside
its sibling, all three rows verified against FPC:

| row | value | what it pins |
| --- | --- | --- |
| `TA.Get` | 8 | one nested specialization (the easy row) |
| `TA.Both` | 804 | two DIFFERENT specializations of one inner template — this ticket |
| `TB.Both` | 401 | a second OUTER specialization — catches a fix that binds the first one's arguments everywhere |

The third row exists because a fix that contaminated across outer
specializations would print `804` twice, and without that row the file would
pass.

Also corrected `test_generic_nested_specialize_in_method_body.pas`, whose header
told the reader this shape "still fails" and named this ticket. That statement
was true when written and is now false — the kind of stale claim this ticket's
own umbrella has been bitten by three times.

## Log
- 2026-08-30 — resolved, commit PENDING-COMMIT.
