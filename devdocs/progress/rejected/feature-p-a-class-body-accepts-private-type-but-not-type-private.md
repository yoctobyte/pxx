---
slug: feature-p-a-class-body-accepts-private-type-but-not-type-private
title: "REJECTED: `type private` is refused by FPC too — both compilers agree on both orders"
track: P
prio: 25
type: feature
blocked-by: []
status: rejected
owner: frankB
created: 2026-09-06
summary: "REJECTED 2026-09-06 on a FALSE PREMISE: fpc does NOT accept `type private TF = (one, two);` in a class body. It refuses it in all four modes (default, -Mobjfpc, -Mdelphi, -Mtp) with Syntax error, \":\" expected but \"=\" found -- same line and same reason as pxx's own `expected ':' before '='`. The two compilers AGREE on BOTH orders: `private type` compiles under each and prints the same answer, `type private` is refused by each. The construct is fpc-testsuite tclass10b, a %FAIL row whose whole subject is that a visibility section after `type` resets the section so what follows must be a member and not a type -- so pxx passing that row is passing it FOR ITS OWN SUBJECT, which is the opposite of what this ticket recorded. Nothing to fix: refusing here is the specification."

---

# The measurement

```pascal
type TFoo = class
     private type              { ACCEPTED }
       TF = (one, two, three);
     private
       f: TF;
     end;
```

```pascal
type TFoo = class
     type private              { REFUSED: expected ':' before '=' }
       TF = (one, two, three);
     ...
```

# Ranked 25 on purpose

`private type` is the commoner spelling and works, so real code mostly does not
hit this; and the failure is a clean refusal at compile time, never a wrong
answer. It is here so the gap is recorded rather than rediscovered, and because
it is currently propping up a `%FAIL` corpus row that is not testing it.

`task-t-twelve-syntax-shaped-fail-rows-may-be-refused-by-a-parse-gap-rather-than-their-own-subject`

## 2026-09-06 (frankB) — rejected: the oracle was never run

**The premise is false.** This ticket says *"FPC accepts both orders"*. It does
not. Measured on the ticket's own probe:

```
type
  TB = class
    type private TG = (three, four);
    public function H: Integer;
  end;

pxx           pascal26:9: error: expected ':' before '='
fpc (default) tp1.pas(9,21) Fatal: Syntax error, ":" expected but "=" found
fpc -Mobjfpc  tp1.pas(9,21) Fatal: Syntax error, ":" expected but "=" found
fpc -Mdelphi  tp1.pas(9,21) Fatal: Syntax error, ":" expected but "=" found
fpc -Mtp      tp1.pas(9,21) Fatal: Syntax error, ":" expected but "=" found
```

All four modes, enumerated rather than assumed — the mode is the parameter that
has made two other measurements disagree today, so it is not left unstated. Same
line, same reason, same construct. And the OTHER order agrees just as exactly:

```
type TA = class private type TF = (one, two); public function G: Integer; end;

pxx   A 1        fpc -Mobjfpc   A 1
```

**So there is no asymmetry to close. There are two orders, one legal and one
not, and pxx and fpc make the same call on each.**

### The `%FAIL` reasoning is inverted, and that is the durable part

The ticket records this as *"found dispositioning tclass10b, whose `%FAIL` was
satisfied by this gap rather than by its own subject"*. It is the reverse.
`tclass10b.pp` is:

```pascal
{ %FAIL}
// check that "protected" or any other section resets the section type to accept regular fields
  Tfoo=class
  type private
    TF = (one,two,three);
```

Its subject IS that a visibility section after `type` resets the section, so
`TF = ...` is no longer a type declaration and must be refused. Run it through
both: pxx says `pascal26:12: error: expected ':' before '='`, fpc says
`tc10b.pas(12,8) Fatal: Syntax error, ":" expected but "=" found`. **Same line,
same reason.** The row passes in pxx *for its own subject*, which is the exact
opposite of the false pass this ticket was filed to record.

That distinction matters beyond this ticket, because the real pattern —
`tclass14a`, a `%FAIL` row satisfied by pxx dying at `stored` in ANY property
long before it reached a class property — is real and was closed today
(`27dff0dd7`). Two rows in the same file family, one a genuine false pass and
one not, and the discriminator between them is a single fpc run.

### What would have caught it in one command

The ticket says *"Measured 2026-09-06 by probe"*, and the probe was run against
pxx only. **A claim of the form "FPC accepts X" is not a measurement of pxx; it
is a measurement of FPC**, and nothing in the write-up records fpc having been
invoked. Us refusing what fpc refuses is not a gap in any direction — it is the
one outcome that needs no ticket at all.

Not moved to `known-incompat/`: nothing here is incompatible. Not `low-prio/`:
that would leave a false claim about FPC in the ranker forever. `rejected/`,
which is what a false premise means.
