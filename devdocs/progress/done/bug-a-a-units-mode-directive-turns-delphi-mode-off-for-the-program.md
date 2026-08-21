---
slug: bug-a-a-units-mode-directive-turns-delphi-mode-off-for-the-program
track: A
prio: 70
type: bug
blocked-by: []
summary: "A `uses`d unit's {$mode} directive changed DelphiMode for the rest of the compile. Latent for months; live from 28bd01e11, which added {$MODE PXX} to 136 lib/rtl units — so any program that uses the RTL (i.e. every program) lost {$mode delphi}. Five test-core tests red on master, one of them a SEGFAULT."
status: done
owner: claude-A
---

# A unit's `{$mode}` turns delphi mode off for the program

## The regression

Reported by Track T as five simultaneous `test-core` reds, `bad a2ae11a64191`,
last good `6ab56d11a9aa`, five commits in range — `28bd01e11 feat(A): strict
flags scope by dialect ownership, not program-vs-unit`. Still red at HEAD when
re-measured (`fa7334d6b`), which is the check that matters: a tstate callback
names the sha it was found at, not the sha you are standing on.

| test | symptom at HEAD |
| --- | --- |
| `test_mode_delphi` | rejected: bare own name `Gate` warns instead of recursing |
| `test_mode_delphi_callarg` | rejected: `undefined variable (Dbl)` |
| `test_mode_delphi_methptr` | rejected: `"TCounter.Add" is a procedure and has no result` |
| `test_procvar_value_context` | wrong output |
| `test_delphi_bare_alldefaulted_arg` | **compiled, then SEGFAULTED** |

That last row is the one to notice. Four of five refused to compile — loud, and
easy to read as "the strict-flag commit got stricter". The fifth built a binary
that dumped core, which is the failure this dialect's `@`-optional rule produces
when it is silently switched off: `p := Dbl` stops meaning "take Dbl's address"
and starts meaning something the backend will happily emit.

## Cause

`ParseUsesUnitBody` scopes a unit's lexer state to that unit — it saves and
restores `CaseSensitiveMode` and `NestedComments` around the load, with a
comment naming `bug-unit-mode-directives-leak` (Synapse's `jedi.inc` sets
`{$MODE DELPHI}` and broke every lib/rtl unit lexed after it).

It did not save `DelphiMode`. And **one line** in `lexer.inc`'s `{$mode}`
handler sets both:

```pascal
      DelphiMode := CaseEqual(name, 'delphi');
      NestedComments := not DelphiMode;
```

So the leak was half-plugged: the derived flag was scoped and the flag it is
derived FROM was not. Textbook `devdocs/dev/normalise-dont-special-case.md` —
if you fix a bug on one arm of a double case, grep for the sibling.

## Why it stayed invisible until now

Every `{$mode}` a unit actually declared set `DelphiMode` to the value it
already had. `lib/` carried 9 mode directives before this month (`{$mode fpc}`,
8 × `{$mode objfpc}`) and all of them mean `DelphiMode := False`, which is the
default. A latent leak that only ever writes the value already there is
indistinguishable from no leak.

`28bd01e11` added `{$MODE PXX}` to 136 lib/rtl units. `pxx` is not `delphi`, so
every one of them now writes `DelphiMode := False` — and a delphi program that
uses *anything* from the RTL (including the ambient pulls, which is every
program) lost its mode at the first `uses`.

**The commit that exposed this is not the commit that caused it.** `{$MODE PXX}`
does exactly what it says; the scoping hole was there and untriggered. Reverting
it would have hidden the bug again rather than fixed it.

## Fix

One line each side, next to the flag it has to move with:

```pascal
    savedDelphiMode := DelphiMode;      { beside savedNestedComments }
    ...
    DelphiMode := savedDelphiMode;      { beside NestedComments := savedNestedComments }
```

The comment there now says the two must move together and why, so the next
person adding a mode-derived flag has the rule in front of them.

## Tests — two, because a one-armed fix passes a one-armed test

`test/modeunits/pxxdial.pas` (`{$MODE PXX}`) and `delphidial.pas`
(`{$mode delphi}`) are the props.

1. **`test_mode_delphi_unit_leak.pas`** — a `{$mode delphi}` program that uses
   both, then relies on `p := Dbl` (the `@`-optional value, delphi-only) *after*
   the uses clause. **The uses ORDER is the control:** the `{$MODE PXX}` unit is
   named LAST, so a leaking compiler ends with `DelphiMode` off and rejects the
   program. Written the other way round it compiles even when broken, because
   `delphidial`'s own `{$mode delphi}` leaks ON and hides the bug — measured on
   `pinned`, which accepts that ordering and rejects this one.
2. **`test_mode_delphi_unit_leak_off_fail.pas`** — the other arm: a
   default-mode program that uses the `{$mode delphi}` unit must still REJECT
   `p := Dbl`. A fix that only stopped the OFF leak passes test 1 and fails
   here.

## Measured after the fix

All five reported tests green against their exact `test-core` expected output
(`p5=10 / Gate=42 calls=3 / Tally=105`, `total ok 8 / 8`, `ApplyFn=42 / log=20 /
CallNul=14`, `total=12 / kicked=1`, `procvar-value-context OK`), both new tests
green, and `pinned` fails both new tests.

`test-core#src:test/test_record_helper_for_string_b331.pas` is **not** this bug —
different bisect range (`ee388cf3a fix(P): a typed class/record const was
global`), still red, filed separately.

## Gate

`make compiler/pascal26` (byte-identical fixedpoint) + the five reported tests +
the two new ones + `tools/gate.sh quick`.

## Log
- 2026-08-21 — resolved, commit 59cddd3b7.

## Follow-up measurement: it covered four more reds

After the fix landed, the three remaining delphi-shaped open regressions in
`TSTATE.md` were re-checked at HEAD and are green too — they were the same bug
reported by a different job (`test-nilpy`, whose row set includes these `.pas`
tests), with a much wider bisect range (`bad 23becd24b8e5`, 109 commits) that
never named the real commit:

- `test_pascal_at_procvar_mode.pas@1`
- `test_pascal_mode_switch_cli.pas@2`
- `test_pascal_self_result_delphi.pas@1` and `@2`

All nine of their Makefile assertions verified by hand against their exact
expected output, including the two that must DIFFER between `-Mdelphi` and
`-Mobjfpc` (a mode flag that is ignored fails those by construction) and the
warn-count row that must be 0 in delphi mode.

Worth recording for the shape, not the count: **one cause, three bisect ranges,
five commits / 109 commits / 3 commits wide.** A wide range is not weak
evidence of a different bug, it is often the same bug on a job that runs less
often — so re-measuring every open red at HEAD after a fix costs one command
and closed four extra rows here.
