---
slug: bug-p-an-unknown-compiler-directive-is-silently-ignored
title: "The directive dispatch has 34 arms and no unknown-directive diagnostic"
track: P
prio: 35
type: bug
blocked-by: []
status: done
owner: frankS
created: 2026-08-28
summary: "compiler/lexer.inc's {$...} handler is an if/else chain of 34 CaseEqual(command, ...) arms with no terminal else, so ANY directive outside those 34 is silently ignored — no warning, no note, exit 0. {$FATAL} is one confirmed instance (bug-p-fatal-directive-is-silently-ignored) and the mechanism guarantees there are others. Filed separately from the {$FATAL} ticket on purpose: fixing {$FATAL} closes that ticket and leaves this generator intact."
---

# The mechanism, not the instance

Filed by frank-coordinator from a follow-up frankB flagged while filing
`bug-p-fatal-directive-is-silently-ignored`. **Separated deliberately** — CLAUDE.md's
`normalise-dont-special-case` rule says to grep for the sibling before closing a
double case, and here the sibling is *unbounded*: fixing `{$FATAL}` closes that
ticket and leaves the mechanism that produced it untouched.

**Measured, 2026-08-28:**

```
grep -c "else if CaseEqual(command" compiler/lexer.inc   ->  34
```

Thirty-four arms (`warning`, `message`, `error`, `mode`, …) and **no terminal
`else` that diagnoses an unrecognised directive.** A directive outside the set is
consumed and discarded: no warning, no note, exit 0.

## Why this is a bug and not a diagnostic-parity nit

Same reasoning frankB used for `{$FATAL}`, and it generalises: **a directive's
purpose is to change what the compiler DOES.** Ignoring one does not change a
message — it changes the artifact, or whether an artifact exists at all. A source
that says *"this configuration is unsupported, do not build"*, or that sets a range
check, an alignment, a calling convention, gets silently built the other way.

That is the silent-wrong-behaviour escape in CLAUDE.md's compat table, not the
deferrable "our diagnostic differs" row.

## What the sweep is

1. Enumerate the directives FPC/Delphi accept that real Pascal in our corpora
   actually uses, and diff against the 34.
2. **Do not trust a single extraction of either side** — the census that found this
   class in `lib/crtl` was written twice and each implementation silently dropped a
   different name (`atexit` to a `(*` filter; `longjmp` to `sort -u` under a UTF-8
   locale). Manufacture a disagreement.
3. Add the terminal `else`. **Its shape is the real decision:** a hard error breaks
   every source using a directive we do not implement but could safely ignore
   (`{$IFOPT}`, vendor-specific pragmas); silence is the current bug. A warning that
   names the directive is the likely answer, with a small allow-list of
   known-inert ones so the warning stays meaningful.

## Related

- `bug-p-fatal-directive-is-silently-ignored` [P, p35] — the confirmed instance.
  Note its own trap: `fatal` must join the `messageText` capture at
  `lexer.inc:1697` or the diagnostic comes out empty.
- Do not close this when that one closes. **This ticket is the generator; that one
  is one of its outputs.**

## Fixed 2026-09-04 (frankS, Track P)

The chain has a terminal arm now. It classifies rather than warning flatly,
because the ticket's open question — hard error, warning, or allow-list — has
three answers and not two:

- **class 0, inert:** recognised, and ignoring it leaves pxx doing what the
  source asked or something strictly more permissive. Silent. `{$X-}` is here:
  it asks us to REFUSE a discarded function result, we accept it, and CLAUDE.md
  says accepting what FPC rejects is not a defect.
- **class 1, recognised but not implemented:** FPC gives it meaning, we do not,
  and ignoring it changes a layout, a width or an evaluation. Warns, and says
  which. `{$PACKENUM}`, `{$PACKSET}`, `{$MINENUMSIZE}`, `{$Z1,Z2,Z4}`,
  `{$BITPACKING}`, `{$CALLING}`.
- **class 2, unknown:** warns as unknown. Almost always a misspelling.

**A one-polarity switch splits on the SIGN, not on the name** — `{$H+}` is pxx
behaviour and inert, `{$H-}` asks for a shortstring default we do not implement.
Same for `{$A}` and for `{$B}`, where it is `+` that asks for something we do
not do. **And the long spellings split the same way**, which is the sibling this
repo's normalise-dont-special-case rule is about: listing `longstrings` or
`booleval` as flatly inert would have put the consequential polarity back in the
silent set through its other spelling. `{$BOOLEVAL ON}` = `{$B+}`,
`{$LONGSTRINGS OFF}` = `{$H-}`.

**Warning, not error, and FPC settled it rather than taste.** Measured
2026-09-04: `{$PACKRECRDS 1}` (the ticket's own class, one letter dropped) gave
`SizeOf(T)=8` under pxx where `{$PACKRECORDS 1}` gives 5, silently; FPC says
`Warning: Illegal compiler directive "$PACKRECRDS"` and then lays it out the
same 8. The layouts already agreed — the entire divergence was the diagnostic.
`-Werror` reaches it, so a project can make it fatal without a flag of its own.

**The census the ticket asked for was written twice and the two mechanisms
disagree by construction** (a `grep -o` requiring the letter immediately after
`$`, and a Python walk allowing whitespace and the `(*$ *)` form). Positive
control fired: mech-1 misses `{$ mode delphi}` and `(*$H+*)`, mech-2 catches
both. On the real tree they agree on 54 names, and a static pass over every
`.pas/.inc/.pp` in the repo confirms the only occurrences that would now warn
are inside COMMENTS — which `make compiler/pascal26` corroborates by building
silent.

**The test's total count is the silence control and it is the part that
matters.** The failure value here is silence, so "the inert block stayed quiet"
is a row that passes on the broken compiler. `test_pascal_directive_unknown_warns.pas`
puts 19 inert directives above the five that must warn and asserts
2 / 3 / **exactly 5** — the third number is the only one that catches an inert
directive starting to warn, which is how this diagnostic would get switched off.

**It found real work immediately.** `--mimic-fpc-compiler --target=arm32` now
gets past `{$i fpcdefs.inc}` (see the packrecords ticket) and reports that FPC's
own compiler sources open with `{$H-}` and `{$PACKENUM 1}`, neither implemented
here. Both were silent before. Filed as
`feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus`.

## Log
- 2026-09-04 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b4017f96d.
