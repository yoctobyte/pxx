---
track: P
prio: 25
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "When two method overloads both take an ARRAY at the slot a `[...]` argument lands on, selection cannot separate them and falls through to arity, i.e. first-declared. `P2(N: Integer; A: array of Integer)` and `P2(N: Integer; A: array of const)` with `c.P2(2, [7, 8])` runs the Integer body; fpc 3.2.2 runs the array-of-const one. Silent — both bodies compile and run, only the printed line differs. Pre-existing and unchanged by f00d3d230, which narrows the bracket case to a single array candidate and deliberately declines this one: the speculative probe in FindUMethOverloadAhead still cannot PARSE a bracket argument, so it cannot rank two of them, and guessing would replace one silent wrong body with another."
---

# Two array parameters at one bracket slot are decided by declaration order

- **Type:** bug (compat) — **Track P** (`compiler/pasparser_call.inc`).
- Found while measuring the controls for
  [[bug-p-a-bracket-argument-turns-off-method-overload-selection]] (`f00d3d230`).

## The repro

```pascal
{$mode objfpc}
type TC = class
  procedure P2(N: Integer; A: array of Integer); overload;
  procedure P2(N: Integer; A: array of const); overload;
end;
...
c.P2(2, [7, 8]);
```

| | |
| --- | --- |
| fpc 3.2.2 `-Mobjfpc` | `vr n=2 cnt=2` — the `array of const` body |
| pxx at `f00d3d230` | `ints n=2 cnt=2` — the `array of Integer` body |
| pin v405 | `ints n=2 cnt=2` — **pre-existing, not a regression** |

Reversing the declaration order changes which body pxx runs. That is the tell:
nothing about the argument is being consulted.

## Why it is not fixed in `f00d3d230`

That commit made `ArgListHasBracketElem` return a mask of the bracket SLOTS and
narrowed the candidates on them. With **one** array candidate at the slot the
answer is unambiguous and it is taken. With two, the narrowing declines and
falls through to the arity path unchanged, on purpose:
`FindUMethOverloadAhead`'s probe parses arguments speculatively to learn their
types and **cannot parse a bracket argument at all** — no parameter to bind
against, so `ParseArgExpr` reads the `[` as a set literal and `Error` halts.
It therefore has no element type to rank `array of Integer` against
`array of const` with. Picking one anyway would be a guess wearing the shape of
a decision, and the failure mode is a silently wrong body either way.

Unblocking this needs the probe to become parameter-aware, which is the
residual of
[[refactor-p-the-overload-probe-cannot-see-the-argument-match-channels]]
(`done`, but its own summary says the `TypesCompatible` widening was not done).

## Is fpc even right here?

Unclear, and it matters for the prio rather than for the diagnosis. `[7, 8]` is
two integers and `array of Integer` is the closer fit by any element-type
reading; fpc prefers `array of const` regardless. **No real source is known
that wants either answer** — this shape came out of a control I wrote, not out
of a corpus. Rank it when something real asks for it; what must not happen is
someone re-deriving the boundary from scratch, which is why the rows above are
here.

Note the neighbouring case, which is NOT this one and is settled: a `tySet`
parameter at a bracket slot vetoes the narrowing outright, because there the
`[...]` really may be a set. fpc calls `M(1, ['a'])` against
`M(N: Integer; S: TCh)` / `M(N: Integer; A: array of const)` **ambiguous and
refuses it**; we accept it as the set. Us accepting what fpc rejects is not a
defect.

## Gate

`make compiler/pascal26`, the repro above matching fpc, plus
`tools/run_fgl_corpus.sh` 7/7 and `tools/run_pascal_conformance.sh` 391/0 —
the two rows that catch an overload-selection regression; quick alone does not.
