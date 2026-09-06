---
track: P
prio: 45
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-06
found-by: frankB
summary: "`function WordPosition(const N: Integer; ...): Integer; var i, n, count: Integer;` declares a parameter `N` and a local `n` in one routine. Pascal is case-insensitive, so that is ONE identifier declared twice and fpc refuses it as a duplicate; pxx accepts it silently and registers two symbols. Three routines in our own `lib/rtl/strutils.pas` were written that way and read the two as different variables. Found only because a name-resolution fix (bug-p-an-exact-case-match-in-an-outer-scope-beats-a-case-insensitive-one-in-a-nearer-scope) made the two collapse onto one symbol and broke them -- the duplicate itself is invisible today. THE VALUE IS THE DECLARATION-SITE DIAGNOSTIC: the collision is trivially detectable where it is written and is otherwise found three functions later as a wrong value. Not landed with the resolution fix because a refusal is a NARROWING over a population nobody has enumerated, and that commit already moved name resolution. CENSUS DONE 2026-09-06 (frankA) AND IT DECIDES: ERROR -- the narrowing costs exactly ONE site corpus-wide, lib/rtl/bignum.pas:495, a routine-local `result` beside the implicit `Result`, which fpc refuses outright (Duplicate identifier 'RESULT') and which only survives because lib/rtl is built by $(PXX_STABLE) and never by the seed. Re-ranked 35->45. THE STATED BOUNDARY IS TOO NARROW: four of the five cascade instances were `const SPARE` beside `var spare` at PROGRAM scope, neither two locals nor an outer-scope collision -- the population is two declarations in ONE scope differing only in case, at ANY level. BEWARE THE COUNT: 342 of the 350 same-scope hits are gtk3 GDK keysyms arriving through a C header import, where the two names are legitimately distinct and DO resolve correctly (probed with four differing values), so ranking by hit count sends a reader straight to the one file that is fine."
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
