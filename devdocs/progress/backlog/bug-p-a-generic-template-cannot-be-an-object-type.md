---
slug: bug-p-a-generic-template-cannot-be-an-object-type
track: P
prio: 60
type: bug
status: backlog
blocked-by: []
summary: "`TCustomPointersCollection<T, PT> = object` is rejected with `generic templates must be class, record, interface, array or procedure declarations`. FPC accepts a generic over an OBJECT type; the frontend's template-kind check simply has no arm for it. This is the CURRENT stop for `uses Generics.Collections` (generics.collections.pas:146) — measured on both HEAD and pinned, so it is not a recent regression."
owner: unassigned
---

# A generic template cannot be an `object` type

## Repro

```pascal
program g;
{$mode delphi}
type
  TBox<T> = object
    V: T;
  end;
var
  b: TBox<Integer>;
begin
  b.V := 7;
  writeln(b.V);
end.
```

```
pascal26:N: error: generic templates must be class, record, interface, array or procedure declarations
```

FPC compiles it. `object` is the old Turbo Pascal value-semantics class: a record
with methods and inheritance, no reference semantics, no automatic lifetime. It
is not deprecated in FPC and rtl-generics uses it deliberately, for exactly the
reason it exists — a collection helper that must not allocate.

## Where it was found, and the measurement that matters

The current stop for `uses Generics.Collections`:

```
pascal26:146: error: generic templates must be class, record, interface, array or procedure declarations
  in: .../rtl-generics/src/generics.collections.pas
  near:  T  PT   >>> object strict private
```

```pascal
  TCustomPointersCollection<T, PT> = object
  strict private type
    TLocalEnumerable = TEnumerable<T>;
  protected
    function Enumerable: TLocalEnumerable; inline;
```

**Measured on HEAD and on `pinned`, same command, same line, same message** — so
this is a long-standing gap and not a regression from any of the generics work of
2026-08-29/30. It is recorded that way deliberately: the nested-type ticket's
summary carried a stale "the stop is line 120" figure that no longer reproduced
against either binary, and an unverified corpus figure is worth less than none.

## Shape of the fix, as far as it was looked at

The rejection is a kind-check on what follows `=` in a template declaration; the
list already admits class / record / interface / array / procedure. `object` is
closest to `record` in every respect that matters to the template machinery
(value semantics, a body terminated by `end`, nested type sections), so the
question is whether it can join the `record` arm outright or needs its own —
which is a question about inheritance (`object` can have a parent, records
cannot) and about the class-vs-record split in the specialization streamer, not
about the kind check itself. Nobody has traced it; do not treat this paragraph as
a design.

Note the second line of the corpus snippet: `strict private type` — a
visibility-qualified nested type section inside an `object`. Whoever takes this
should check that path is reachable before assuming the kind check is the whole
job.

## Gate

`make compiler/pascal26` (the byte-identical self-host fixedpoint) +
`python3 tools/forwardlint.py` + the repro above + the named generic tests. A new
test with FPC as the oracle. Track T sweeps the matrix.
