---
track: P
prio: 45
type: bug
blocked-by: []
status: done
owner: frankB
created: 2026-09-06
found-by: frankB
summary: "`function WordPosition(const N: Integer; ...): Integer; var i, n, count: Integer;` declares a parameter `N` and a local `n` in one routine. Pascal is case-insensitive, so that is ONE identifier declared twice and fpc refuses it as a duplicate; pxx accepted it silently and registered two symbols. Three routines in our own `lib/rtl/strutils.pas` were written that way and read the two as different variables, and four of the five fixtures in the 0dd59f05 cascade were `const SPARE` beside `var spare` at PROGRAM scope -- one of them handed a signal handler a stack pointer computed from an array read as an integer. Every instance was found as a wrong value far from the declaration that caused it, and every one is decidable AT the declaration. FIXED 2026-09-06: `CaseDupRefuse` in `SymHashInsert` refuses two case-insensitive declarations of one name in one scope, naming the implicit `Result` when that is the other side. THE CASE-SENSITIVITY BIT IS WHAT MAKES IT SAFE: 340 distinct GDK keysym pairs arrive through a C header import and are two names by construction, as are the `{$CASESENSITIVE ON}` fixtures and every NilPy symbol, so the rule asks BOTH sides` SymCaseSensitive rather than the current mode. MEASURED COST OVER THE CORPUS: exactly ONE file, and it is this ticket`s own fixture, which inverted from running to refused as its earlier header said it must. THE RE-COUNT IS WHY THIS DID NOT LAND ON THE FIRST CENSUS: it found EIGHT sites the first count called same-scope that are LEGAL -- an `on E: Exception` binder beside an outer `var e`, which fpc accepts with no warning -- because a HANDLER IS A SCOPE and nothing recorded that, so a refusal written on the old flag would have rejected the fixture that exists to prove the construct legal."
---

# A parameter and a local that differ only in case are two symbols

Measured 2026-09-06 at compiler `6a676f92b94d`.

```pascal
function WordPosition(const N: Integer; const S: AnsiString;
                      const WordDelims: TSysCharSet): Integer;
var i, n, count: Integer;
begin
  n := Length(S);
  while (i <= n) and (count <> N) do ...        { `n` and `N` are ONE identifier }
```

fpc 3.2.2 refuses this (`Duplicate identifier`). pxx registers two symbols and,
until the resolution fix above, kept them apart by case — so the routine
*worked*, and would have started returning wrong answers the moment the lookup
was corrected. Three routines in `lib/rtl/strutils.pas` had this shape
(`WordPosition`, `ExtractWordPos`, `ExtractDelimited`); the locals were renamed
to `sLen` as part of that fix.

## Why it is worth a diagnostic rather than a rename campaign

The collision is decidable **at the declaration**, from two lists we already
have, and it is otherwise found as a wrong value in a routine that reads the two
names as different variables. Everything about this defect is cheap on one side
of the line and expensive on the other.

## Why it was not landed together with the resolution fix

A refusal is a narrowing, and the population is unknown: no sweep has asked how
many routines across `lib/**`, `compiler/**`, the corpus and the frontends
declare a parameter and a local differing only in case. Two were found by
accident, in one file, because a *different* change made them fail. **The first
step is the census, not the diagnostic** — and if the count is large, the answer
may be a warning rather than an error.

## Boundary, so nobody re-derives it

Two LOCALS differing only in case, or two PARAMETERS, are the same question and
should be caught by the same check. A local differing in case from a symbol in an
OUTER scope is NOT this: that is ordinary shadowing and is now resolved
correctly.

## Neighbour

[[bug-p-an-exact-case-match-in-an-outer-scope-beats-a-case-insensitive-one-in-a-nearer-scope]]
is the lookup half; this is the declaration half, and only the declaration half
can name the file that is wrong.

## The census instrument landed 2026-09-06 — `PXXDBG=a.casedup`

`SymHashInsert` reports every symbol registered under a name that differs only
in case from one already visible: `samescope=1` is this ticket's population,
`samescope=0` is ordinary shadowing of an outer name. It is a committed channel
and not a local print, deliberately — frankS's condition for running it over the
fpc-testsuite corpus, and the right one: *a measurement taken with an
uncommitted compiler is one nobody can reproduce.*

`test/test_a_parameter_and_a_local_that_differ_only_in_case_are_two_symbols.pas`
is its positive control, drawn from this population rather than from the
shadowing one, and it is wired into `test-core` with a matching silent-when-off
control. **When the diagnostic lands, that file must be REFUSED and its
assertion inverts** — it asserts the channel, never the values.

### First count: `compiler/compiler.pas` — 21 pairs, ZERO same-scope

So our own compiler has no instance of THIS defect. What it does have is the
same collision across scopes under `{$CASESENSITIVE ON}`, which fpc ignores;
that is a different bug and is filed as
[[bug-a-the-compilers-own-source-means-two-different-things-to-fpc-and-to-pxx]].

The corpus count is still open, and it is the one that decides error-or-warning.

## The corpus census — 2026-09-06 (frankA), and it answers error-vs-warning

Run at frankB's invitation, because this ticket blocks on its own sentence:
*"The corpus count is still open, and it is the one that decides
error-or-warning."*

**Population:** every fixture under `test/`, compiled with `--threadsafe` so the
ones that need it reach their program body, plus every unit they transitively
use. Twice — once at `10797249be20` and again at `e5b9b3a096b1` after frankB's
`samescope` fix landed. The corpus GREW by four files between the two runs
(2053 then 2057); both numbers are printed rather than the later one alone.

**Every count below is of DECLARATION SITES, not occurrences.** A pair inside a
shared unit is re-reported once per fixture that uses it: 2847 occurrences
collapse to 2363 sites. Ranking by occurrence says `pylib`, `rsa`, `ecdsa`,
`ed25519` — which is a ranking of *how many fixtures use a unit*, not of how
many declarations are wrong, and it is how the first read of this census got the
shape of the problem exactly backwards.

**Reach, so the zeroes are not vacuous:** 2057 attempted, 1790 compiled to the
end, **267 did not**. Those 267 report zero pairs for their own bodies and that
zero means nothing. This is the trap recorded in
[[bug-a-the-compilers-own-source-means-two-different-things-to-fpc-and-to-pxx]],
applied to this sweep.

### The result: eight same-scope sites, one of which is this ticket

| site | pair | what it is |
| --- | --- | --- |
| `bignum:495` | `result` / `Result` | **the only real instance** — a routine-local beside the implicit function result |
| `test_a_parameter_and_a_local_..._two_symbols:47` | `n` / `N` | this ticket's own positive control |
| `test_case_sensitive:4`, `test_case_sensitive_error:7` | `value` / `Value` | deliberate `{$CASESENSITIVE ON}` fixtures |
| `test_class_inherits_from_tobject:93,101,102`, `test_threadsafe_exception_managed_fields:52` | `E` / `e` | a DIFFERENT defect — the exception-handler binder leaked its scope; fixed separately |

Plus 342 in `gtk3`, which are **correct** and are the trap in this data. They are
GDK keysyms arriving through `uses gtk3_c`, a C header import, where
`GDK_KEY_Armenian_AT` and `GDK_KEY_Armenian_at` are legitimately two names.
Probed with four values that all differ, so a merge would be visible:

    Armenian_E = 0x1000537   Armenian_e = 0x1000567
    AT         = 0x1000538   at         = 0x1000568

All four resolve correctly and distinctly from a case-INSENSITIVE program —
lookup respects the declaring unit's case mode. `a.casedup` reports them because
it fires whatever the case mode is, which its doc says is deliberate. **The
consequence is that a reader ranking by `samescope=1` count goes straight to the
one file that is fine**, and the channel's doc should say so.

### Recommendation: ERROR, and re-ranked to 45

**The narrowing costs one site.** That is the whole argument. A refusal was held
back because *"a refusal is a NARROWING over a population nobody has
enumerated"*; the population is now enumerated and it is `bignum:495` — which
fpc refuses outright (`Error: Duplicate identifier "RESULT"`), and which only
survives because `lib/rtl` is built by `$(PXX_STABLE)` and never by the seed. A
warning buys nothing when there is one thing to warn about.

**`result`/`Result` needs the diagnostic to name the implicit side.** The
collision is with a name the LANGUAGE declares, not one the author wrote, so a
message pointing only at the user's declaration points at nothing.

**Prio 35 -> 45.** Not higher: every instance known today is fixed, so nothing
is red on it. Not left at 35: the class has now produced silent wrong values
three times in `lib/rtl/strutils.pas`, five times across the cascade fixtures —
including a signal handler handed a stack pointer computed from an
array-as-integer — and each was found as a wrong value far from the declaration
that caused it.

### The stated boundary is too narrow, and four of five instances fall outside it

This ticket's Boundary section says two locals or two parameters are the same
question, and that a collision with an OUTER scope is not. **Four of the five
cascade fixtures were neither**: `const SPARE` beside `var spare` at PROGRAM
scope — one scope, and the case fpc refuses. The population is *two declarations
in one scope differing only in case*, at any scope level, and `samescope` could
not report it at program scope until frankB's fix because it derived from
`Procs[CurProc].ScopeBase` with `CurProc = -1`.

### What this census does NOT cover, measured rather than guessed

The population is the transitive closure of the fixture corpus. `lib/` holds 141
`*.pas` files and **I did not establish which of them no fixture reaches** — a
unit nothing imports contributes no pairs and is indistinguishable here from a
clean one. `examples/**` and the frontend corpora are not covered at all.
`compiler/compiler.pas` was counted separately by frankB (21 pairs, all
cross-scope).

## RESOLVED 2026-09-06 — and the second census is the finding

The diagnostic is `CaseDupRefuse`, called from `SymHashInsert`. What is worth
recording is that **the census this ticket blocked on was not enough, and the
re-count is what stopped a false refusal.**

### The rule, and the one field that makes it safe

Two declarations whose names differ only in case, visible in the same scope, and
**neither declared under a case-sensitive mode** — `SymCaseSensitive` on BOTH
sides, not the mode in force at the check. That last part is the whole safety
argument and it is not a heuristic:

| population | pairs | why it is not a duplicate |
| --- | --- | --- |
| GDK keysyms via `uses gtk3_c` | 340 distinct | a C header import; `GDK_KEY_dead_A` and `GDK_KEY_dead_a` are two names, and they resolve correctly and distinctly |
| `{$CASESENSITIVE ON}` fixtures | 2 | the directive says so |
| every NilPy user symbol | — | `DeclCaseSensitive := CaseSensitiveMode or NilPyUserCode` |

A reader ranking by raw `samescope=1` count goes straight to gtk3, which is the
one file that is fine. The bit is what separates them, per declaration, and it
was already being recorded.

### The re-count found eight LEGAL sites the first census called same-scope

frankA's census answered the question this ticket blocked on — ERROR, one real
site — and it was right about that. Re-measuring at HEAD before landing found
the site already gone (`bignum:495`'s local `result` is renamed to `acc`) and
found something the first count could not have known it was reporting:

```
on E: Exception do WriteLn(E.Message);   { beside an outer `var e` }
```

**fpc accepts this with no warning** — measured, not assumed — and
`test_exception_handler_binder_is_scoped_to_its_handler.pas` exists in this tree
to assert exactly that the binder is scoped to its handler. `a.casedup` reported
all eight such sites, across three fixtures, as `samescope=1`.

The cause: **a handler is a scope, and nothing recorded that.** A routine's scope
is named by `Procs[CurProc].ScopeBase`; a handler's had no name, so at program
scope the derivation fell through to "same unit" and the binder read as a
program-scope declaration. `CurHandlerScopeBaseP1` records it now, set before
`AllocVar` because the binder is itself in the handler's scope, saved and
restored so nested handlers nest.

**This is the second time this derived flag has been wrong, in opposite
directions** — first it could never report 1 at program scope, which hid four of
the five cascade fixtures; then it reported 1 for something legal. Both times a
peer or a re-measurement caught it, never the flag itself. So every input it is
derived from is now printed beside it (`proc=`, `base=`, `hbase=`, `cs=`,
`vscs=`, `unit=`, `vsunit=`), and the census channel and the refusal call **one**
`CaseDupSameScope` rather than two copies of the subtraction.

### Measured cost: one file, and it is this ticket's fixture

Not reasoned from the channel — **measured by compiling.** The whole corpus was
compiled before and after with identical arguments and the exit codes diffed:

| | compiled | refused |
| --- | --- | --- |
| before | 1834 | 275 |
| after | 1833 | 276 |

**Newly failing: exactly one**, this ticket's own fixture. Newly passing: none.
Exactly one file in the corpus mentions the new diagnostic at all. The 691
non-Pascal frontend sources compile identically (598 before, 598 after, zero
refused by it) — expected, because C, Rust, Zig and NilPy all declare
case-sensitively, but measured rather than argued.

### The fixture inverted, as its own earlier header promised

`test_a_parameter_and_a_local_that_differ_only_in_case_are_two_symbols.pas` used
to RUN and print `CASEDUP FIXTURE OK`, asserting only that the census channel saw
the pair. It is now a program that must not compile, and the Makefile asserts
**both** message arms by text plus that both are reported from one compile —
the check recovers, and a fatal one would have certified the second arm untested.

The second arm is the one with no positive control otherwise: a local `result`
colliding with the implicit function result. The collision is with a name the
LANGUAGE declares, so a message pointing only at the user's declaration points at
nothing, and ours names it:

    duplicate identifier "result": Pascal is case-insensitive, so it is the
    same identifier as the implicit function result "Result" of Doubled

fpc says `Duplicate identifier "RESULT"`. Both refuse; ours says which side the
author did not write.

The three negative controls are wired beside it and are drawn from the census's
own data rather than invented: `test_case_sensitive.pas`, `test_c_gtk_types.pas`
and `test_exception_handler_binder_is_scoped_to_its_handler.pas`.

### Blank, named

`lib/` units that no fixture reaches are not covered, for the reason frankA's
census records about the same population: a unit nothing imports contributes no
pairs and is indistinguishable here from a clean one. A duplicate in one of those
would now be a hard error the first time something imports it.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 7b2b6e31b.
