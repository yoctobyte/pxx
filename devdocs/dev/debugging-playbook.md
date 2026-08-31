# Debugging playbook — which tool, in which order

Start here. The individual tools are documented in
`devdocs/dev/debug-switches.md` (runtime + compiler switches) and
`devdocs/dev/dwarf.md` (gdb). This page is only the decision.

## What this file has actually caught, which is less than its length suggests

**Prefer building the guard that FAILS over writing the rule that describes the
failure** (frank-coordinator, 2026-08-31). This page grew by roughly a dozen
sections in a few hours on 2026-08-30/31, and the honest audit is that **none of
them caught anything prospectively.** Every real catch that night came from one
of three places: a positive control that fired, an artifact someone opened, or a
second agent measuring the same thing independently. Not once did someone
recognise a named shape here in time to avoid the cost.

The sharpest instance is *the signal fires, it is just not about what you think*
-- three separate occurrences in one night (a saturation check scoring 0.000, a
`trackt health` structurally stuck, `tgenconstraint38` flipping green under a
wrong fix). **All three were caught by different means and none by noticing the
pattern**, even by people who had just written the pattern down.

**Counter-instance, same night, and it sharpens the rule rather than softening
it.** frankwasm confirmed frank-rust's regression, then took **the shape** -- a
builtin table stealing a name the user declared -- and aimed it at its *other*
landed change of the night rather than at the diff. It broke on the first try:
`19bb32f31` refused `LongInt = class end;` used as a generic constraint argument,
which fpc 3.2.2 accepts -- a **false rejection**, the direction that commit's own
message claimed to have avoided. Fixed at `d9e3420e5`.

Two properties make it a real catch and not a lucky one: the bug was in a
**different function reached by a different caller**, so the shape travelled where
the code did not; and frankwasm is explicit that **reviewing the diff would not
have found it**, having already been there twice and been pleased with its
control both times.

So **one named shape has now been the proximate cause of a catch**, and what made
it fire was aiming it at a named artifact -- not recognising it in passing. The
deletion criterion gets sharper, not weaker: **a rule you can POINT AT something
is a different object from one you can only agree with.** The operational form is
frank-coordinator's and it is a procedure: **a regression found in one change is
a PROBE you can aim at your other changes** -- actually run the failing case
against unrelated work, rather than remembering the shape.

The mirror that closes that family, since it is the half people get wrong: in
frank-rust's case the builtin table is consulted *before* the user tables, so
widening it does damage. In frankwasm's, the user-class lookup ran **first** --
the ordering was already right -- and it still broke, because the user's
declaration had not been parsed yet. **Correct ordering was not sufficient; the
second question is WHEN you are entitled to ask.**

**And the cleanest evidence for the opening rule is not in this file at all,
which is the point.** `tools/gate.sh:113` prints, beside a failing self-host
check: *"compiler/pascal26 is OLDER than the last commit touching compiler/ --
that is a STALE BINARY, not a miscompile."* Written 2026-08-13 (`87be2d98b`). On
2026-08-31 it fired on frank-rust, who had pulled a sibling's `compiler/**` and
re-gated without rebuilding, and who was one command from reporting a miscompile
on master -- CLAUDE.md's case 3, and the one member of that family that fails
**loudly and wrongly**, so the false accusation arrives fully evidenced.

It caught someone in a different lane, two weeks later, **who had never read
it**. That is the property prose cannot have: a playbook rule must be recalled at
the moment it applies, and the moment it applies is exactly when you are
convinced of something else. A line printed beside the failing output does not
need to be remembered.

So the ranking the deletion criterion implies, worst to best: a rule you can only
agree with; a rule you can point at an artifact; **a guard that fires at the
point of use without being recalled.** Prefer the third. When a section here is
worth keeping, the question to ask of it is *what would print this?*

So read this file as a **diagnosis aid for a bug you already have**, not as a
prophylactic. When a section here suggests a guard, the section is the cheap part
and the guard is the deliverable -- and a rule that has never been the proximate
cause of a catch is a candidate for deletion, not for elaboration. The failure
mode of a playbook is that writing one *feels* like fixing something, which is
the same confusion as writing a plan and testing a plan (see *The `## The fix`
section is trusted MORE than the summary*).

## The rule this is built on

**The expensive bugs in this project do not crash. They produce a plausible
wrong value far from the cause.** Three from one week:

| symptom | what it actually was | cost |
| --- | --- | --- |
| `len(self.evidence)` = `1751084129` | a missing retain; the field pointed at a recycled block | 3 sessions, 2 reverted fixes, a wrong root cause recorded in the ticket |
| correct-looking key analysis, WRONG keys, no error | `not <object>` was always true | found only by diffing one helper against CPython |
| SIGSEGV, no diagnostic | a `{Code,Recv}` pair jumped to as code | the cheap one — a crash has a location |
| `"Kind": no such member`, compiling a clean tree | a type TAG: `+` on `tyAnsiString` is *concatenation*, so address arithmetic emitted a concat of a literal with the integer 8 | caught by the self-host fixedpoint in one build (2026-08-30, `perf-a-a-string-literal-passed-to-an-ansistring-parameter-is-copied-every-call`) |

So: **reach for the tool that makes a wrong VALUE visible, not the one that
makes a crash easier to locate.** A crash was never the expensive case.

**The last row's distance is worth stating on its own, because it is the largest
in this table: a whole compiler generation.** The chain was tag address
arithmetic as a managed string → `+` means concat → the backend concatenates a
literal with 8 → **round 1 builds cleanly** → the round-1 *compiler* mis-compiles
member lookups, because a name comparison now runs against a mangled string.
Nothing between the first and last stage looks like a type-tag error, and no
test suite catches it, because **the artifact under test is the thing doing the
testing** — a suite run by the bad compiler is a suite compiled by it. This is
the case `make compiler/pascal26` exists for, and the reason it is not
skippable: a compiler that is subtly wrong about strings still builds, still
passes, and only fails to reproduce *itself*.

## If you can name the hot spot without measuring, that is evidence it is not the hot spot

Three times in one day, in three domains sharing nothing — matrix composition,
devtest attribution, compiler hot path — a careful person named the obvious
candidate and was wrong, and the real answer fell out of a measurement in under
an hour:

- The matrix looked like it was made of Pascal micro-tests (44% of jobs). They
  are 7.4% of the time. **70% is one target**, and the tax is not part of a NilPy
  job — a zero-byte `.npy` costs nearly what a 288-line test costs.
- A flaky devtest file "obviously" flaked in the three cases whose notes said
  *measured on the 12-core xeon*. Those feed frozen literals and measure nothing.
  The offender was a fourth case that **passed**.
- A compiler slow at compiling looked like a register-allocation problem. **56%
  of a one-line NilPy compile was in the first 5 KB of `.text`** — runtime blobs
  and the builtin heap — with 8.7% in two `idiv`s dividing by the literal 8.

The mechanism is not that intuition is bad. It is that **the obvious candidate is
the one everyone has already optimised**, so the surviving cost is *definitionally*
in the place nobody looked. Which sharpens "measure first" into something you can
act on directly: **your ability to name a hot spot without measuring is itself
evidence that it was named — and therefore fixed — before you got there.**

## Find your section

The sections below accumulated in the order they were learned, which is the wrong
order to read them in. Route by what you are holding:

**You have a failing thing and want the tool**
- `## Order` -- the tool per question, and the reason to reach for one at all
- `## Order` item **6** -- *it faulted on a cross target and I have only an
  address*: `-strace` for the `si_code`, `-d in_asm` for the block, `--debug` to
  name the routine, and where the cross binutils actually live
- ``## `perf` being blocked is not "no profiler"`` -- FPC `-pg` + gprof, read call
  counts not percentages
- ``## Profile the SHIPPING binary`` -- and `tools/pxxprof`, for when `perf` and
  gdb-attach are both refused

**A measurement or a verdict is telling you something and you are about to believe it**
- `## A guard can fail in the FALSE DIRECTION` -- a red that means "this box
  checks MORE"; the reflex it invites is to delete the extra coverage
- `## Min-of-N tells you HOW to sample. It does not tell you your RESOLUTION`
  -- run a null that CANNOT be affected; ~6% floor measured on this box, and
  anything under it is unresolved however many pairs agree
- `## The natural repair action can destroy the diagnostic` -- rebuilding a
  suspicious binary erases the anti-Thompson check
- ``## The self-host fixedpoint builds at `-O2`, so it is ZERO coverage for
  every `-O3`-gated pass`` -- decidable from the Makefile without running
  anything; a green `converged` on a `-O3` pass is not weak evidence, the code
  under test was never compiled
- `## A job name is a promise, not a description of what ran` -- two hosts can
  report the same job list, count and verdict and check different things
- `## A/B the hunk, bisect the window` -- with a named suspect, one build beats
  eight, and it answers *which hunk* rather than *which commit*
- `## Ancestry is not existence` -- a behind checkout makes a real commit look
  like a ghost; only `cat-file -t` proves one
- `## A wrong fact gets challenged. A MISSING fact collides with nothing.` --
  why a compressed relay is invisible from both ends; give the LOCATION
- ``## Profile the SHIPPING binary`` -- `-g` alone silently means `-O0`, so
  `make pxx-debug` profiles a different program and says nothing about it
- `## Reading a NEGATIVE result` -- a change that measures as NO CHANGE is
  data about your model
- `## Prefer the version of the question that has an ON/OFF answer` -- when
  the box is noisy, look for the experiment that cannot be a margin
- `## A canary nobody has watched fail is indistinguishable from one that is
  not measuring`
- `## Correct code whose correctness is a joint property of TWO places` -- the
  edit that is only right in company, and the warning shape that survives an
  agent who is sure the general rule applies
- `## Min-of-N tells you HOW to sample. It does not tell you your RESOLUTION`
  -- run a null; a benchmark with no null row prints a number instead of
  "unresolved", and the number is real without measuring your change

## Reading a NEGATIVE result — the gap four agents named on the same day

The rest of this playbook is about finding a wrong **value**. Most of the work in
some lanes is disproving a **hypothesis**, and nothing here covered it. Filed
2026-08-30 after four agents independently reported the same hole in four
different words.

**A change of yours that measures as NO CHANGE is data about your model, not
about the change.** Track A built `ProcCdecl and (not CProgramMode)` — the gate
anyone would write for a C callee prologue — and got a table byte-identical to
baseline. Three readings were available and only the third was right:
`CProgramMode` means *"the source in front of me is C"* and was True in **both**
populations, so the guard partitioned nothing. A null is a measurement of your
instrument at least as much as of your subject.

**Before treating a zero count as evidence, ask what the count would be if
nothing were wrong.** `TKey occurs 0 times in generics.defaults.pas` was read by
two agents as proof of mis-attribution. It is what a *correct* specialization
looks like — the argument is not in the template's text. **If the answer is also
zero when nothing is wrong, the grep told you nothing.**

**Verify a new instrument against a control before believing a null from it.** An
agent nearly recorded "TKey is not collected" from a probe written twenty minutes
earlier; the probe's own `sort -u | head -12` was truncating its output and the
real number was 4800.

**When your finding is an ABSENCE, ask what ELSE produces that same absence — and
put one of those in the probe.** The paragraph above is about a null from a
*broken* instrument. This is the harder one: the instrument is fine, the null is
**true**, and the fix built on it is still wrong. Measured 2026-08-31. A census of
all 51 builtin type names found twelve that `var v: N` accepts and `SizeOf(N)`
rejects, so the fix was to chain the declaration table as the builtin table's
fallback. It built, kept the fixedpoint, and turned the census clean. It also made
a builtin **steal the name from a user's own type** — `type Currency = record a,
b, c: Integer; end` went from `SizeOf` 12 to 8, a `Boolean` named `longbool` from
1 to 4, a ten-byte array named `tdatetime` from 10 to 8. `SizeOf` consults the
builtin table *before* the user tables, so a rejection there was never a
rejection: **it was the fallthrough into the user-type lookup.** Every probe
program in the census declared no user types, which makes those two causes emit
byte-identical output.

The tell was in reach and was read past: the table's own header says *"callers
must consult a user type alias FIRST where that matters."* So the guard is
population, not scepticism — the author was already sceptical and already
measuring. **One case where the absence has the OTHER cause is worth more than
fifty where it has the one you are looking for**, and it is the same asymmetry as
a positive control, pointed at a negative result. Full numbers and the control
program: `bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts`.

**Its positive-space mirror, and the more dangerous of the two — frankwasm's,
`2b99d6c19`, `LOGBOOK.md:210`:**

> **AN EXONERATING SHAPE IS ONLY EVIDENCE IF IT CONTAINS THE INGREDIENT.** Before
> writing "X is unaffected" into a ticket, name what makes X affected and check
> the probe has it — otherwise the row you add is the one that stops the next
> agent looking.

Measured: a shape table carried the row *"outer class NOT generic → ok"*,
established honestly, on a probe with **no name collision** — when the collision
was the entire mechanism. The probe could not have failed. The non-generic case
was silently returning a decoy's answer (FPC 7, us 1) the whole time, and that
row is what kept anyone from checking.

**This form is worse than the absence form, for a reason about follow-up rather
than about evidence.** An absence is conspicuous — it reads as *nothing here
yet*, and invites another look. An exoneration reads as a **result**, and
**nobody re-opens a cleared suspect**, so there is no natural trigger to
re-check it ever. It is also the same animal as every instrument in the
2026-08-30 ledger: it answered correctly, about a program with no collision.

So the pair, and they are the same question asked at opposite signs:

| your finding | ask |
| --- | --- |
| an **absence** | what else produces this absence? Put one of those in the probe. |
| an **exoneration** | could this probe have failed at all? Name the ingredient and check it is present. |

*(Attribution note: this rule reached me relayed, and I credited the relayer.
The coordinator caught it and verified it back to frankwasm's logbook line —
which is frankT's "a relay strips the authorship, and an authorless claim is
unfalsifiable in a way the original was not", happening to the rule about
unfalsifiable claims. Check the logbook before crediting a rule you received
second-hand.)*

**An unmeasured baseline in a control does not weaken a comparison — it inverts
it.** A control asserting "green on all five targets" was written having checked
one. Two later results would have read backwards: a real regression as
pre-existing, and a pre-existing failure as newly caused. Build the baseline from
the **same source in the same run**.

**Elimination by intervention is legitimate work and should be recorded as
such.** Build the change, measure that it does *nothing*, cross the hypothesis
off. Track O did this four times in one day (integer arithmetic, threading
dispatch, exec, every `-O3` gate group) and it is most of that lane's real
output. **Table your negative results** so the next agent does not re-run eight
shapes.

**Two instruments agreeing on ONE HALF of a claim reads as corroboration for all
of it.** This is how a correct measurement grew a false explanation: `-O3`'s
23-34% win survived every check, and the *cause* attached to it — the removed
instruction counts — was never tested at all. Both instruments measured that the
code changed; neither measured that the change was what made it fast. Split a
claim into its measured half and its causal half before deciding you have
corroboration.

**When two agents disagree about a mechanism, the tie-breaker is a paired
measurement — not seniority, not who edited the file first.** Three disagreements
were settled this way in one day, each reversing the more confident party. Nobody
should have to happen to have a measurement handy in order to win.

**A CONTROL that never ran is the worst place for a silent instrument, because a
null is the answer you are half-expecting.** frankA, 2026-08-31, one command from
publishing *"CONTROL DID NOT FIRE"* over a binary that had never been rebuilt:
the control's edit script asserted `count == 2`, found 2 where he expected 1,
raised, and changed nothing — so the probe ran the OLD binary and dutifully
reported no divergence. Every step behaved correctly. **What caught it was
printing `sha256sum` beside the result and seeing it unchanged**, which is
CLAUDE.md's rule for measurements doing duty as a rule for controls.
The general form: a control asks "does this test still fail when I break the
thing?", and *no* is both the alarming answer and the answer a control that never
executed gives. **Assert that the artifact CHANGED before you read the result.**

**And when the artifact DID change and the control still passes, that indicts the
CHECK, not the thing you broke.** frankA again, same day, the other direction:
his canary ran `collect(*[5, 6, 7])` against a compiler with the star-splice arm
switched off — sha confirmed different, so not a silent instrument — and printed
the right answer. A LITERAL star operand and a VARIABLE one take different paths:
with the arm gone, `collect(*xs)`, `collect(1, *xs)` and `collect(*xs, *xs)` are
all rejected, while `collect(*[...])` still compiles and answers correctly. One
construct, two paths.

**The trap is that the shorter spelling is the one you reach for when writing the
test, so the wrong path is the DEFAULT.** Nobody writes `xs = [5,6,7]` on a line
above when the literal fits inline. Same shape in his statement-position twin:
`print(html.escape(s, quote=False))` exercises the EXPRESSION loop, because the
call is an argument — a statement-position probe has to be a bare call statement,
and the natural way to make a probe observable (wrap it in `print`) is exactly
what moves it off the path under test.

**A null from two COMPENSATING defects recommends the fix that breaks it**
(frankA's phrasing, 2026-08-31, for a case measured that day). arm32, riscv32 and
xtensa take no `PXXObjRetain` when boxing an object into a variant, *and* no cross
arm of `EmitManagedLocalCleanupForTarget` releases a NilPy `tyClass` local at
scope exit. Both probes are flat at 20k and 400k iterations, and the churn test
prints CPython's own answer — a clean bill of health from three instruments,
which is what a balanced refcount and a pair of errors that cancel look like from
the outside. The trap is not that the null is wrong; it is that **the natural
first move makes it worse.** "The epilogue is missing an arm" is the easier gap
to see, and adding that release alone drops the local's reference while a variant
slot holds an object it never retained — a bounded leak converted into a
use-after-free. The other half alone is merely a leak. So: when a null is
*expected* under your hypothesis and also under "two defects cancel", ask what
each single-sided fix would do before you make one, and if either direction is a
UAF, the halves move together or not at all
(`bug-a-cross-backends-neither-retain-into-a-variant-nor-release-a-class-local-and-the-two-must-move-together`).

## Prefer the version of the question that has an ON/OFF answer

Named by frankwasm 2026-08-30 from two of Track O's results, both of which
survived scrutiny that a difference of means would not have.

**"The evidence points elsewhere" and "the hypothesis is unreachable" are
different strengths, and only the second is stable.** Clearing a suspect by
*isolation* is an argument about what you controlled — it degrades the moment
someone finds a second variable you did not know about. Clearing it by
*construction* is an argument about what is possible, and nothing later can
weaken it.

The two instances:

- **`-O3`'s win is not DCE.** Settled not by timing `-O2` against `-O3` — the box
  was at load 10 and every timing attempt had already failed — but by
  `-O3 --no-dce` keeping the **whole** win. A flag, not a margin.
- **A pass cannot cause a bug at an optimisation level it does not run at.** A
  string regression was suspected of belonging to a newly promoted pass; it
  reproduced identically at `-O0` and `-O1`, where the pass's own gate
  (`if OptLevel < 2 then Exit`) means it never executes. No measurement precision
  enters into it.

**Neither was reasoned into.** `-O0`/`-O1` were run because they were the fastest
thing to try, and the gate happened to make the answer categorical. That is why
it is written down: the *reflex* is to ask, before you start timing, whether
there is a flag, a gate, or a level at which the mechanism cannot run — because a
noisy box cannot resolve a margin but can always resolve a present/absent.

Its sibling is `## When the box is busy, stop timing and start COUNTING`; this is
the stronger form, because a count is still a quantity and this is not.

## A canary nobody has watched fail is indistinguishable from one that is not measuring

Measured 2026-08-30 on `test/quick_canary_nilpy.npy`, checks 24-27.

**Passing is what a canary always does**, so a green tells you nothing about
whether it can detect the thing it names. It will sit at `27 / 27` through the
exact regression it was written for and nobody will know — the same reading as an
instrument that is not connected.

**Two probes, and they are NOT the same claim even though both end in a red
gate:**

| probe | proves |
| --- | --- |
| invert the assertion by hand | the **harness**: `chk` → counter → `tail -1` → `expect_same` → a red gate. A failure can *travel*. |
| build the compiler at the offending sha | the **canary**: this check detects the thing it names. |

Every canary here has the first property by construction and the second only if
someone went and got a broken compiler. Doing it: `## Ancestry is not existence`'s
neighbour rule about seeds applies — build at the sha, and accept the result only
on `converged after N round(s)` with a fixedpoint sha that **differs from the
seed you copied in**, or you have measured the current compiler while believing
you measured history.

**Two controls in opposite directions, from ONE artifact, beat a green test.**
For a change that should reach exactly one backend: the *other* backend's emitted
bytes must be **byte-identical** (a negative control — the change did not leak)
and this backend's must **differ** (a positive control — the change is not inert).
Measured 2026-08-30 on an aarch64-only compare fold: x86-64 identical,
aarch64 548 -> 546 stack pushes. **A green test is consistent with the change
having done nothing at all**; a byte count is not, and neither costs a run you
were not already making.

**A property you get for free while doing this, and it is stronger than the one
you were checking:** if the tree is reseeded from `pinned` and rebuilt, and it
converges to the **same sha** as the build seeded from its own output, that is
two different starting points reaching one fixedpoint. A single seed cannot
distinguish a real fixedpoint from a **self-perpetuating miscompile** — a
compiler that reproduces its own bug reproduces itself perfectly. Two seeds can.
Costs one rebuild you were probably doing anyway after a probe.

**What it bought beyond a yes/no:** the run failed check 24 and *only* 24, with
the deliberate variable-form twin (25) passing. That converts a localisation
*intuition* into a measured property — a future failure now reads as *the literal
arm* on sight instead of collapsing into "strings are broken". Design a canary in
pairs and the pair is worth more than either row, which is the same reason the
original diagnosis was cheap.

## Correct code whose correctness is a joint property of TWO places

The category, and it is the inverse of the trap this repo usually records. Normally
a comment disagrees with the code and one of them is wrong. Here the code
disagrees with a **general rule**, the rule is sound, and it is the rule that does
not apply — so the better an agent's grasp of the principle, the more confidently
they break it.

Measured 2026-08-30 by frankwasm; the code is at `bcd4e68a4`'s comment.

`ir.inc` tags `pystr_repeat`'s argument node `ASTTk[argVal]` — the *original
expression's* type, not the parameter's kind. Every general principle says that
is wrong, and the obvious correction was nearly landed as a latent-correctness
fix. Built alone, nothing else, self-hosted: **`len("a" * 3)` segfaults.** The
tag must describe what `IRLowerCallArg` **returns**, not what the parameter
declares, and it becomes right only in company with an optimisation that makes
the call hand back the literal's own handle.

**And this is why the warning must carry the MECHANISM, not just the
prohibition** (frankwasm, 2026-08-30, after the rule was tested on an arm nobody
had considered): **a mechanism extends to new arms; a prohibition only forbids
the arms someone thought of.** A ticket cleared two hazards for a compare fold by
measurement, both correctly, and a later arm reached a third — a complex right
subtree can contain a *store* — that the prohibition could not have covered and
the mechanism did, because the mechanism could be re-asked of the new case. Write
down *why* it is unsafe and the next person can decide whether it still is; write
down *do not* and they can only obey or not.

**The tell you are in this category:** the "wrong" thing has a partner, and
changing either one alone is a regression *in either direction*. The warning that
works is therefore not "do not touch this" — it is **"one change or nothing, in
either direction"**, which names the coupling instead of forbidding the edit, and
survives an agent who is certain the rule applies.

**It has already attracted one repair attempt from someone holding the correct
general principle.** That is what makes it a trap rather than a wart, and the
reason a comment at the line beats a ticket: the ticket is read by whoever went
looking, and this is found by whoever was not.

**A cheap discipline that catches the whole category:** when a "latent
correctness" fix is obvious and nothing is currently broken, build it **alone**
and run something that exercises it before you believe the reasoning. A latent
fix has no failing test to go green, so the only evidence available is that
nothing new goes red — and if you land it with four other changes you will not
learn which one segfaulted.

**And that discipline needs its own honesty clause, or it degrades into the
thing it replaced** (frankwasm): if the site is unreachable in the configuration
you built, your "exercise" silently collapses back into *nothing went red* — and
it looks like success, because the run is green **and** you did the extra work.
So establish that the exercise REACHES the site, and when it cannot, report the
fix as **unexercised** rather than as verified. The model is a probe that moves a
number: breaking a saturation floor to 0 and watching peak RSS go 392 KB → 13824
KB proves reachability and effect in one step, where a green run proves neither.

## The instrument answered, correctly, about something else

**The dominant failure of 2026-08-30 — fourteen measured instances, from at
least five agents, and not one of them produced an error.** Every probe ran, returned, and
was right. About a different question than the one asked.

It is not the same as a broken tool. A broken tool announces itself. This
returns a clean, plausible, *true* answer, which is why it survives review: the
reader checks whether the instrument worked, and it did.

| what was asked | what the instrument answered | how it read |
| --- | --- | --- |
| does `AllocMem` zero-fill? | does this allocator hand back zeroed pages? (it does, even for a recycled block, even under `-dPXX_HEAP_DEBUG`) | **green — and plain `GetMem` passes identically** |
| does pxx accept a property on an interface? | does it accept one in a body it never parses? (an uninstantiated generic) | **green — fails the moment you instantiate** |
| did the cross-build succeed? | did the output contain the string `error:`? (`unknown option: --target=riscv64` does not) | **"BUILDS" — no artifact existed** |
| did the probe pass? | did it print anything? (`ok: ...` is the SUCCESS line) | every row **FAIL** |
| is this sha a ghost? | is it in *my* object store? (unfetched) | **"not a valid object"** — it was real |
| is the bug still there? | is it there in *my* HEAD? (missing one of two fix commits) | **"still broken"** — half-pulled |
| does FPC disagree with us? | does my source have duplicate identifiers? | **"oracle failed"** — my bug |
| where is this parse error? | what text sits at a token index past the unit's end? (`Tokens[]` is shared; it lands in a *neighbouring unit*) | a plausible Pascal declaration in an **innocent file** |
| did this test pass? | did `diff` exit 0 against a **missing** `.expected`? | **FAIL** — output was identical to pinned |
| is `sizeof(*p)` right? | is it right for struct, union and scalar pointees? (`csizeof_deref_ptr_b79.c` has no array pointee) | **green test sitting on top of an open gap** |
| is Track T down? | is the watcher daemon in **this box's** process table? (T runs on `seven`; no other host can match) | **DOWN, with total confidence** — the only answer it could reach |
| was my commit in the tree Track T tested? | is the TESTED sha an ancestor of MY FIX? (the question backwards — `merge-base --is-ancestor A B` is not symmetric) | **NO** — it was there; I "corrected" a peer's correct attribution |
| which commits are in this range? | which commits are reachable from `origin/master` **OR** from the range? (a stray ref beside a range is a **union**, not a restriction) | **40 commits, 5 touching code** — the range holds **4**, and **1**. Produced while auditing someone else's ancestry arithmetic |
| is the pinned sha a ghost? | is `992065f21f33` a **git object**? (it is the first 12 of the pinned binary's **sha256** — `pin.log` puts the 64-hex binary hash in the middle and the 40-hex GIT sha last) | *"Not a valid object name"* — read as a pre-rebase ghost in the pin ledger. **Third instance of this exact confusion**; nothing was lost |
| does the pin predate my fix? | `--is-ancestor A B` where B is not an object at all — **the tool answers correctly (128, with text); the SHELL IDIOM threw it away** | the RIGHT answer, reached by accident. See the correction below |
| is this `new_red: []` vacuous? | here is `new_red: []`. (`parent_tested` lives in the REPORT front-matter and is **absent from the ndjson row** — not empty, *not present*) | correct about the field, silent about its scope, and **no sign that the question cannot be answered from here** |
| did my edit land? | did `git commit` succeed? (the script before it printed a traceback and exited nonzero; a shell newline is `;`, not `&&`) | **a commit whose SUBJECT announces a playbook row, whose DIFF touches only the logbook** |
| is this NilPy class leaking its fields? | is the field walker correct? (it was — `PXXObjFinalizeHook` was **nil**, so the walker was never reached; the hook's nine install sites are all pylib CONTAINER constructors) | three probes in a row "confirmed" a bug in the FINALIZER. The tell was that adding an unrelated `dummy = [1]` made the same program flat |
| does this field store balance? | does it cost MEMORY? (it leaked a REFCOUNT on one shared string — same object every iteration) | **flat RSS, and a real over-retain**. The next probe, with a fresh string per iteration, leaked 2000 B/iter through the same line |

**The two git rows are the cleanest instances in the table and the only ones
that need nothing to be wrong.** No stale tree, no missing file, no unfetched
object, no mis-chosen predicate — just an argument in the wrong order, or one
argument too many. `git log <ref> A..B` is legal, silent, and returns a
*plausible superset*: 40 where the range holds 4. Both were produced by someone
**checking somebody else's work**, which is when you are least braced for your
own instrument.

**The last row is the mirror of those two, and it is the one that generalises
furthest.** They need nothing to be wrong; this one had an error, **loudly**, and
the next line did not read it. `python3 edit.py` then `git commit` on the
following line is `;`, not `&&` — so a failed edit and a successful commit are
the normal outcome of a normal-looking shell block.

**A commit message is a claim about a diff, and nothing checks it.** The shell
operator is the cause; the exposure is that **the message and the diff are
written in the same breath by the same author and verified against each other
never.** Every commit in this repo carries it. The instance that demonstrated it
was a commit *about* instruments that lie, claiming a row it did not add and
crediting itself with someone else's paragraph.

The cheap guard is `&&` between an edit and its commit, and `git show --stat`
before you believe your own subject line.

**The pin-ledger pair is worth a recipe, because it has now caught three
people** and CLAUDE.md already lists two of them. A `pin.log` line is:

```
<ts>  pinned v398  <64-hex BINARY sha256>  (was <12-hex prev binary>)  <40-hex GIT sha>
```

**The git sha is LAST. Count the hex: 40 is a commit, 64 is a binary.** Twelve
characters of either look identical and both are plausibly a commit prefix.
`tools/trackt.py`'s `read_pin_log` gets this right and says why — *"the GIT sha
is last in both, so key off that rather than a field index"* — so the tooling is
not exposed; the exposure is entirely in reading the pin **commit's subject
line**, which is hand-written and puts the binary hash where a reader expects a
commit. Verify with `sha256sum stable_linux_amd64/default/pinned` before
concluding anything. `--is-ancestor` *will* tell you — 128 with a fatal for a
bogus sha, 1 and silence for a real non-ancestor — but only if you read `$?`
rather than branching on it with `!` or `||`, which is how that distinction gets
thrown away in practice (measured; shape 5 has the table).

#### Correction: `--is-ancestor` DOES distinguish them. My row blamed the tool for what the idiom did.

Published in `35351e33f`, retracted within the hour after frank-rust measured it
and the reporter retracted his own claim. **I verified both arms myself before
changing it back**, which is the only reason this correction is worth more than
the row it replaces:

```
git merge-base --is-ancestor HEAD <real commit, not an ancestor>   -> exit 1,   silent
git merge-base --is-ancestor HEAD 992065f21f33                     -> exit 128, "fatal: Not a valid object name"
```

**The tool draws the distinction cleanly and says so out loud. What collapses it
is the shell around it:** `if ! git merge-base …`, or
`git merge-base … && x || y`, sends 1 and 128 down the same branch — and the
`2>/dev/null` that habitually rides along eats the only part that was talking.
Reproduced in one line.

**Why the wording matters more than the fact** (frank-rust's point, and it is the
real content): *"the tool cannot distinguish"* is unfalsifiable advice that leads
nowhere, while *"your `!` collapsed 1 and 128"* names a line you can go and fix.
A rule that blames an instrument invites you to distrust it; a rule that blames
your idiom invites you to change it.

**So: branch on `$?` being 1 versus 128. Never test an ancestry query with `!` or
`||`. Do not redirect its stderr.**

## A RADIX is part of a value, and `db 65` was hex

Measured 2026-08-31, and it is small enough to be worth stating plainly because
the disambiguating evidence could not have been closer to hand.

Two `test-asm` jobs had been red for days with no visible failure. I found the
cause — one undecoded byte, `db 65`, at the same line of two different
disassemblies — and wrote into the ticket that **65 was decimal, so `0x41`, so
REX.B**, plus a hypothesis: *"a lone `0x41` immediately before an instruction
that carries its own REX is suggestive of a redundant prefix."* Plausible,
internally consistent, and about a byte that was never there.

**It is `0x65`: the `gs` segment prefix.** The `-S` output's own second line says
the fallback is `db 0xNN`, and I had **pasted that line into the same ticket**.
The decoder simply does not accept `$65` as a legacy prefix
(`compiler/asmdisasm_x64.inc:328` takes `$66`, `$F2`, `$F3` only), so a correct
`gs`-prefixed TLS access falls through to the raw-byte fallback. **The compiler
emits correct code; the disassembler cannot read it back** — which inverts the
lane the ticket was headed for.

**A bare integer in tool output carries no radix, and the reader supplies one
from habit.** `65`, `41`, `10`, `20` are all legal in both and mean different
things; only `0x`, or the tool's own documentation of its format, settles it.
The rule that would have caught me is this file's own, applied one notch
earlier: *what would this be if it were false?* — and the answer was two lines up
in text I had already copied.

The corollary worth keeping: **the disambiguating fact is often already inside
the artefact you are quoting.** I did not need to go and find anything; I needed
to read what I had pasted.

#### The family, because it is four operators and it caught three agents in four hours

The coordinator saw all three instances (each was reported to it separately, and
none of us saw more than our own). **`!`, `&&`/`||`, a pipe, and `2>/dev/null`
each replace the exit status you asked for with a different one, and none of them
says so.**

| | the line | what `$?` became |
| --- | --- | --- |
| 1 | `git merge-base --is-ancestor A B 2>/dev/null && x \|\| y` | 1 and 128 down the same branch; the fatal text discarded |
| 2 | `git show <sha>:<file> 2>&1 \| head -2 ; echo $?` | **0** — it is `head`'s. Found inside the command being used to measure instance 1 |
| 3 | `$(sha256sum "$D/pinned" 2>/dev/null \| cut -c1-12 \|\| echo unknown)` | the pipeline's, i.e. `cut`'s — and `cut` succeeds on empty input, so `echo unknown` **could never run** |

**The third is the one to lead with.** It is a guard that cannot fire, written
**into the fix for a guard that could not fire**, by an agent an hour deep in
exactly that topic. Its failure output would have been `binary sha256 ` with
nothing after it — **a labelled blank, which reads as truncation rather than
absence**, and so is strictly worse than the unlabelled hash it was replacing.
Reading the line did not catch it. **Asserting the absent-binary arm caught it on
the first run.** That is the positive-control rule paying out inside one hour,
with the strongest control case available: maximal context, and it still took the
assertion rather than the reading.

**Practical form: branch on `$?` explicitly when the distinction matters, keep the
query off a pipe, and never redirect the stream carrying the only diagnostic.**

**A fourth instance, and the first in code that SHIPS** — frankwasm asked the
question none of the other three had (*is this also in the committed tooling?*),
which is the "then what?" behind the finding. One live hit, in the pin gate:

```
tools/gate.sh:180   tools/twatch.py --status 2>/dev/null | sed 's/^/  /' || echo "  (twatch status unavailable)"
```

`||` reads `sed`'s status and `sed` exits 0 on empty input, so with `twatch.py`
missing or broken `gate.sh check` printed **nothing** where the status block
belongs, and the fallback written for exactly that case **was unreachable for its
whole life**. Verified here: `(exit 3) | sed 's/^/  /' || echo fallback` prints
neither the status nor the fallback, and the pipeline exits 0.

The near-miss is in the pin ledger itself (`Makefile`, the `OLDSHA=` line): the
`||` sits downstream of `awk`, so it only ever fired because `test -e`
short-circuited *before* the pipeline. Any other failure — present but
unreadable, `sha256sum` absent — left `OLDSHA` empty and wrote `(was )` into
`pin.log`. **Both are the labelled-blank shape**: an empty status block reads as
*"the watcher had nothing to say"*, not *"I could not ask"*.

#### Two rules that keep this from becoming a churn campaign

**1. A dead suppressor is noise; a dead fallback is a LIE.** `… | cut … || true`
appears all over the tooling and the `||` is equally dead there — but the
intended behaviour on failure is *"empty, don't abort"*, which is what happens
either way. **The shape is a defect only when the `||` branch is meant to be
reachable.** frankwasm triaged several such sites and deliberately left them
alone; that distinction is the whole difference between a fix and a sweep.

**2. The obvious grep for it is WRONG, and a SCAN needs a positive control too.**
`… | grep -q X || fail` is the *correct* idiom and dominates the hits — `grep` is
last and its status is exactly what is wanted. The defect requires the pipeline
to end in a **passthrough that succeeds regardless**:

```
\|[[:space:]]*(cut|head|tail|tr|sed|awk|wc|tee|sort|uniq|xargs)\b[^|]*\|\|
```

He gave that scan a positive control — a file containing its own pre-fix line,
asserted to match — on the grounds that **a scan finding nothing and a scan that
CANNOT find anything print the same result.** That is the guard doctrine applied
to a *search* rather than to a check, and it is the more useful generalisation:
an empty result set is only evidence if the query has been shown capable of
returning a non-empty one.

**And the layer above that, measured 2026-08-31 (frankB): A CONTROL MUST ASSERT
ITS OWN SETUP, NOT JUST ITS OUTCOME.** Sweeping `lib/**` for the nested-type
miscompile's precondition, I got a clean "0 collisions", distrusted it, and wrote
a decoy file with a known collision to prove the scanner could fire. The control
came back **FAIL** — apparently vindicating the distrust. It was a false alarm:
the scratchpad path I wrote the decoy to already existed as a *file*, not a
directory, so the decoy was never written and the control scanned nothing.
**Missing input scored as a result — shape 4, one level up, inside the very
instrument built to catch shapes.**

The scanner *was* also broken, for two unrelated reasons, so the FAIL was
accidentally correct — which is the dangerous part: a control that fails for the
wrong reason still points you somewhere, and being pointed somewhere true is what
stops you asking why it failed. Had the scanner been sound, the same missing
fixture would have read as "the scanner is broken", and the hunt would have gone
into a working tool.

**So a control needs two assertions, not one:** that its fixture exists and
contains the ingredient (`ls` the file, or print the bytes the probe will read),
and only then that the probe reacts to it. Cheapest form is to make the setup
loud — create the fixture and read it back in the same command — because
`mkdir -p` on an existing *file* and a heredoc into an unwritable path both fail
in the direction that leaves you with no fixture and no error you will notice.
Same family as frank-rust's "I edited it" versus "the edit landed".

#### And why all three were long-lived: an instrument fails silently in whichever direction resembles CAUTION

frankwasm's polarity note, generalised past the guard case above.

| | stuck on | why nobody reported it |
| --- | --- | --- |
| the saturation check | PASS | let bad things through — found in hours, once someone looked |
| `trackt health` off-host | DOWN | produced *more testing*, which reads as diligence |
| a binary sha256 read as a commit | **ABSENT** | absence looks like the cautious answer |

**A binary sha256 prefix NEVER resolves. That failure mode is structurally
incapable of producing a false YES** — it can only ever produce certainty about a
NO that was never tested. So there is no surprising confirmation to interrogate,
and the answer arrives in the shape we are all trained to trust.

**Nobody audits the direction it would be *safe* to be wrong in** — which is
exactly why the accept-side control is the one nobody writes: writing it *feels
like weakening the check*. The pattern to copy is
`tools/twatch_cascade_qualifier_devtest.py` asserting that a bad which really
touches `compiler/` gets **no** qualifier at all. Cite it as the pattern, not as
one test.

**The operational tell, and "verify the sha" is NOT it:** if twelve hex characters
do not resolve, **ask what else in this repo is twelve hex characters** before
concluding the object is missing. `sha256sum stable_linux_amd64/default/pinned`
costs nothing and settles it. The reader who got this wrong *did* verify — against
his own object store, which is precisely the one instrument that cannot separate
the two cases.

**And the free half, which lands on this table's own advice:** the row above
recommends *"prefer an instrument with no orientation — `git show <sha>:file`"*.
Measured on the same bogus sha:

```
git show <bad sha>:tools/trackt.py 2>&1 | head -2 ; echo $?    ->  0
git show <bad sha>:tools/trackt.py >/dev/null 2>&1 ; echo $?    ->  128
```

**A pipe replaces the exit code you are asking about — `$?` is `head`'s.** So
*"prefer the artifact"* needs *"and let it speak"*: `git show` does fail loudly,
just not through a pipeline.

**My own exposure, stated rather than left implicit.** I used the
`&& … || …` form several times tonight, including to establish that `b4904151c`
was PRE-rewrite — the load-bearing step in a set-difference argument that
released a pin blocker. That conclusion stands (`b4904151c` resolves; I have
since checked), but the evidence was weaker than I presented it, in exactly the
way I was writing up someone else for. **The idiom is the defect, and it is in
everybody's fingers.**

**And the last row is the one to carry into any archive question: two artifacts
of the same run disagreed about what could be known from them.** The report's
front-matter carries `parent_tested`; the ndjson row does not carry the key at
all. So *"is this verdict comparing against anything?"* is answerable from one
and unanswerable from the other — and the unanswerable one **looks complete**. An
absent baseline is exactly as vacuous as a self-baseline, with the evidence of
its own emptiness removed.

**Its fix generalises past being careful:** ask the question that has no argument
order. "Was my change in that tree?" is answerable directly —
`git show <sha>:compiler/symtab.inc | awk '/^function IsNodeArray/,/^end;/'` —
and reading the code out of the tested tree **cannot be asked backwards**. Prefer
an instrument with no orientation to remembering which way round to point one.

### The worst version: a wrong answer that AUTHORISES something

The Track T row is the one to remember, because it did not merely mislead — **it
licensed an action.** `tools/trackt.py health` asked the *local* process table for
a daemon that runs on `seven`, so on every other box `DOWN` was the only reachable
answer. CLAUDE.md names a DOWN from that command as proof T is down, and the
documented consequence is *run your lane's FULL gate*. So a check with exactly one
possible answer was authorising the ten-minute widening the `no-full-suite` hook
exists to prevent — **through the documented path, not around it.** Fixed at
`78bbe63b8a49`.

Two things generalise:

- **A predicate that cannot return both answers is not a check.** Before trusting
  one, ask what it would take to see the *other* answer. If nothing on this box
  could produce it, the instrument is a constant wearing a question's clothes.
- **A stale tool is confidently wrong with no error, and it sits in every checkout
  that has not pulled.** The fix landing does not fix the copies. When a tool's
  answer would widen your gate or change a verdict, `git pull --rebase` **first** —
  the same discipline as proving your tree is current before reporting a not-fixed.

The repaired command is a model for how these should read: it names what it
**cannot** see ("this box cannot see a remote process table"), says plainly that
absence "is NOT proof it is down", and points at the second instrument
(`twatch.py --status`, which needs a `git fetch` first). **An instrument that
states its own blind spot cannot be mistaken for one that has none.**

### The six shapes

1. **Wrong scope** — the answer is about your tree, your object store, your
   checkout. Staleness is the commonest, and *the tell is a partial result*: crash
   rows fixed while the silent row fails is what a half-pull looks like **and**
   what a half-fix looks like. Same signature, two causes, so prove the tree is
   current *before* reporting a not-fixed.
2. **Wrong predicate** — grepping for `error:`, treating any output as failure,
   exit codes where the failure is a wrong *value*. Judge a build on the **exit
   code and the artifact**; judge a behaviour by **comparing the value against an
   oracle**.
3. **Vacuous subject** — the code under test was never reached. An uninstantiated
   generic body is not parsed; a suite that stops at the first tier never runs the
   rest. A green here is *no measurement*, not a null.
4. **Missing input scored as a result** — no `.expected`, an empty archive, a
   truncated log tail. Absence enters the arithmetic as data.
5. **Argument order** — the `merge-base` row above, and it is the purest of the
   five: no stale tree, no missing file, no wrong grep, no unreached code. The
   right tool, the right two objects, asked in the wrong direction. An ancestry
   query is a question with a *direction*, so it can be asked backwards and will
   answer, cleanly, about the reverse relation.
   **The guard is not "be careful with the argument order" — it is to ask a
   question that has no direction to get wrong.** `git show <sha>:<file>` and
   read whether the code is in it. Ancestry infers; the artifact states.

   **And the sub-case that gets reported wrong, MEASURED — the tool is not the
   problem, the idiom is.** The coordinator hit `--is-ancestor` against a sha
   lifted from a commit subject that does not resolve, got a non-zero exit, and
   read it as "not an ancestor". The natural conclusion is that `--is-ancestor`
   cannot tell a missing object from a real non-ancestor. **It can:**

   | | exit | stderr |
   | --- | --- | --- |
   | real commit, not an ancestor | **1** | silent |
   | not an object at all | **128** | `fatal: Not a valid object name` |
   | `git show <sha>:<file>`, bogus sha | **128** | `fatal: invalid object name` |
   | `git show <sha>:<file>`, real sha | **0** | — |

   The distinction is there and both idioms anyone actually writes destroy it:
   `if ! git merge-base ...` and `git merge-base ... && x || y` **both put 1 and
   128 down the same branch**, and the `2>/dev/null` or the pipe that usually
   accompanies them eats the one part that was talking. So do not test an
   ancestry query with `!` or `||`; **capture `$?` and branch on 1 versus 128.**

   Same trap one step further out, and it happened *while measuring this table*:
   `git show <sha>:<file> 2>&1 | head -2; echo $?` printed **0** for a bogus
   sha, because `$?` was `head`'s. A pipe replaces the exit code you are asking
   about with the last stage's. The artifact check is still the better
   instrument — its failure is `invalid object name`, a different KIND of answer
   rather than a plausible one — but it is only better if you let it speak.
6. **Wrong subject** — the probe is reached, runs, and answers correctly, but
   about a *neighbouring construct* rather than the one under test. Distinct from
   shape 3: nothing is unreached and nothing is vacuous. The program is
   well-formed, the output is right, and it is right about the wrong thing.

   Measured 2026-08-31. The coordinator broadcast, to four agents, that a nested
   routine capturing a fixed-size array is refused by `pinned` and accepted at
   HEAD, naming both binaries. Checking it, I wrote the obvious repro — an
   `array[0..3] of Integer` at **program level**, read by a nested function. It
   compiled and printed the right answer *on the very binary said to reject it*.

   A program-level variable is a **global**, not a capture. The nested routine
   reads it directly; no uplevel access is generated; the code path under test is
   never involved — yet nothing about the run says so. Moving the array to be
   local to an enclosing procedure produces the error verbatim, exit 1.

   **Two things make this the expensive one.** First, it **fails in the
   reassuring direction**: the wrong repro says *the compiler accepts this, there
   is no blocker*, which is the answer nobody re-checks, and it would have gone
   back up as "there is nothing behind the pin." Second, a passing probe reads as
   *proof the other agent was wrong* — so the error propagates as a confident
   correction of a correct claim, which is worse than a silent wrong answer.

   **The guard, which is frankwasm's rule specialised:** when the bug is about
   the BOUNDARY of a concept — what counts as a capture, a copy, an alias, an
   escape — a probe drawn from the middle of the concept cannot see it. Ask what
   makes this instance the thing at all, and check that the probe has it. Here:
   *what makes it a capture is that the variable is local to an ENCLOSING
   ROUTINE.* A repro missing that property is not a weaker test of the claim, it
   is a test of something else.

   **And the cheap positive control that settles it in one command:** a probe for
   an unsupported construct must FAIL on the binary said to lack it. If it
   passes, you have not confirmed support — you have learned your probe does not
   exercise the construct. Same rule as "a guard that cannot fail is not a
   guard", pointed at the repro instead of the guard.

### The bias that has a trigger: a tool you were *just* told is broken

Every instance above is about an instrument. This one is about **when you are
most likely to misread one**, and it is the only entry here that names a moment
rather than a command.

**The mechanism (frank-coordinator's, and it is the load-bearing half): being
told an instrument is unreliable SHIFTS YOUR PRIOR, so the same evidence now
buys a filing it would not have bought an hour earlier.** Nothing about the
evidence changed. What changed is what you were willing to conclude from it.

**The symptom, which is how you meet it: a real mislabel and a correct report
are identical from one command away.** You see a tool print something odd, you
have just been warned that tool was broken, and the two readings are
indistinguishable without one more question.

Three instances on 2026-08-30/31, all within an hour of `trackt.py health` being
fixed and announced:

- I saw `health` name a sha whose subject was a `tstate(...)` commit and
  concluded it was printing the **publishing** commit instead of the **tested**
  one. It was not. The watcher genuinely tested a tstate commit, because that
  was the tip when it sampled. I was one command from filing a bug against a
  tool fixed an hour earlier.
- The coordinator read a truncated `--status` and began composing a second,
  larger alarm about the instrument everyone had just been told to trust.
- The coordinator then called `992065f21f33` in the pin commit's subject a
  pre-rebase ghost. It is the first twelve of the pinned **binary's sha256**
  (`sha256sum stable_linux_amd64/default/pinned` — verified). Third recorded
  instance of that confusion, produced by the agent who had been quoting the
  first two at other people all night.

**Why it earns an entry rather than "watch out for confirmation bias":** that
advice converts into nothing you can do. This one has a **trigger**, so it
converts into a question you can actually ask:

> **Have I just been told this instrument is unreliable?**

If yes, the bar for concluding "it is still broken" goes UP, not down — and the
cheapest way over it is one more question aimed at the *other* explanation. For
each instance above that question was: does the ndjson row's `sha` field hold
what health printed (it did); is `--status` truncated (it was); is this twelve
hex a 40-hex prefix or a 64-hex one (`sha256sum` answers in one line).

**The general form is the section's own rule pointed at yourself: "what would
this be if it were false?" — where *this* is your suspicion of the tool, not the
tool's answer.** The three instances above cost nothing only because somebody
asked that before filing. It is the same move as pairing a green with a row that
would have gone red: pair a suspicion with the observation that would clear it.

### The habit that defeats all five

**Say out loud what question the instrument actually answers, then check it is
the one you asked.** "Verify it" does not help — every agent above *did* verify.
And where an ARTIFACT can answer instead of an inference, read the artifact.

Then: **pair every green with a row that would have gone red.** Not a second
test — a specific row you can point at and say *this one fails if the bug is
present*. `GetMem` passing the `AllocMem` zero-check is that row. An instantiating
probe beside the uninstantiated one is that row. Its absence is what makes a
green unfalsifiable, and an unfalsifiable green is the most expensive artifact in
this repo.

**And the sharpest case, because it inverts the intuition:** in
`bug-a-indexing-through-a-pointer-to-an-array-is-wrong-for-several-element-kinds`,
fixing the crashing rows is what **exposed** a second silent arm (a 264-byte
stride for a 15-byte slot). A sweep that stops when the segfaults stop is not an
incomplete sweep — it has *guaranteed* it cannot see what remains.

## A flat RSS is not a balanced refcount

**Measured 2026-08-31, and it cost two probes read backwards.** RSS is the
instrument everyone reaches for first on a lifetime bug, and it is blind to the
whole class of errors where the COUNT is wrong and the ALLOCATION is not.

`self.s = s` where `s` is built once outside the loop, stored into a fresh
instance every iteration: the store over-retained, so every instance's
reference leaked. **Flat at 976 kB over 200k iterations**, because 200k leaked
references to ONE string cost nothing. Change the source to `s + "!"` — a fresh
string per iteration, same line of compiler code — and the identical bug reads
**399 MB**. Nothing about the defect changed; what changed is whether it had to
allocate to be visible.

So the rule is about how you build the probe, not about which tool you pick:

- **Make each iteration allocate.** A shared payload converts a refcount leak
  into silence. A fresh one converts it into a slope. This is free — it is one
  concatenation.
- **Two loop counts, always.** An absolute number answers nothing; only the
  slope does. Both of tonight's confirmed leaks were read off `20000` vs
  `400000`, and both of tonight's false negatives were flat at BOTH.
- **A leak whose object is immortal by construction is unreachable by RSS
  entirely** — a module-level binding, an interned literal, a singleton. If the
  shape under test can only ever hold one object, RSS cannot answer and you need
  `-dPXX_OBJTRACE` (which prints `A`/`r`/`F` per object and *can* show a
  refcount that never reaches zero) or a counter.

The mirror is worth stating too, because it is what made the first fix look
harder than it was: **an RSS number that moves is not proof you found the right
mechanism.** `dummy = [1]` — a statement with no relationship to the failing
code — took the same program from 399 MB to 980 kB. A one-line change that
flips the measurement is a *bisect step*, not a diagnosis.

## Do not read a green as coverage

**One shape passing is not the shape space passing.** arm32 passed five of six
argument shapes and was red on `(int, double)` — AAPCS32 wants a 64-bit argument
in an even core-register pair. Two people nearly filed "two targets affected" for
a three-target defect.

**A green needs a control proving it is not vacuous.** "It compiles" and "it is
correct" are different claims when an uninstantiated generic body is never
type-checked; gate it with something that must move, such as a proc-count delta
(1661 → 1672). Without that, a green means the compiler agreed to say nothing.

**Name which direction of the result is a FAILURE before you run it.** For a
string-copy fix: `cmp` identical = pass, `cmp` differs = the change altered
semantics and is a failure — *not* an interesting result to investigate. Deciding
afterwards is how a nice-looking diff gets rationalised.

**Before widening any check that can REFUSE code, build a false-reject canary:**
a program containing everything that must keep compiling, run it, and diff its
stdout against FPC's. The fail-side test is the obvious half; the accept-side
half is the one that catches the regression, because *accepted* and *correct* are
different claims and only the running program separates them. This is how a fix
that would have started refusing `ptr := o.I` — which FPC accepts — was caught:
an interface is spelled `tyRecord`.

**A SKIP is not an answer — go find the corpus.** Asked whether an aarch64
sqlite red was a real defect, the honest report from a checkout with no sqlite
tree is "SKIP: no source here", and that is a passlike hole wearing the shape of
a verdict: nobody reverts a pin on a SKIP and nobody clears one either. Pointing
`SQLITE_SRC` at a read-only tree elsewhere on the box
(`/home/neo/pxx/library_candidates/sqlite`) turned it into six real runs and a
real verdict. The same move settled an unrelated `fgl` question the same evening
from a different agent, unprompted — which makes it a pattern worth naming rather
than an anecdote about sqlite.

The generalisation: **when the instrument cannot reach the subject, move the
instrument.** A corpus you do not own is usually somewhere on the machine, and a
read-only path costs nothing. Report a hole only after looking, and say where you
looked — a SKIP that has been chased is evidence; a SKIP that has not is the
absence of any.

Its mirror, when the corpus IS reachable: **check that your view of it is the
whole of it.** A scan of the run archive piped through `tail -8` while looping
several hosts scrolled every one of the target host's rows off the end, and the
truncated view was read as the complete set — "there is no `pin: v398` row" when
the row is at line 249. That is not a misread of the data; it is a misread of the
instrument, and it is the more dangerous kind, because a ghost value is a wrong
answer while a truncated view is a *right answer to a question you did not ask*.
It then travelled: it was taken into a ticket second-hand and had to be corrected
there. Bound your own view before you quote it, and when you pass a negative on,
say whether you measured it or read it.

**`make compiler/pascal26` is not sufficient evidence for widening a
diagnostic.** What is cheap and decisive: compile two or three `examples/*` plus
a Rust and a Zig sample as individual commands. Twenty seconds, catches a
false-reject class the fixedpoint cannot see, and goes nowhere near the
no-full-suite hook.

### The self-host fixedpoint builds at `-O2`, so it is ZERO coverage for every `-O3`-gated pass

**This was already written down, and the citation matters more than the
anecdote:** `devdocs/progress/backlog/feature-opt-o3-register-pressure.md:72-79`,
rule 1 of the umbrella's `READ FIRST` block, landed `d8ec3553a` on **2026-08-29**:

> **Every `-O3` pass needs its OWN control test. The self-host gate cannot see an
> `-O3`-only defect.** Not "might not" — cannot: `make compiler/pascal26` builds
> the compiler at the DEFAULT `-O` level, so no `OptLevel >= 3` arm runs while
> building it. Demonstrated on purpose, not inferred: slice 5's comparison
> encoding was deliberately broken in the ModRM field, `-O3` printed `acc=0`, and
> the fixedpoint reported `converged after 1 round(s)` the whole time.

A day later, landing the x86-64 zero-extend fusion, frank-optimize broke the new
emitter on purpose to prove the test fires — dropped `REX.R`, so `r8`–`r15` read
`rax`. The test fired in the expensive way (`acc=374503906869` against
`1299819431187`: a plausible wrong number, no crash), and:

```
make compiler/pascal26   ->   converged after 1 round(s), e4a7919b39b4
```

**The compiler reproduced itself byte-identically with a deliberately broken
encoder in it** — the anti-Thompson agreement check blind alongside it, since both
properties are about *reproduction*.

**That is a REPLICATION, not a discovery, and it is worth exactly what a
replication is worth:** a second encoding (`REX.R` where slice 5 broke ModRM),
across two backends' worth of gate sites, same outcome. What it is not is the
evidence for the rule. The evidence is a day old and sits at the head of the
ticket the slices were being landed into.

**The reason is not subtle and it is decidable without running anything**, which
is the part worth carrying:

| | |
| --- | --- |
| `compiler/compiler.pas:838` | `OptLevel := 2;` is the default, `OptLevelExplicit := False` on the next line |
| the pass | gates on `if OptLevel < 3 then Exit;` — **nine** sites: `ir_codegen.inc:2800,2937,10236,11000,11181,11196`, `ir_codegen_aarch64.inc:758,912,1509` |
| `tools/selfhost_fixedpoint.sh:78-79` | invokes `"$cur" "$SRC" "$a"` bare; `grep -- -O[0-9]` returns **0 hits** |
| `Makefile:281-282` | invokes `"$$cur" $(PXXFLAGS) …` with `PXXFLAGS :=` **empty** at `:119` (overridden only by `bootstrap-frozen`, `test-managed`, `test-frozen` — none of them the fixedpoint rule) |
| `compiler.pas:971` | the only other write is `-O<n>` on the command line; there is no env path |

So the fixedpoint compiles the compiler at `-O2`, and **no `-O3`-gated pass can
execute during it at all.** Zero firings — and zero was never in doubt, because
there is no path by which it could have been nonzero.

**The claim to carry is about the TIER, not about that one construct: a green
`converged after N round(s)` is not weak evidence for a `-O3` pass, it is NO
evidence, because the code under test was never compiled.** That covers all nine
gate sites, the whole W1 register-pressure campaign, and every `-O3` slice
landed. The Makefile rows for this pass ask for it explicitly — `./$(COMPILER)
-O3 test/test_shr_resident_zeroext.pas` at `Makefile:4239` — which is exactly
why the fixedpoint had nothing to say about it.

**This is not a new scope limit. It is CLAUDE.md's FIRST one at full strength.**
There the optimisation-level limit reads "the claim holds at the default `-O`
only", which is true and sounds like a weakening. It is not a weakening: for a
tier above the default the guarantee is not weaker, it is **absent**, and the
absence is total, permanent, and decidable by grep. Rule 1 says the same thing
and says it first; the greps above only show *where the default comes from* and
that no wrapper overrides it on either self-host path. Useful, not a finding.

#### The two wrong readings this subsection went through before it said the above

Recorded because the section was rewritten twice in three hours, by two people,
in the same direction each time — **towards the duller and more useful claim.**

**Mine: I asserted a mechanism nobody had measured.** I wrote that the limit here
was one of **propagation** — the emitted code being wrong without the wrongness
reaching the bytes that get compared. It reads well and it is wrong: the pass was
never compiled in, so nothing propagated or failed to. I had named the dull
alternative ("the pass never fires"), and had written in the same paragraph that
the separating check was free and unrun. **Then I ranked the interesting
mechanism first anyway and left the dull one as a caveat.** The guard is this
file's own — **ask what this would be if it were false**: for propagation to be
the mechanism, the pass would have to be able to *run* at the fixedpoint's `-O`
level. One grep at its gate. I had a measurement and converted it into a
mechanism claim by choosing, not by checking.

**Theirs, volunteered unasked, and the sharper of the two:** the byte-identical
self-host was **duller** than they reported it, not sharper. Not a surprising
survival — the only possible outcome, and a rule they had themselves been landing
slices under said so in advance. Both corrections point the same way: **a real
measurement acquires a story on the way to being written down, and the story is
the part nobody measures.**

They put the finding at the Makefile rows rather than in the commit message,
which is right and worth copying: it lands where someone deciding whether to
trust a green will read it, not in a log nobody greps before trusting one.

#### Build the deliberately-broken compiler to a SCRATCH path

The control this whole section rests on — break the pass on purpose, confirm the
test goes red — has a trap in it, and the fix is one argument:

```
./compiler/pascal26 compiler/compiler.pas $SCRATCH/p26-break     # yes
make compiler/pascal26                                            # no
```

Building the broken emitter **with the good compiler, to a path that is not
`compiler/pascal26`**, confines the damage to the programs it emits. Overwrite
`compiler/pascal26` instead and the breakage is now in the tool doing the
building. Measured 2026-08-30: the same experiment at `MSTR_STATIC_RC=4` **hung
`make compiler/pascal26` for six minutes**, because a compiler that frees its own
`.data` literals cannot reach a fixedpoint — a hang, so no error text, which is
the worst shape to debug into.

Restore with `git checkout -- <file>`, never a copy-back (CLAUDE.md's parking
rule, and the hazard is in the *revert*), and **print `sha256sum
compiler/pascal26` before and after**: unchanged is the assertion that the
experiment stayed where you put it.

#### And for a pure MOVE, byte-identity is the WRONG bar — the right one is stronger

frankA, 2026-08-31, carving NilPy arms out of shared parser files, having written
*"byte-identical is the bar — the default build must not move"* into the ticket
at filing and then found it wrong.

**Relocating a function between `.inc` files changes procedure emission order, so
the compiler binary differs while nothing about its behaviour does.** A bar that
a correct change cannot meet is not a strict bar, it is a broken one: it will be
missed, and the natural next move is to weaken it to something vague rather than
to something better. `make compiler/pascal26` never promised byte-identity across
a source change either — it says the compiler reproduces ITSELF.

The bar that is right for a move is **equivalence of what the two compilers
EMIT**, and it is stronger than the one it replaces:

1. build a compiler from the before-sources and one from the after-sources;
2. compile a batch of programs with both — `compiler.pas` itself included;
3. diff the emitted binaries. His run: **11 identical, 0 differing.**

**The sharpest form falls out of that for free, and it is worth asking for by
name: the BEFORE compiler over the AFTER sources produces exactly the after
compiler, while the two compilers differ in bytes.** Those two facts together say
the difference is emission order and nothing else. Neither says it alone.

**Then he did not believe it.** 11/11 green is also what a batch that never
reaches the carved code looks like, so he injected a defect into the moved arm
(`PyMakeStrIndex(node, GenZeroLit)` — always index 0), rebuilt, and
`test_nilpy_subscript_of_a_call_result` diverged from CPython on its first line.
Note what made the control land: **that test's own header says `f()[0]` was
"correct", which is exactly how the bug survived, so any probe must use a
NON-ZERO index** — the control was designed against a recorded near-miss rather
than chosen freely. Reverted; restored build byte-identical, which is the right
bar for a revert because a revert really should not move anything.

**The general shape:** when a change is expected to be behaviour-preserving, ask
what artifact the preservation is a property OF. For a bug fix it is the emitted
program. For a move it is the emitted program too — not the compiler that emits
it. Reaching for the compiler's own bytes is reaching for the artifact that is
easiest to compare, not the one the claim is about.

## Where is the time going — profiling on these boxes

**`perf` is dead here** (`perf_event_paranoid=4`) and that is NOT the same as
profiling being unavailable — the fleet was told it was, and it was wrong.

**gdb SIGINT-sampling works.** It needs three non-obvious settings and
**omitting any one yields zero samples with no error**, which reads exactly like
"the program was not running". Recipe: `devdocs/dev/session-roster.md`.

**`objdump -d` on a binary built without `-g` disassembles nothing and exits
0**, so any static instruction count over it silently reads zero. Same shape as
the above and the same tell: a clean exit with an empty result.

**Compare with min-of-N, interleaved A/B — never before-then-after, never
means.** On a contended box a mean mostly measures the other agents; load moved
7.7 → 5.4 during one session, and a sequential comparison would have credited
~20% of that session's win to the box. **Keep the previous binary** rather than
rebuilding it afterwards, and name each binary's sha beside its number.

## Min-of-N tells you HOW to sample. It does not tell you your RESOLUTION — run a null

The rule above is necessary and **not sufficient**, and the gap is where most of
one night's published numbers died. Min-of-N says how to sample; it says nothing
about how small an effect your instrument can resolve, so a min quoted to two
decimals reads as precision it does not have.

**Measure the floor, do not estimate it: run a control that shares NO MECHANISM
with your change.** Measured 2026-08-30 on this box, benching a static-literal
retain guard — the control was a program with **no strings at all**, which the
change cannot touch:

```
no strings at all   (the box)   +6.27%   sign test 7/15   <- a coin flip
```

**That is the noise floor with its clothes off: ~6% on a ~5 ms program at that
load, at min-of-15.** In frank-optimize's words, *the controls were doing more
work than the treatments.* It retired three of its own published rows on the
spot — a mixed row at −3.04%, a pure-cost row at +3.66%, and an earlier +2.3%,
all under the floor and none of them resolved. What survived cleared it by a
wide margin: `compiler.pas` at +6.95%, and an aarch64 change at **−33.9%, 9 of
9** — clear by a factor of five.

**A change smaller than the floor is not one that FAILED A BAR — it is one your
instrument CANNOT RULE ON** (frank-optimize's phrasing, and the distinction is
the whole point: "no win" and "no answer" get written up in the same grammar and
mean opposite things). A mixed microbenchmark near the break-even flipped sign
between runs: `+2.3%` at 1/11, then `−3.04%` at 10/15 — same program, same
isolated change. Pair counts do not rescue an effect smaller than the noise; they
just make a coin flip look deliberate.

**So when the magnitude is inside the floor, report the SIGN COUNT and say
unresolved.** `7/15` is an honest sentence; `+6.27%` is not, and the second is
what a benchmark prints if you let it.

**The mechanism, in one line, and it is the guard rule turned inside out:** *a
guard that cannot fail prints PASS; a benchmark with no null row cannot output
"unresolved", so it outputs a number.* Neither errors. Both answer.

**This is the positive-control rule pointed at benchmarks.** A guard needs a case
it **must reject**; a measurement needs a case that **must not move**. In both,
what catches you is the arm you did not expect to be informative — and this
control was informative *precisely by moving when it could not have been
affected*. Same corollary too: **run it in the same command as the treatment**,
or the temptation is to skip it exactly when the treatment already looks clean.

### The polarity asymmetry: a guard stuck on PASS gets caught. One stuck on FAIL may not.

frankwasm's, 2026-08-31, and it changes which control you must remember to write.

Both halves were measured the same night, on the same fleet:

| | | |
| --- | --- | --- |
| the saturation check | could only print **PASS** | found in hours, because someone went looking |
| `trackt.py health` off the watcher host | could only print **DOWN** | survived **two days** |

> A guard that cannot fail gets caught eventually, because it lets bad things
> through. A guard that cannot **pass** may never get caught, because **its
> damage looks like diligence.**

A check stuck on the conservative answer produces no visible fault. It produces
**more testing** — which reads as prudence, so nobody ever has a complaint to
file. `health` reporting DOWN licensed every dev agent on the box to run a
ten-minute full gate under CLAUDE.md's own exception, and the cost landed as
slow minutes that everyone attributed to a busy machine. There was no symptom to
report, because the symptom *was* the recommended behaviour.

**The consequence for the positive-control rule is concrete, and it is the whole
value of the observation: the control you naturally write is one the guard must
REJECT**, because rejection is the direction you are afraid of. The
stuck-conservative failure needs a control in the **other** direction — a case
the guard **must accept** — and that is the one nobody thinks to write.

So: **every guard needs both arms asserted.** One case it must reject, one it
must accept. `tools/trackt_remote_health_devtest.py` carries the accept-side one
(*"a FRESH archive and no local daemon is REMOTE, not DOWN"*), and it is stated
here as doctrine rather than left as an artefact of somebody having been careful
on the night.

**The consequence for anything with a per-change value bar** — the O charter's
promise gate is the live example, and this is a note for whoever owns it, not a
ruling: if the floor on this hardware is ~6% and a rule also forbids batching
changes to measure them together, then a pass worth 2-4% cannot be cleared by
any measurement currently available — not because it is too small to be worth
having, but because it is **too small to be seen**. A stateable bar exists
underneath that — *resolvable on a workload long enough that the null row goes
quiet, sign test only, no magnitude claimed below the control* — and it is
different from "measure it".

**And withdraw a statistic that is pointing your way.** The same session
retracted a "10 of 11, p≈0.006" on the grounds that the test assumes
independence and stationarity and this box is neither — **while the conclusion it
supported survived anyway.** That is the retraction nothing prompts and nobody
catches, and it is the one worth naming.

**None of this was self-generated, and that is the part to copy.** The correction
is recorded at the measurer's own request, because the section read as though the
discipline arrived on its own. It did not: **frankwasm declined to accept a
result reported as settled** and told them to go find the on/off version of the
question. The null row exists because a peer refused a summary.

So the reproducible move here is not "remember to run a control" — nobody
remembers, and the session that produced the ~6% floor had already published
three rows without one. It is: **when someone hands you a settled-sounding
summary, ask what would make the question on/off**, and be the peer who does not
accept it. That is cheap, it does not require you to know anything about their
measurement, and on this occasion it retired three published numbers.

### The natural repair action can destroy the diagnostic

`tools/gate.sh:104`, and it is the only thing that knows this:

> Deliberately a hint, not a fix: gate.sh must NOT rebuild before comparing, or
> it loses the ability to catch a genuinely contaminated binary — which is the
> entire point of the anti-Thompson check.

Finding a binary that disagrees with its sources, the instinct is to rebuild.
**Rebuilding is the one action that erases the evidence**, and the check exists
for the case where the binary is contaminated rather than merely stale. Same
hazard as restoring a `.PRISTINE` copy over a file: the danger is in the
*repair*, not in the edit, which is why nothing watches for it.

The staleness case is also the common one and is *not* a miscompile: the gate's
own testmgr step rebuilds as a side effect, so the first run after a sibling's
commit fails and the re-run passes — which reads as flakiness. It cost two full
gate runs on consecutive days before anyone saw the pattern.

**THREE causes produce that one message, and the gate's hint can only help with
one of them.** Measured 2026-08-30, twice in one evening by the same session:

| cause | mtime tell? | is it a defect? |
| --- | --- | --- |
| a sibling landed a `compiler/` change and you did not rebuild | **yes** — binary older than the last `compiler/` commit | no |
| a `git stash`/`checkout` round trip: you built a control binary, restored the sources, never rebuilt | **no** | no |
| the binary is genuinely contaminated | **no** | **yes, and it is the only one that matters** |

**The second has no tell, and the reason is worth understanding rather than
memorising: the staleness is against your WORKING TREE, not against history.**
The heuristic compares the binary's mtime to the last commit touching
`compiler/` — and in a stash round trip no commit is involved at all, so there
is nothing for it to compare. The gate has the right answer, states it plainly
(*"the fixedpoint reached from PINNED differs from `compiler/pascal26`"*), and
has no way to say which of the three you are in. **The reader does that
discrimination, and cases two and three look identical.**

**And the repair does not merely erase the evidence — it makes the evidence look
like a LIE.** `gate.sh:104` says the gate must not rebuild before comparing, and
then a later step rebuilds anyway. So the sequence you actually experience is:
RED on a claim about the binary, then `sha256sum compiler/pascal26` showing that
claim to be *false*, because the gate's own testmgr step repaired it in between.
That reads as the gate lying to you, and it was one message away from being
filed as a gate bug. **It is the same artifact as the loud stale seed:** a
correct instrument, a plausible wrong story, and nothing that errors.

The practical form, and it costs nothing: **after a fixedpoint RED, `make
compiler/pascal26` and re-run BEFORE concluding anything** — not to fix it, but
because you cannot tell cause two from cause three without eliminating cause
two, and eliminating it is twelve seconds. If it goes green, you were stale. If
it stays red with a freshly built binary, *now* you have the case the
anti-Thompson check exists for.

## Match by SYMBOL, never by coordinate

**No line/column field in a diagnostic is trustworthy.** Three independent cases
in one day of a position field disagreeing with its own message text. When you
are deciding which ticket a diagnostic belongs to, match on the **symbol** it
names; matching on the coordinate got it wrong at real cost.

## Building an FPC oracle — two traps that read as findings

**pxx accepts case-insensitive identifier collisions that FPC rejects** — `PStr`
the type against `pstr` the variable, `PI`/`pi`, `PC`/`pc`. The symptom is "my
canary compiles under pxx and FPC refuses it", which reads like a divergence
finding. It is a name clash in your test, and it cost three rebuild rounds.

**FPC has TWO knobs that change a non-ASCII answer, on different axes, and
either one silently changes what your oracle is answering.** The **source
codepage** decides how a literal becomes an AnsiString; the **widestring
manager** decides how an AnsiString converts to a WideString. Plain FPC ships
the dumb manager, which widens byte-for-byte. Measured 2026-08-30 on `'café'`
written as UTF-8 source bytes, printing every code unit:

| build | AnsiString `s` | WideString after `w := s` |
| --- | --- | --- |
| pxx (HEAD and `pinned`) | 5: `99 97 102 195 169` | 5: `99 97 102 195 169` |
| `fpc` stock | 5: `99 97 102 195 169` | 5: `99 97 102 195 169` |
| `fpc` + `uses cwstring` | 5: unchanged | **4: `99 97 102 233`** |
| `fpc` + `{$codepage utf8}` | **4: `99 97 102 233`** | 4: `99 97 102 233` |

**pxx matches the UN-KNOBBED oracle on both axes**, so for these constructs the
probe's default `FPC=fpc` is the correct oracle and **turning either knob on
MANUFACTURES a divergence rather than revealing one.** That is the opposite of
the intuition ("the oracle is stale, give it the modern setting"), and it is why
`tools/fpc_diff_probe.sh` now detects both knobs at startup and refuses the
non-ASCII crossings against a knobbed oracle instead of reporting them as DIFF.

Whether pxx *should* decode UTF-8 source or ship a widestring manager is a real
open question and a Track P/A one — but it is a question about pxx's dialect,
not something this oracle can settle, and the two must not be confused.

And **an ASCII oracle cannot see a width bug at all**, because a UTF-8 byte
count and a UTF-16 unit count are the same number on ASCII — which is how
`UTF8Encode`/`UTF8Decode` survived as the identity function. A canary for this
axis must be non-ASCII or it proves nothing.

**The two knobs are independent, and neither is reachable from the other.** No
source-codepage setting changes the widening (it is not the source being read),
and no manager changes the literal. Both directions cross: `s := w` narrows the
same way, and under `cwstring` a round-trip returns to 5 UTF-8 bytes through a
4-unit intermediate.

**A CORRECTION, recorded because the wrong numbers sat here for a day.** An
earlier note on this page reported "pxx answered 4/233, stock FPC answered
5/195" and advised adding `cwstring` before recording a crossing divergence.
Neither number reproduces: re-measured at both `pinned` and HEAD with every code
unit printed, pxx answers 5/169 and so does stock FPC — 195 is the *fourth* unit
of five, not the last. The advice that followed from it was backwards. The
mechanism the note identified is real and worth keeping; the values were read
off a summary rather than a run, which is the same failure this page exists to
name.

## Sections in here that record a confident WRONG reading
- `## A bisect can name the RIGHT commit and still be wrong` -- the tell is that
  the named commit looks like an improvement
- `## A/B the hunk, bisect the window` -- with a named suspect, one build
  beats eight; the bisect answers a coarser question
- `## Ancestry is not existence` -- `--is-ancestor` returns false for a
  behind checkout too; only `cat-file -t` proves a ghost sha
- `## A number moving in the direction you hoped is not a check` -- the
  confirmation may be the symptom
- ``## "The compiler couldn't compile X" and "the language can't do X" look
  identical from inside `compiler/**` `` -- an "undefined" error in a
  compiler-internal file may be a define at the top of the translation unit,
  not a gap; compile it standalone before filing
- ``## "The pinned binary reproduces it" may be a claim about a MIXED compiler``
- `## A silent assertion makes the harness report something else, confidently`
- ``## A RADIX is part of a value, and `db 65` was hex`` -- I read a byte as
  decimal and built a hypothesis on it; the file's own second line said
  `db 0xNN`, and I had already quoted that line into the ticket
- ``## The self-host fixedpoint builds at `-O2` `` -- I named PROPAGATION as the
  mechanism when the pass was simply never compiled in; I had written that the
  separating check was free and unrun, then ranked the interesting mechanism
  first anyway. Three greps settled it
- `## When you are about to conclude something`

**A check exists, passes, and you are trusting it**
- `## Assert the INVARIANT, not the current numbers` -- and assert the
  CONSEQUENCE, not the number
- `## A guard that greps the source can only catch what is visible in the text`
- ``## "Ruled out" and "could not look" must never print the same`` -- the
  strongest instance of the asserts-nothing family, plus close conditions about
  the wrong subject and diffs against a missing operand
- `## A correct fix on an opportunistic path is inert` -- the tests answer *does
  it work*, never *does it run*

**You are about to write the fix**
- `## A blocklist costs one outage per symptom; an allowlist closes the class`
  -- and key an exemption on what a thing DECLARES, not what it appears to BE
- `## A one-way repair flag defeats the mechanism that would have corrected it`
  -- store a rule version, re-derive from bounds, never filter in place
- `## The design counterpart: choose an ILLEGAL sentinel, never a plausible one`

**You are reading a ticket, or writing one**
- ``## A ticket's prescription is a hypothesis, and it can rule out the answer``
  -- when a fix does not take, re-read what the ticket EXCLUDED
- ``### The `## The fix` section is trusted MORE than the summary``
  -- a summary reads as a claim and invites doubt; a fix section reads as a
  conclusion, and was never tested. Test it against the oracle before implementing
- `## A comment is an unverified claim, and tickets inherit it`
- `### The polarity asymmetry: a guard stuck on PASS gets caught. One stuck on
  FAIL may not.` -- the conservative failure produces MORE testing, which reads
  as diligence, so nobody files it; assert the ACCEPT arm too
- `## A CENSUS is a predicate, not a number` -- six counts of the same thing,
  13 to 45, all correct about what they measured; relay the predicate and the
  command, never the number
- `### The same error one level up: pricing a NAME by its position in an
  ordering` -- quick<native<limited<full is not a volume knob; `limited` is the
  no-qemu tier, so it answers 0% of a cross question, not a fraction of it
- `## A STANDING-RULES block is skipped by whoever has landed the most slices`
  -- not buried, not stale, not hard to find; skipped by the reader most
  confident he knows the campaign, which is the one with the most slices landed
- `## Record the negative result` -- and record the option you measured and
  declined, with its number

Its sibling `normalise-dont-special-case.md` carries the structural half: why the
second path is the broken one, and why a special case gets the careful wording
while the general case keeps the words from before anyone knew.

## Order

**1. Does it disagree with CPython (NilPy) or gcc/FPC (C/Pascal)?**

```sh
tools/pydiff.py run    prog.py      # NilPy vs CPython: stdout + exit code
tools/pydiff.py bisect prog.py      # names the first diverging statement
tools/pydiff.py probe               # the standing corpus
tools/fpc_diff_probe.sh             # Pascal vs FPC
tools/gcc_diff_probe.sh             # C / crtl vs gcc's libc
tools/gcc_diff_probe.sh --target i386|arm32|aarch64|riscv32   # ...and cross
tools/lib_cross_sweep.sh            # a cross target vs our own x86-64 output
tools/crtl_decl_probe.sh            # is a declared crtl fn IMPLEMENTED, or
                                    # silently binding to libc.so.6?
```

All five, plus the shared traps that make them lie to you, are indexed in
**`devdocs/dev/differential-probes.md`**. Read that before adding cases — the
rules there were each learned by chasing a phantom.

First, always, for a wrong-answer bug. It is the only method that finds a bug
with no crash, no error and confident output. `bisect` keeps every def/class and
varies how many top-level statements run, so it narrows without the truncation
problem.

**2. Is memory being read after it is freed?**

```sh
compiler/pascal26 -dPXX_HEAP_DEBUG prog.py out
```

Freed payloads become `$DD`, held out of the free list. A dangling read then
returns `0xDDDDDDDD` / `-572662307` / `-2459565876494606883` instead of a
recycled neighbour's plausible bytes. Also reports DOUBLE FREE, WRITE AFTER
FREE, and RETAIN/RELEASE of a freed object.

*Tell:* the bug appears only when something churns the heap in between, or
`list(x)` fixes it and `x` does not. That is ownership, not typing.

**3. Who took the reference, and who dropped it?**

```sh
compiler/pascal26 -dPXX_OBJTRACE prog.py out
./out 2>trace.log
grep 0x7fffd7e00018 trace.log       # one object's whole life, in order
```

Use *after* step 2 has told you there IS a use-after-free. Poison says which
read hits it; the trace says which release caused it.

**3b. How much does it allocate, and of what size?**

```sh
compiler/pascal26 -dPXX_ALLOC_CENSUS prog.py out
./out 2>census.log
grep 'allocs=' census.log | tail -1        # the closest thing to a total
grep 'sizes'  census.log | tail -1         # where the churn actually is
```

The three defines above answer *correctness* questions. This one answers a
*cost* question, and it exists because the answer used to require callgrind —
which is **not installed on plexus**, where `perf_event_paranoid` is 4 and
blocks even user-space sampling. Three sessions of
`bug-o-uforth-blocktest-runs-slower-under-pxx-than-under-cpython` ranked their
own follow-ups on shares nobody present could re-run.

```
pxx-census: allocs=14482408 frees=14040465 live=441943 bytes=595241560 reuse=13999247 list=41000 bump=442161 arenas=1
pxx-census: sizes 8:37176 16:558 24:509 32:11710484 40:899237 48:571422 ...
```

Read it as: **`live` flat with `allocs` climbing is churn; `live` climbing is
retention.** `reuse` vs `bump` says whether the free lists are working. The
histogram is bin size in bytes → count, and it is what makes a change legible
as a mechanism rather than as a percentage: turning string literals into static
blocks took uforth's `core.fr` from 14.48M allocations to 8.04M, and the
histogram said *why* — the 32-byte class alone fell by 6.14M, which is 95% of
the whole reduction and exactly the size of a short literal's block.

*Two things to know before you use it.* There is **no exit hook** — the
program's exit is emitted by codegen, not by the runtime — so the report fires
on a schedule instead: at each 12.5% growth in the allocation count. The last
line is therefore a floor within 12.5% of the true total, never the total. In
exchange it gives a growth *curve*, and **a program that segfaults still leaves
its census**, which a report-at-exit would not. And there is deliberately **no
call-site attribution**: that needs a caller tag threaded through every entry
point or a stack walk, and both change what they measure.

*Tell:* you are about to argue that some routine is "most of the allocation
cost". Count it first. This is a counting instrument, so it is immune to the
box being busy — unlike every timing number, which on plexus drifts enough that
the same binary measured 2.514s and 2.817s twenty minutes apart.

**4. Step through it.**

```sh
compiler/pascal26 -g -O2 prog.py out
gdb ./out
(gdb) source tools/pxx-gdb.py       # Variant decoding + pxxrc
(gdb) break combine
(gdb) pxxrc obj                     # refcount — lives at [inst-16], else invisible
```

`-g -O2` works and is usually right: `-O2` is where the ownership bugs appear.

> **Was broken on `compiler.pas` for a few hours on 2026-08-30; FIXED in
> `e1b35bad1`, and the lesson is not the one the ticket title suggests.**
> `-g -O2` and `-g -O3` died with `DWARF buffer overflow (-g)` while plain `-g`
> built — but **nothing about `-O2` was special except that it got there first.**
> Measured: plain `-g` was already emitting 1,033,241 bytes against a fixed
> 1 MiB cap (98.5%, ~15 KB of headroom), and `-O2` added 17,673 bytes of
> `.debug_line`. `.debug_info` grew by ONE byte, and `.debug_abbrev` and
> `.debug_frame` were identical, so inlining produces no extra DIEs. One more
> unit under plain `-g` would have broken it identically. The cap is now a
> ceiling with the buffer grown on demand (`GrowDbg`, modelled on the existing
> `Code`/`GrowCode` pair), and BSS dropped 1,048,568 bytes as a side effect.
> **Do not read this as "avoid `-O2` with `-g`".** Verified past "it compiles":
> `gdb -batch -ex 'info line IRLowerAST'` on the `-g -O2` compiler resolves to
> `compiler/ir.inc:5831` — a buffer fix can easily yield well-formed-looking
> truncated DWARF, so compiling was never the acceptance test.
Works for Pascal, NilPy, C, Rust, Zig, including breakpoints inside imported
`.py` modules and C headers.

**5. Is the COMPILER doing the wrong thing?**

```sh
PXXDBG=help                                    # topics
PXXDBG=n.locals    compiler/pascal26 prog.py out   # inferred local types
PXXDBG=n.ctorargs  compiler/pascal26 prog.py out   # construction arg types
PXXDBG=a.ir:myproc compiler/pascal26 prog.py out   # IR of ONE routine
PXXDBG=a.ast:myproc compiler/pascal26 prog.py out  # its AST before lowering
PXXDBG=a.symptr:p  compiler/pascal26 prog.pas out  # what a pointer DECL recorded
PXXDBG=a.opovl     compiler/pascal26 prog.pas out  # operator lookups + candidates
PXXDBG=a.srcmap:*  compiler/pascal26 prog.pas out  # token->file map + every plant
PXXDBG=a.poisonslot compiler/pascal26 -O3 prog.pas out # does ANYTHING still read that slot?
make pxx-debug && gdb --args compiler/pascal26-debug prog.py /tmp/out
```

**`a.ir` at TWO `-O` levels is the cheapest disconfirming measurement here, and
it is worth running before any bisect of an optimizer bug.** Dump the diverging
routine's IR at the level that is right and the level that is wrong and diff
them. If they are identical, every IR-level pass is exonerated in one command
and the search is now inside the backend — that is half the candidate sites gone
before the first rebuild. It settled
`bug-a-o3-drops-the-first-of-two-chained-qword-multiply-xor-statements` (33
nodes, same numbering at `-O2` and `-O3`), where a site-by-site probe of nine
`OptLevel >= 3` gates was the alternative at ~20s per rebuild each.

*The wrinkle that makes it look like the tool does not apply:* `a.ir:<proc>`
takes a ROUTINE NAME, and a program's MAIN BODY has none, so a top-level repro
prints every routine but the one you care about. **Wrap the repro in a
`procedure` first** — if the bug survives that (check, do not assume), you can
ask for it by name.

**A CHANNEL SPELLED WITHOUT ITS `:` PRINTS NOTHING AND EXITS 0, and there are
two kinds of channel.** `PxxDbgEnabled` takes a bare topic (`PXXDBG=n.locals`);
`PxxDbgWants` takes `topic:<name>` or `topic:*` and returns False for a bare
topic, because `PxxDbgArg` only matches a segment whose next character is `:`.
So `PXXDBG=a.srcmap` and `PXXDBG=a.xtrelax` are silent — indistinguishable, at
the terminal, from the code path never running. Measured 2026-08-30: an
instrument added specifically to answer "did this fire?" reported *did not fire*
for four programs, two of which provably did, and the reading survived one round
of debugging the wrong thing. **Establish the channel can speak before you read
a silence as an answer** — run it once on an input that MUST print. `PXXDBG=help`
lists the topics; it does not tell you which kind each one is, so the check is
the positive control, not the listing.

*The main body has no name here either.* `PxxDbgWants(topic, Procs[CurProc].Name)`
with a `CurProc >= 0` guard cannot fire for a program's top-level block, which is
exactly where a generated repro puts its code — the same wrinkle as `a.ir:<proc>`
above, one level down, and it silently costs you the measurement instead of an
obviously missing routine.

**Before you believe a PXXDBG count, check that the tag has a site and that the
site is in the backend you are building.** Measured 2026-08-30 by
frank-optimize: seven readings taken while chasing a residual, of which **four
were not measurements.** The separator is one grep and a filename, and it is
cheap enough to run over every tag you use:

```sh
grep -rc "PxxDbgEnabled('<tag>')" compiler/     # does it exist?
grep -rl "PxxDbgEnabled('<tag>')" compiler/     # and in WHICH backend?
```

| tag | sites | file | what a `0` meant |
| --- | ---: | --- | --- |
| `a.reload` | **0** | *none* | **the tag has no implementation** — it can only ever print 0 |
| `a.w1left` | 1 | `ir_codegen.inc` | x86-64 only: on an aarch64 build, the expected answer to a question never asked |
| `a.w1cmp32` | 1 | `ir_codegen.inc` | same |
| `a.a64binop` | 1 | `ir_codegen_aarch64.inc` | a real site, but its own comment says **`REPORT ONLY`** — it prints a *population*, not a firing count |
| `a.w2` | 1 | `ir_codegen_aarch64.inc` | a real measurement (105) |
| `a.resid` | 6 | both | a real measurement (2280) |

**Four distinct failure modes, and not one of them is a bug** — a population read
as a count, a real probe in the wrong backend, a tag with no implementation, and
the two genuine readings that look identical to the other four from the caller's
side. Every one is a correct artifact read at a scope it never claimed.

**`a.reload` is the purest specimen in this file of *a guard that cannot fail is
not a guard, and it prints PASS*** — and it is worse than the saturation guard
that named the rule, because that one at least ran and scored something. This is
an **empty question returning a believable answer**: `0` is exactly what a real
negative result looks like, and nothing distinguishes them.

That it lands on `PXXDBG` specifically is the sting. **This is the instrument we
reach for after reasoning has already failed us** — it exists because editing a
probe into the compiler and self-compiling was so expensive that reasoning won
and was wrong. The measuring instrument needs the same discipline as the thing it
replaced.

**And the consequence worth more than the taxonomy: two aarch64 slices from that
session have no probe at all, so whether the fuzzer reaches them is not
*unmeasured*, it is *unmeasurable with what is in the tree*.** "We did not look"
and "there is nothing to look with" want different responses, and only the second
tells you what to build.

The next two answer a question this repo keeps asking in different words: *was
the metadata never populated, or never read?* `a.symptr:<name>` (or `:*`) prints
a pointer variable's recorded depth, pointee and ultimate base — the exact
fields `IsNodePChar` and friends consult, so a shape that lowers wrong tells you
in one run which half is missing. `a.opovl` prints every operator-table query,
each candidate for that operator with its stored right-operand key, and the
answer; "my operator did not fire" otherwise has four indistinguishable causes.
Both were added while chasing a bug whose FIRST fix attempt was written against
an assumed layout, compiled, and changed nothing.

`a.poisonslot` answers a DIFFERENT shape of question, and it is the one to reach
for when the blocker is an audit rather than a bug: *does anything still read X?*

At `-O3` a register-resident local is dual-written — register and frame slot
both current — and the optimisation that stops writing the slot is safe only if
nothing reads it. The readers you can find by grep are easy; the question that
stops you is whether some direct `[rbp+off]` emit, somewhere in 10k lines, still
does. **That is an audit with no completion criterion: unanswerable by grep,
unfalsifiable by reading, and normally the point where the work gets parked.**

The probe converts it into one experiment. It fills the slot with `$5EEDADAD`
immediately after each dual-write, so a surviving reader returns *garbage*
instead of a plausible value:

> **A stale slot and a correct slot are indistinguishable. A poisoned one is
> not.**

Same trick as `-dPXX_HEAP_DEBUG`'s `$DD` fill, one level up — and it works for
the same reason. Run the corpus under it and any reader announces itself.

Measured on the run it was built for: **2 of 19 programs changed behaviour, and
both were the ones with `try`/`except` in a loop** — one hung, the other printed
`1592634797` (`$5EEDADAD`) straight back. The culprit was the exception landing
pad, which re-syncs residents *from* the slot and so is the one reader residency
cannot see through. No amount of careful reading had found it; the probe found
it in one run, and the resulting gate (`RcProcHasExc`) is what made the
optimisation land.

**The rule that makes it evidence rather than decoration: a poison probe must
call the SAME predicate as the change it is testing** — `PoisonResidentSlot`
calls `ResidentSlotIsDead`, the function the optimisation itself gates on. Copy
the condition instead and you poison a *neighbouring* set, so a green result is
evidence about something you are not shipping. This is the whole reason the
result can be trusted.

Two things it does NOT tell you, which matter as much as what it does:

- **It writes exactly `TypeSize` bytes.** A wider store would corrupt the
  neighbouring slot and manufacture the bug it is hunting.
- **It covers only what it poisons.** It fills GPR residents; float residents
  (xmm8/xmm9) were never poisoned, so nothing is known about them and their
  dual-write stayed. *Not covered is not the same as fine* — a null result is
  only worth what the probe's reach is worth, so state the reach whenever you
  report one.

Generalise the shape, not the flag: when you are blocked on "is there a reader /
writer / caller I have not found", **poison the thing rather than auditing for
its users**, and make the poison match the change's own predicate.

`a.srcmap:*` answers the third variant of the same question: *is the map wrong,
or is the index into it wrong?* It prints the token->file range table (each
range's start, the source lines and text of the tokens on either side of the
boundary, and the path) plus the token index the diagnostic actually asked
about, and a PLANT line for every mark as it is recorded. It exists because
`in: <path>` was naming a 707-line RTL file for an error on line 2074 of a
corpus unit, and from outside there is no way to tell whether the ranges drifted
or the lookup was reading a different token — the first two guesses at the
mechanism were both wrong, and the dump settled it in one run
(`bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file`).

No rebuild, no source patch. **This exists because patching a probe in and
self-compiling (~90s) is how a wrong premise got recorded in a ticket** — the
cheap move was to reason instead of measure. Do not reason about what type the
compiler inferred; print it.

**6. It faulted on a CROSS target and all you have is an address.**

```sh
tools/run_target.sh <arch> ./prog                  # the plain run
qemu-<arch> -strace ./prog                         # WHY it died, and where
qemu-<arch> -d in_asm -D /tmp/asm.log ./prog       # the block it died in
qemu-<arch> -d cpu    -D /tmp/cpu.log ./prog       # register state
compiler/pascal26 --debug ... 2>&1 | grep '^proc'  # "proc N: NAME at OFFSET"
```

New in 2026-08-30, because until then no xtensa binary could be executed at all
and "it faulted" was not a shape this repo had. Take them in that order — the
first line usually ends it:

- **`-strace` first, always.** It prints the syscalls, then the signal *with its
  `si_code` and address*. `SIGBUS si_code=1` is `BUS_ADRALN` and the address
  will be odd — which converts *"a wild pointer somewhere"* into *"a misaligned
  one, go look at the frame"*, and those are different searches. A wild pointer
  sends you hunting ownership; a misaligned one sends you to the frame layout,
  where the bug actually was
  ([[bug-a-a-hidden-aggregate-result-temp-gets-an-unaligned-frame-slot]]).
- **`-d in_asm` names the block**, and its last instruction is the faulting one.
  `-d cpu` gives the registers, but read it knowing the dump is at the last
  *exception*, which for a normal syscall is the syscall itself — a register
  there is not necessarily the register at the fault.
- **`--debug` maps an address to a routine.** It prints `proc N: NAME at
  OFFSET`, and the base is the ELF **entry point**, not the load address (our
  images have no section headers, so nothing else will tell you). Without this
  you are staring at a hex address with no name.
- **Then, and only then, a probe** in the backend's own emitter to print the
  offending symbol. That is what turned "an odd offset" into eight named slots.

**The cross toolchains are installed and are not on `PATH`.** ESP-IDF puts
`xtensa-esp-elf-objdump`, `xtensa-esp-elf-gdb` and the riscv32 pair under
`~/.espressif/tools/**`, reachable only after `. $IDF_PATH/export.sh`. A bare
`command -v xtensa-esp-elf-objdump` in a fresh shell answers about the SHELL and
reads exactly like the tool being absent — this cost the fleet five weeks on the
QEMU emulators and cost one session a weaker verification the same night, in the
same directory tree. **A stated absence about this box is a claim about a
search, not about the box**; before concluding a capability is missing, grep the
repo for something that already uses it (`tools/esp_run.sh` had been globbing
that directory for four weeks).

Our ELFs carry program headers only, so disassemble the raw image:

```sh
OD=$(ls ~/.espressif/tools/xtensa-esp-elf/*/xtensa-esp-elf/bin/xtensa-esp-elf-objdump|head -1)
$OD -D -b binary -m xtensa --adjust-vma=0x08048000 \
    --start-address=0x... --stop-address=0x... ./prog
```

Two cautions worth the lines. **Objdump desyncs on the inline literal pools**
xtensa emits mid-code (a `j` hops over each one), so anchor `--start-address` on
a known instruction boundary — a proc start from `--debug` — and treat
`excw` / stray `.byte` runs as the tell that you have drifted. And **the
strongest evidence is two backends, not one**: the same source compiled for
xtensa and riscv32, disassembled with each toolchain, showed *identical* frame
offsets, which is what proved a suspected xtensa codegen bug was shared layout
that five backends simply never trap. One backend's disassembly could not have
said that.

## Two traps that produced confident wrong readings

- **Stale binary.** A still-running instance makes the compiler's write a silent
  no-op (ETXTBSY) while still printing `ok:`. **Use a fresh output name and check
  it changed** — that is the whole fix, it needs no signal at all, and it cannot
  hurt anybody else. If you genuinely must kill the running copy, kill **the pid
  you started** (`$!`, or `setsid` and kill the group), never a name pattern:
  `pkill -f <tool>` asks *"is there a process whose command line contains this
  text?"* when your question is *"is there a process **I** started?"*. Those
  coincide exactly while one agent runs the tool and diverge silently the moment
  two do — and several agents share this box. `tools/gui_shot.sh:52` carries the
  same rule, learned when one agent's pattern-kill took down another's live Xvfb
  mid-capture; a `pgrep` waiter has the mirror-image bug, because it matches
  *itself* and never returns. **And `pkill` has that same self-match**: the shell
  running `pkill -f "reduce.py"` has `reduce.py` in its own command line, so it
  kills itself and the call returns 143/144 — measured 2026-08-30, and read as a
  crashed tool rather than as the documented trap, because the entry above named
  `pgrep`'s presentation and not the mechanism. The general form: **a `-f`
  pattern match runs inside a process whose command line contains the pattern**,
  and the three victims (a sibling's process, the waiter, the asker) look like
  three unrelated faults. Bracket one character — `pkill -f "[r]educe\.py"` — or
  kill the pid you started.
- **Lost stdout.** SIGTERM discards buffered stdout, so "the marker never fired"
  and "it fired and the output died" look identical. Give tests a clean exit.

## A/B the hunk, bisect the window — they answer different questions

Measured 2026-08-30. `"a" * 3` returned length 285 instead of 3 under NilPy —
correct under CPython, correct under the **pinned** binary, wrong at HEAD, and
the wrongness was a plausible value read from a wrong base (it emitted bytes
from the RTTI type-name table) rather than a crash. The window was 140 commits.
A bisect was the obvious move and was the wrong FIRST move.

**When you already have a named suspect, disable its hunk and rebuild once.**
frankwasm put `if False and` in front of one guard in `IRLowerCallArg`, rebuilt,
and got the whole answer in a single build:

| repro | arm ON | arm OFF | CPython |
| --- | --- | --- | --- |
| `"a" * n` | 288 | 3 | 3 |
| `"ab" * 2` | 49982 | 4 | 4 |
| `a * 3` (variable operand) | 3 | 3 | 3 |

A bisect over that window would have named the same commit and **told you
less**: it answers *which commit*, and where a commit touches several files you
must then open the diff to find *which hunk* — a second search. The A/B answers
both at once. It also fails safe: if the repro stays red your lead was wrong,
you learned it in one build instead of eight, and the bisect is still there.

So: **named suspect → A/B the hunk. No suspect → bisect the window.** Reach for
bisection when you cannot name a candidate, not as the reflex for "something in
this range broke it".

And narrow the *construct* while you are there, because that is what localises
the fix. Repeat with a **literal** left operand was wrong; the same value in a
variable was right; `f("abc")`, `len("abc")`, `"abc"+"de"`, `"abc".upper()`,
`"abc"[1:]` and the Pascal `const AnsiString` cases were all right. That shape
is one callee consuming the frozen form at the wrong offset — which is a hunk,
not a commit.

### Anchoring: two windows, both defensible, one correct per question

The same investigation produced a 55-commit window and a 140-commit window, and
neither was a mistake:

- `<last clean pin shadow>..<sha>` answers **"what could have flipped the pin
  shadow?"**
- `<pin tree>..HEAD` answers **"what could have broken something that is green
  under `pinned`?"**

For a regression whose known-good is the pinned *binary*, the second is the
right anchor. State which question your range answers; a range that silently
answers the other one converges confidently on the wrong side.

### The build line must be READ, not assumed — and not only when bisecting

`make compiler/pascal26` is a **no-op that exits 0** in any tree seeded with a
copied-in binary: `cp` stamps the seed newer than the sources, so make prints
`'compiler/pascal26' is up to date` where `converged after N round(s)` belongs.
CLAUDE.md documents this for seeded trees, which makes it easy to file mentally
as a bisect hazard. It is not. **Any build whose result is load-bearing needs
that line read** — a bisect that hits it tests the seed at every step and
converges confidently on the wrong sha, and a one-off verification that hits it
reports on a tree that no longer exists. There is no error to wait for.

Read `converged after N round(s)`; confirm the binary's sha256 differs from
`pinned`. Absence of the line is the whole tell.

**And the trap has a MIRROR that is louder and more dangerous.** A seed too
*new* makes the build a silent no-op. A seed too *old* makes it FAIL — with a
compiler-internal error naming a file in somebody else's lane. Measured
2026-08-30: `make compiler/pascal26` died with

```
pascal26:2084: error: LoadFile expects string variables in IR codegen
  in: compiler/cpreproc.inc
```

which reads exactly like "Track C just broke master's self-host gate", and was
one command away from being reported as that. It was a thirteen-hour-old local
`compiler/pascal26`. The source at HEAD uses `LoadFile(CPrepInclude[depth])`,
the codegen that makes an array-element destination legal
(`EmitLoadFileManagedAt`) landed after that seed was built, and **the error
string it printed does not exist anywhere in the tree** — which is the tell, and
a free one: `grep` for the exact message, and if the source does not contain it,
the compiler that printed it is not the compiler you think you are running.
`pinned` built HEAD without complaint; reseeding gave `converged after 2
round(s)`.

The silent direction costs you a verdict. This direction costs you a **false
accusation against another lane**, complete with a file name, a line number and
a plausible mechanism. Before reporting that master's gate is red, reseed from
`pinned` and rebuild — three commands, and the alternative is a peer bisecting
a bug that is not there.

## A guard can fail in the FALSE DIRECTION, and that costs more than a silent one

Measured 2026-08-30. `tools/csmith_target_devtest.py` asserted, unconditionally:

    no ILP32 oracle on this box (gcc -m32 compiles, does not link),
    so none is claimed

True on the box it was written on. **False on plexus**, where `gcc -m32` links
and `probe_oracle("arm32")` returns an ILP32 datamodel oracle. So a csmith run
on one host compares ILP32 checksums against an oracle and on the other silently
does not — and the only thing that noticed was a guard, **which reported the
host with MORE coverage as the defect.**

**That is worse than a silent failure, and for a specific reason: nobody chasing
a red reads it as "this box checks more".** The reflex is to make the red go
away, and the cheapest way to do that is to *remove the extra coverage*. A
silent guard costs you a verdict; a false-direction guard costs you the
capability, and it recruits you into destroying it.

Same family as the loud stale seed two sections up, which read as another lane
breaking master's self-host gate. Both hand you a specific, plausible, wrong
culprit; neither errors; both are *correct about something else*.

**The fix is never to pick the other host's answer.** Assert the property that
holds on any box — here, that the probe gives an answer and says what it means —
with **both arms asserted** so neither can go silent, and print which arm ran so
a reader of this host's output knows what it actually covered.

### A job name is a promise, not a description of what ran

frank-user's form, and it is why a job-set diff cannot see the above:
**`csmith-fuzz#arm32` names the INPUT.** It says nothing about whether an oracle
was claimed, and both hosts keep the promise. Two hosts can run the same suite,
report the same job list, the same count and the same verdict, and check
different things.

So a host-parity check keyed on job names is necessary and not sufficient: the
artifact everyone compares is the one place the difference is guaranteed to be
absent. The unit is **capability × job**, and the capability half is what no
census of corpora or job names will ever show you.

### And the recurring shape underneath all three: the instrument already had the answer and threw it away

Three instances in one day, and in every one the fix was **persistence, not a
new instrument**:

- `probe_oracle` computes the full oracle vector and drops it after printing;
- `sync.sh` proved each commit was on origin and discarded the sha it had just
  resolved — which is why the ghost-sha rate was ~100% by construction;
- `skip_summary` counted coverage holes without naming them.

Before building a prober, check whether something already probed. The question
to ask of a tool that nearly answered you is not *"what else could measure
this?"* but ***"what did this already compute and then not write down?"***

## A wrong fact gets challenged. A MISSING fact collides with nothing.

The coordinator's, 2026-08-30, after relaying half of a comment and watching the
weaker half nearly become a playbook section.

The relay was *"`gate.sh:104` says the gate must not rebuild before comparing, or
it loses the anti-Thompson check."* **True, and it had been read at the source.**
What was dropped is that the same comment says the *common* cause is staleness
rather than contamination, that it therefore reads as **flakiness** — the gate's
own testmgr step rebuilds as a side effect, so the first run after a sibling's
commit fails and the re-run passes — and that this cost two full gate runs on
consecutive days before anyone saw the pattern.

**A wrong fact gets challenged, because it collides with something the recipient
already knows. A missing fact collides with nothing.** So a compression failure
is invisible from *both* ends: the sender believes it was relayed, the receiver
believes they have it, and no moment ever arrives at which the gap surfaces. It
is the sibling of *a verification claim scopes to exactly what was checked* —
except the casualty is what the sender chose not to say rather than what they
failed to check, and it is worse, because a scope error at least has an edge
somebody can find.

Two habits, both cheap, and the first is the one that scales:

- **Give the LOCATION, not only the conclusion.** `gate.sh:92-107`, never
  "gate.sh says". The pointer costs the sender nothing and lets the receiver
  outgrow the summary — which is the only mechanism that recovers what was
  compressed out.
- **When a relay is about to become a written artifact** — a playbook section, a
  ticket, public copy — say *"read the source, I compressed it"* out loud. The
  moment a summary stops being conversation and starts being a record is the
  moment its omissions become permanent.

Worked example, both directions, same night: the relayed half would have produced
the weaker section; going to the source produced a section carrying the
`flakiness` cost, which the person who had *lived* that failure had filed as "the
check worked" — a true reading, and exactly the one that teaches you to shrug at
the third occurrence. The third occurrence is the contaminated binary.

## Ancestry is not existence: `--is-ancestor` cannot tell you a commit is a ghost

Measured 2026-08-30, twice in one session, by two different agents.

This repo rebases constantly, so a cited sha that resolves to nothing is a real
and common failure (`bug-t-resolve-cites-a-sha-the-rebase-then-rewrites`). The
test for it is `git cat-file -t <sha>` — **"not a valid object" is the only
answer that proves a ghost.**

`git merge-base --is-ancestor <sha> origin/master` answers a different question,
and it returns false for at least three unrelated reasons: the commit does not
exist; the commit exists but is not on that branch; or **your checkout is behind
and you are reading a ref you have not fetched.** A `git fetch` updates refs and
does not touch your working tree, so "I fetched" does not make your tree current
either.

Both directions cost:

- calling a **real** commit a ghost dismisses the mechanism you needed — it
  happened here to `fe297522b`, the commit that explained why a suite had
  started running;
- calling a **ghost** real sends the next reader after a citation that resolves
  to nothing.

**A "not found" is only evidence once you have proved your own tree is
current.** `git rev-list --count HEAD..origin/master` is that proof and costs
nothing.

### `git log <mysha>..HEAD` is EMPTY BY CONSTRUCTION after your own push

frankA, 2026-08-31, twenty minutes chasing his own tail. A rebuild produced a
different binary from one built minutes earlier off what he believed were the
same sources. To rule out a teammate's commit he ran:

```
git log <mysha>..HEAD -- compiler/      # empty
```

**His push had just rebased that commit to the tip, so `<mysha>` WAS `HEAD` and
the range was empty by construction.** The command could not have answered; it
reported the absence of anything after the newest commit, which is always true.
The unbounded form found it immediately: `git log -8 -- compiler/` showed a
sibling's commit sitting one below his, arrived during his own `sync.sh`.

**In a repo where every push rebases, the bounded form is the wrong default.**
The anchor you are most likely to reach for — your own sha — is precisely the one
the rebase has just moved to the tip, so a range starting there is empty however
much landed. And an empty range and "nothing landed" print identically.

Same family as `--is-ancestor` above and the same cure: **ask what this would be
if it were false.** For the range to be able to answer, `<mysha>` would have to
be strictly behind `HEAD` — one `git rev-list --count <mysha>..HEAD`, or just
read the unbounded log and look at the dates.

## A sha that EXISTS can still be the wrong sha for the question

Distinct from the ghost family above, and more expensive. A ghost is a sha that
does not exist and resolves to nothing. This one exists, is yours, and is simply
wrong for what was asked of it.

Measured 2026-08-30. A pass was promoted in `440c822e6a80`; a sweep was requested
against that sha as "the promotion sha". It carries a **broken** commit that
landed 36 minutes before it, and **not** the revert that landed 11 minutes after
it. A full tier on it returns RED with ~24 unrelated jobs, in an archived row
keyed to the promotion.

**"My change landed at X" and "X is a good tree" are different claims, and the
second decays with every commit that lands after yours.** A sweep request, a
bisect anchor, a "please reproduce at" — every one of them is a question about a
**tree**, never about your commit. So the sha to hand over is the newest one that
contains everything the answer depends on, which is usually not the one you
wrote.

**Check it, do not assert it** — one command per dependency:

```
git merge-base --is-ancestor <the-revert-you-need> <sha-you-are-about-to-send>
```

Catching it before the sweep runs is cheap. The version where it runs is the
expensive shape: a RED with real evidence attached, pointing at the wrong author,
in a record that outlives the session that knew better. **The archive is what the
next person reads**, and no footnote travels with it.

## A bisect can name the RIGHT commit and still be wrong

Measured 2026-08-26, on `test-uforth#core` and a NilPy type-name red. Read this
before you trust a bisect result, because the failure is not that the bisect
missed.

`293d70509` genuinely is the commit that changed the behaviour. It is also
**correct**, and reverting it would have been the wrong fix. It removed a
**leak** -- an unmanaged `tyPointer` handed back from a value-position arm and
never released -- and that accidental permanent reference was the only thing
keeping a borrowed closure alive. Deleting a real bug made a second, older real
bug reachable: a use-after-free that had been latent all along.

So the honest sequence is: bisect converges, names a commit, the commit really
did flip the symptom, you revert it, **the crash goes away**, and you record a
fix. You have restored a leak and re-hidden a use-after-free that will resurface
the next time anyone tidies that arm.

**The tell is that the named commit makes things better on inspection.** When a
bisect lands on a change that looks like a cleanup, a leak fix, a lifetime
tightening, or a removal of dead state, do not revert it. Ask what it was
propping up. The question to answer is "what did this change stop compensating
for", not "what did this change break".

What actually found it: `-dPXX_HEAP_DEBUG` put `0xdddddddddddddddd` in `rax` at
an `incq` -- a **retain** of a pointer read from freed memory, which is not a
thing a leak fix can cause and is a thing a borrowed reference can.
`-dPXX_OBJTRACE` then showed the free cascade. Endpoint measurement, not
bisection, is what separated "the compiler changed" from "the RTL changed":
pinned stable ran the repro clean, HEAD did not, and HEAD-compiler-plus-old-RTL
still crashed.

Related, and it compounds: the range that bisect ran over was anchored wrong, so
it had already converged in four steps onto a commit whose entire diff was 250
`prio:` frontmatter lines. A range can exclude the culprit *and* contain
untestable commits, and neither failure announces itself -- see
`normalise-dont-special-case.md` on why the compensating case is the one that
punishes bisection specifically.

### The commit is right, an EXPECTATION was retired -- and the SHAPE of the divergence tells you which

The cheaper cousin of the above, measured 2026-08-31 by Track T on seven, and the
one I got wrong from the other side.

`ce4d9004c` deliberately changed `SizeOf(Extended)` from 10 to 8, resolving
`bug-p-sizeof-extended-disagrees-with-the-storage-extended-gets` -- pxx really
does store an `Extended` in 8 bytes, so the old `10` agreed with FPC while
**misdescribing our own layout**, which is the worse of the two errors. The
`Makefile` expectation still said 10. The bisect range was right, the commit is
not a fault, and the fix is one character in an expectation nobody updated.

**The discriminator is free and it is the shape, not the cause:**

```
actual   1 1 2 2 4 4 4 4 8 8 8 8 8 8 8 1 1 4 8 8  8 16 2 4 1 8 8
expected 1 1 2 2 4 4 4 4 8 8 8 8 8 8 8 1 1 4 8 8 10 16 2 4 1 8 8
                                                  ^ 1 of 27
```

**Exactly one of twenty-seven values moved.** A table merge going wide cannot
produce that; a single retired expectation is the only thing that fits. Count the
divergences before theorising about them -- one is an expectation, many is a
mechanism.

**And the trap that is mine, because it is a dispatch failure rather than a
debugging one: a commit that did several things has several candidate mechanisms,
and naming the commit does not pick one.** I circulated a don't-bisect note for
that very commit describing the *shadowing* failure (builtins stealing a user's
own type name). That is real and is frankwasm's measurement -- and it is **not**
what the red was. `test/test_sizeof.pas` declares no shadowing user type; its one
divergence is a builtin's own width. Same commit, different hunk, different
mechanism, and **watching for one signature makes you look straight past the
other.** A warning that names a commit but only one of its mechanisms is worse
than a warning that names neither, because it will be believed for the wrong red.

## When you are about to conclude something

Check it against a second source before writing it down. Every wrong root cause
in this repo's ticket history was a plausible story that nobody diffed against
an oracle. `pydiff`, gcc, FPC and CPython are all cheaper than a reverted fix.

### When a NEW variable explains everything you have seen, cross it against the old one

Varying what you held fixed is how you find a boundary. Walking that one new
axis is how you write down a rule that fits every observation you have and is
still wrong.

Worked example, `bug-n-from-import-with-an-as-rename-loses-what-it-renames`,
2026-08-18. `from M import X as alias` was misbehaving. Two sessions measured
it, and each produced a table that was accurate and complete for the rows in
it:

| reading | evidence for it | why it was wrong |
| --- | --- | --- |
| "the argument count is the axis" | `alias()` with no arguments crashed; `alias(x)` worked | every working row happened to use a one-character source name |
| "the source name's length is the axis" | `a` worked, `ab`/`abc`/`abcd` crashed; a name sweep agreed | every crashing row happened to be a zero-argument call |

Both rules fit all the data their author had. Crossing the two settled it in
six compiles:

```
name len 12, ZERO args   -> CORE DUMPED     name len  1, ZERO args  -> ok
name len 12, ONE arg     -> ok              name len  6, ONE arg    -> ok
```

The crash needs **both** — zero arguments *and* a source name of two or more
characters. Neither variable alone predicts it, so neither rule was safe to act
on, and the second one had already been written into the ticket as superseding
the first.

**Two symptoms with different boundaries under one construct usually means two
faults.** The same investigation had a second symptom — an omitted default
coming back silently wrong — which was present at *every* name length and so
could not be the length fault at all. A fix aimed at the crash would have
turned the obvious test green and left that one alive. If your two symptoms
disagree about where the boundary is, do not unify them; record both, and say
in the ticket that a fix for one must be re-measured against the other before
it closes.

**And a crossed boundary still is not the mechanism.** The as-rename case above
was resolved by a crossing; a sibling bug found the same evening was not. That
one's boundary — "subscripting a container LITERAL inside a function crashes,
binding it to a local first does not" — held on every row of a four-axis
crossing, and the subscript turned out to be innocent: the fault was RETURNING
anything derived from a literal, including a method call with no subscript in
it, and the boundary looked like subscripts only because the rule that would
have saved it lived in a path keyed to a non-literal receiver. So a crossing
tells you where the behaviour changes, which is what you need to hand someone a
repro — it does not tell you why, and a rule that fits every row you have can
still be naming a correlate of the real path. Write the boundary into the
ticket as a boundary, not as a cause, and say which one you are claiming.

The corollary, since it is what actually caught this: **two sessions measuring
the same bug and disagreeing is a signal, not a nuisance.** Four confounded
readings were resolved that way in one day — including one where the correction
to a confound was itself confounded. Deferring to whoever measured last would
have given the wrong answer three of those four times.

---

## A one-way repair flag defeats the mechanism that would have corrected it

Track T stored "this regression has been repaired" as a **boolean**. So
*already repaired* was indistinguishable from *repaired under a rule we have
since corrected* -- and the first rule was wrong, in the too-narrow direction. A
range narrowed by the bad rule could never be re-widened. **The fix for a wrong
rule had installed a flag saying do not revisit.**

The shape is worth recognising anywhere state records that work was done:

- **Store a rule VERSION, not a done bit.** Bump the constant and everything
  re-derives on the next pass.
- **Re-derive from the bounds; never filter the stored result in place.**
  Filtering in place is one-way by construction -- information leaves and cannot
  come back. Re-deriving from `good`/`bad` is idempotent and correctable in *both*
  directions, and here it cost no extra storage, because the bounds were already
  in the state file.

A repair that cannot be repaired is the corrective mechanism eating itself, and
it is invisible while the rule happens to be right.

The sharpened rule, after the same author caught a weaker instance in their next
commit -- a value stamped behind an existence check, write-once, whose answer
depended on a prefix list that can change: **cache a fact about a frozen
artifact, never a fact derived through a rule that can change.** A completed
run's `timed_out`, a build's `pin_built` -- immutable, safe to persist forever. A
verdict computed *through* a policy is a one-way cache wearing different clothes,
and recomputing it is almost always cheaper than the machinery that would make it
correctable. An audit on that criterion found every other persisted boolean in
the file was a fact about a run, and clean.

Its complement, for the other direction: **persist for the published artifact,
derive for the live reader.** A reader that waits on a writer-side field is inert
until the writer next happens to run -- so a status command that reads a stamp
shows a human nothing until the daemon's idle repair fires, while one that
re-derives (one `git diff-tree`, falling back to the stamp) answers tonight. The
cache rule says what is safe to freeze; this says who should be freezing it.

And a corollary from the same fix: **a distinction that is not recorded in the
history decays after one iteration.** Marking the current run torn-down while the
history rows stay unmarked buys exactly one cycle, until the pointer moves past
that sha. A fix that expires is not a fix.

## A property that holds for the wrong reason will stop holding silently

Track T set a new job's class to `selfhost` for its 600s timeout, then found it
was **already** classed that way -- but only because `classify()` matches on the
expanded `make -n` text, and the `$(COMPILER)` prerequisite expands to text
naming `compiler.pas`. The class was right by accident of a prerequisite, not by
anything about the job. A comment had been written asserting the opposite.

This is the quiet cousin of every defect in this file. Nothing is failing;
something is **passing through a path nobody chose**, and the day that
prerequisite is refactored the timeout silently drops to the default and a
600-second job starts getting killed -- with no change to the job, no change to
the class, and no diff to blame.

- **When you find a property already true, ask WHY before being pleased.** "It
  already works" and "it works for the reason I would have chosen" are different
  facts, and only the second survives someone else's refactor.
- **Then make it true on purpose.** They changed `classify()` to match
  `selfcompile` directly, so the class no longer depends on how a prerequisite
  happens to expand. Same cost, and now the reason is the one written down.
- **Correct the comment that asserted the other thing.** This one had been wrong
  from the start and nothing had ever contradicted it.

## A guard that greps the source can only catch what is visible in the text

Same session, second defect. A repair path called `testable_only()`, which reads
like a module helper and is in fact a **closure nested inside another function**.
It parsed. It read correctly. And it **passed the devtest written for it** --
because that guard grepped the source for the call. The guard asserted the call
existed; the call existed; the call was wrong. It would have raised `NameError`
the first time an idle cycle reached that branch, hours later, in a process
nobody watches.

This is the same failure as the `137 -> 2` measurement above: **a check that
runs, passes, and asserts nothing about the thing at issue.**

A third costume, since it recurs: **a close condition about the wrong subject.**
The breadth ticket above closed on `carried_runs != 0` -- satisfied from the day
the mechanism shipped, so it would have closed the ticket **six days early, on a
mechanism recovering 0.33% of what it saves, in the middle of a 40-hour breadth
gap.** `resume_health()`'s own docstring stated the right standard -- *"One line
of RATES, not events"* -- and the ticket closed on an event anyway. **The
instrument that answers "is breadth starved" is breadth staleness**, and nothing
else. Write close conditions on the symptom the ticket is about, not on the
mechanism you happened to build.

The sharpest instance of the family is worth stating on its own, because it is
the one that hides best: **the run that proved the least was the one that most
effectively silenced the request for more.** Staleness asked *is there a record
for this sha?* -- and a torn-down run leaves a record. A timed-out run is the
weakest possible evidence about a sha and was being counted as the strongest,
purely because its artifact is shaped like a completed one. Whenever a check asks
whether an artifact EXISTS, ask what the artifact looks like when the work
failed. Text-shaped guards
are especially prone to it, because writing one feels like verification and the
grep is trivially satisfiable by the broken code.

Three separate text-shaped guards failed this way in one night, which is enough
to call it: **a grep-guard is the weakest guard shape available.** One asserted a
call existed when the call was a scoping error; one matched a name form the
consumer never keys by; and one -- nearly a joke, and the clearest possible
demonstration -- **went red on its first run against the comment explaining the
rule it checks**, because the author had written the forbidden string three lines
above while saying why it was forbidden. A grep reads prose as eagerly as code.
Prefer a guard that executes the path. Where only text will do, strip comments
and match on the form the CONSUMER uses, not the form that reads naturally.

A related recurrence worth naming: the same fix nearly died twice on **coarse
predicate where a precise one exists** -- `target in PIN_BUILT_TARGETS` (a list
that is sufficient, never necessary) standing in for `j.pin_built` (the measured
fact). Same author, same file, same pair of predicates, twelve hours after the
first instance. A wrong distinction does not get learned once; it gets learned
per call site. When you correct one, grep for the predicate, not for the bug.

It was found by running the path end to end against a live case rather than
trusting that it looked right.

The response was a **narrow** checker rather than a linter (`tools/tools_scope_devtest.py`;
there is no pyflakes/flake8/ruff on these boxes). It reports exactly one class:
*a name LOADED where it is not in scope but BOUND somewhere else in the same
file*. That pairing is what keeps it near false-positive-free -- an unbound name
has a dozen innocent explanations, but a name bound in a **sibling function** and
read here is almost never anything else, and it is precisely what a 5,000-line
file of nested helpers invites. Verified by re-injecting the real defect, not a
synthetic one.

Deliberately not general, for the reason this file keeps arriving at: **a checker
that reports everything gets suppressed, and a suppressed checker asserts
nothing.**

## A ticket's prescription is a hypothesis, and it can rule out the answer

Stronger than "distrust the ticket's where-to-look", and more expensive: a ticket
can name the fix that works and **explicitly exclude it**.

`bug-t-the-push-rate-starves-breadth-coverage-entirely` summarised itself as
*"Fix is resumability plus bounding consecutive idle, NOT reserving a slot."*
The dates say the opposite and they are not close. The two prescribed shapes
landed 2026-08-19, after which full-to-full gaps went 12.8h, 9.4h, 21.6h, 19.2h,
31.5h, **40.1h**. The ruled-out shape -- breadth reserves a slot when stale --
landed 2026-08-25, and the next three gaps were **1.1h, 3.1h, 1.3h**. Median
full-to-full over the following 24h: **1.3h**, from 3,828 run records.

Six days of degradation after the prescribed fix; recovery within the hour of the
excluded one.

- **A prescription in a ticket carries the confidence of a decision and the
  evidence of a guess.** It was written before the work, by someone reasoning
  about a system they had not yet measured, and then it sits there in the
  imperative for months looking settled.
- **This is a triage hazard, not just an engineering one.** The prio and the plan
  both inherit the wrong frame, so a ticket can be correctly ranked for work that
  cannot fix it.
- **When a fix does not take, re-read what the ticket ruled out.** That set was
  never tested; it was reasoned. It is the cheapest unexplored space available.

**State the confound rather than let someone find it.** Here, 08-20 is when this
box became a shared workstation, so load rose almost exactly when the prescribed
shapes landed -- the fair reading is that they were not harmful but insufficient.
That does not rescue the headline, because *the confound never went away*: still
a shared workstation, still throttled, same push cadence. **Load held constant,
mechanism changed, outcome changed** -- as close to a controlled comparison as a
live box will give, and worth saying in exactly that form.

### And a structural ceiling, recorded so nobody tries to raise it

The resume ledger reused **73 of 22,280 saved job-results, 0.33%**, and
`superseded: 70` is the whole explanation. A partial is keyed on `(sha, tier)`,
and on abort the watcher re-targets to the new HEAD -- so the partial it just
saved is for a sha nobody will ask about again. **Resumability can only pay where
the same `(sha, tier)` is retried, and a push-driven ladder almost never retries
one.** That is a ceiling, not a defect. It does pay for the one phase that does
retry a single sha -- pin verify, where the log shows 56 jobs already decided
against that exact binary.

### The `## The fix` section is trusted MORE than the summary, and it is the softer claim

frank-coordinator's framing, and it explains why the section above keeps
recurring rather than being learned once: **a summary announces itself as a claim
about the world, and therefore invites doubt. A fix section announces itself as a
conclusion** -- it reads as the product of thinking rather than of measuring, so
it arrives with the authority of something already settled. The two sit in the
same file, written by the same author in the same sitting, on the same evidence.
The one that reads as more finished is the one that was never tested.

So the trust is **inverted exactly where it costs most**: the fix section is
believed hardest by the reader least able to check it -- the agent who has just
claimed the ticket and wants a plan. Writing a plan and testing a plan feel like
the same activity while you are doing the first.

**frankwasm's case, `tgenconstraint39`** (Track P, prio 70). The ticket's
`## The fix` said to check the generic constraint at the end of the type section.
fpc 3.2.2 checks at the **specialization point**. The test itself corroborates
the distinction without needing to trust either party --
`library_candidates/fpc-testsuite/tests/test/tgenconstraint39.pp` is marked
`{ %FAIL }`, and its `specialize TGeneric<TTest>` sits between `TTest = class;`
and `TTest = class(TSomeClass)`:

```pascal
  generic TGeneric<T: TSomeClass> = class end;
  TTest = class;                          { forward -- not yet a TSomeClass }
  TGenericTTest = specialize TGeneric<TTest>;   { <-- FPC checks HERE: fails }
  TTest = class(TSomeClass) end;          { by end-of-section: would pass }
```

Implementing the prescribed fix would have **accepted an invalid program** --
trading one wrong answer for another, in a lane whose whole job is rejecting what
should be rejected.

**Why the corroboration is STRUCTURAL, said here because the section demands it.**
A subsection about not trusting a relayed conclusion, resting on a relayed
conclusion, would be self-refuting. So the check above deliberately does not
depend on being right about fpc 3.2.2's internals: a `{ %FAIL }` marker plus a
specialization sitting in the gap between the forward declaration and the
completion gives the two candidate check sites **opposite verdicts by
inspection**. FPC's actual behaviour is frankwasm's measurement and is attributed
to them; it is not something this file verified.

**And the limit, because it is the kind this file keeps catching: that snippet is
not in the repository.** `library_candidates/` is gitignored (`.gitignore:36`)
and the file is untracked, so a reader on a fresh clone cannot open the path
above -- which is why the shape is pasted here rather than cited by path alone.
frank-coordinator could not corroborate it for exactly that reason and **said so
instead of staying quiet**, which is the correct move: silence beside a claim
reads as assent, and an unlabelled companion is how a bad claim travels.

- **And the partial green would have sold it.** `tgenconstraint38` flips green
  under the prescribed fix, so the change would have arrived with a test moving
  in the right direction, which is the most persuasive possible cover for a wrong
  check site. Same family as *a guard that cannot fail prints PASS*: the signal
  fires, it just is not about what you think.
- **The dispatch form, and it is one line:** *the summary is a claim to verify;
  the fix section is a hypothesis to test against the oracle before implementing.*
- **Never relay a prescription as "the ticket says to do X."** Relaying strips
  the one cue a reader had -- that a person wrote it in advance -- and reissues it
  as an instruction from the system. Say "the ticket proposes X, untested."

**The cheap discharge, when an oracle exists:** the prescribed site is usually a
one-line question to put to FPC or gcc directly (`devdocs/dev/differential-probes.md`).
Ask it before you edit, not after your change fails to take -- the section above
is what "after" costs.

## A correct fix on an opportunistic path is inert, and nothing reports it

The runtime twin of every routing defect in this file, and the one that hides
best, because **the code is present, the tests pass, and the output stays wrong.**

`repair_regressions` was correct. It lived inside `bisect_step`, which is the last
arm of an elif chain of idle phases -- pin verify, breadth backfill, opt, bench,
then bisect -- so it ran only once every earlier phase had declined. Pin verify
alone was preempted by a push three times in one hour, and idle work on this box
has been starved for 40 hours at a stretch. **A correction to what the board
publishes was gated behind the busiest lock in the system.** A dry run found
three repairs that had never reached the published board, two of them written
hours earlier: 99 untestable commits still in one range, and a red still
attributed to a commit that could not have caused it.

The generalisation: **it is not enough for the right answer to exist and be
correct; it has to be on a path that runs when the answer is needed.**

- **The tell is a trigger that is a PHASE rather than an EVENT.** "Runs during
  idle", "runs after the queue drains", "runs on the next full pass" -- each
  inherits the availability of something unrelated to the thing it fixes.
- **Correctness tests cannot see this.** They call the function directly, so they
  answer *does it work*, never *does it run*. A guard that exercises the caller's
  scheduling is a different test and usually does not exist.
- **The honest status of such a fix is "fixed in the code, inert in this
  configuration"** -- not "fixed". Say it that way; a count of closed tickets that
  includes inert ones is worth less than a smaller honest count.
- **Make the repair idempotent and call it unconditionally.** It now runs every
  cycle before any phase decision, costing one `diff-tree` and one `rev-list` per
  *open* regression -- two -- against a cycle that otherwise spends minutes
  compiling. And `bisect_step` calls it too rather than assuming the loop did:
  **a repair that depends on its caller having been polite is not a repair.**
  Guard that a second pass is a no-op, or an always-saving repair dirties the
  tree every cycle and wedges the publish loop.

### Its worse sibling: a call site that DOES run, and does nothing

frankA, 2026-08-31. The section above is about a correct path that never
executes. This is a path that executes and has no effect, and it is worse for one
reason: **a dead guard is visible to anyone who reads the condition; a live no-op
is invisible to reading and only a control finds it.**

He disabled `PyFixIterableArgs` outright — `Result := False; if True then Exit;`
— and nothing anywhere changed. Including
`test/test_nilpy_user_iterable_in_builtins.npy`, **the test that exists to cover
it**, which emitted a byte-identical binary and the same 37 lines, still matching
CPython. The routine runs; nothing depends on what it returns.

Note what this is NOT evidence for. He found it while deleting a set of arms he
had already proved inert, and the honest reading is that it says nothing about
that deletion — it is a separate defect that the control happened to walk into.
Filed on its own rather than folded into the change that found it, with the
predicate to check named and an explicit instruction to **find an input that
makes the control fire before deleting anything.** A routine that is inert on
every input you tried is not the same as a routine that cannot matter.

**The cheap general probe, and it is the same one that turned two hook designs
into deletions:** before designing anything around a region, instrument the
ENCLOSING function's ENTRY and print the flag the region is guarded by.
`ParseStatementAST` gave **20603 entries on one canary, every one False, not one
True.** That count is its own positive control — a zero out of twenty thousand
is a measurement, where a zero out of zero is nothing — and it cost one build.

## A blocklist costs one outage per symptom; an allowlist closes the class

When plexus stopped being headless, every test job began inheriting a live
desktop session -- 24 variables, including `XDG_RUNTIME_DIR`, which is where
at-spi autolaunches its bus. `test_c_gtk_call.pas` then hung forever after
`gtk_init` and cost three days of native tiers their full hour.

The first repair set `NO_AT_BRIDGE` and `GTK_A11Y`. It worked, and it fixed
nothing: the next opportunistic client of a display, bus, keyring, portal or
notification daemon hangs identically and looks just as mysterious, because the
repo has not changed. **A blocklist buys one symptom at a time and leaves the
class intact.** The allowlist -- 11 keys plus the `PXX_`/`TESTMGR_`/`LC_`/`QEMU_`
families -- ends it.

**And it found something a blocklist never would have**: an unrelated third-party
API key from the login profile had been reaching ~3,000 job subprocesses per run
for days. Nobody was looking for it. That is the general argument for enumerating
what may pass rather than what may not -- you find out what was passing.

### The pass-through rule was backwards in the dangerous direction

The obvious reading of "plus whatever a job explicitly asks for" is *a job that
runs `xvfb-run` or `Xvfb` is a display job, so give it the session.* **That is
exactly wrong: those tools start a display of their own.** All three GTK jobs run
under `xvfb-run -a`, including the one whose at-spi hang started the ticket -- so
matching on the tool name would have re-admitted the session bus to the fix's own
motivating case. The rule triggers on a literal reference to a session
*variable* in the recipe text instead: a dependency the job states, not a guess
about what it probably does.

The generalisation: **an exemption keyed on what something appears to BE will
re-admit the case you built it for; key it on what the thing DECLARES.**

### Guard the mirror failure too

Stripping an environment creates the opposite defect -- a job losing something it
needs and going red with no cause in its log. Three things hold it off, and all
three are worth copying: the run **prints** what it dropped and which jobs kept
the session, into the same log as the verdicts it could change; a one-run
rollback exists and is **implemented, not merely documented**; and the guard pins
**both** directions, including that an `xvfb-run` job is *not* given the session
and a job naming `$DISPLAY` *is* and actually receives it.

## A silent assertion makes the harness report something else, confidently

The most expensive misread of 2026-08-26 traces to one shell idiom. A red job's
recorded `reason` was:

```
ok: $TMP [code=152328B ...] | ok: $TMP [code=65652B ...]
```

Two compile summaries with wildly different code sizes, which reads unmistakably
as a codegen divergence -- and was passed between two agents and put at the top
of a worker brief as "the strongest signal" before anyone checked. **They are the
aarch64 and x86-64 builds of the same source.** The job compiles for two targets
and then compares their *output*; the sizes were never supposed to match.

The mechanism is worth knowing because it will do this again. `job_reason` is the
**log tail**, by deliberate design. The recipe's actual assertion is a bare

```sh
test "$a" = "$b"
```

which prints **nothing** when it fails. So the tail is necessarily the two lines
*before* the assertion -- the last thing that did print, which was the two `ok:`
summaries. The harness reported them faithfully. Nothing was broken.

- **A silent assertion does not merely fail to explain itself. It causes a
  confident wrong explanation to be published in its place**, because a tail-based
  reporter always has something to show and no way to know it is unrelated.
- **Every failing check should print what it compared.** `test "$a" = "$b" ||
  { echo "outputs differ: ..."; exit 1; }` costs one line and removes an entire
  class of misdirection.
- **When a `reason` reads as a smoking gun, check whether the tool that produced
  it knows what the failure was.** A log tail does not. Read the recipe before
  reading meaning into its output.

A cross-target size difference in particular is the **null hypothesis, not
evidence**: two targets emit different amounts of code for the same source, and
that is the expected state of the world.

## A guard's human-readable note is triage evidence, so it must say what the guard DID

A devtest file flaked intermittently. The ticket fingered three cases; all three
were innocent, and they were innocent in a way that should have been visible:
they feed **frozen literals** to the predicate and measure nothing at all. The
real offender was a fourth case, **absent from the ticket entirely because it
passed** -- it called the timing probe three times against the real box and
asserted on the relationship between three ambient numbers.

What sent triage to the wrong three was a note in the *passing* output:
`Measured on the 12-core xeon`. That describes **where a constant came from**. It
was read as describing **what the case does at run time**. Meanwhile the one case
that genuinely measured the box said nothing about measuring. So the file
advertised the wrong suspects and concealed the real one, and every word of it
was true.

- **Anything a guard prints is read during triage, under time pressure, by
  someone who has not read the code.** Provenance and behaviour are different
  claims and must not share a phrasing.
- Say `FROZEN observations, fed in as literals` where a triager will see it, and
  say plainly when a case *does* touch the live environment.
- **An intermittent-flake ticket that cannot say WHY it is intermittent is
  usually pointing at the wrong line.** Here the explanation only appeared once
  the right case was found: the probe takes `min()` of three samples, so a
  momentary stall is absorbed -- the flake needs a load window spanning all three
  samples of the first call that has lifted by the second, i.e. a tier finishing
  mid-devtest. That is exactly the recorded observation (red during a full,
  green on immediate rerun) and exactly why it never reproduced on demand.
- **Supplying the timings made the assertions stronger, not weaker**: `r2 == 4.0`
  where observing had forced a loose `> 2.0`, and an exact reference where the
  old file could only bound it -- plus one it had never made at all, that a
  slower probe must not raise the reference. Determinism is not a weaker test; it
  is what lets you assert the thing you actually mean.

## A comment is an unverified claim, and tickets inherit it

Two N tickets in a row named the wrong mechanism, and the second one shows how a
wrong lead becomes durable. `PyImportIsConsumedOnly` carried a comment asserting
that `Counter` maps to *"pylib's TPyCounter constructors"*. It does not:
`TPyCounter` is the `itertools.count` shim, sharing four letters with `Counter`
and nothing else. The comment was wrong, the ticket quoted it as its "where to
look", and the investigation started up the wrong tree with a citation behind it.

The real binding was ordinary and discoverable in a minute: pylib has three
`function Counter` overloads returning a dict in counter mode, so `Counter("aab")`
compiles **with no import at all** and the from-import binds nothing.

- **A comment is documentation of an intent, not of a fact**, and unlike code it
  is never executed, so nothing ever contradicts it. It rots silently and in
  place.
- **A wrong comment is worse than none, because it launders into tickets.** Once
  quoted, it arrives with apparent provenance and the next reader has no signal
  that it was one person's belief.
- **Verify the lead before following it.** Find what a name is *actually* bound
  to -- read the binding site, or print it (`PXXDBG=n.locals`, `n.sig`) -- before
  theorising about why it misbehaves. That check is cheap and it is exactly the
  step the ticket's confident wording persuades you to skip.

The companion habit, from the same fix: **when you disprove a comment, correct
it in place, and grep for its copies.** That one had two.

## A CENSUS is a predicate, not a number — and the number is what gets relayed

Measured 2026-08-30, when a count of `-O3` gate sites was about to be adopted as
a checksum for "how much code sits behind the self-host blind spot". **Six counts
of the same population existed, spanning 13 to 45. Five were correct about what
they measured; the sixth was reached twice, by two people, from two different
wrong sets.**

| count | predicate | scope | |
| ---: | --- | --- | --- |
| **13** | literal `OptLevel < 3`, comments stripped | `compiler/**` | correct |
| **14** | literal `OptLevel < 3`, raw grep | `compiler/**` | the extra is *prose*: `inline_expand.inc:138` is a sentence **about** the gates |
| **32** | any spelling, comments stripped, **backend emitter files only** | 2 files | correct — this is `tools/check_o3_backend_parity.py`, and it is GREEN |
| **41** | any spelling, comments stripped | `compiler/**` | correct |
| **44** | any spelling, "comment-leading lines dropped" | `compiler/**` | **wrong — and produced TWICE, by two filters, from two different sets**; see below |
| **45** | any spelling, raw grep | `compiler/**` | correct |

The thing being counted never changed. What changed was **the spelling admitted**
(`if OptLevel < 3 then Exit` is the minority form — 14 of 45; the inline
`(OptLevel >= 3) and …` clause is far more common at 31), **whether prose counts
as code**, and **which files are in scope**.

**A fourth axis is WHITESPACE, and it produced a triple whose parts do not sum to
its own total.** `OptLevel >= 3` with single spaces occurs 29 times;
`OptLevel>=3` unspaced occurs 2 more. A verification run independently — by
someone who was *disagreeing carefully and checking before agreeing* — reported
`< 3` = 14, `>= 3` = 29, any form = 45. Those are three correct measurements and
**14 + 29 = 43**. The missing 2 are the unspaced spelling: the `>=` grep was
whitespace-**intolerant** while the `any form` regex was whitespace-**tolerant**,
in one message, three lines apart. The inconsistency sat in the middle of a
message whose whole purpose was to verify. Nobody noticed, including the person
who produced all three numbers, because each was right.

**That is a cleaner instance than either 44, and its author says so: there was no
filter bug to find — just two greps nobody had asked to agree.** Both 44s needed
a defect. This needed only two instruments answering slightly different questions
and never being put in the same sentence as a sum. **The only tell was arithmetic
nobody had a reason to do**, which is the cheapest check in this whole file and
the one no process asks for. When you report parts and a total, add them.

So: four axes, and a bare number carries none of them.

**There are TWO different 44s, and that is the instructive part.**

Two agents produced 44 from two different filters, over the same tree, and the
sets do not overlap:

| | dropped | kept | 44 = |
| --- | --- | --- | --- |
| theirs — drop lines starting `{`, `//`, or a **backtick** | 1 prose line (`inline_expand.inc:138`) | every gate, and **3** prose lines beginning with an ordinary word — `ir_codegen.inc:5030` *"only. Guarded by OptLevel>=3…"*, `ir_codegen_aarch64.inc:1324` *"is unaffected: at OptLevel >= 3…"*, `inline_expand.inc:364` | 41 + 3 |
| mine — drop lines starting `{`, `//`, or **`(`** | one **real gate** (`ir.inc:11086`) — `(` is not a comment in Pascal, it is the continuation of a multi-clause condition | all **4** prose lines | 41 − 1 + 4 |

Theirs is wrong by +3 in one direction. Mine is wrong in **both** directions and
lands on the same total by cancellation. Neither errored.

**And the part that belongs in this file more than the counting does: I
reproduced their 44, found a filter that produces 44, and concluded it was their
filter.** It was not. Same number, different set, different bug. A reproduction
that *agrees* is the most convincing shape a wrong diagnosis can take — there is
no discrepancy left to investigate, so the inference feels closed. It is the
section's own thesis landing on the section: **correct about something else.**
They caught it and sent the actual filter; I would not have looked again.

**The positive control that settled it, and it was free:** an independent
comment-stripper, run over the two backend files, must reproduce
`check_o3_backend_parity.py`'s own numbers. It does — 22 and 10, matching
`EXPECTED` exactly. That agreement is what licenses the 41 for the other five
files; without it the 41 would have been a seventh number with no more standing
than the 44.

**And the substantive answer the checksum was wanted for survives all of this:
41 gate sites exist, 32 are inside the parity tool's scope, and 9 are outside it**
— `symtab.inc` 3, `inline_expand.inc` 2, `ir.inc` 2, `emit.inc` 1,
`compiler.pas` 1. That is not a defect in the tool: its scope is CLAUDE.md's
per-backend rule ("x86-64 + aarch64 only") and those nine are not backend files.
**The tool is right about its question. The error would be borrowing its number
to answer a different one.**

**The fourth axis is TIME, and it is the one that makes a count unusable as a
checksum here.** At `d8ec3553a`, 24 hours earlier, the same two predicates gave
**11** and **36**; they are **13** and **45** now. At ~1900 commits/day a census
is stale within hours of being taken, so a relayed number is a claim about a tree
nobody still has. `check_o3_backend_parity.py` is the right shape for exactly
this reason: it does not relay a number, it **re-derives** it and fails when it
moves.

### The same error one level up: pricing a NAME by its position in an ordering

Recorded the same night, by the same person, about a different artifact — which
is what makes it a class rather than an anecdote.

Asked for a cross-target verdict, they offered to downgrade the request from
`full` to `limited` as *"a fraction of the question for a fraction of the cost"*.
It is **0%** of the question: `limited` is by construction the **no-qemu** tier
(`TIERS` in `tools/testmgr.py` — *"the cross variants stay in full"*, and
`test-float-determinism` is excluded **specifically** to keep a qemu-less box able
to run it). There is no cross in `limited` to break. Their own diagnosis:

> I was pricing a tier by its position in an ordering rather than by what it
> contains — the same error as reading a count without its command.

**quick < native < limited < full looks like a volume knob and is not.** The
tiers differ in *contents*, and the contents are not nested along the axis you
care about. Same shape as the `-O` levels, where CLAUDE.md already has to say it
out loud: **trade-offs are NOT a level** — `-Ofast`, `-Os`, `-funroll-loops` are
*sideways*, not "more than `-O3`", and an author chooses **which** trade, never
**how much**. A name that sorts is the most confident-feeling proxy there is,
because sorting feels like knowing.

**And the economics inverted once the contents were read.** The sampler already
had three native runs at descendants of the target, so the native half was
answered and `full`'s entire marginal value was the cross matrix — making `full`
the **cheap** option per question answered. The downgrade would have paid for the
half already free and skipped the half being asked about. **Ask what a tier
contains before pricing it, not where it sits.**

**The rule, and the coordinator sharpened it in retracting the version built on
the bad count: the unit is the COMMAND, not the predicate.** A predicate stated
in words does not pin the number — the two 44s above share a predicate ("any
spelling, comments stripped") word for word and differ by an entire gate, because
they differ in *implementation*. So: never relay a census as a number, and do not
settle for relaying the predicate either. **Relay the command, or relay a check
that re-derives it.** If you are given a number, ask what command produced it
before asking whether it is right — and expect the answer to change it by a
factor of three.

### A BUILD FAILURE is a census that stops counting at the first fatal error

frankA, 2026-08-31, on `feature-a-build-a-reduced-compiler`. The question was how
many NilPy symbols the Pascal-only compiler still depends on. The instrument was
`fpc -dPXX_NO_NILPY`, read as *"the errors are the list"*. It answered **7**.
The true answer was **279**.

Seven is not an absurd number — it is exactly the shape the six esoteric
frontends have, so it read as a small, finished job. And the instrument had not
malfunctioned: `pyforwards.inc` was still supplying ~190 forward declarations, so
FPC resolved each name against a forward and deferred the complaint to the
end-of-module pass — which the fatal error meant it never reached. **7 was the
count of symbols with no DECLARATION. The question was symbols with no BODY.**

Two things generalise, and the second is the sharper one:

- **A compiler used as a census counts only what its FRONT passes reject.** A
  forward declaration, a weak symbol, a `{$ifdef}`-supplied stub — anything that
  satisfies the early pass — is invisible, and the answer comes back small and
  confident rather than empty.
- **A fatal error truncates exactly the pass that would have reported the rest.**
  This is worse than a partial count, because the truncation point is chosen by
  the very defect you are measuring: the more broken the build, the earlier it
  stops, so the count falls as the problem grows.

**What caught it was an implausibility test registered BEFORE the run** — the
ticket said the population was 176 symbols, and 176 -> 7 fails on sight. Nothing
in the output was wrong; there was no discrepancy to notice. A number you have
pre-committed to disbelieving is the only guard that fires when the instrument
answers cleanly, which is this whole section's failure mode.

## A STANDING-RULES block is skipped by whoever has landed the most slices

Measured 2026-08-30, and proposed by the agent it happened to — who was wary of
proposing a rule whose evidence is that he broke the existing one. It is worth a
paragraph precisely because of that, so here is the paragraph.

`feature-opt-o3-register-pressure.md` opens with **`READ FIRST — four standing
rules for every slice in this campaign`**, and says why they are there:

> Each of these was paid for once. They are here, at the top, rather than inside
> the write-up of the slice that learned them, because that is where the next
> slice will actually read them.

That is correct ticket design and it worked for four slices. On the fifth it was
skipped, and rule 1 was then **re-derived from scratch** — by deliberately
breaking an encoder, observing the green fixedpoint, and reporting it as a
finding — by the agent landing slices into that very ticket.

**The failure mode is not "buried", "stale", or "hard to find". All three are
false here:** the block is at line 66 of the file, it is headed `READ FIRST`, its
rules are true, and the reader had the file open. **It was skipped because he
already knew the campaign** — and *having landed the most slices* is exactly what
produces that confidence. So the block decays fastest against its most
experienced reader, which is the opposite of how documentation is usually assumed
to fail, and it means seniority in a campaign is a **risk factor** for re-deriving
its own standing rules rather than a protection against it.

Two things follow, and neither is "write it more prominently" — there is no more
prominent than line 66 under `READ FIRST`:

- **Re-read the standing block at CLAIM time, not at read time.** Same guard
  CLAUDE.md already gives for a ticket's `summary`, and for the same reason: the
  agent most likely to append to a long ticket without reading it is the one
  under the most pressure to produce something, and that is whoever is mid-slice.
- **When a "finding" is about the campaign's own machinery rather than about the
  code, grep the ticket for it before writing it up.** A rule that was paid for
  once tends to have been written down once. The cost here was small — an
  experiment that was going to be run anyway — but the write-up travelled to
  three agents and a coordinator before the citation caught up with it, which is
  where a re-derivation actually gets expensive.

## "The compiler couldn't compile X" and "the language can't do X" look identical from inside `compiler/**`

A new backend file needed to write a text file. It used the idiomatic form —
`var f: Text` with `Assign` / `Rewrite` / `Writeln` / `Close` — and the
self-host build failed:

```
pascal26:166: error: undefined variable (Close)
  in: compiler/asmtext_wasm.inc
```

That reads as an RTL gap, and the obvious next move is a ticket against the RTL
for a missing `Close`. **The RTL is fine.** Three steps settle it, and they take
about ten seconds:

- A standalone pxx program does `Assign` / `Rewrite` / `Writeln` / `Close` and
  writes its file. **This is the disproof, and it is the step people skip.**
- The implicit textfile surface is pulled in by a token pre-scan at
  `pasparser_prog.inc:651` — but only `if (not NoDefaultRtl)`.
- `compiler.pas:19` is `{$define PXX_NODEFAULTRTL}`.

The compiler deliberately opts out of the default RTL surface. `Close` is absent
**by design**, and the error is the compiler handing back exactly what it asked
for. Nothing at the failure site points at any of that: the define is one line
near the top of a 2000-line program, and the gate that consumes it lives in a
different file from the error.

- **Inside a compiler-internal file you are not compiling in the language's
  ordinary environment**, and an "undefined" diagnostic cannot tell you which of
  the two you hit. It reports absence at the *use* site; the cause is a define at
  the top of the translation unit.
- **Compile the same construct standalone before filing anything.** Works there,
  fails here → the absence is a property of the translation unit and there is no
  language or RTL bug to file. Fails in both → now you have something.
- **Getting this wrong files a bug that does not exist**, against a component
  that works, with a real error message as its evidence. That is the durable kind
  of wrong: nothing about it looks like a guess.

**And it decides which form is platonic**, which matters under the
do-not-revert-platonic-patches rule, where direction is the whole rule. If the
idiomatic form is blocked by a defect, it is platonic and stays, with a
`blocked-by:`. If it is blocked because this translation unit excludes the
surface it needs, it was never the platonic form *here* — the house form is
(`sysopen`/`syswrite`: 18 sites in `compiler/**`, zero declare a `Text`), and the
idiomatic form remains right on the other side of that boundary. Both are correct
in their own translation unit, neither is a workaround for the other, and nothing
is owed a revert.

Companion habit: **when you resolve one of these, write the chain into the file,
not just the conclusion.** The conclusion alone gets re-litigated by the next
person who hits the same error message, and their most likely move is the RTL
ticket that should not exist.

## "The pinned binary reproduces it" may be a claim about a MIXED compiler

A ticket recorded that `$(PXX_STABLE)` reproduced a segfault, which made a
brand-new feature's own hole read as a pre-existing bug and sent the next agent
looking in the wrong century of the history. It was measured honestly and it was
wrong.

**A stable binary run from a directory with no `builtin/` beside it falls back to
the CWD-relative `compiler/builtin/` -- that is, to the WORKING TREE.** So a
"pinned" run launched from the repo root is the pinned executable driving
whatever builtins are checked out right now, uncommitted work included. That is
not the pinned compiler; it is a hybrid that exists on nobody's machine but
yours, and it can fail in ways neither endpoint does.

The rule this file already states -- *any result you report must name the sha of
the binary it came from* -- is necessary and, here, not sufficient. The binary's
identity was known. Its **builtin tree's** identity was not, and nothing in the
invocation made the difference visible. So:

- Run a pinned binary **from beside its own frozen `builtin/`**, or verify which
  tree it actually resolved before believing the result.
- When an endpoint measurement says "broken at both ends", suspect the harness
  before concluding "latent since forever". Two greens and a red in the middle is
  a shape a mixed compiler produces easily.
- A provenance line in a ticket is evidence like any other, and it decays. The
  agent that closed this one re-measured instead of inheriting, found v374 and
  v375 both green, and turned "latent, unbounded" into "fixed two commits after
  it was filed".

Same family as `code : STALE` in the watcher and the frozen-builtin seam
`gate.sh` now guards: **the artifact you are measuring is assembled from more
parts than the one you named.**

## "Ruled out" and "could not look" must never print the same

The sharpest version of this file's refrain, and it cost six days. A ticket
recorded: *the kernel log is unreadable unprivileged, so OOM can be neither
confirmed nor excluded.* That sentence made **ruled out** and **not looked at**
indistinguishable -- and a hypothesis nobody can check is the one an
investigation drifts toward, because nothing ever pushes back on it.

It was also false. `dmesg` is blocked here (`kernel.dmesg_restrict=1`), but
**`journalctl -k` is not, for anyone in group `adm`, and this account is.**
Everyone who hit the wall hit it with `dmesg` and stopped. The real answer took
minutes: **0 kernel OOM kills across three boots**, 35,486 kernel lines, journal
reaching back far enough to cover the date in question.

Three things to carry:

- **One blocked tool is not a blocked question.** Before writing "cannot be
  determined", find the second reader. Privilege here is per-interface, not per-
  fact: `dmesg` restricted, `journalctl -k` open to `adm`.
- **Check the mechanism that logs somewhere else.** `systemd-oomd` kills on cgroup
  PSI *before* the kernel is out of memory, logs to its own unit rather than the
  kernel log, and targets the heaviest cgroup -- here, a fuzz batch or the test
  matrix. A kernel-only answer would have read as an all-clear with the actual
  candidate unexamined. (It had killed nothing, ever.)
- **State exactly how far the exclusion reaches.** Kernel OOM and oomd both leave
  a durable record; a peer's `SIGKILL` leaves none. So excluding them is not
  "nothing killed it" -- it is *every hypothesis that would have left evidence
  did not happen*, which leaves the one that never does. That is a real narrowing
  and it is the most the evidence supports.

**And the most dangerous: a corrupted input arriving dressed as a finding.** A
differential probe used fixed paths -- `/tmp/fdp.pas`, `/tmp/fdp_f`, `/tmp/fdp_p`
-- so two concurrent copies overwrote each other's source and binaries. The
result was not a crash. It was a **report**: `new divergences: 34`, `no-oracle
skips: 90`, rows reading `fpc=[]`. An oracle whose binary had been overwritten
mid-run presented as an oracle that *disagreed*. This is worse than a torn-down
run publishing in the vocabulary of a completed one, because the tool's entire
job is to be believed about findings, and the corruption is indistinguishable
from its output. **A tool that reports divergences must isolate its workspace
(`mktemp -d` + trap), or its worst failure looks exactly like its best work.**

**The most literal instance: a diff against a missing operand.** The bench
harness emits `CANARY-DIFF vs -O0` for each optimisation level -- and when the
`-O0` build itself fails, `ref_out` stays `None`, so every other level dutifully
reports a difference from a baseline that was never produced. Three red rows, one
defect, and nothing in the output separates *the levels disagree* from *there was
nothing to compare against*. Any comparison must state that its reference exists
before reporting a difference from it.

The design counterpart is now in `tools/whokilled.sh`: **three verdicts, and any
blind probe forces a distinct exit code**, so a caller cannot mistake blindness
for clean. Its CANNOT-TELL branches had never executed on this box, so the
devtest drives them with fakes on PATH -- a branch that has never run is not yet
known to work.

## A caveat attached to a claim is not the same as declining to make the claim

The sharpest self-correction of 2026-08-26, and it came from someone who had
already written the caveat that would have saved them:

> *"105 logs is a partial view, so tell me if the clean result does not hold at
> the end."*

They wrote that, and then reported the hazard **absent** anyway — twice,
confidently. The signature appeared at log 684. The caveat was true, was
attached, and did no work at all, because **a hedge does not change what the
reader does with the claim.** Everyone downstream acted on "absent"; nobody acted
on "of 105".

The rule: **if the caveat is load-bearing, the claim is not ready.** Report the
observation (*"clean through 105 of ~3000"*) rather than the conclusion
(*"the hazard is absent"*), and let the conclusion wait for the evidence that
would justify it. This is the same failure as stopping a search at the point
where the evidence agrees with you — the caveat is what you write instead of
continuing to look.

Its twin, from the same day: **when a fix works, count how many things you
changed.** A gate went RED from a `/tmp` worktree; the worktree moved and the
seed mtime changed in the same window; the RED went away; one story fit, so
nobody looked for the second variable. Both errors are the same shape — stopping
at the first sufficient explanation — and neither is caught by any test.

## A suite that never sets the flag is blind to what the flag guards

A green suite is evidence about the code the suite *reached*. For anything behind
a gate, the gate is what decides whether it was reached — so the same property
that makes a feature safe to land makes the suite unable to say anything about it.

The instance, 2026-08-26: four `-O3` optimisation passes, and the question was
whether to promote them to `-O2`. The tempting evidence was a full-tier verdict at
the sha that contained them. But **almost nothing in the tier compiles at `-O3`**
— the NilPy recipes are `./$(COMPILER) test/x.npy out`, no `-O` flag at all — so a
full-tier GREEN would have proven mainly that *the gate kept the passes out of the
default path*. That is a fact about the gate, not about the passes, and reading it
as "they are safe to promote" inverts what it shows.

**The same reasoning tells you which evidence does bear on it:** the two-oracle
differential run across all four `-O` levels, and `test-selfcompile-odiff`, which
actually varies the flag. Ask *what in this suite sets the flag* before treating
its verdict as coverage.

**The corollary that catches bugs rather than just weak evidence:** if a change
carries a gated half and an ungated half, the tier can only see the ungated half —
so when a gated-feature window produces a regression, the ungated half is the
first suspect, however small it looked in the commit message. A commit whose
subject was `-O3 cmp-immediate` also carried an ansistring runtime blob change
that no gate guarded, and that half is the only part of the work the suite could
observe.

The general form: **a flag makes a feature invisible in exactly the tier you
would use to judge it.** Coverage is not "did the suite pass", it is "did the
suite execute this path", and a gate is a machine for guaranteeing it did not.

## Record the negative result, or someone will spend a night rediscovering it

Track T profiled the test matrix and reported three findings, one of which was
that **the scheduler is fine** -- 90% core utilisation, ~1,343 idle core-seconds
out of 13,663, near the floor for a job graph with dependencies. Nothing to
unpick. They wrote it down deliberately, in the owning ticket, in the same
prominence as the positive findings: *"I would rather cost myself the finding
than have the next person spend a night discovering it."*

That instinct is right and it is rare, because a negative result feels like an
absence of work. It is not. "The obvious suspect is innocent" is expensive to
establish and free to forget, and it is the single most re-derived kind of fact
in a long-running project -- the scheduler, the allocator, the disk, whichever
component *looks* like it should be the problem will be re-measured by every new
arrival until someone writes down that it was not.

So: when a measurement clears a suspect, **say so in the ticket, name the number,
and say plainly that nobody should start there.** The same applies to a plausible
fix you tried that did not help. An unrecorded dead end is a trap that resets
itself.

**And record the option you measured and DECLINED, with its number.** Track T
priced a skip cache for pin-built jobs -- provably unchanged verdicts, genuine
repeated work, the predicate already written -- at **~3% of the matrix**, and
turned it down. The reason is the one worth copying: its failure mode is *a job
that should have run and did not, reported as a pass*, which is the exact defect
class removed five times in two days (the unenrolled rung asserting nothing, the
torn-down run silencing the request for coverage, unreached jobs reading as
FIXED). **Adding a sixth source of silent under-coverage to save 3% is a bad
trade at any exchange rate** -- and the fact that the mechanism would have been
easy to build is not a point in its favour.

The general form: **price a saving in what it costs you in assurance, not only in
what it costs to build.** A cache, a skip, a memo and an early-exit are all the
same bet -- that a thing you did not check is unchanged -- and the bet is only as
good as the predicate, forever, including after someone edits the predicate. In
the ticket it now sits as *declined, with the number and the reason*, plus the
condition that would reopen it: if the NilPy tax is fixed, 3% becomes a large
share of what remains and the trade is worth re-pricing.

That is the difference between a decision and an oversight, and only the write-up
tells them apart later.

The companion rule, also demonstrated: **do not extrapolate across a moved
denominator.** They declined to state a post-fix matrix total until the next full
lands, because the compiler's own cost had changed underneath the measurement.
Multiplying two estimates is how a number stops being a measurement.

## A number moving in the direction you hoped is not a check

Track T narrowed a blame range from 137 commits to 2, ran it against the live
regression, saw the reduction, and read that as confirmation. It was evidence of
the bug. The cut had been derived from "a pin-built job builds with the pinned
binary, so only pin moves can change its verdict" -- but `make pin` freezes only
`compiler/builtin/**` and **deliberately leaves `lib/rtl` and `lib/pcl` live**
(the Makefile says so: Track B expects its lane editable), and the job compiles
from the live `test/` tree. A pin-built job is blind to `compiler/**`, not to
everything except the pin. Those 137 commits held **2 `lib/` and 34 `test/`**
commits, every one a genuine candidate, and the cut discarded all of them. The
corrected number is **137 -> 37**.

Two lessons, and the second is the transferable one.

**Too narrow is the direction that costs you.** A too-wide range costs bisect
steps; a too-narrow one can exclude the culprit, and then the bisect terminates
cleanly, prints a sha, and is indistinguishable from a correct answer. So when a
range shrinks, the question is never "by how much" but "what did it drop, and
could any of it have caused this?" **A commit whose file list cannot be read is
KEPT.** Never narrow blindly.

**The measurement confirmed what it was pointed at, which was the wrong
question.** It answered *did the range shrink* when the question was *did it drop
anything causal*. This is the sharpest instance in this file of a check that
runs, passes, and asserts nothing about the thing at issue -- and it is more
dangerous than an absent check, because it discharges the urge to look. A result
that agrees with your hypothesis is the moment to ask what else would have
produced that same result.

The catch, both times it has happened: **writing the assertion forced an
enumeration where the reasoning had been gesturing.** Asking "what must a
pin-built job be able to see?" as a guard, rather than as a sentence, put `lib/`
in the list immediately. The guard has now caught two defects the reasoning
missed, both by demanding names instead of a wave.

## Assert the INVARIANT, not the current numbers -- and expect it to catch you

Two things happened within an hour on 2026-08-26 that belong together.

**A guard whose first catch is its own author is working.** Track T measured
which test tiers contain pin-built jobs (quick 0, native 0, limited 0, full 191)
so that pins could be scheduled around them, then wrote a devtest asserting it
so the answer could not silently go stale. One hour later, enrolling
`test-fpjson` into `limited` turned that devtest RED, naming the breach exactly:
*"limited now has 1 pin-built job(s) -- a pin taken during one of these runs can
no longer be called safe."* The author broke their own invariant, and the guard
said so before anyone planned a pin around a claim that had stopped being true.

And the author's own account of why it caught them is the part to copy into the
next guard you write: **it asserted the CONSEQUENCE, not the number.** The
message was "a pin taken during one of these runs can no longer be called safe",
not "expected 0 pin-built jobs, got 1". Their words: *"the number would have
been just as red and I might well have edited it."* A count mismatch invites you
to update the count -- it reads as a stale expectation, which is usually what a
red count is. A sentence naming what breaks tells you which side is wrong, and
makes editing the guard visibly the wrong move. Assert the property somebody
downstream depends on, in the words they would use.

The resolution is the part to copy: **the invariant won, not the coverage.**
`test-fpjson` became full-only rather than the guard being relaxed. "quick,
native and limited are pin-free" is a property other people schedule around, and
a property with an exception is not a property. `full` cycles ~40 minutes, so
nothing was really lost.

**Sufficient is not necessary -- do not assert equality where you mean subset.**
The same guard also asserted that `full`'s pin-built target set EQUALS
`PIN_BUILT_TARGETS`. Wrong direction. Membership in that list is *sufficient*
(it rescues a shell-out recipe like `make demos`, where the pinned path lives one
level down in the Makefile and the recipe body never names it) and never
*necessary* -- a recipe naming the pinned path directly is pin-built whatever its
target is called, which is exactly what `test-fpjson` was before it was listed.
Equality did not encode the rule; it froze an accident of which targets happened
to be enrolled that day. It is a subset check now.

Both are the shape this file keeps returning to: **the system held the right
answer internally and published something that could not express it.** An
equality assertion cannot express "at least these"; a tier count with an
exception cannot express "pin-free".

## The design counterpart: choose an ILLEGAL sentinel, never a plausible one

Everything above is about finding a plausible wrong value after it has travelled.
This is how to stop one being created in the first place, and it is a *design*
rule rather than a debugging one — it is decided when you pick the encoding, and
it is unfixable afterwards.

**The cost of a sentinel is paid entirely at the moment it is wrong.** A
*plausible* marker — 0, empty string, `None` — is indistinguishable from a
legitimate value, so the failure travels arbitrarily far from its cause and
arrives as this file's opening sentence. An *illegal* one collapses that
distance to zero.

Worked example, `PYSIG_DFLT_UNSET` in `compiler/defs.inc`. A NilPy signature
record holds one variant per defaulted parameter, and an unfilled slot needed a
marker. Zero was the obvious choice and would have been wrong: `VT_EMPTY` **is**
`0` and `VT_EMPTY` **is** `None`, so an unfilled slot would have answered `None`
— which is a perfectly ordinary default (`def f(x, lo=None)`). The marker is
`-1`, an illegal variant tag, precisely so "never filled in" cannot be mistaken
for a value.

### The half that makes it more than a convenience

When the slot was later reached, it did not merely fail early — **it detected a
bug nobody was hunting.** The raised error named the parameter, one `PXXDBG`
probe followed, and the cause turned out to be two unrelated parameters in
unrelated defs (`r.s` and `outer.inner.b`) reporting the *same symbol index*,
because a rolled-back trial parse frees an index and a later def's parameter
gets it. That symbol-recycling defect was independent of the feature being
built; a silent `None` would have hidden it along with the first fault, and it
would have surfaced months later in a corpus as a wrong value.

So the argument is not "a loud sentinel is easier to debug". It is:

> **A loud failure is a detector for defects you were not looking for.**

That is what to say when someone proposes a convenient zero. Applies equally to
variant tags, index fields, capacity counts, and any "not set yet" state whose
type has a natural-looking neutral value.

### And a companion trap from the same episode

**Verifying one arity and generalising.** The same callable-value work was
checked against a four-parameter callee and pronounced correct; a two-parameter
one was silently wrong (`map` answered `[1,2,3]` where CPython says `[2,3,4]`).
Boundaries are where these live — check the smallest and the largest case, not a
comfortable middle.

## Reaching for the instrument is necessary and not sufficient — the FORMATTER is part of its aperture

The section above is about choosing a sentinel the *program* cannot mistake for
a value. This is its mirror: an illegal sentinel, chosen correctly, destroyed on
the way to your eyes by the thing that printed it.

Measured 2026-08-30, hunting `bug-c-a-header-reached-by-uses-discards-function-
bodies-and-imports-them-instead`. The question was what `CModuleOfTok` returns
for a token in a `uses`d header, where **-1 means "no C module"** — a properly
illegal sentinel, exactly as the section above prescribes. The probe printed it
with `IncSmallIntStr`, whose own doc comment says *"decimal text of a small
**non-negative** int"* and whose first line is `if n <= 0 then Result := '0'`.

So the probe printed `module=0`. Which is a module id. The one value that meant
*"no module"* was rendered as a real answer, the output looked entirely
reasonable, and the conclusion drawn from it was wrong. `differential-probes.md`
already carries this warning — *a probe that FORMATS its output can answer a
different question than you asked* — and it had been read the same night, in
this repo, by the person who then walked into it.

**The sequence is the lesson, because each step was closer to measurement than
the last and each still produced a plausible wrong answer:**

1. **Reasoned about the function instead of printing it.** This file's headline
   failure, committed by someone who had read this file.
2. **Printed it — through a formatter that could not represent the answer.**
   The instrument was right, the aperture was not.
3. **Measured a harness artefact and read it as the bug.** The test program and
   the test header shared a stem, so `uses foo` resolved to `foo.pas`, the
   program itself. The compiler reported a real and correct error about *that*,
   and it was read as the defect under investigation — which is the most
   expensive of the three, because everything about it looks like signal.

Only the fourth attempt — distinct names, and a formatter with a branch for the
negative case — produced the boundary table the ticket now carries.

**What to actually do**, in rough order of cost:

- **Print the sentinel's own spelling, not its number.** `module=NEG` /
  `module=none` cannot be confused with an id. Branch on the sentinel in the
  probe rather than trusting the renderer.
- **Read the helper you reached for.** `IncSmallIntStr` says non-negative in its
  first comment line and clamps in its first statement; thirty seconds of
  reading beats a rebuild and a wrong conclusion. Its siblings
  (`CPSmallIntStr`, `AsmIntToStr`, `RIntToStr`) do not all agree on this, so
  which one is in scope changes the answer.
- **Sanity-check the probe against a case whose answer you already know.** Here
  a header with no includes at all was known to work; had its probe line said
  `module=0` while the failing one also said `module=<some id>`, the collision
  would have been visible immediately.
- **Give the harness distinct names.** A test program and its test header
  sharing a stem is not an exotic mistake — it is what you get from naming both
  after what they test.

The general form, which is what makes this more than one bad night:

> **An instrument narrows what you can be wrong about; it does not eliminate it.
> Everything between the value and your eyes — the accessor, the formatter, the
> harness, the file names — is part of the instrument, and any of it can quietly
> answer a different question.**

## A background job's reported exit code is the LAST command's, not the job's

Measured 2026-08-30, six times into a night of the same class.

I launch gates as:

```sh
tools/gate.sh quick > gateq8.log 2>&1; tail -12 gateq8.log
```

so that the log is visible when the job returns. The `;` makes **`tail`** the
last command in the list, so the shell's exit status is `tail`'s — always 0 —
and the completion notification read:

> `Background command "Gate slice 2a" completed (exit code 0)`

for a gate whose own last line was `gate: RED (exit 1)`.

**A green light reporting on a red run, produced entirely by the shape of my own
invocation.** Nothing was wrong with the gate, the log, or the notification —
each reported correctly on what it was actually given. Had I trusted the
notification instead of reading the log, I would have committed on a red gate
and had a green summary line to point at.

**The fix**, and prefer the first:

```sh
tools/gate.sh quick > gateq.log 2>&1              # exit code is the gate's
tools/gate.sh quick > gateq.log 2>&1; rc=$?; tail -12 gateq.log; exit $rc
```

**The rule.** In a `;`-list the status belongs to the last command, and a
convenience appended for readability is a command. Pipelines have the same shape
(`cmd | tee log` reports `tee`); so does `cmd && echo done` in the other
direction. **Anything appended after the thing you are measuring becomes the
thing that reports.**

This is the same family as the formatter section above and the stdout-capture
one: the instrument was fine and the *plumbing around it* answered a different
question. It belongs with them because the tell is identical — a result that
looks clean, arrived at through a layer nobody was examining.

## `perf` being blocked is not "no profiler" — build the compiler with FPC and `-pg`

`perf` is refused on plexus (`kernel.perf_event_paranoid = 4`) and cannot be
lowered without root. A session concluded from that there was no way to profile
the compiler, recorded *"there is no pathological function to optimise"* on the
strength of a linearity argument instead, and was wrong: the next session's
profile found **four** hotspots and cut the measured cost in half
(`bug-a-every-nilpy-compile-pays-a-fixed-nine-second-cost`).

`compiler.pas` is FPC-bootstrappable by construction. FPC supports `-pg`.
`gprof` is installed. Eleven seconds:

```sh
fpc -O2 -Tlinux -Px86_64 -pg -FU/tmp/units -o/tmp/pascal26-pg compiler/compiler.pas
/tmp/pascal26-pg /tmp/repro.npy /tmp/o        # writes gmon.out into $PWD
gprof -b -p /tmp/pascal26-pg gmon.out         # flat profile WITH CALL COUNTS
gprof -b -q /tmp/pascal26-pg gmon.out         # call graph: who called whom, how often
```

(`-FU` a scratch unit dir, or a `-pg` `.o` will collide with a later non-`-pg`
build and fail at link with `undefined reference to mcount`. Run the compiler
from the repo root — it resolves `pylib`/`builtin` relative to the working
directory.)

**Read the CALL COUNTS, not the percentages.** The `-pg` binary is FPC's
codegen, FPC's ansistrings and FPC's heap manager, so its time shares are
*indicative* of ours and no more — measured on the same workload, the FPC-built
compiler runs 3.8x faster than our own build of the same source. But the counts
are properties of the SOURCE and are exactly ours. "284,481 calls issuing
20,058,632 AppendChar" is not a judgement call, and it is what named the
function. Confirm every fix on the real self-hosted binary before believing it.

**Linear throughput is not evidence against a hotspot.** The wrong conclusion
above came from a good measurement read badly: compile time tracked emitted code
volume at a near-constant ~4 s/MB across a 150x range, which rules out a
*superlinear* blowup and nothing else. A function costing a fixed 3 microseconds
per emitted instruction plots as a perfectly straight line and is still 30% of
the compile.

## Profile the SHIPPING binary — `-g` alone silently means `-O0`

The section above gets you call counts. When you want *shares* — where the time
actually goes — the trap is one line of `compiler.pas`:

```
compiler.pas:739    OptLevel := 2;        { the default }
compiler.pas:1536   if DebugInfo and not OptLevelExplicit then OptLevel := 0;
```

So **`make pxx-debug` builds a `-O0` compiler.** For gdb that is the point (1:1
codegen keeps breakpoints on the lines you set them on). For a profile it is a
different program from the one everyone runs, and *nothing in the output says
so* — you get a plausible, well-shaped, confidently wrong weighting.

Build the real one explicitly, and check you got it:

```sh
./compiler/pascal26 -O2 -g compiler/compiler.pas /tmp/p26-g-O2
# its code=NNNN must match the plain default build's code=NNNN.
# If it does not, -g changed the codegen and the profile is of something else.
```

Measured 2026-08-26 on the same zero-byte `.npy`: the `-O0` build put 53.5% of
in-`.text` samples in the builtin runtime blob range, the real `-O2` build 48.1%,
and the parser's share moved with it. The *ranking* happened to survive; the
numbers did not, and there is no way to tell which you are holding from the
report alone. **Record the `-O` level of the profiled binary the way you already
record its sha.**

### `tools/pxxprof` — when `perf` AND gdb-attach are both refused

`perf_event_paranoid = 4` blocks `perf`; yama `ptrace_scope = 1` blocks
attaching to a non-descendant. `tools/pxxprof` forks the target and
`PTRACE_SEIZE`s its own child, so it needs neither:

```sh
cc -O2 -o /tmp/pxxprof tools/pxxprof.c
/tmp/pxxprof /tmp/samples.txt 150 /tmp/p26-g-O2 /tmp/repro.npy /tmp/o
python3 tools/pxxprof_symbolize.py /tmp/syms.txt /tmp/samples.txt | head -30
```

Two things it will not tell you, both of which have to be read around:

- **The `<outside .text / vdso>` bucket is not time.** Its own header warns the
  share swings 8-38%; measured, it was **70% in one run and 0.9% in the next of
  the same binary**, with the address moving under ASLR
  (`75522eaa642c` -> `73d5a58a642c`). Cross-check against `/usr/bin/time`: if
  `user` is within a few percent of `wall`, the process is pure user CPU and the
  bucket is sampling noise. **Exclude it and renormalise on in-`.text` samples**
  — every percentage that includes it is deflated by an amount that changes per
  run.
- **The builtin runtime carries no DWARF**, so `PXXAlloc`, `PXXFree` and the
  hand-emitted retain/release blobs all fall into the FIRST symbol's range and
  show up under the *file* name. When that range is hot — it was 48% — read it
  by histogramming the raw addresses and disassembling around the hot ones, not
  by trusting the label. That is how three `idiv`s by the literal 8 turned out
  to be 11.4% of the whole compile.

**It did not compile as committed** (`open()` with no `<fcntl.h>`; fixed in
`1202429f4`). Worth naming because of what it cost rather than what it was: a
profiler that does not build is a profiler nobody reaches for, and the published
figure it was committed with — 56% in the first 5 KB of `.text` — is closer to
what the `-O0` debug build gives than the `-O2` one. **A tool that fails to
build fails silently in the worst possible way: as an absence of measurements,
which reads exactly like an absence of anything to measure.** Build it before
you trust a number attributed to it.

## Only binaries timed inside ONE interleaved run are comparable — and a pass changed to fix a measurement is as sound as the measurement

The `-O3` residency slice (2026-08-28) measured mandelbrot at **1.10 s** before
a change and **1.18-1.24 s** after it: a clean 7% regression, min of 5, same
command, same box. The obvious reading was that the change had a cost, so a
per-class fix was built to remove it, and — this is the part worth recording —
**the causal explanation was written into `ir_codegen.inc` as a comment stating
it as fact**, complete with the two numbers.

Re-measuring all three binaries *inside a single interleaved run* gave
**1.34 / 1.33 / 1.34**. The same "before" binary that had measured 1.09 now
measured 1.34. There was no regression, there had never been one, and the fix
was a fix for the box's load.

Why the usual precaution did not save it: `%U` user time, A/B alternating,
**min of 5** is the discipline this repo already uses, and it is not enough
here. plexus runs Track T's watcher and several agents; load swung between 4
and 13 during that session. Min-of-N removes noise *within* a run and removes
nothing at all *between* runs, so two numbers taken ten minutes apart are two
measurements of the machine, with the binary as a minor term.

- **Time every variant you intend to compare inside one loop**, alternating, in
  the same process invocation window — `for k in 1..N; do for v in old new t3;
  do time ./$v; done; done`, then take each one's minimum. Three variants in
  one run is comparable; the same three run one after another as separate
  commands is not.
- **A delta measured across runs is not evidence for a cause.** It is not
  evidence for an effect either. The interleaved re-run comes *before* the fix,
  never after it.
- When you do revert an experiment, **verify the revert by rebuilding and
  comparing the binary sha to the pre-experiment one.** Bit-identical is proof
  the tree is back where it was; "I undid the edits" is not.

The general shape, which is why this sits next to the bisect entry above: a
change made to fix a measurement inherits every weakness of that measurement,
and a *comment* asserting the cause outlives the measurement entirely. The
comment would have been read for years as a finding. It was a load average.

**Interleaving alone is not enough, and the same slice proved that too.** Having
adopted the rule above, the same session then reported a "~2-6% slower
self-compile", *interleaved*, "reproduced in three runs" — and it evaporated at
higher repetition (min of 6: +0.3%; and the same compiler was FASTER on a
min-of-15 short-compile workload). Three under-powered runs share a bias; they
do not confirm each other. **Interleaving fixes WHICH runs you may compare;
repetition fixes how confidently.** Concretely, on this box: 3-4 reps cannot
resolve a 5% effect on a 17-second workload, and **a short workload with many
reps beats a long workload with few** — `hello.pas` at min-of-15 settled in two
minutes what `compiler.pas` at min-of-3 had got wrong in ten. If the effect you
are claiming is smaller than ~10%, say how many reps produced it, or do not
claim it.

## Regenerate the baseline; never reuse one from earlier in the session

The same slice checked that an `-O3`-gated pass had not disturbed `-O2`, by
hashing a fixed corpus compiled for all six targets and diffing against hashes
taken earlier that session. One program, `exc`, came back **changed on all six
targets**.

That result is impossible: the pass exits on `OptLevel < 3` and the corpus is
compiled at the default level. The impossibility is what made it cheap —
an implausible-but-conceivable delta would have been debugged for an hour.
Direct comparison of the two compilers on that program showed `cmp` finding no
difference at all, which located the fault in the harness rather than the
compiler. `exc` is the only corpus program that `uses SysUtils`, and a
`git pull` between the two hash runs — the v389 pin — had updated `lib/rtl`
underneath it. Re-running **both** sides back to back gave 48/48 identical.

- **A baseline is only valid against the tree that produced it.** In a repo
  where a pin can land `lib/rtl` mid-session and other lanes push continuously,
  "earlier today" is a different tree. Regenerate both sides, back to back,
  from the state you are actually comparing.
- **Say what you pinned, when, to whoever is mid-measurement.** A pin that moves
  `lib/rtl` invalidates every in-flight before/after in every lane, silently.
- The tell that saves you is the one above: **when a result is not merely
  surprising but structurally impossible, suspect the harness first**, and go
  find the shortest path that bypasses it.

## An optimisation's value is a property of the transform AGAINST A BASELINE — and the baseline moves, sometimes by your own hand

Three items of one optimisation ticket were sized on 2026-08-27, ranked, and
dispatched in that order. Within a day the ranking had inverted twice, and both
times the cause was **another item of the same ticket landing**:

- **An item was emptied.** Store->reload elimination for register-resident
  destinations was filed when the value round-tripped through the frame, which
  made it a real memory access to remove. By the time it was claimed, the
  residency change had put that value in a register, and the "reload" was a
  reg-reg move worth nothing. 6 instructions out of 13,483.
- **An item was revived.** An emit-time operand scheduler had been *correctly*
  disconfirmed at **1.4%** hours earlier — the loop body was then 12 cyc/iter
  dominated by two frame round-trips, and every `mov %rN,%rax` sat in their
  shadow. The residency change removed the memory traffic. The body became 6.5
  cyc/iter with **zero memory reads**, the dependency chain now ran *through*
  those staging moves, and the same transform measured **~1.6x**.

**The same instructions that are free while they overlap a 5-cycle
store-forward are the critical path once it is gone.** Neither measurement was
wrong; each was a measurement of a different machine.

So: **re-measure the prize before starting an item, not just the mechanism.**
Disassemble what the compiler emits *today* and time it; the ticket's number
describes a compiler that may no longer exist. A stale prize is more expensive
than a stale number, because it does not look like a claim to re-check — it
looks like work waiting to be done, and the backlog protects it.

## An A/B comparison is only valid when B is A minus exactly ONE thing

The same session's first model priced "make the register authoritative" at
**2.15x** by comparing a variant that kept the frame dual-writes against an
idealised body that had neither the dual-writes nor any of the operand staging.
Two changes, one credited. Isolated properly — every variant transcribed from
the *current* disassembly and differing from the baseline **by deletion only** —
the store removal was **~5%** and the staging removal was the rest.

The failure mode is not carelessness, it is that a variant table looks rigorous.
Four rows of times with four descriptions reads as a decomposition whether or
not the rows are separable. Two habits fix it:

- **Build each variant by deleting from the previous one**, never by writing the
  "ideal" version from scratch. If you cannot express B as "A minus X", you are
  not measuring X.
- **Calibrate the baseline against the real artifact** before trusting any row —
  the transcribed A above had to reproduce the shipping binary's 0.61 s. A model
  that does not reproduce the thing it models decomposes nothing.

## Interleaving, repetition, amplification — three different fixes for three different lies

One optimisation session produced three separate false readings in one night, on
one box, with the same command. They are worth stating together because they
look identical from the outside — a number that is wrong — and each needs a
different fix. The two entries above cover the first two; this is the third,
and it is the one that survives both of them.

**Amplification: below ~2% of the workload, `/usr/bin/time` is quantisation, not
measurement.** A boolean-heavy loop benchmark measured **0.49 vs 0.51**, and on
a re-run **0.55 vs 0.56** — "2-4% slower", twice, interleaved, min-of-15 both
times. That is exactly the shape of a real small regression: consistent sign,
survives repetition, plausible mechanism available if you go looking for one.
It was **one 10 ms tick** on a ~0.5 s workload. `%U` is reported to 10 ms, so at
half a second the quantum *is* 2%, and the "consistent" sign was one tick
landing the same way twice.

The fix is to make the sample long enough that the timer's resolution is small
against it — run the binary several times inside one timed command:

```sh
/usr/bin/time -f "%U" sh -c './bench >/dev/null; ./bench >/dev/null; ./bench >/dev/null'
```

At ~1.9 s per sample the same comparison resolved to **1.46 vs 1.45** — neutral,
and the regression had never existed. The same correction turned a compile
workload's "0.18 vs 0.19" into "0.64 vs 0.64" on a longer input.

The three compose, and the order matters because each is invisible to the one
before it:

| | fixes | symptom when missing |
| --- | --- | --- |
| **Interleaving** | WHICH runs you may compare | the same binary measures 1.09 and 1.34 |
| **Repetition** | HOW CONFIDENTLY | three under-powered runs share a bias and read as confirmation |
| **Amplification** | WHETHER THE TIMER CAN SEE IT AT ALL | a one-tick difference reads as a consistent few-percent effect |

So before believing any delta under ~5%: is it interleaved, is the rep count
enough to resolve it, and **is the effect larger than one tick of the timer?**
The last question is the cheapest of the three to ask and the easiest to skip,
because the number already looks like a measurement.

## When the box is busy, stop timing and start COUNTING

All three corrections above make a wall-clock delta trustworthy. None of them
help when the box itself is the problem — this fleet routinely runs nine agents
and seven concurrent self-host builds, at load 9-19 on 12 cores. At that point a
wall-clock A/B is not measuring your change, and no amount of interleaving fixes
it.

**Count retired instructions instead. The count is load-invariant by
construction, not by assumption.**

`perf stat` is the obvious tool and is **unavailable here**: this workstation runs
`kernel.perf_event_paranoid = 4`, which denies unprivileged access to every event,
hardware and software alike. Raising it is a root sysctl on the owner's machine.

So use qemu's execution trace, which is better anyway (frank-optimize-b4,
2026-08-29):

```
qemu-x86_64 -one-insn-per-tb -d exec ./bench 2>&1 | wc -l
```

One log line per instruction **executed** — exact and deterministic rather than
sampled, with no multiplexing and no skid. It costs ~100x slowdown, and you pay
for that by **shrinking `n` instead of enduring it**: a straight-line loop with one
back-edge has a constant per-iteration cost, so the count scales exactly and small
`n` proves the same thing. Measured on the W1 shift slice:

| n | BASE | HEAD | delta | delta/n |
| --- | --- | --- | --- | --- |
| 2 000 | 44 211 | 42 211 | 2 000 | 1.000 |
| 20 000 | 440 227 | 420 227 | 20 000 | 1.000 |
| 50 000 | 1 100 235 | 1 050 235 | 50 000 | 1.000 |

**Delta exactly `n` at all three sizes, no residue** — one instruction per
iteration, proven rather than argued. Load was 9.51 during the run and 16.44
shortly before; recorded, and *irrelevant*, which is the whole point.

**It also corrects the denominator, which eyeballing the emitted code will not.**
b4 had counted the hot loop as 18 instructions from the straight-line body. The
execution trace showed 18 addresses hit exactly `n` times **and 3 hit `n−1` times**
— the increment tail, skipped on the last iteration. The real body is 22, so the
win was 4.55%, not 5.6%. **Reading the emitted code tells you what was emitted;
only running it tells you what retires**, and loop control is the part a human
reading a listing reliably forgets.

Wall clock is still owed for anything claiming a *time* improvement — instruction
count cannot see cache behaviour, port pressure or branch prediction. Take it when
the box is quiet, and stamp both numbers with the binary sha **and** the load
average.

## A capability that exists and cannot be asked for costs you at the worst moment

`compiler/asmtext_wasm.inc` could write a `.wat` — the text form of a wasm
module, the oracle you diff the binary against — from the day it landed. The
compiler had no way to ask for it: the only caller was a standalone test.

That was invisible for weeks and then cost an hour, because the moment it
mattered was `0001db0: error: unable to read i32 leb128` — a *parse* failure,
which reports a byte offset and no function name, on a module of 124 functions,
with no way to look at what had been emitted. The gap and the need arrived
together, which is the shape: **an unreachable capability is only ever
discovered from inside the problem it would have solved.**

Two things to take from it:

- **When a tool grows an output the maintainer uses by hand, wire it to the
  command line the same day.** The fix here was one branch on the output
  extension. Deciding it was not worth a flag was correct and irrelevant — the
  cost was not the flag, it was that nothing could reach the code.
- **When a diagnostic reports a byte offset, the first move is to make the
  thing readable, not to read the bytes.** The actual root cause (an
  `i32.const` of 4294967295, unencodable as a 32-bit signed LEB) was five
  minutes' work once the `.wat` could be produced and the WAT/binary pair could
  be compared. Decoding the binary by hand first was the slow path, and it is
  the one you take when the fast path does not exist yet.

## A comparison with no floor: two totally-failed runs diff clean

`FAIL` compares equal to `FAIL`. So a differential harness that emits a per-case
verdict and is then diffed will report **perfect agreement** when both sides
managed to run *nothing* — and it reports it in exactly the same words it uses
when both sides ran everything and agreed.

Measured, 2026-08-29. A corpus harness compiled 8 programs for 6 targets with two
compiler binaries and diffed the hash lists. It did not export `PXX_HOME`, and
the binaries under test had been copied into a scratchpad, so neither could find
its RTL. All 48 rows on both sides were `FAIL`. The diff was empty. The result
was read as "48/48 byte-identical across all six targets", written into a commit
message, and cited in a ticket — for **four separate steps** of an optimisation
campaign. Every one of the four conclusions turned out to be true when re-run
properly, which is luck, not method: the evidence had been vacuous the whole time.

> **A comparison that can succeed by measuring nothing has no floor.** It is most
> confident exactly when it is least informed, and no amount of staring at the
> output distinguishes the two cases.

Same signature as `make compiler/pascal26` printing `up to date` in a freshly
seeded tree (CLAUDE.md): a success message in the wrong dialect, with everything
downstream healthy. Both belong to the family this whole document is about — the
expensive failures here do not crash, they return a plausible answer.

**So give every differential harness a floor, and make it refuse rather than
answer emptily:**

- **Count the comparisons you actually made, print the count, and exit non-zero
  when it is zero.** One line. It is the whole fix.
- **Report the count alongside the verdict**, so "identical" is never read
  without its sample size. "identical (25 rows)" cannot be misread; "identical"
  can.
- **Subtract the rows that can never work** — 3 of those 8 corpus files were
  `unit`s, compilable standalone on no target ever, and 8 rows were xtensa, which
  has no dynamic-symbol support. Their permanent `FAIL`s were the noise that made
  a screen of `FAIL` look normal.
- **Set the environment inside the harness, not in the caller's shell.** The bug
  was one missing `export` in a script that had been correct every time it
  happened to be invoked from the right directory.

And the discipline that catches it when the harness is someone else's: **before
believing a clean differential, make it fail on purpose.** Point it at a
deliberately broken binary. If it still says "identical", it was never looking.

## A count inferred from a size delta is not a count

Sibling of the empty-diff entry above, from the same day, and the more common of
the two because it reads as *more* rigorous rather than less.

A probe was added that emits an 11-byte instruction per site. To find out how
many sites there were, two binaries were compiled — one with the probe, one
without — and the size difference divided by 11. Answer: 261 sites. The probe
was then asked directly, and the answer was **76**.

Nothing about 261 looked wrong. It was arithmetic on two measured quantities,
and it was three and a half times the truth, because a binary's size is not its
code size, code motion and alignment absorb bytes, and the emitted sequence was
not the length assumed.

> **The instrument that produced the effect can also count it. Ask it.** A number
> derived from a side effect of the thing you are measuring inherits every
> assumption you made about that side effect — and unlike the measurement, it
> carries no signal when one of those assumptions is wrong.

Chasing the discrepancy paid twice over: reconciling the counted 76 against the
37 instructions actually removed from the binary is what surfaced a real gap
between codegen-time site counts and emitted code, which two further hypotheses
(dead-proc elimination, double emission) were then measured and ruled out.
The gap is recorded as unexplained rather than smoothed over.

**In practice:**

- **Print the count from the code that does the thing.** One `WriteLn` behind a
  debug flag, emitted where the transform fires. It cannot drift from reality
  because it *is* reality.
- **When two counts disagree, that is a finding, not an annoyance.** Both were
  measurements of the same population; one of your models is wrong and you have
  been handed the case that proves it.
- **Quote the artifact number, not the derived one**, and say which is which.
  "37 fewer instructions in the binary" survives review; "261 sites, inferred"
  does not, and should not.
- **`code=NNNNB` from the compiler's own success line beats `stat -c%s`** for
  anything about code size — the file carries data, bss and headers too.

## When success and a failure produce the same output, the output is not evidence

The entries above are each an instance; this is the shape they share, written
once. It is the most expensive family in this repo's history because every
member of it *reads as a pass*, so nobody looks.

The canonical case is already in `CLAUDE.md`: in a tree seeded with a copied-in
binary, `make compiler/pascal26` prints `make: 'compiler/pascal26' is up to
date` and exits 0. A verified fixedpoint also exits 0. **No fixedpoint was
proved and nothing says so** — the absence of `converged after N round(s)` is
the only tell, and an absence is precisely what a reader does not notice.

Four more from a single day, all different mechanisms, all the same shape:

- **A skipped test and a passing test both printed nothing.** 39 guards in
  `lib-test`; three of them, when their dependency was missing, took a branch
  that emitted no line at all and let the rule continue. "green" meant "passed"
  for 36 of them and "was never run" for 3, in the same word.
- **A remedy already in force and a remedy that worked are indistinguishable.**
  Applying a fix and seeing the symptom gone proves nothing until you know the
  fix was not already there. The test is *"did applying it change anything"*,
  and it is answerable **before** the result exists.
- **"Still red" and "the pin has not moved" are the same red.** Under the pin
  boundary a `$(PXX_STABLE)`-gated job keeps failing after the fix lands,
  because it is not running the fixed compiler. "It is still red, so there is a
  second cause" is the natural reading and it is wrong.
- **A no-op patch and a correct component are the same measurement.** Patching a
  suspect arm and seeing byte-identical output was read as "this arm is not
  defective". It licensed only "this arm is not on *this shape's* path" — the
  arm was in fact broken, for a spelling the repro did not contain. **A
  refutation is scoped to the shape that was tested**, and the negative result
  cannot tell you which of the two it earned.

- **An under-powered instrument reports a null, and a null reads as a finding.**
  Measured 2026-08-30, and it reached a *decision* before it was caught. A
  per-pass `-O3` sweep run at **min-of-3 under load 6-13** cannot resolve a 20%
  effect; it returned zeros for every pass, and those zeros were written up as
  *"no individual pass reproduces the tier's win, so per-pass promotion may never
  deliver it."* Re-measured at **min-of-5**, one pass — `EmitStaticLitHandle`,
  `ir_codegen.inc:3480` — is **20% of the 28% gap, ~71% of the tier on its own.**
  The original claim was not a wrong number. It was **no number**, wearing the
  grammar of one.
  **Ask what effect size your instrument can resolve BEFORE you report a null**,
  and record the load beside it. A null from an instrument that could not have
  seen the effect is not evidence of absence; it is absence of evidence, and the
  two are written identically.
  **The row that survived that sweep survived for a structural reason worth
  copying:** the DCE result held up because it was settled **by a flag, not by a
  margin** — decided by construction rather than by a difference of means. When
  you can arrange for the answer to be a flag, the load on the box stops
  mattering.
- **The batch is not the sum.** From the same measurement: promoting *every*
  `-O3` gate at once measured **worse** (18.06 s) than promoting the single best
  pass alone (16.23 s). Optimisation passes interfere, so a campaign must promote
  and measure one at a time. "All of them" is not a shortcut through "each of
  them" — it is a different experiment with a different answer.

- **A SHELL READS ITS SCRIPT ONCE — the sync that pulls in a fix still runs the
  old copy.** Measured 2026-08-30, and it hit the agent who had corrected two
  others for the same underlying bug three times that night: `sync.sh` had been
  taught to print the landed sha at 21:35, and his next *two* syncs still did not
  print it, because the run that fetched the new script was already executing the
  old one. He quoted two ghost shas in between. **The fix landed, the running
  process did not have it, and nothing anywhere said so.** After any sync that
  updates a tool you are about to rely on, the FIRST run of that tool is the old
  one; check the behaviour changed rather than assuming the pull applied it.
  Generalises past shells to anything that loads once and is edited underneath.
- **"master is broken" vs "my copy is" — `git stash` + rebuild on clean HEAD,
  2.5 s.** One measurement instead of an argument, and against a 120 s timeout it
  is free. CLAUDE.md's parking note has the slower form (build with the *pinned*
  compiler against a clean tree); this is the fast one and it answers the same
  question. Reach for it the moment a failure looks like someone else's fault —
  that is precisely when a false accusation is cheapest to make and most
  expensive to retract.
- **"Same repo" and "same tree" are different, and `ps` cannot tell them apart —
  `/proc/<pid>/cwd` can.** Every agent's `make compiler/pascal26` has an
  identical command line and builds into `/tmp/pxx-build-*`, so a `pgrep` showing
  three concurrent builds is **not** evidence they are colliding, and it is also
  not evidence that anyone is safe. Read the working directory instead:

      for p in $(pgrep -f 'pascal26|make compiler'); do
        echo "$p $(readlink /proc/$p/cwd)"; done

  Measured 2026-08-30 (frankA's method, and it corrected me the same hour): a
  warning went out naming three agents as sharing one worktree. All three were in
  their own checkouts; the tree had **exactly one** occupant, and it was none of
  the three. To enumerate the fleet rather than one build, read the cwd of each
  session socket — `readlink /proc/$(basename s .sock)/cwd` over
  `/run/user/1000/cc-socks/*.sock` — which maps every live session to its tree
  and takes a second. **A claim about who is in a directory is checkable; do not
  relay one.**

And the cheapest one, which cost a full probe cycle the same evening: a compile
whose output flag was wrong (`pascal26 x.pas -o out` — there is no `-o`; the
second positional IS the output) wrote a file literally named `-o`, exited 0,
and left last night's `out` on disk. Running it printed the pre-fix answer.
**"The fix does not work" and "you ran yesterday's binary" produce the same
bytes**, and the fix was correct the whole time.

> **Ask of every green: what else would produce exactly this?** If a second
> state answers, you have not measured anything yet. Do not go looking for the
> cause of a result until you have established the result is real.

**In practice:**

- **Make the two states print differently, and prefer a POSITIVE token.** Not
  "no failure line" but `converged after N round(s)`, `SKIPPED: synapse-ssl`,
  `76 sites`. A pass that is defined by an absence cannot be distinguished from
  a run that did not happen.
- **A summary line must name what it did NOT cover.** `lib-test ok (...) --
  SKIPPED: x y z (green here does NOT cover them)` is the whole fix for the
  first case, and it is three lines of `make`.
- **Name the binary, not the commit.** "The fix is in HEAD" and "the fix is in
  the binary I just ran" are different claims and only the second is evidence.
  `git merge-base --is-ancestor` answers the first while you execute a stale
  artifact. Check the sha of the thing that ran.
- **Confirm the intervention took before reading the result.** The compiler sha
  changed; the toggle is present in the file; the flag reached the process. A
  probe that never fired and a probe that fired and found nothing both print
  nothing.
- **A regression test nobody has watched fail is not yet a regression test.**
  Run it against the pre-fix binary. If it passes there, it does not test what
  you think, and you will never learn that from a green suite.

## A Pascal comment cannot contain its own delimiters, and the error lands nowhere near the edit

**Cost: five wasted builds in one session (frankC, 2026-08-30), all self-inflicted, all the same mistake wearing different clothes.**

This dialect's comments **nest in both styles**, and the consequence is that the
most natural thing to write in an explanatory comment — the syntax you are
explaining — silently terminates or extends it.

```pascal
{ a struct member cannot have a body: a missing } closes here, not below }
```

The comment ends at the **first** closing brace, so `closes here, not below }`
becomes code. Same trap in the other style, from the other direction:

```pascal
(* the arm at (*name) is the one that... *)
```

`(*` **nests**, so this comment is now one level deep and swallows everything
until a second `*)` — often hundreds of lines away, sometimes the rest of the file.

A string literal inside a comment is not a refuge either: `{ pass '}' to close }`
fails identically, because the lexer is not reading a string, it is counting
delimiters.

### The tell, and why it wastes a whole build each time

The compiler reports where the *damage surfaces*, not where the comment is:

```
pascal26:2998: error: unexpected character
pascal26:3187: error: unterminated comment
```

Both of those were **a hundred-plus lines below a comment I had just edited**, in
code I had not touched. The instinct at that point — read the reported line,
find nothing wrong with it, start widening — is the expensive path, and it is the
wrong one every time.

> **`unexpected character` or `unterminated comment` at a line you did not edit,
> in a build you started right after editing a comment, is the comment. Look
> UP, at your own last edit, before you look at anything the error names.**

### The rule

**A Pascal comment must not contain `{`, `}`, or `(*` in either style.** When the
comment's subject *is* brace syntax — and in a C frontend it constantly is —
**spell the delimiters out in words**: "a closing brace is missing above this
line", not the character. That is why `CEndCMember`'s diagnostics read the way
they do; it was not a stylistic choice.

This belongs with the tool-aperture entries above rather than the measurement
ones: nothing was mismeasured, the instrument reported correctly on what it was
given, and the input had been corrupted by an edit that looked inert. A comment
is the one construct you edit while believing it cannot change behaviour.

### `code=` is page-quantized — for a real code size, ask the object file

The compiler's summary line (`ok: out [code=221036B data=... bss=...]`) reports
the **page-padded** text size. Swept over programs with 1, 2, 4, 8, 16, 32, 64
and 101 procedures, it moves only in **4096-byte steps** — so it will report a
delta of **zero** for a change that alters every prologue in the image, and it
will report **+4096** for one that added 1944 bytes.

Measured 2026-08-30, twice, in opposite directions on the same day: a riscv32
change was published as "+1.67%, which is 1024 forward jumps x 4 bytes" (the
arithmetic fitted a rounded number and was a coincidence — the true figure is
+2.14%), and an xtensa change that provably rewrites 161 prologues measured as
**no change at all**. The second is the dangerous one: a null result from an
instrument that cannot see the effect looks exactly like a fix that does
nothing, and the natural next move is to go looking for why the change did not
take.

The exact instrument, and it costs one command:

```
pascal26 --emit-obj --target=<t> prog.pas out.o
readelf -S out.o | awk '$3==".text"{print $7}'      # hex, NOT page-padded
```

`--emit-obj` is supported for xtensa and riscv32. For the linked executables the
same padding shows up in `readelf -l`'s `FileSiz` (0x3c000 for a 243060-byte
text), so that is no better. When neither is available, count the instruction
pattern you changed straight out of the artifact — that is what settled which
of the two riscv32 jump forms was firing, and what frankS used independently on
the same xtensa change (the emitted NOP count moved 243 -> 428 -> 1072 while
`code=` sat flat at 221036).

**When you have no command at all, the general shape is frankS's: force the
input somewhere the output MUST move, and check that it does.** Setting the
reserved-slot count to an absurd 20 finally shifted the number — by exactly 8192
— and that is what proved the instrument had a floor rather than the change
having no cost. A measurement that cannot come out different is not a
measurement. The command above is the reusable part; this is what you do when
you do not have one.

## Two identical-looking walls: where the FIXUP TABLE lives decides whether relaxation is possible

Measured 2026-08-31, on xtensa, twice in one session. Both walls produce an
error of the same shape — *a forward reference reserved a three-byte slot before
its target existed and the displacement does not fit* — and one of them is
fixable by relaxation while the other is not. **Nothing in either error message
says which.**

| | forward JUMP to a label | forward CALL to a proc |
| --- | --- | --- |
| fixups recorded in | a **per-body** list, reset at the top of `IREmitMachineCodeXtensa` | `CallFix`, **whole-program**, drained once by `ApplyCallFixups` |
| when the target is known | end of this body | after every body in the image exists |
| so "try again wider" means | re-emit **one body** | re-emit **the image** |
| state to restore | 7 append-with-count arrays, enumerable and enumerated | everything, and in a parser-driven backend it is a second **parse** |
| outcome | relaxation, 2 passes, free below the bound (`dd417a986`) | a flag the author must know about (`f6660111e`) |

**The rule, and it generalises past xtensa:** a slot can be widened by re-running
the emission that reserved it, and *only* by that. So the question is never "can
this instruction be widened" — it is **"what is the smallest unit I can emit
again, and does it contain both the slot and the answer?"** For a label, the
body contains both. For a call, the body contains the slot and the *program*
contains the answer, so no unit smaller than the program will do.

Check it before reaching for a fix that worked on the sibling: find the array
the site appends to, and see whether the pass that drains it runs per body or
per image. It is one grep, and it is the whole design decision.

## A completion marker cannot see a concurrency defect — it is preserved by almost every race

Measured 2026-08-31 while landing `feature-a-io-lock-owner-from-tls-not-gettid`.
I deleted the stack-bounds check from the `--threadsafe` I/O lock, changing
nothing else, and rebuilt. The lock now believes an inherited TLS block, so a
glibc `pthread_create` thread answers *"already mine"* for a lock it does not
hold: **mutual exclusion is gone.** Then:

| the suite's threading tests | result on that build |
| --- | --- |
| `test_multithreading` (4 glibc threads, heap churn, `write('.')`) | **PASS** |
| `test_threadsafe_io_lock` (reentrancy, write-arg writes) | **PASS** |

The first greps for `multithreading test completed successfully`; a program that
races still completes. The second is single-threaded. **Both are the tests the
ticket's own `Gate:` line named**, so the gate would have blessed the defect it
spends three sections explaining.

**The shape:** a race almost never stops a program — it changes what the program
*produced*. So a concurrency guard must assert on the OUTPUT's structure, not on
the run's survival. The replacement (`test_threadsafe_io_lock_foreign.pas`) has
four threads each write 50 lines of 300 identical characters — a `Writeln` is
two `write(2)` calls, so an unserialised pair tears — and demands **exactly 200
whole lines**. Watched failing at 52, 108 and 57, with 1200-character lines.

Two details that are the actual reusable part:

- **Count the GOOD, never the bad.** "No malformed lines" scores an empty run,
  a crash and a hang as a pass. `= 200` cannot.
- **The tearing must be BIG.** `test_multithreading` also writes from those
  threads — single dots. Interleaved dots are indistinguishable from ordered
  dots. If the payload is one syscall wide, there is nothing to tear.

Same family as frankA's *a read-back test verifies agreement, not correctness*
(same day, `feature-signal-siginfo-ucontext`): the instrument answered honestly
about the wrong question. Here the honest answer was "it finished".

## A guard whose failure mode is a SILENT FALLBACK cannot be distinguished from a guard that is absent

frankS's, handed over rather than written by them, because the case that names it
is one I would have walked into. Measured 2026-08-31, in the same hour as the two
sections above.

The `--threadsafe` I/O lock validates its cached owner by checking that the
reader's own `rsp` lies inside the stack bounds its TLS block records. Reusing
that check for the **signal** slots looks obviously right and is a trap: a
handler installed with `SA_ONSTACK` runs on the **sigaltstack**, i.e. deliberately
*outside* the thread's stack bounds. The check would therefore miss on **every
single delivery**, fall back to the process-wide slot, and fix nothing.

Nothing about that failure is visible:

- it never errors — a fallback is a valid path, taken deliberately elsewhere;
- it is self-consistent — the same wrong answer every time, so no flapping;
- and the fallback **is the pre-fix behaviour**, which is the part that closes
  the loop: *the fix not working and the fix not being present produce
  byte-identical behaviour.* There is no observation that separates them.

**So the rule is not "prefer a guard that errors".** It is: when a guard's miss
path silently restores the old behaviour, **the guard needs a positive control
that asserts the HIT path was taken** — a counter, a distinct value, anything
that could not be produced by the fallback. Without it you have written a
no-op with the shape of a fix, and every test agrees with you.

The generalisation of the trap is worth stating separately, because it survives
the specific case: **a check borrowed from a working use is validated for that
use's population, not for yours.** The bounds check is correct in the I/O lock —
there a miss genuinely means "not my block" and falling back to `gettid` is the
right answer. Moving it to a caller whose population includes the alt stack
changes what a miss MEANS while changing nothing about what it DOES.

Same family as the two sections above and named the same way: *the instrument
answered honestly about the wrong question.* Here it would have answered
honestly about the wrong stack.

## A census is only as good as its KEY — and the only way to check the key is to run the census where the answer is known

Two censuses, 2026-08-31, both taken before touching anything, both printing a
reassuring number, both wrong in a different way. Together they say what the
guard actually is.

**Mine (frankS) was indexed on the right key and I stopped reading it.** Moving
the exception chain head to per-thread TLS, I listed every file mentioning
`BSS_EXC_*` first. `compiler/symtab.inc: 1` was in that list. I then worked from
the subset I had decided were "the x86-64 sites", converted those, and never went
back to check the list was exhausted. `symtab.inc`'s
`EmitLeaveExceptionFrameX64` kept storing to process-wide BSS while every read
came from `gs:`. Pascal `try/except` passed — its path goes through the
converted copy — and **every NilPy `try` segfaulted**, 30 jobs red.

**frankA's was indexed on the wrong key and had a clean bill of health.** He
censused names defined in *both* `ir_codegen.inc` and `symtab.inc`, looking for
exactly this class of duplicate: ten hits, all `forward;` declarations, no
duplicate bodies. Then — and this is the whole lesson — he ran it against
`e0a818429^`, the tree where my duplicate is known to exist. **It did not find
`EmitLeaveExceptionFrameX64`.** It could not: that routine is defined only in
`symtab.inc`, and `ir_codegen.inc` emitted the same three instructions *inline*
under no shared name. A name-based census is structurally incapable of seeing
duplication that has no name, and it would have printed the same reassuring zero
on the night the bug shipped.

**So the rule is not "keep consulting your census". It is: a census indexed on
the wrong key is the failure, and it feels exactly like completeness.** Mine
listed the right file and I under-used it; his was answering a question nobody
asked. Neither errored. Both answered.

**The key that works here is the SLOT, not the name** — the thing the code
touches, not the identifier it touches it through. frankA's, after the name
census failed its control:

```
BSS_SIG_NUM — 8 files, 14 mentions, writers exactly 5:
  ir_codegen386 / arm32 / aarch64 / riscv32   one stub each (plain BSS)
  ir_codegen.inc                              the x86-64 pair
read side: exception_emit.inc:27  `if TargetArch <> TARGET_X86_64 then Exit`
```

That is a falsifiable property — *no arm exists where a read comes from `gs:`
while a store goes to BSS* — rather than a file list, and it is the shape of the
bug stated so a census can answer it.

**And the control is free, so there is no excuse for skipping it.** Run the
census against a commit where the defect is known to be present; if it does not
find it, the key is wrong. This is the positive-control rule (a guard that
cannot fail is not a guard, and it prints PASS) applied to a *search* rather
than to a test — and a search is where it is easiest to forget, because a
search's output is a list and a list looks like evidence.

## The best positive control is one you FIND, not one you build — look for a case the change must still refuse

The rule above says a search needs a control. The objection to it is always cost,
and the answer is that the control is usually already sitting in the population
you are about to sweep.

Worked example, 2026-08-31 (frankA). The `-S` disassembler's prefix scan accepted
only `$66/$F2/$F3`, so the `$65` (gs) prefix on the new per-thread status slots
fell through to the raw-byte path and printed `db 65`. The fix widens the scan
into a **loop** over prefix bytes — and a loop is exactly the shape that fails
*permissively*: written a little too broadly it swallows bytes it does not
understand and reports a clean sweep, which looks identical to a correct fix.

The control cost nothing and was not constructed:

```
hello.pas / compiler.pas       db=0   (the two jobs that were red)  -> must be 0
test_asm_sse_packed.pas        db=75  -> must STAY 75
test_asm_avx.pas               db=77  -> must STAY 77
```

The AVX and SSE-packed programs contain VEX and packed forms this disassembler
genuinely does not cover and **must** still fall back to `db`. They assert
nothing in any job, they were red in neither, and they were already in the tree.
So the sweep proves both directions at once: the fallback *stopped* firing where
it should and *still fires* where it must.

**The move to copy is the question, not the example.** Before building a control,
ask: *what in the existing population must this change still refuse?* A widening
almost always has one — an input outside the widened set, a target the fix does
not claim, a construct the feature does not cover. Finding it is a grep; building
one is an afternoon, which is why the control gets skipped.

### When a finding is an ABSENCE, ask what ELSE produces that absence -- and put one of those in the probe

frank-rust's rule, 2026-08-31, and it is the companion the section above was
missing: the control question has a second form when what you measured is a
**negative**. A rejection, a missing entry, a zero count -- none of them tell you
*which* mechanism produced the nothing.

The instance is unusually well-run, which is the point. A census of all 51
builtin type names found twelve that `var v: N` accepts and `SizeOf(N)` refuses.
The one-line fix -- chain the declaration table as the builtin table's fallback
-- was built, **held the fixedpoint**, produced a **clean census**, and came with
an explicit safety argument: every existing arm still wins, so it can only turn a
rejection into an answer. It was wrong. `SizeOf` consults the builtin table
*before* the user tables, so widening it makes a builtin **steal a user's own
name**: `SizeOf(Currency)` goes 12 → 8 against a user's
`type Currency = record a, b, c: Integer; end`, and a `Boolean` named `longbool`
goes 1 → 4. Reverted;
`bug-p-sizeof-rejects-twelve-type-names-that-a-declaration-accepts` carries the
numbers and the counter-example.

**Why it sits beside frankwasm's prescription case rather than under it, in
frank-rust's own distinction: that one was a prescription trusted without an
oracle. This one HAD an oracle, ran it, and it passed.** The census was
structurally incapable of catching the defect, because **every probe program
declared no user types** -- so "rejected by SizeOf" and "resolved by the
user-type path" emit identical output. The absence being measured was never a
rejection at all; it was the fallthrough, and one `type Currency = record` in the
probe population separates them.

- **The control argument, not the care argument.** The table header said *callers
  must consult a user type alias FIRST where that matters* -- correct, present,
  and read while the change was being written. **A control fires whether or not
  you understood the sentence**, which is the only property that scales.
- **A clean census is a claim about the probe population first and the system
  second.** Before believing one, ask what the population cannot express. Here it
  was user-declared types, and that is also exactly what the change endangered.
- **The mechanical form, and it is the one to apply without thinking: a control
  sampled from INSIDE the old boundary cannot detect that you moved the
  boundary.** When the same merge was built a second time and landed
  (`ce4d9004c`), its accept-side control ran **37 names, every one a builtin** --
  drawn entirely from the population the change was about. The change moved
  *which names the table answers for*, so the only arm that could fail was the
  missing one: a **user** type. Sample the control from the other side of the
  line you are moving.

## A reader that drops a byte it does not know does not report "unknown" — it makes a confident statement about a different instruction

The same bug, read for its blast radius, because it is worse than a cosmetic gap.

`db 65` on its own line is **not** a decode failure. It is a decode of the
remaining bytes *as if the prefix were absent*: the `mov` behind it rendered as
`mov r8, [0x00000000]` — an **absolute** access, where the binary holds a
**per-thread** one. The tool did not error. It answered, fluently, about an
instruction that is not there.

**The near-miss is the reason this is here** (frankS, whose change it was). Their
proof that the per-thread form costs a prefix byte rather than a load was a count
of `0x65` in the raw object bytes: 10 under the new compiler, 0 under the
control. Had they reached for `-S` instead — *the obvious tool, and the one they
would have recommended to anyone else* — it would have shown the absolute form,
they would have read it as "the TLS conversion did not take", and they would have
gone hunting a codegen bug that does not exist, with a correct change as the
prime suspect. They got past it by accident.

So: **when you add a byte to the instruction stream, every reader of that stream
is part of your change's surface.** Disassembler, profiler, coverage tool,
anything that resyncs. A reader that resyncs *always produces plausible output* —
that is what resyncing means.

**And the ambiguity can be two characters wide.** In the same hour, frank-rust
read `db 65` as decimal — `0x41`, a stray REX.B — and had built a story about a
redundant prefix in the code generator before checking the radix (`DisHexByte`
settles it in one grep). One ambiguous surface, two entirely different suspects:
a spurious prefix *from* codegen versus a missing prefix *in* the disassembler.
Only the second is real, and only the implausible reading was checkable. They
caught it against themselves; a subtler byte would have entered a ticket as fact.

The companion, also frank-rust's, for anyone diffing a `case` statement for
per-target node coverage: a grep anchored at line start reported `IR_WRITELN`
missing from riscv32. It is the trailing label of `IR_WRITE, IR_WRITELN:`. That
was caught only because "riscv32 cannot write a line" is absurd on its face — so
**a coverage diff over a `case` needs its own positive control: a node you KNOW
the backend has, asserted present.**

## When a better story is already in hand, the one-command check gets filed as "downstream"

Measured 2026-08-31, over six rounds of
`bug-a-xtensa-windowed-abi-faults-on-frozen-strings-copy-and-dynarray-setlength`.
A `Copy` under the xtensa windowed ABI died with SIGBUS. Round 2's register dump
contained this, and round 2 wrote this note about it:

> *(The post-fault A-register view shows `A07=00000001` where a7 is the windowed
> frame pointer, and a following block would compute `addi a2, a7, -32`. That is
> downstream of a failed window restore and is NOT load-bearing evidence —
> recorded so the next reader does not chase it as the cause.)*

**Every clause of that is true except the verdict.** a7 *is* the windowed frame
pointer. `addi a2, a7, -32` *is* the faulting instruction. And `A07=00000001` was
not corruption at all — it is literally the `movi a7, 1` the compiler emits for a
Char operand's length in the managed-string marshalling arm, which had chosen
a4-a7 as its scratch quad on the grounds that *"a2-a7 survive call8"*: true of
the Xtensa ABI, false of this compiler.

**Why it was set aside is the transferable part, and it is not carelessness.** A
better story was already in hand — `retw`, `WINDOWSTART`, a window underflow
whose reload dies — and it is a *good* story: mechanical, specific, and one in
which a garbage frame pointer is exactly what you would expect to see afterwards.
The register fitted the story as a **consequence**, so it was labelled a
consequence. The note even exists to protect the next reader, which is the right
instinct aimed one step wrong.

Rounds 3, 4 and 5 then cost three purpose-built programs and five falsifications
— misaligned copy, `sp`-movement volume, call depth, the prologue's ABI
violation, frame size, and finally a program reproducing the exact fault state
(`wb=2 ws=04`, identical frame shapes, same wrap depth) **that passes**. All of
that sat between the note and `grep reg_xtensa_a7 ir_codegen_xtensa.inc`, which
answers it in seconds and names seven sites.

**The rule: before you write "downstream, not the cause", ask what this would be
if it were NOT downstream.** Here that is "a value someone deliberately put
there", and the check for it is one grep. A *dismissal* is a claim, and it needs
its own cheap check exactly as much as an accusation does — the more so when a
satisfying mechanism is already available to absorb it. This is the exculpation
rule (*"not X" is half a finding*) pointed at a single register instead of a
commit.

**What is NOT the lesson: rounds 1-5 were not wasted and must not be re-run.**
They are what killed every *shape* explanation, and it was round 5's conclusion —
*every shape explanation is now matched by a working program* — that made a
**content** instrument (which register holds what) the only remaining move. The
falsifications were the work; the delay was one unasked question inside them.

## A selftest over fixtures YOU wrote tests the logic, not the input — run the control against the real file

Sharpens *"the best positive control is one you FIND, not one you build"* above,
with the failure that section does not quite cover: a control you build can be
**green, asserted, and blind**.

Measured 2026-08-31. `tools/iropname_lint.py` checks that `IROpName` names every
declared IR op. It shipped with a selftest carrying a real positive control — a
fixture with one op deliberately unnamed, asserted to be reported. It passed.

The tool was still blind. It scanned the `case` body for `IR_*` tokens
**including comments**, and the comment written above the seven new arms names
`IR_CLASSREF`. So on the real file, deleting the `IR_CLASSREF` arm left it
reporting **clean** — the prose satisfied the check.

**The fixture could not have caught it, because the fixture had no comments.** I
wrote both the tool and its fixture in one sitting, from one mental model of
what the input looks like, so the fixture inherited the assumption instead of
challenging it. That is the general shape:

> **A synthetic fixture is written by the same person with the same blind spot.
> It tests whether the logic does what the author meant. It cannot test whether
> the author understood the input.**

Only the real file has the properties you did not think of. So:

- **Run the positive control against the REAL input**: delete a real arm, break
  a real entry, mutate the real baseline — then require the failure.
- **Assert the mutation LANDED before trusting the result.** A `sed` for a token
  that is not there changes nothing and the tool says "clean", which is
  indistinguishable from the control passing. `diff` against the backup and
  print `control armed` first. Same day, same session, both halves of this:
  *"I edited it"* and *"the edit landed"* are two claims and only the second is
  worth anything.
- **Assert the instrument can SEE its input before trusting any verdict.** The
  cheapest form is a count: *how many files did you actually open?*
- Keep the fixture selftest anyway — it is fast and it catches logic
  regressions. Just do not let green there mean the tool works.

**The A/B control has the same exposure as the tool, and it bit immediately.**
To prove a linter fix mattered, I built the pre-fix variant and ran both. The
old variant reported **clean** — apparently disproving the bug I had just
measured by hand. It was a copy living in the scratchpad, and it resolved its
repo root relative to `__file__`, so it globbed a directory containing **zero**
`ir_codegen*.inc` files and correctly reported no findings in nothing.

*The instrument answered, correctly, about something else* — third instance in
one day, and this one was **the control built to validate the fix**. A script
copied out of its tree takes its path resolution with it. The tell is free and
it is the bullet above: printing `files scanned: 7` before the verdict makes
`files scanned: 0` impossible to read as a pass. Nothing errored; it never
does.

The sting is that this was `abi.inc`'s dead review grep reproduced from scratch,
hours after replacing it, by the same author, in the tool written to prevent
that class of thing. **A checker satisfied by prose is this repo's house failure
mode**, and it gets *more* likely as the comments get better — which means the
usual remedy, write a clearer comment near the hazard, feeds it.

## A condition's bug is as likely to be in the half it LETS THROUGH — and a diff against the predicate cannot tell you which

Measured 2026-08-31, and it cost a wrong analysis in a filed ticket.

A linter flagged `ir_codegen_aarch64.inc` for deciding a parameter question by
hand instead of asking the ABI oracle. Diffing the two:

```pascal
  hand:   (Kind = skParam) and TypeIsFrozenString(tk) and not IsArray
  oracle: IsRef or IsArray or TypeIsFrozenString(tk) or (tk = tyVariant)
```

The delta is `not IsArray`, so I built a truth table on `IsArray`, wrote out the
two outcomes that follow from it — *reachable, so call the oracle*, or
*unreachable, so the text is dead* — and called them exhaustive.

**Both were wrong.** The bug was a two-line SIGSEGV with `IsArray` **False
throughout**: the arm fires *because* `not IsArray` is true, and the emitter one
line above has already dereferenced the by-ref param, so the extra load is a
second dereference. And the site legitimately cannot call the oracle at all —
the real question is *"has the emitter one line up already consumed that
fact?"*, which a `symIdx` cannot express.

Two things generalise:

- **A diff tells you where two things differ, not where either is wrong.** I
  anchored every branch of the analysis on the token that differed, and the
  defect was in the region both spellings agreed on. Enumerate outcomes over
  what the code *does*, not over the delta you just computed.
- **A condition-vs-predicate comparison is blind to the call site.** The
  correct answer here was a property of *what ran one line earlier*. No amount
  of staring at the two boolean expressions could contain it — and a truth table
  is seductive precisely because it looks like the whole analysis.

**Read this as a limit on the method, not a reason to drop it** (frankS, who
fixed the bug): diffing the condition against the predicate is *what produced
the hit at all*, and the hit was real. It is a good instrument for **finding**
a suspect site and simply not an instrument for **deciding** which half of it is
wrong. Keep the diff; stop where it stops. The mistake was not the truth table —
it was writing *"either it is reachable and ... or it is not and ..."* as though
the table exhausted the possibilities.

The cheap discipline that would have caught it: **the repro was two lines.**
Whenever an analysis is about to produce a branch labelled "unreachable", that
branch is a prediction, and predictions of unreachability are the ones most
worth spending two minutes falsifying — they are how a live SIGSEGV gets filed
as possibly-dead defensive text.

The tell: I wrote *"either it is reachable and ... or it is not and ..."*. A
two-branch enumeration built from a one-token delta is a claim that the token
is the only thing in play. Write the repro instead; it took two lines.
