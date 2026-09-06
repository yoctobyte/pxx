---
slug: bug-a-a-generic-body-takes-its-directive-state-from-the-specialization-site
track: A
prio: 40
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankS
blocked-by: []
title: "A generic body takes its {$R}/{$Q}/{$I}/… state from the SPECIALIZATION SITE, not from where the template was written"
summary: "A generic method body is compiled under whatever directive state is in force where it is SPECIALIZED, discarding the state its own source wrote. Both directions measured with an isolating control: an identical body in a PLAIN class in the same unit raises correctly, so it is generics and not units. Missing-check direction — a body wrapping `field:=l` in {$R+}, specialized under {$R-}, drops the check and stores 1234 as 210 (fpc-testsuite tgeneric7.pp, whose own comment calls it 'checks proper saving of compiler state'). FALSE-REFUSAL direction, the worse half — a body under {$R-} specialized under {$R+} GAINS a check it never asked for, so a library that deliberately turned checking off is overridden by its consumer. Cause is NOT range-check code: ShiftTokParallel fills a splice gap from the token before it (right for a synthesized token, wrong for a specialization's verbatim template copies), and the specializer already overwrites TokSrcOff/TokSrcLen right after the shift for exactly that reason while leaving the NINE directive states behind. ShiftTokParallel's own comment predicted this caller class and the sibling channel was never carried. NOT reachable through pxx's own RTL today — neither collections.pas nor p256field.pas contains a directive, and both compile and run correctly under a {$R+} consumer — so this is latent here and live for FPC-shaped library code."
---

# Measured 2026-09-06, compiler `2b936bf5b43f` (commit e8bbdae43)

Two units, one body, differing only in `generic`:

```pascal
unit ugr;  { plain and generic side by side, same method text }
{$R-}
procedure TPlain.test; begin l := 1234; {$R+} field := l; {$R-} … end;
procedure TGen.test;   begin l := 1234; {$R+} field := l; {$R-} … end;
```

```
program {$R-}, calls TPlain.test   -> Runtime error 201     CORRECT
program {$R-}, calls TGen<byte>    -> "gen stored 210"      WRONG (check dropped)
program {$R+}, calls TGen<byte>    -> Runtime error 201     right answer, wrong reason
```

The third line is the tell: flipping a directive **in the program** changes
whether a check inside a **library body** fires. The body's own `{$R+}` is
never consulted. The inverse confirms it from the other side — `ugr2`, whose
body is entirely under `{$R-}`, raises 201 when specialized under `{$R+}`.

## Where

`lexer.inc` `ShiftTokParallel` fills the inserted gap from `src := atPos - 1`,
i.e. the splice site. Its comment already states the limit:

> *"A caller that HAS real spans cannot say so through this procedure, so it
> does not try to: the specializer overwrites these two slots itself, right
> after this shift."*

`pasparser_generic.inc` `SpecializeStreamAt` does that overwrite for
`TokSrcOff`/`TokSrcLen` (~line 790) and for nothing else. The nine positional
directive states — `TokPackRecords`, `TokQChecks`, `TokAssertions`,
`TokRChecks`, `TokIChecks`, `TokNChecks`, `TokScopedEnums`, `TokPackEnum`,
`TokHMinus` — are owed the same carry and never got it. Per-token, not
per-template: `ugeneric7` flips `{$R}` twice *inside one method*.

## Recommended shape, and why it is not landed here

Capture the nine states in `CaptureTemplateTokenFrom` (~line 873, beside the
existing `TemplateSrcOff` capture) into nine `Template*` arrays; give the spec
buffer **one** new column, `SpecTmplIdx[i]` = the originating template index,
set at the same ~5 sites that already set `SpecSrcOff`; have
`SpecializeStreamAt` copy the nine from `Template*[SpecTmplIdx[i]]`. Substituted
tokens keep their template index (the state is about the source POSITION, which
survives substitution); only genuinely synthesized tokens take -1 and fall back
to `ShiftTokParallel`'s lexical answer, which is correct for them.

### Sequencing, and a trap that decides it (frankH, relayed 2026-09-06)

`MAX_TEMPLATE_TOKENS` is the *small* end of the conversion problem, not the
`MAX_IR` end: six arrays in two parallel trios, two cap sites, ten refs of which
eight are declarations. So converting it is one `Ensure` growing six arrays —
**and these ten columns then become ten `SetLength`s inside it rather than ten
more fixed tables to keep in lockstep by discipline.** Land this AFTER that
conversion, not before.

**The trap, and it is why "after" is not merely tidier:** the `Specialize` trio
has NO cap site of its own. It is bounded *implicitly* through the Template
pool's — `SpecializeToBuffer` runs `while i < count` with `subCount` advancing at
most once per iteration, so `subCount <= count <= MAX_TEMPLATE_TOKENS` with no
guard anywhere. Converting the Template trio ALONE therefore silently un-bounds
the Specialize trio: `count` can exceed 65536, six arrays get written at
`subCount`, nothing fails, and the symptom surfaces somewhere else entirely.
All six move together, with an explicit Spec guard added in the same change.
Anyone adding columns here inherits that constraint. See
[[feature-dynamic-compiler-tables]].

Ten new columns, and that is the reason this is ranked rather than landed:
`MAX_TEMPLATE_TOKENS` pools are still fixed `array[0..N-1]` tables, and
[[feature-dynamic-compiler-tables]] (frankH) is actively removing fixed tables
from `defs.inc` — adding ten worth ~2.6 MB of BSS into that lane wants its
owner's sequencing, not a unilateral landing. **Do not use a record** for the
nine: a new record type in the compiler's own source risks the
`CheckBuiltinRecSize` wall that makes `TGenericFunc` unmodifiable.

## What it buys

`tgeneric7.pp` in the fpc-testsuite corpus (skip reason already rewritten to
this mechanism, `e8bbdae43`). The `{$R}` face is the one with a corpus row; the
other eight states are the same defect and have no test asserting them either
way.
