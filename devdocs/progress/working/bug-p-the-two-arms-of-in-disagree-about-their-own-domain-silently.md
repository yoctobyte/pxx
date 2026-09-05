---
slug: bug-p-the-two-arms-of-in-disagree-about-their-own-domain-silently
title: "`x in [...]` has a 64-bit domain with constant elements and a 0..255 domain with a variable one, chosen silently"
summary: "ParseSetMembershipAST picks a compare chain when every element is constant and a 256-bit mask when any element is a variable. After 831919a7d the first has a full Int64 domain and the second still has 0..255, so `q in [300]` is TRUE and `q in [r]` with r=300 is FALSE — same construct, no diagnostic either way. FPC warns here and pxx says nothing; the recommendation is to diagnose, not to widen."
track: P
type: bug
prio: 35
status: working
found: 2026-09-05
found-by: frankO (the check bug-p-set-membership-item-constant-truncated-to-32-bits asked for by name)
owner: frankB
---

## The fact

```pascal
var q, r: Int64;
q := 300; r := 300;
WriteLn(q in [300]);   { TRUE  — constant arm, compare chain }
WriteLn(q in [r]);     { FALSE — runtime arm, 256-bit mask   }
```

Measured at `831919a7d`. Both lines are the same operator on the same values;
the only difference is whether an element is spelled as a literal. Nothing is
reported.

Full runtime-arm row set (`q in [4294967297, r]`, r = 9):

| q | pxx | fpc 3.2.2 |
| --- | --- | --- |
| 1 | TRUE | TRUE (+warning) |
| 4294967297 | FALSE | TRUE (+warning) |
| 9 | TRUE | TRUE |
| `q in [r]`, q = r = 300 | FALSE | FALSE (+warning) |

## Why this is filed as the DOMAIN question and not as the 2^32 rows

`bug-p-set-membership-item-constant-truncated-to-32-bits` closed the constant
arm and said in its own body that the runtime arm is broken "by what looks
like a different mechanism", and that **neither arm going green is evidence
about the other**. It is a different mechanism, and reading FPC changed what
the finding is:

```
rt.pas(7,26) Warning: range check error while evaluating constants
             (4294967297 must be between 0 and 255)
```

So the 2^32 rows on this arm are an **out-of-domain element**, which FPC
itself diagnoses. CLAUDE.md is explicit that where an input is only produced
by a mistake, FPC's post-warning value is not a specification and matching it
is not a goal — so `q in [4294967297, r]` answering FALSE is **not** the
defect, and this ticket does not ask for it to be changed.

**The `q = r = 300` row is the defect**, because 300 is not exotic and is
in-domain on the arm next door. pxx's constant arm is a compare chain with no
set at all behind it, so it deliberately has a much wider domain than a Pascal
set; the mask arm is a real 0..255 set. Both choices are defensible. Having
the source silently select between them is not.

## Recommendation: diagnose, do not widen

Widening the mask to cover 0..2^63 is not on — a real Pascal set is 0..255 and
the mask is the right representation for it. The cheap, CLAUDE.md-shaped fix is
to **make the mistake visible**: when the runtime arm sees a constant element
outside 0..255, say so, the way FPC does. That converts a silent wrong answer
into a named stop and leaves both arms' representations alone.

Open question for whoever takes it, and the reason this is not a one-liner:
whether the diagnostic should also fire for a *variable* element that happens
to be out of range at runtime (FPC does not — its warning is
"while evaluating constants"), or whether that stays a silent FALSE.

## Prio: 25 -> 35, and deliberately not higher

Raised because the reachable row is `r = 300`, not 2^32: a set with a variable
element is ordinary code (the parser's own comment cites fcl-json scanning with
`FTokenStr^ in [#0, C]`), and the arm is chosen by whether an element is
spelled as a literal, so this bites on a REFACTOR — replacing a literal with a
constant-valued variable silently changes the answer.

**Not higher, and the reason is worth keeping so nobody re-inflates it:** FPC
answers `q in [r]` with r = 300 FALSE as well, so a program written against FPC
sees no divergence and no real-world Pascal is relying on the TRUE. What pxx
adds is an internal inconsistency plus a missing diagnostic, and CLAUDE.md
ranks a differing diagnostic as deferred. So the harm is real but it is
refactor-time surprise, not a wrong answer that ships. 35 is a wrong answer
from code that compiles; it is not a 55.

The coordinator independently suggested ranking this up and agreed with the
reachability argument. Recording that it was raised on the measurement rather
than on the endorsement — the endorsement is not the evidence.

## Repro

```
printf 'program t;\nvar q,r:Int64;\nbegin q:=300; r:=300;\n WriteLn(q in [300]);\n WriteLn(q in [r]);\nend.\n' > /tmp/t.pas
./compiler/pascal26 /tmp/t.pas /tmp/t && /tmp/t     # TRUE then FALSE
```
