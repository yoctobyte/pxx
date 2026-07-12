---
prio: 70
---

# Method default parameters land on the WRONG slot (silent wrong values)

- **Type:** bug (correctness — silent, no diagnostic)
- **Track:** P — Pascal frontend (shared `parser.inc`, so Track A file-lane)
- **Status:** done — found + fixed 2026-07-12, commit 2e6af610.
- **Found by:** compiling fcl-fpcunit for [[feature-pascal-corpus-fpcunit]].

## Symptom
A method **implementation** that repeats its declared defaults had every default
written to the *previous* parameter's slot:

```pascal
type TB = class procedure M(a: Integer = 1; b: Integer = 2); end;
procedure TB.M(a: Integer = 1; b: Integer = 2);
begin writeln('a=', a, ' b=', b); end;
...
o.M;        { printed a=2 b=2 — must be a=1 b=2 }
```

No error, no warning — just wrong values. Reproduced on the **shipping pinned
binary**, so this was live, not a regression from the work that found it.

## Root cause
`ParseSubroutine` injects the implicit `Self` at param 0 for a method impl and
shifts the staging arrays up by one — `pnames`, `ptypes`, `ptypesRec`,
`ptypesPtrElemTk/Rec`, `ptypesProcSig`, `parr`, `pbyref`, `pNDims`, `pDynDepth`,
`pDimLo/Span` — but **not** `pdefault` / `pdefaultval`. Those stayed at the
declared (unshifted) indices, so committing them wrote each default one slot low.

It stayed latent because the *class declaration* already registered the correct
(shifted) defaults; the impl pass then overwrote them with the misaligned copy.
A same-typed neighbour therefore just silently took the wrong constant.

## Fix
Shift the default arrays with the rest of the params, and zero slot 0 (Self).
The same commit adds string-literal defaults, whose new `pdefaultisstr/soff/slen`
arrays shift alongside — the mismatch is what surfaced the bug: a string default
misaligned onto an ordinal slot segfaulted instead of merely lying.

## Regression
`test/test_method_default_param_b246.pas` (in `make test`): covers ordinal
defaults, a defaulted call, a partially-defaulted call, and a string default that
is not the last parameter.

## Gate
`make test` green + self-host byte-identical. Both held.

## Log
- 2026-07-12 — found while compiling fcl-fpcunit; fixed in 2e6af610.
