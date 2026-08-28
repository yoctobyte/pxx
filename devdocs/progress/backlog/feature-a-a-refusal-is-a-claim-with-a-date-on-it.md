---
slug: feature-a-a-refusal-is-a-claim-with-a-date-on-it
title: Refusals cite blockers that may have landed, and nothing checks the difference
track: A
type: feature
prio: 35
status: backlog
found: 2026-08-28
found-by: frankwasm (measured on the wasm branch), generalised by frank-coordinator
---

## The observation

Measuring a string-heavy program for the wasm backend, frankwasm found **9 refusals reading
"address of managed string — needs the heap, Phase 6."** The heap landed that morning. The
refusals were true when written, are false now, and nothing in the build can tell the
difference.

> **A refusal is a claim with a date on it.**

Nothing distinguishes a correct refusal from an obsolete one, so an obsolete refusal keeps
working perfectly: it compiles, it is not a test failure, and it silently costs whoever
next measures that surface — the measurement reports mass that no longer exists.

## Not confined to one branch

Grepped on master: **~19 sites** across `ir_codegen386.inc` (5), `ir_codegen_arm32.inc` (3),
`asmfront.inc` (3), `lexer.inc`, `pylexer.inc`, `cparser.inc`, `rparser.inc`, `zparser.inc`,
`pasparser_stmt.inc`, `defs.inc` carry refusals of the form *"not implemented / not
supported … yet"*, several naming a ticket slug.

**Whether any of those is actually stale today is UNMEASURED.** That is step one, and the
ticket must not pretend otherwise — the shape is confirmed repo-wide, the staleness is not.
Same discipline as `bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`:
find out whether the baseline is non-empty before building anything on it.

## The cheap mechanism, and why the spelling decides it

A refusal citing **"Phase 6"** is not machine-checkable — nothing in the repo knows which
phases have landed. A refusal citing a **ticket slug** is decidable by construction: if the
slug now sits in `devdocs/progress/done/`, the refusal is stale, full stop.

**So the recommendation is a convention change, not a tool**: refusals name the ticket slug
that would remove them, and a ~15-line check (beside `tools/forwardlint.py`) flags any
refusal whose cited slug has been resolved. The check is trivial *given* the convention and
impossible without it, which is the whole content of the ticket.

Adopt the convention on new refusals; retrofit opportunistically rather than as a sweep.

## Priority, honestly

p35. Nothing is broken and no program misbehaves. The cost is **wasted measurement and
misdirected effort** — the failure mode is a lane planning a phase around mass that was
already removed, which is precisely what almost happened here and was caught only because
someone was measuring rather than reading.

frankwasm's position, which is reasonable and is why this is filed rather than assigned:
*"I do not think it wants a mechanism; I think it wants the phase that removes it."* True
for those nine. **The phase removes the instances; it does not remove the generator**, and
every future phase leaves refusals citing a phase that has since landed. Filed so the
generalisation is not lost when the nine disappear.

## Related

Fourth face of one generator this week, with
`bug-a-per-cpu-ifdef-chains-in-builtinheap-fail-open`,
`bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`, and the
vacuous-negative case in `feature-t-audit-tests-that-pass-with-the-implementation-removed`:
**an absent symbol, a silent environment, a grep matching zero, and a refusal that outlived
its cause are all states that are indistinguishable from correctness while carrying no
information.**

**This list is OPEN, and saying so is not a formality.** On the same day these four were
grouped, Track T confirmed a **fifth face** of a *different* four-face family
(`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good`) whose parent ticket sits
in `done/` beneath a table headed **"All four faces, closed."** Four were found, four were
fixed, and the ticket said so honestly — and a fifth existed the whole time.

frankT's warning is the one that applies here: **this shape presents one face at a time, and
each one looks like the last.** A closing table asserting an enumeration is complete is
itself a check that cannot fail, which makes it an instance of the very generator it is
summarising. So: no "all N faces" line goes on this family, and a new instance is expected
rather than surprising.

---

## A STRONGER pattern than this ticket proposes: give the note a mechanical expiry

frankwasm invented a better form of this while writing a scope note, and it should be
preferred wherever it is available.

`check_managed.sh` documents that the wasm32 managed-string slice passes only because its
live set is a handful of short strings the free list recycles inside the first kilobyte —
i.e. **"this is not 'managed strings work'."** A prose note saying so would go stale exactly
the way the nine "needs the heap, Phase 6" refusals did. So the script's last check asserts
`PXXAlloc` still returns an address **below 1024**.

**The day the heap ticket lands, that check FAILS BY DESIGN**, and whoever lands it must
rewrite the scope note instead of letting it quietly outlive its cause.

That is this ticket's generator solved with a **mechanism** rather than a **convention**:

| | slug convention (this ticket) | mechanical expiry (better) |
| --- | --- | --- |
| detects staleness | when someone runs the checker | at the moment the cause is removed |
| who is told | whoever runs the tool | the person whose change invalidated it |
| failure mode | nobody runs it | none — the build stops |

**Prefer the mechanical expiry when the claim's cause is observable from a test.** Fall back
to the slug convention when it is not — a refusal in the compiler cannot easily assert
against `done/`, which is why the convention still earns its place.

Note the pattern's own precondition: it works because the expiring check is attached to a
condition that a *future correct change* must violate. A note whose cause cannot be
expressed as a failing assertion gets the convention instead.

---

## FACE SIX, within the hour of this list being marked OPEN

The family above was marked open rather than closed on 2026-08-28. A sixth face arrived the
same hour, and it is genuinely distinct: **a refusal that never had a cause at all.**

`WasmEmitBinop` refused string operands from **inside the arm that runs when the width
oracle fails**. But `s + 'x'` is a handle and a Char — pointer-sized and ordinal — so the
oracle agreed on i32 and **the guard was never reached**. Measured on a body with no managed
store: `writeln(t + 'x')` lowered to `handle + 120`, passed to `PXXWriteStrMW`. **Valid
module, plausible garbage.**

It appeared to work only because a **different** check — the managed-store refusal — fired
first in the common shape. So:

> **Face five is a refusal that outlived its cause. Face six is a refusal that never had
> one, and was masked by an unrelated check happening to fail earlier.**

The second is worse, because there is no date at which it became wrong. It was always wrong
and always covered. Nothing in this ticket's slug convention or the mechanical expiry
detects it — **the detector for face six is removing the OTHER check and seeing what still
refuses**, which is the negative-control method from
`feature-t-audit-tests-that-pass-with-the-implementation-removed` pointed at guards instead
of at tests.

---

## FACE SEVEN — where the CORRECT build is the one that looks wrong

Every face so far is a check that cannot fail. This one is a check that fails **on the right
answer**, and it is how the x86-64 comparison leak was found.

frankwasm's leak check diffed the wasm heap advance against the native build's. They
disagreed. **The native build was the wrong one** — x86-64 leaks 40 bytes per evaluation of
`if F(x) = 'lit'` — so a check reading "does my backend match the reference?" would have
reported the correct backend as broken, and a check reading "do they agree?" would have
reported a *shared* bug as a pass.

> **A diff against an oracle is only as good as the oracle. The only thing separating "my
> backend agrees with the reference" from "my backend agrees with the reference's BUG" is
> measuring something the bug has to SCALE with.**

The fix was to take the figure at **two iteration counts and compare the slope**, not the
value: 0 → 1032 bytes, 1000 → 41032, 10000 → 401032. A constant offset is allocator
bookkeeping; a slope is a leak. Two independent oracles then confirmed the direction (same
source to wasm32 gives 1032; FPC's `GetHeapStatus.TotalAllocated` gives 0).

**Attempt one is worth recording too**: comparing `PXXAlloc(64)` addresses produced 72 vs 112
and *neither build was leaking* — free-list bookkeeping read as a signal. **Three attempts to
get one assertion that asserts the thing.**

**Rule: when diffing against a reference implementation, assert a PROPERTY the bug must
violate (a slope, an invariant, a bound), never equality with the reference.** Equality
inherits the reference's defects silently, and this repo has now been on both sides of that:
the reference was right when it caught face six, and wrong here.

---

## FACE EIGHT — an assertion wrong in BOTH directions at once

Previous faces are wrong in one direction: they cannot fail, or they fail on the right
answer. This one is vacuous **and** false-positive simultaneously, and it was green on first
run.

frankwasm wrote a grep for an `i32.load` before a `PXXStrSetLen` call, intending to catch
slot-vs-handle confusion. Measured:

- **Vacuous for both shapes it could see**: a global's slot address is an `i32.const` and a
  local's is `fp+N`, so **no load ever appears** — the assertion could never fire.
- **False-positive for the one shape it could not see**: a `var s: string` parameter's slot
  address legitimately *is* a load, so correct code would have failed it.

An assertion can be simultaneously unable to detect the defect and able to reject the fix.
Neither half is visible from reading it; both came out of asking what it was quantified over.

**It was caught by the rule from the previous slice** — *when a negative control passes on
first write, check what unit it is quantified over before believing it.* That is now two
consecutive slices where "passed immediately" was the tell, which makes it a reliable trigger
rather than an anecdote.

---

## The family has TWO POLARITIES, and the second one was hiding in plain sight

Every face above is **a check that cannot fail**. The same defect exists inverted: **a signal
that can never go clean.**

Three `IInterface` methods are declared without implementations. The RTTI names them, so a
function index must exist, and each gets `unreachable` because calling one must trap. **That
is correct code, not missing code** — and it was counted into the broken total and announced
under *"op coverage is incomplete"* on every program linking the interface RTTI. The per-body
reason already said *"normal for a method DECLARED without an implementation."* **The headline
did not, and the headline is the half that gets read.**

The consequence is structural, not cosmetic: the completion criterion for that backend is the
count reading N of N, and three permanent non-defects made N of N **unreachable by
construction**. A signal that can never go clean is a signal nobody reads — the slow version
of crying wolf, arriving from the opposite side.

> **A check that cannot fail and a signal that cannot go clean are one defect in two
> polarities. Both are states that carry no information, and both train the reader to stop
> looking.**

Fixed by splitting the line rather than hiding the stubs: gaps claim incompleteness,
declaration-only stubs do not, both stay listed. Two corpus programs now report *"op coverage
is complete for this program"* — **which was true before the change and which nothing said.**

---

## FACE NINE — an inert flag, and it lived in a COMMENT

New location for the family: not in a check, but **in the comment explaining why a check was
sound** — the layer nothing tests.

`check_host.sh`'s node:wasi arm called `wasi.initialize`, which node refuses on a module
exporting `_start`. Its comment said this was fine because the caller compiled a second module
with `-dWASM_NOMAIN`, and added that reactor-ness *"is a property of how it is COMPILED, and
now it says so."*

**`host_slice.pas` did not contain the string `WASM_NOMAIN`.** The define was inert. Both
builds were the same program, and the arm had worked only because nothing we emitted exported
`_start`, so every module looked like a reactor to node. **The comment asserted a property of
the build that the build did not have**, and had done so for weeks.

> **AN INERT FLAG IS INVISIBLE FROM THE OUTSIDE.** A misspelled or unread define does not
> warn. The build succeeds and produces a module that is simply not the one you asked for.

**The guard is the same one that catches a vacuous assertion:** if a flag is supposed to change
the output, the check passing it must be able to **fail without it**. Here that took one line
and one rebuild — and the moment the define became load-bearing, **a second arm went red**,
because it had been quietly relying on the same module still running its body. One inert flag
was propping up two arms.

Note the fix that was **refused**: suppressing `_start` under the define would have kept the
old framing alive by *inventing a compiler flag to serve a test's story* — when the story was
the thing that was wrong. Nothing this backend emits is a reactor (const initialisers alone
produce a main wrapper), so `initialize` is refused by design and the arms moved to
`wasi.start`.

**A second WASI instance of the same family, worth recording next to it:** WASI errno numbering
is **alphabetical** — WASI 2 is `EACCES` where Linux 2 is `ENOENT`. Passing the number through
turns every missing file into a permission error, and **both are non-zero**, so any check
asking only *"did it fail?"* agrees with the bug. Same shape as the coverage count that
measured lowering rather than correctness: the predicate is true, and true of the wrong
question.

---

## FACE TEN — an unfiled GRANT, which reads as covered

Face nine was an inert flag asserted in a comment. This is its sibling one level up, and it
was found by pulling on face nine's thread.

A shared-file edit on a branch was authorised in conversation and **its only record was the
commit message of the change it authorised.**

> **A grant recorded only in the commit that used it is not a record. The commit is the thing
> being justified; it cannot also be the justification's index.**

Why it is this family and not mere untidiness: **an unfiled grant does not read as missing —
it reads as covered**, because a neighbouring ticket covers the same *file*. `compiler.pas`
had a real ticket authorising three of its five edits, so a reviewer checking "is compiler.pas
accounted for?" gets **yes**, and the two unauthorised edits are invisible. The absence is
indistinguishable from presence, which is the family's signature exactly.

Measured outcome when the thread was pulled: **master's record covered three of eight arms.**
The report said four arms in three files; the diff said eight arms in four files; and the two
agreed on everything except the thing that mattered.

**`check_tickets.sh` makes an unfiled TICKET unrepresentable. It cannot see an unfiled GRANT.**

### The enabling condition: a ledger that lives on the branch is not a ledger

The lane's merge set was read off an escapes table in the branch's own `CHARTER.md`, untouched
since Phase 1 — still saying the exception mechanism was "not yet taken" three phases after it
was taken, with no row for two of the files. **Invisible to master, to the ranker, and to a
merge reviewer.** Exactly what `check_tickets.sh` exists to prevent for tickets, one level up.

Fix in place: the master ticket is the ledger
(`feature-a-merge-the-wasm-branch-the-shared-file-arms`, p40, ranked); CHARTER's table is
marked a convenience copy; and the ordering rule is written down — **when you take an arm it
goes to the master ticket in the SAME PUSH, then it is mirrored to the branch.**

### The coordinator's half, which is the half that generalises

**The grants were mine, and I never required a ticket for any of them.** All session I have
enforced *"a finding is recorded when it is in a ticket on master; a message is transport"* —
on two lanes and on myself. I applied it to **findings** and exempted **my own
authorisations**, which is the same shape as applying a rule to the code under test and not to
the test.

**An authorisation is a finding about what is permitted.** It decays the same way, is invisible
in the same places, and needs filing by the same rule. A coordinator who grants an exception
without filing it has produced exactly the artefact this ticket family is about: a permission
whose absence from the record is indistinguishable from its presence.

---

## FACE ELEVEN — a correction that did not travel to the copies

A refusal read *"needs the heap, Phase 6."* Phase 6 shipped the heap. The refusal stayed
**correct** and its stated **cause** stopped being true — what is actually missing is the
dynamic-array LAYOUT (descriptor, refcount, length, element arithmetic, `SetLength`,
copy-on-write), none of which the heap provides.

The sharp part is not the stale reason — that is face five. It is that **the file already
carried a note retiring that exact phrase**, written earlier by the same author when they found
it was an assumed cause rather than a measured one. **It was retired in one place and left
standing in two others**, including a calls note asserting that every builtin needs the heap
while `SetLength` on a string lowers today.

> **Correcting a wrong reason where you found it does not correct it where it was copied to.
> Grep the phrase, not the site.**

**This repo already has this rule for CODE** — `CLAUDE.md:338`, from
`normalise-dont-special-case.md`: *"if you fix a bug on one arm of a double case, grep for the
sibling before closing the ticket."* The finding is that it applies identically to **prose**:
comments, refusal messages and stated causes get copied exactly like code paths do, and nothing
greps them.

Place it beside *"applied the rule to the code under test and not to the test"* rather than
under it — that one is **a rule not carried across kinds**; this is **a correction not carried
across copies.**

---

## A planning instance: a list of gap NAMES carries no magnitude

Not a check, but the same disease in the artefact that orders work. Five gaps were reported as
roughly comparable. Measured on `compiler.pas` compiled for wasm32 — 3647 bodies, 2056 lowered,
1591 refused — they are not:

| gap | share |
| --- | --- |
| dynamic-array family (incl. open-array params, `SetLength`, `Length` of a Pointer) | **83%** |
| set membership `in` | 8% |
| `IR_DEFAULT_MEM` | 7% |
| record via `RetViaHiddenDest` | **5 lines** |

**Record returns read as a peer of dynamic arrays on the name list and are five lines.**
Ordering the phase off that list would have spent it on items worth under a percent each.

And the label that hid it: `in` was reporting as **`builtin unrecognised (-999)`** — *the one
label that tells a reader nothing about how big a gap is.* Named now and confirmed by repro
(`if i in [1,2,3]`) rather than inferred from the constant.

> **A list of gap names carries no magnitude, and magnitude is the only thing that orders
> work.** Same shape as diff-versus-summary, pointed at planning.

### CORRECTION 2026-08-28 — the histogram above is a FIRST-REFUSAL count, not a gap size

Left visible rather than edited away. The table is real and its framing was wrong, and the
wrongness was mine to catch: **a body reports its FIRST refusal and stops**, so the histogram
ranks what each body *reached*, not what it is *missing*.

Measured after the dynamic-array slice shipped:

| | before | after |
| --- | --- | --- |
| lowered | 2056 | **3222** of 3650 |
| refused | 1591 | 428 |
| `in` | 68 | **267 — UP, and nothing about `in` changed** |
| `IR_DEFAULT_MEM` | 59 | 74 |
| open-array param | 23 | 30 |

**Removing the leader does not subtract its share — it PROMOTES everything the leader was
masking.** 1163 bodies were stopping at a dynamic array before they could discover they also
needed `in`.

So *"one feature at 83%, then a tail"* was right about the leader and wrong about the tail, in
the direction that matters: **the tail was not small, it was hidden.** The honest claim is *83%
of what programs hit first*.

**And the least trustworthy number in such a table is the smallest one** — "record returns are
five lines" was the punchline of the version above and is the most masked entry in it. A tail
item's count is a lower bound, not a size.

> **A HISTOGRAM IS A MEASUREMENT AND IT STILL MISLED, because the quantity it counts is not the
> quantity it appears to count. Measuring the right thing is a separate act from measuring.**

That is the sharpest form of this family yet: the fix for *"a name list carries no magnitude"*
was to take a measurement, and the measurement's **framing** was then trusted without asking
what it was a count OF.

---

## FACE TWELVE — a ONE-DIRECTIONAL instrument

An arena-slope probe detects refcounts that are too **HIGH** — a leak. It is blind **by
construction** to refcounts that are too **LOW**, which is a premature free: the direction that
**corrupts** rather than wastes.

Found because a deliberate break passed. Removing a retain makes refcounts too low, and every
assertion in the suite pointed the other way. Worse, it is **invisible in the output until the
freed block is REUSED** — the stale bytes survive and the wrong build prints the right answer.
The assertion that catches it allocates a same-sized array between the free and the read.

> **An instrument that can only be wrong in one direction reports "clean" for the entire
> opposite half of the defect space, and nothing in its output says which half it covers.**

Distinct from face seven (diffing against a buggy oracle): there the instrument was sound and
the *reference* was wrong. Here the instrument is sound, the reference is sound, and the
instrument's **sensitivity is one-sided**.

**Consequence, disclosed and not yet measured:** three phases of managed-string work shipped
with only the leak half of that pair. Filed as
`chore-a-audit-the-managed-string-slices-for-the-premature-free-direction` — as a measurement
task, not as a bug, because nobody has measured it.

---

## FACE THIRTEEN — two arms that share an upstream

Polarity: **a signal that cannot go dirty.** A differential test compares two
implementations and reports disagreement. When the two arms share an upstream — a parser, an
AST, an IR — a defect in that upstream makes **both sides wrong identically**, and the
differential is green.

Measured the same hour as its own counter-example. A set-membership item constant funnels
`Int64 → Integer → Int64` through one `var` line in the Pascal parser: `1 in [4294967297]` is
TRUE on **all five targets**, so no cross-target diff can see it
(`bug-p-set-membership-item-constant-truncated-to-32-bits`). Its sibling — i386 and arm32
truncating the *test value* — is a genuine cross-target divergence and a diff catches it at
once (`bug-a-set-membership-truncates-the-test-value-on-32-bit-backends`). **Same feature,
same session: one visible to the method, one invisible to it, and nothing in the output
distinguishes the two cases.**

> **AGREEMENT BETWEEN TWO ARMS THAT SHARE AN UPSTREAM CARRIES NO INFORMATION ABOUT THAT
> UPSTREAM** — so a green pxx-vs-pxx run is evidence about the backends and about nothing
> above them.

Kin to face twelve and distinct from it. Face twelve: an instrument sensitive in only one
**direction**. This: an instrument blind over a **region** — everything the two arms hold in
common. Both answer "clean" for a defect class while looking exactly like a passing run.

The caution now lives where the violator will open it — the limits section of
`devdocs/dev/differential-probes.md` — because in a ticket it is a fact, and in that file it
is a check.

---

## FACE FOURTEEN — a CONFIRMING measurement of the wrong configuration

The known hazard is that a proxy can mislead. The sharper one, and the reason this is a face
rather than a footnote:

> **A PROXY WILL OFTEN AGREE WITH THE STALE CLAIM YOU WERE CHECKING, AND AGREEMENT ENDS THE
> INVESTIGATION.**

Measured 2026-08-28. `feature-random-library` claimed *"riscv32 cannot build this unit at
all"*. The re-measurement **confirmed it** — and was wrong: it used the default platform units,
while the Makefile builds that target with `--platform=esp`. Under the shipping configuration
the unit builds, exit 0; the atomics refusal is specific to **hosted** riscv32. Caught only by
re-reading what had been measured, not because anything looked odd.

**Confirmation and refutation are not symmetric in cost.** A wrong-configuration measurement
that *disagrees* provokes a second look and corrects itself. One that *agrees* is absorbed as
verification and closes the question — so the wrong-config measurements that survive are
precisely the ones that happened to agree. Nothing in the output distinguishes *"the claim is
true"* from *"I measured something else and it happened to match."*

Practical form: **name the configuration before reading the result**, and treat a
re-measurement that confirms an old claim as the case needing a second read, not the case that
just closed. The same day produced the coordinator's mirror image — a search in the wrong
directory returning silence, which reads exactly like a refuted claim.

**Sharpened by frankB the same night, and its version supersedes the framing above.** This is
not a property of *proxies*, and it is not a property of *silence* either — those are two
surfaces of one mechanism:

> **A RESULT FROM THE WRONG SYSTEM THAT HAPPENS TO MATCH THE EXPECTED SHAPE OF THE CLAIM UNDER
> TEST TERMINATES THE CHECK.**

Both polarities, measured within an hour of each other: a wrong-**configuration** build
returned an *error* and the error read as confirmation; a wrong-**directory** grep returned
*nothing* and nothing read as refutation. Opposite signals, same mechanism — each matched the
shape the checker was braced for, and the investigation stopped.

That formulation is what makes a four-character directory ambiguity worth a ticket rather than
a note: it is a **standing generator** of such results, sitting in the tree people search to
verify each other (`decide-two-devdocs-directories-make-a-wrong-grep-look-like-a-refutation`
[U p30]).

Kin to face thirteen: there, two arms that share an upstream agree without evidence. Here, one
arm and a stale claim agree without evidence. Both are **agreement carrying no information**;
thirteen is structural, fourteen is procedural — and fourteen is worse, because it recruits
the investigator into stopping.

## Face fifteen — a control that reports "no effect" on an axis nobody chose

Contributed by frankwasm, 2026-08-28, out of the wasm32 `WasmText` memory fix —
and volunteered as a self-correction, not extracted from it.

Three synthetics were built to reproduce a 7 GB blowup and **all three measured
flat**: 3200 procedures, 1600 `in` expressions, a library-heavy program. Two of
them were reported to the coordinator as controls. The fourth attempt found the
bug immediately. The difference was not scale or luck:

> All three varied body **count** and held body **size** near zero. The defect is
> O(n²) accumulation *within a single procedure body*, so its magnitude is set by
> the largest one body — an axis none of the three touched.

Each synthetic executed correctly and reported truthfully. There was simply no
relationship between what they varied and what the bug depends on.

**A control that reports "no effect" is worth exactly what its axis is worth, and
nothing in its output names its axis.**

The family signature in its purest form so far — a flat reading from a control on
the right axis and a flat reading from a control on the wrong one are the same
bytes. And it is the most dangerous face yet for a reason the others do not
share: **face twelve produces silence, face fourteen produces a wrong-looking
right answer, but this one produces ENCOURAGEMENT.** A blind instrument fails
inside its own axis; these succeeded perfectly, elsewhere. "We tested it and saw
nothing" is how three wrong-axis controls sound, and it is also how three
right-axis controls sound.

Distinct from face twelve (an instrument blind in one direction), which is about
a gap *within* the axis under test. Here the axis itself was never chosen — it
was inherited from whichever knob was easiest to turn, which for a compiler
synthetic is almost always *count*, because generating 3200 of something is one
loop and generating one enormous something is a different generator.

**Practical form:** before a null result is allowed to reassure anyone, state the
axis it varied and the axis the hypothesis depends on, in the same sentence. If
they are not the same word, the control has not been run yet.

Fifteen faces. **Still open — never write "all fifteen".**
