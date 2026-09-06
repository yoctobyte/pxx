---
track: P
prio: 70
type: bug
blocked-by: []
status: open
owner: frankS
---

# A bare method-overload call accepts any argument type and runs the first body

Measured 2026-09-06 at compiler `4dc48164a5ed`. `TT` has `Take(Integer)` and
`Take(string)`; `TT.Go` calls `Take` BARE (implicit Self) with arguments of
neither type:

```pascal
var r: TRec; d: Double; o: TObject;
begin
  r.a := 7; d := 2.5; o := nil;
  Take(r); Take(d); Take(o);
end;
```

    pxx:  INT body: 7      INT body: 0      INT body: 0
    fpc:  2 errors, refused

`Take(r)` runs the **Integer** body and prints **7** — the record's first
field, read as an integer. Not a refusal, not a crash: a plausible wrong value,
which is this repo's expensive class exactly. `Double` and `TObject` reach the
same body as 0.

## This is the sibling of a fix that already landed

`pasparser_call.inc`'s own comment, in the routine this happens in, describes
the identical defect for ARRAYS and says it was closed:

> *"`d.One(ia)` with `One(v: Integer)` and `ia: array[0..2] of Integer`
> compiled and printed the array's ADDRESS (4306992), while the identical free
> `One(ia)` was refused -- because the free path fills MatchArgArray and this
> probe could not."*

The repair filled the array channel. Record, float and class-instance arguments
take the same route and were not filled, so the arm was fixed for the shape
that was reported and left open for its siblings — `normalise-dont-special-case`'s
"fixed one arm of a double case? grep for the sibling before closing", from the
inside.

## The asymmetry that makes it quiet

The FREE path refuses these; the METHOD path does not. So the same call written
two ways gives two answers, and the one people write inside a class body is the
permissive one. Nothing warns.

## Found while diagnosing something else

Discovered trying to build a fixture for the method-overload argument-type
diagnostic: I needed a call that SHOULD be refused and could not construct one
in a single file, because every wrong-typed argument I tried was accepted.
Recorded here rather than as a footnote, because "I could not make this fail"
is the finding.

Related but distinct:
`bug-p-a-unit-redeclaring-a-builtin-interface-alias-types-it-as-a-record` —
that one is a refusal that should have succeeded; this one is an acceptance
that should have been refused. They meet in the same probe.
