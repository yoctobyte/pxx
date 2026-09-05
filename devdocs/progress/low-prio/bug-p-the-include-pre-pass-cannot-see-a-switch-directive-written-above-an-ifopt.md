---
slug: bug-p-the-include-pre-pass-cannot-see-a-switch-directive-written-above-an-ifopt
track: P
type: bug
prio: 20
status: low-prio
found: 2026-09-05
found-by: frankD
owner: ""
blocked-by: []
summary: "ExpandIncludes now answers {$IFOPT} from PasIfOptState like the lexer does (4038b32d0), but it tracks DEFINES and not switch DIRECTIVES, so a {$R+} written in the source above an {$IFOPT R+} is invisible to it and the letter answers at its command-line/default state. Only bites when all three are in one file: a switch set in source, an {$IFOPT} on that letter, and an {$I} inside the arm -- then the include is silently dropped and neither arm runs. Real and reproducible; low-prio because the shape is rare and the six default-ON letters, which is where {$IFOPT} guards usually sit, are already correct."
---

# The include pre-pass answers `{$IFOPT}` at the default state, not the source's

`ExpandIncludes` (`compiler/elfwriter.inc`) splices `{$I}` includes in before
the lexer runs. Since `4038b32d0` it asks `PasIfOptState`, the same function the
lexer uses, so the eight modelled letters answer honestly — **at whatever state
the command line and the defaults left them.** It tracks `{$define}` (it saves
and restores `savedDefineActive`) and does not track switch directives.

## Repro

```pascal
program t;
{$R+}
begin
{$ifopt R+}
  {$I guarded.inc}
{$else}
  WriteLn('else arm');
{$endif}
  WriteLn('done');
end.
```

pxx prints `done` alone. fpc prints the included line and `done`. **Neither arm
runs**: the pre-pass reads R at its default (off), drops the include, and the
real lexer — which *did* see `{$R+}` — then takes the true arm and finds it
empty. No diagnostic.

## Why it is low-prio and not rejected

It needs all three in one file: a switch set **in source**, an `{$IFOPT}` on
that letter, and an `{$I}` **inside** the arm. `{$IFOPT}` guards in real code
overwhelmingly sit on the default state, and the six letters that default ON
here (C I Z G J X) are already right. `R` and `Q` default off, so the guard and
the old hardwired answer agree unless the source moves them.

Recorded rather than fixed because the fix is a different size: the pre-pass
would have to track switch state textually — a second, partial implementation
of the lexer's switch handling, which is the *third* copy of that logic and the
thing `devdocs/dev/normalise-dont-special-case.md` warns about. Doing it right
probably means the pre-pass consulting one shared switch-state walker rather
than growing its own.

Parent: `bug-p-ifopt-is-hardwired-false-so-the-wrong-arm-compiles`, whose stated
residual (G, J, X) is closed.
