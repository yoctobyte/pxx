---
slug: bug-a-a-label-section-must-come-last-in-a-routine
track: A
prio: 45
status: done
commit: f9f1a42bc
---

# A routine's `label` section must come last, or the routine will not parse

ISO Pascal fixes the order of a declaration block as **label, const, type,
var** — label FIRST. pxx accepted only the reverse: a `label` section in a
routine parsed correctly *if nothing followed it*, and any declaration after it
was a syntax error at the routine's `begin`.

```pascal
procedure P; label done; var k: Integer;   { canonical ISO order }
begin k := 1; if k = 1 then goto done; WriteLn('no'); done: WriteLn('yes'); end;
```

```
Expected: begin, but got: var (Kind: 7, Line: 2)
```

`var` before `label` compiled and ran correctly, as did every ordering at
program/unit scope. Confirmed against fpc 3.2.2 (`-Mobjfpc -O1`), which accepts
all of them.

## Cause

`pasparser_proc.inc` parsed the routine's declaration sections in one loop over
`[tkVar, tkConst, tkType, tkProcedure, tkFunction]`, and then handled `label` in
a **second loop further down**, after `EmitManagedLocalsZeroInit` /
`CompilePendingLocalInits` / the `out`-param clearing. With `label` first the
main loop never ran (its first token is an identifier, not `tkVar`), the second
loop consumed the labels, and the caller then met `var` where it wanted `begin`.
So the diagnostic pointed at `var`, four tokens past the real cause.

The four failing orderings are one bug, not four: anything at all after the
label section hits it — `const`, `type`, `var`, a nested routine.

## Fix

`label` is a declaration section like the others, so it belongs in the same
loop. The section body existed **twice** — once here and once in
`pasparser_prog.inc` for program/unit scope — which is why only one of the two
had the ordering defect. Factored into a single `ParseLabelSection` in
`pasparser_decl.inc` (included ahead of both callers) and called from both; the
routine loop now accepts `label` alongside var/const/type/nested-routine.

The trailing loop stays, reduced to a call: the main loop stops at the
out-param clearing, so a `label` section written *after* everything else still
lands there. Labels are purely declarative — they record a name into
`GotoLabelNOff/NLen/CodePos` and emit nothing — so parsing them on either side
of those emits is equivalent.

`devdocs/dev/normalise-dont-special-case.md`: the second copy is the one that
stays broken. It did.

## Verification

- `test/test_label_section_precedes_the_other_declarations.pas`, wired into
  `test-core`. Four routines: canonical ISO order (label, const, type, var),
  label-last (the order that always worked), label ahead of a nested routine,
  and two labels in one section. Output byte-identical to fpc 3.2.2.
- `make compiler/pascal26` self-host fixedpoint, converged in 1 round.
- `tools/gate.sh quick` green.

## Found by

A control-flow differential sweep (25 programs: try/finally crossed with
Exit/Break/Continue/raise/re-raise, case ranges and char cases, goto, repeat,
short-circuit evaluation). Every one of them shared a `procedure P11; label
done; var k: Integer;` helper in the common header, so the entire family failed
to compile at once — the bug was in the harness's own boilerplate, not in
anything the sweep set out to test.

The other 24 rows match FPC exactly. The one remaining divergence is deliberate
and already covered: pxx accepts overlapping/duplicate `case` labels with
first-match-wins semantics, and `--strict-case` rejects them the way FPC does.
