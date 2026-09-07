---
prio: 60
track: P
status: done
summary: "FIXED 2026-09-07 at compiler b744c685f77c. A generic template's per-token directive snapshots ({$R} {$Q} {$C} {$I} {$H} {$NILCHECKS} {$SCOPEDENUMS} {$PACKRECORDS} {$PACKENUM}) did not travel through the specialization pool, so a specialized body took all nine from the SPECIALIZATION SITE. Both directions were wrong and they fail differently: a template {$R+} region instantiated under {$R-} silently dropped the check (1234 stored as 210 where fpc raises 201), and a template {$R-} region instantiated under {$R+} gained a check the source never asked for. ShiftTokParallel fills a splice gap from the token BEFORE it -- right for a synthesized token, wrong for a verbatim copy of a template token -- and the specializer overwrote only TokSrcOff/TokSrcLen afterwards. Three new pool channels carry all nine; conformance row tgeneric7 burns; fixture test_gendirstate26."
owner: frankS
resolved: b829cc7cc
---

## What was wrong

A directive runs in the LEX pass, so the only record of what was in force at a
token is the per-token snapshot the lexer writes — nine parallel arrays beside
`Tokens[]`. A generic template is buffered into `TemplateTokens[]` and spliced
back into `Tokens[]` at the specialization site.

`ShiftTokParallel` fills the gap those spliced tokens occupy from **the token
immediately before the splice**, and its own comment says why that is right:
*"Directive state is LEXICALLY CONTINUOUS, so a spliced token inherits the state
in effect immediately before it."* True for a SYNTHESIZED token. False for a
verbatim copy of a template token, which was lexed somewhere else entirely.

The same comment already names the fix, for the other channel:

> IT IS NOT THE RIGHT ANSWER FOR EVERY CALLER … A generic specialization splices
> tokens that are VERBATIM COPIES of template tokens, each with a real source
> range, so zeroing lost it … **Any future caller splicing real tokens owes the
> same overwrite.**

That was written for `TokSrcOff`/`TokSrcLen` (95c98db70) and the nine directive
channels are the sibling arm of the same double case.

## Measured, both directions

| | template says | site says | fpc 3.2.2 | pxx before |
| --- | --- | --- | --- | --- |
| `byte := longint(1234)` | `{$R+}` | `{$R-}` | 201 | **210, no diagnostic** |
| `byte := longint(1234)` | `{$R-}` | `{$R+}` | 210 | **201 on legal code** |

A silent wrong answer one way and a spurious runtime error the other. The
discriminator that says this is the SPLICE and not the unit boundary: the same
body in a plain (non-generic) class in a used unit is correct.

## The fix

Three channels through the pool, in `pasparser_generic.inc`:

- `CaptureTemplateDirs` — live token → template pool, called from
  `CaptureTemplateTokenFrom` (and `CaptureSyntheticTemplateDirs` from the three
  synthetic-token sites, which take the state at the template's own parse
  cursor).
- `CopyTemplateDirsToSpec` — template pool → substitution buffer, called once at
  the TOP of `SpecializeToBuffer`'s loop. **Every arm, including the two that
  rewrite the token's text**: the spelling channel is cleared there because the
  token stops saying what the template said, but a directive region is a
  property of where a token SITS, not of what it spells.
- `RestoreSpecDirs` — substitution buffer → live token, in
  `SpecializeStreamAt`'s write loop, immediately after the two spelling slots.

**Parallel arrays, not a record, and not by preference.** A record's layout is
hard-coded in `symtab.inc`'s `REC_*` tables and baked into the compiler binary,
so round 0 of the fixedpoint cannot compile a new field — measured before, at
`GenericFuncParams`, and taken as read here.

## Verified

- **`tgeneric7.pp` burns** — its `{ %result=201 }` is exactly this defect, and
  its skip row had already diagnosed the cause correctly. Conformance
  412 → 413 pass, 88 → 87 skip, gap rows 53 → 52.
- **`test_gendirstate26`** —
  `test/test_a_generic_body_keeps_its_own_directive_state.pas`, twelve rows
  identical to fpc 3.2.2. **Three channels, both directions, two sites.** One
  template holds an `{$R+}` region and an `{$R-}` region, a `{$C+}` and a
  `{$C-}` region, an `{$H-}` and an `{$H+}` local; it is specialized once under
  `{$R-}{$C-}{$H+}` and once under `{$R+}{$C+}{$H-}`, opposite in all three, and
  the two blocks must print IDENTICAL rows. A single specialization would have
  passed on half the bug. The pinned compiler differs on six of the twelve —
  three dropped in site A, three inserted in site B.
- gate quick GREEN; self-host fixedpoint converged.

## Not covered

`{$Q}` has a channel here like the rest but no row in the fixture: fpc 3.2.2
does not raise on `high(longint) + 1` under `{$Q+}` where pxx does, so an
overflow row would assert a divergence that is not this ticket's. Its channel
travels with the other eight and is asserted only structurally.
