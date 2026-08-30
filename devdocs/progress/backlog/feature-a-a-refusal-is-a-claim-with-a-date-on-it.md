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

## Face sixteen — a decision that is never reached has been decided by arithmetic

Contributed by pxx-a5, 2026-08-28, on its own ticket, one hour after filing it.

A `decide-*` ticket filed at **p25** behind that lane's p55 / p50 / p45 will not be
reached. Its author's formulation:

> **never-reached is not neutral. It silently selects option 1, the status quo. A
> decision made by queue position instead of by judgment.**

The signature, exactly: **"we considered this and kept the current behaviour" and
"nobody ever looked" produce an identical repository.** Nothing in the board, the
ticket, or the code distinguishes a deliberate status quo from an unexamined one.
The ranked queue is an instrument, and on this reading it returns the same value
for both.

**Why this is a face and not another instance of face ten or of "a trigger nobody
watches".** Face ten is an *absent* record reading as covered. A never-reached
decision is a **present, correct, well-written record that is inert** — the
paperwork is perfect and the outcome is identical to having filed nothing. And
unlike the trigger case, nothing here fails to be evaluated: the ranker runs
correctly, every tick, and its correct output is the silent selection.

**The new instrument is the board itself**, which is what makes it worth a number:
every other face lives in code, comments, tests or measurements. This one lives in
the process that decides what gets looked at — and it therefore has an operational
consequence for whoever holds the queue.

**Consequence: a `decide-*` must not be ranked like work.** Work at p25 is work
deferred. A *decision* at p25 is an answer already given. So a decision ticket has
only two honest states:

| | |
| --- | --- |
| worth deciding | rank it where it will actually be reached, or route it to the owner |
| not worth deciding | **close it as decided** — record that the status quo is the answer, and say who decided |

Parking it low is the third state, and it is the one that lies. Whoever holds the
ranked queue should read a low-prio `decide-*` as a **status-quo selection awaiting
a signature**, not as a backlog item.

Sixteen faces. **Still open — never write "all N".**

### Boundary on face sixteen — it is about DECISIONS, not about work

Marked by pxx-a5 immediately after the face was filed, and it belongs here because
without it the face argues for exactly the thing the ranker exists to prevent.

**"Never-reached is not neutral" is true of decisions and false of work.** A p25
*bug* that nobody reaches stays a p25 bug: the repository is honestly worse, and
visibly so. A p25 *decision* is different because **the status quo executes while
you wait** — the option is being taken, continuously, by everyone who runs the
code.

> **The distinguishing property is whether waiting produces an outcome.** Only
> decisions have that.

Read without this boundary, face sixteen becomes an argument for inflating every
low-ranked item, and a `prio:` used to buy attention stops meaning anything. **The
value of the field is that it is not a volume knob.**

Two nearby mechanisms, both considered and both rejected by the same author on its
own ticket: a **prio bump** (no evidence of cost — see above), and **`keep-open:`**,
which `progress.py:1232` shows is for a `decide-` that *records an answer* while
gating a dependent. On a genuinely undecided question it would be the honest-looking
marker on the dishonest state.

The honest instrument was none of those: **state in the ticket that option 1 is in
force until answered, that this is a default rather than a judgement, and what would
move it.** A reader can then tell that low was *chosen*.

## Face seventeen — an instrument's SCOPE is invisible in its own output

Three instances on 2026-08-28, from **three sessions that did not coordinate**,
found within about an hour of each other. Each is a different instrument; the
shape is identical, and it is the family signature in its plainest form — *two
different conditions produce the same reading.*

| the instrument | its reading | the two conditions that produce it |
| --- | --- | --- |
| a census over `include/**` (Track B, crtl) | "358 declared, all defined" | the symbol is **defined**, and the symbol was **never declared** so there was nothing to enumerate |
| a survey of the four gate tiers (coordinator, `-O3`) | "no `-O3` failures" | `-O3` **passed**, and `-O3` **was never run by the tiers I read** |
| a design log read instead of the tree (Track B, socket facades) | "never built" | it was **never built**, and it was **built by a route the design does not describe** |

In every case the reading is *true of what the instrument measured* and false of
the question asked. And in every case **nothing in the output names the
boundary** — the census does not say "declared symbols only", the tier reports
did not say "in these four tiers", the design log does not say "as of when I was
last edited". The scope exists, it is knowable, and it is simply not carried
alongside the result.

**Why this is a face and not just an error.** The other faces are about a
*signal* that cannot distinguish two states. This one is about the **instrument**
being unable to report its own aperture, so a correct reading arrives with no
handle by which to doubt it. It generalises the two-arms-one-upstream problem
(face thirteen) one level up: there, the shared upstream was hidden; here, the
aperture is.

**What actually caught all three:** in each case someone reached for a *second
instrument of a different kind* — a live re-run rather than a recalled number, a
file's **history** rather than its contents, an `ls` rather than a design log.
Not a more careful read of the first instrument. A more careful read cannot find
this, because the first instrument is not wrong.

**The operational form**, and the reason this is worth a face rather than a
sentence: *before trusting an absence, state what the instrument could not have
seen.* If that sentence cannot be written, the absence has not been measured. It
is the same rule as *an existence claim survives one grep; a non-existence claim
does not*, but pointed at the tool instead of at the searcher.

Instances: the crtl census (parked in `rainy-day/` rather than closed, precisely
on this reasoning); this repo's `-O3` promotion block, lifted in
`feature-opt-o3-register-pressure` after `chore-t-nothing-in-the-matrix-runs-o3-so-no-failures-is-unfalsifiable`
resolved **by refutation** (`c8ec8a1b3`); and
`feature-b-posix-and-fpc-named-socket-facades` (`f2d76bc30`), whose own filer
corrected it the same day it was filed.

A fourth, adjacent and from the same day, is worth listing here because it is the
**prose** variant: a *"stalled because X"* note in a ticket body ages into a false
claim invisibly — `feature-pascal-corpus-oop` headed Track P at p75 on a stall
note whose three clauses had each been false for a week (`cc36aeb5a`). Resolving
a blocker is an event on the **blocker**; the note lives on the **dependent**; and
`progress.sh check` reads frontmatter, so it cannot see prose. Same aperture
problem, with time rather than file-set as the axis.

**Seventeen faces, and the family is still open.**

### Worked instance of face seventeen — a green from an adjacent lane reads as coverage of work it never touched

pxx-a5, 2026-08-29, volunteering a negative nobody asked for.

It ran two quick tiers that evening; both green. frankB had converted 2476
Makefile assertions the same day, none of them suite-executed. **A green tier
from the Track T lane, on the same repo, on the same evening, is exactly the
thing that would be mistaken for coverage of those conversions** — by any lane
reading the board, and by the coordinator relaying it.

It checked instead of letting it stand: **`test-quick`'s 208 recipe lines use
`expect_same.sh` exactly ZERO times**, and its tree at the sha it ran carried
only the 498 cross-target conversions, none of the 1978 native ones. So the
2476 remain exactly as unexecuted as claimed, and nothing it ran that evening is
evidence about them.

**The shape.** A green run's report says what passed. It does not say what it
touched, and the two are indistinguishable downstream — a passing tier and a
tier that never reached the code both produce the same green. Face seventeen
says an instrument's scope is invisible in its own output; **this is that
failure crossing between lanes**, where it is worse, because the reader has no
access to the run's contents at all and only sees the verdict.

**The guard, and it is a habit rather than a mechanism:** when your green sits
adjacent in time or subject to someone else's unverified work, **state what it
does NOT cover, unprompted.** The cost is one grep. The alternative is that
absence of a contradiction gets read as confirmation, and nobody ever asks,
because nothing looks wrong.

Same session, the same lane also declined to treat a freed constraint as
permission: told that plexus's cores had come free, it re-read the load
(4.30/8.84/10.71 against 12 cores), noted six sessions were still live and that
the owner's standing instruction is to leave roughly half the CPU free, and
**wrote the changed fact into its two blocked measurement tickets instead of
launching the sweeps** — so the next reader re-reads the load rather than
inheriting "blocked on a busy box" as a standing truth. *A peer's read on what
is affordable does not outrank the owner's instruction*, and a stale blocker in
a ticket is the same failure family one level up.

### Refinement of face twenty-three — a number the check PRINTS but never TESTS is decoration

frankwasm, 2026-08-29, auditing its own 22 oracle comparisons after face
twenty-three landed. Every one of them **printed** a count. **None asserted
one.** 18 of 22 decided purely by `diff -u native.txt wasm.txt`, and two empty
files diff equal — so the check would print `ok wasm matches the native build
(0 lines)` and pass. Only three had per-row assertions underneath the diff.

> **The printed count was there the whole time and was read as a denominator.
> It is a denominator for a HUMAN reading the log, and no part of the verdict.**

This is the trap inside the remedy. Face twenty-three's guard is *make the
instrument report its N* — and a harness can satisfy the letter of that while
the N participates in nothing. Reporting is not asserting. **If the count is not
in the exit code, it is a comment.**

Not hypothetical on that target, which is what moved it from tidy to necessary:
`PXXSysWrite` returning 0 having written nothing was a real state there —
`writeln` lowered correctly and printed nothing — which is why the phase slices
assert silence. *"The oracle produced no output"* is a condition this backend
has actually been in.

23 guards added, one per comparison, and falsified in **both** directions with
the oracle forced silent: with the guard it fails naming the reason; with the
guard removed it prints "ok wasm matches the native build" over two empty files.
The control has failed once.

## Face twenty-five — a justification that is true of the ADJACENT construct reads as true of this one, and a comment makes it durable

Found by frankwasm, 2026-08-29, in its own RetViaHiddenDest work.

**The instance.** Its first working version put the aggregate copy **after** the
epilogue restored `$sp`, on reasoning it had written into the comment beside it:
*every slot is addressed through `$fp`, so a restored `$sp` cannot move them.*

That statement is **true**. It is true of the scalar load sitting next to it. It
is false here, because this is a **CALL** — `PXXMemMove`'s own prologue sets its
frame at `$sp`, which once raised lands exactly on top of the `Result` local it
is copying out of.

**What the machinery said about it.** It compiled. It validated. It reported
**125 of 125 bodies lowered**. It ran to completion. It returned `x=3 y=8` —
`y` holding the byte-count argument of the memmove that had just overwritten it.
Every instrument in the chain was satisfied. **Only the differential against
native said otherwise.**

**Why the comment is the aggravating factor rather than a mitigation.** A
documented trap is not a guard — that is already recorded. This is worse: the
comment is not a warning, it is a **justification**, and it is a correct one
about the neighbouring case. So it does not read as an assumption to be checked;
it reads as an argument already made. The next reader inherits a conclusion with
its reasoning attached, and the reasoning is sound — for the line above.

> **Resemblance transfers reasoning across a boundary that reduction would have
> found.** The scalar load and the aggregate copy look like the same operation
> at that point in the epilogue. One is a load; one is a call with a frame.

**The guard.** When you write down *why* something is safe, name the property
that makes it safe and ask which neighbouring constructs lack it. Here the
property was "does not establish a frame", and a call does. A justification
whose scope is not stated is a justification that will be applied one line over.

## Face twenty-six — a red for a HOST reason masks a real regression in that job, permanently, and reads as still-red rather than as coverage loss

Found by `seven` (Track T), 2026-08-29, in its own first baseline — and it
refused to leave it as a baseline, which is the finding.

**The instance.** A new watcher box published its first verdict: 1646 jobs,
1630 pass, 15 red. Every one of the 15 is **host coupling**, not a repo defect —
4 gtk (no dev packages), 3 sqlite3, 3 tcl/tk, 1 `Illegal instruction` from
`RDRAND` on a **Xeon E5645 (Westmere, 2010)** that predates the instruction, and
4 under triage.

The tempting move is to accept them as this host's baseline and diff future runs
against it. **That is the trap:**

> **A job that is red for a host reason is not a neutral constant. It masks a
> real regression in exactly that job, permanently — and it reads as STILL-RED
> rather than as COVERAGE LOSS.**

Once `test_sqlite_crud` is red because `libsqlite3-dev` is absent, it is red
forever, and a genuine sqlite regression landing later changes nothing anyone
can see. The baseline diff says "no new reds". It is the never-changed-number
failure wearing a red coat instead of a green one.

**And it is strictly worse than a SKIP.** A SKIP announces that it did not run —
this repo's own tooling prints `coverage — N job(s) SKIPPED on seven (absent
corpus or unmet precondition): green here does not cover them`. A host-coupled
red announces nothing, because the report distinguishes reds by *count*, not by
*cause*. **The failing state is indistinguishable from the state it hides.**

| condition | how the matrix reads |
| --- | --- |
| job red because the host lacks a package | 1 red, unchanged from baseline |
| job red because the host lacks a package AND a real regression landed | 1 red, unchanged from baseline |

**The two correct responses, and they differ by fixability.** Where a package
closes it (`libgtk-3-dev`, `libsqlite3-dev`, `tcl-dev`, `tk-dev`, `csmith`), the
red is provisioning debt and should be *fixed*, not baselined. Where no package
can — the missing `RDRAND` is a permanent property of 2010 silicon — it must
become a **documented host-capability exclusion**, so the job reports as *not
applicable here* rather than as failing. An exclusion is honest about coverage;
a permanent red is not.

**The general form.** *Any per-environment failure absorbed into a baseline
converts a coverage gap into a silent one.* The gap is real either way — what
baselining removes is the ability to ever notice it again.

## Face twenty-seven — the repro that found the bug is, by construction, the shape that reaches the code you changed

Found by frankB, 2026-08-29, fixing the x86-64 comparison leak — and the finding
is what it did NOT do.

**The setup.** The ticket said `if F(x) = 'lit'` leaks 40 bytes per iteration and
supplied a repro measuring 401032 bytes over 10000 iterations. Attach the release
to the string-comparison emitter call, re-run the repro, watch it go flat. Done.

**Why that fix would have been wrong while measuring perfectly.** Two of the three
comparison blocks carry **inline `AnsiString`-vs-`Char` arms that compare in place
and never reach the emitter at all.** So `F(x) = 'c'` — a Char literal — takes a
different path from `F(x) = 'one'`, and a release attached at the emitter call
would have left it leaking.

**The ticket's repro cannot detect that, and no repro of that bug could.** A repro
is written to *exhibit* the defect, so it necessarily travels one path to it. The
fix site is then chosen to satisfy that path. Verification re-runs the same
repro. **Every step is downstream of the single shape that happened to be
reported**, and the sibling shape is invisible at all three.

| condition | what the repro shows |
| --- | --- |
| the leak is fixed for every shape | flat at 1032 |
| the leak is fixed for the shape the repro uses | flat at 1032 |

frankB wrapped the save/release around the whole block instead, so the inline
arms are covered too.

### The sharper form (frankB, same evening) — three checks that were one check

> **"The repro, the fix site and the verification were not three independent
> checks — they were one check counted three times."**

A repro travels the single path that exhibits the reported shape. The fix is
placed to satisfy that path. Verification re-runs the repro. Three steps, all
downstream of whichever shape happened to get reported first — so the apparent
redundancy is zero, and it *feels* like defence in depth.

**What broke it was not care at any of the three steps.** It was asking a
different question entirely — *what other shapes reach this code* — which is a
question none of the three can pose about itself. That is why the answer was
`F(x) = 'c'`, **a program nobody had written down anywhere**: not in the ticket,
not in the repro, not in the test suite.

The operational form: after a fix verified by the reporting repro, ask what
*else* reaches the changed code, by reading the dispatch rather than by running
anything. If two arms reach it and your repro exercises one, you have tested
half of what you changed and all three of your checks say you tested it fully.

**And the ticket named the wrong site.** It asked for `EmitStrCmpReg`; the leaking
emitter is `EmitAnsiStrCmpReg`. A release in `EmitStrCmpReg` is **provably dead
code** — it is the `else if` after the `tyAnsiString` block, so neither side can
be `tyAnsiString` and a `tyString` owns nothing. It *"would have looked like the
fix, changed no emitted byte, and left the leak running."* The block now carries
a comment saying so and naming what would make it needed — which is the right
artefact, because the next reader's question is exactly "why is there no release
here".

**Two instrument checks in the same fix, both of which could have inverted it:**

- **A naive opcode grep reads machine code as text.** Its first instrument
  reported a stray `push rax` in two emitters. Those `$50` bytes are ModRM in
  `mov rdx,[rax-8]`. Had it been believed, the emitters would have looked
  stack-dirty and the save slot unusable.
- **`-O3` W1 could have made the save write garbage.** `w1RightReg` can place the
  right operand in `r12..r15` rather than `rcx`, which would make `mov [rsp], rcx`
  save the wrong pointer and release it. Confirmed unreachable structurally *and*
  measured at every `-O` level — because **"it passes at `-O3`" would not have
  shown whether the W1 path was exercised at all.** Face twenty-three, applied to
  an optimisation gate.

**The sibling census was done by code, because the ticket's line numbers were
stale** (it cited aarch64 at 1541/1631/1680; the pairs are at 1824/1914/1963).
All five backends release at all three site kinds; the inline Char arms exist on
x86-64 **and i386** and nowhere else, and i386 was measured directly, already
flat. *No second arm left broken this time* — which is the standing instruction
after this bug's own mirror image went the other way.

**And the residue was left open rather than closed quietly.** The predicate is
still hand-copied twelve times across the four cross backends; x86-64 went from
three copies to one. A shared hook reaches outside the allocated file, so it is
recorded as the sixteenth-copy problem rather than closed with six copies and no
note.

## Face twenty-eight — a guard whose message conflates NONE with MANY, and the arithmetic that caught it

frankB, 2026-08-29, closing the assertion campaign. Its ambiguity guard existed
to refuse any line where the separator ` = ` occurs more than once, since the
split would be ambiguous. It flagged `Makefile:14309` as **an ambiguous
separator**.

It was not ambiguous. That line spells the separator `"   = "` with extra
spaces, so the guard counted **zero** occurrences — and its "not exactly one"
test fired with a message that says *many*.

**The skip was correct. The reason given for it was false.** And that is worse
than no message at all, because **a named cause stops the next reader
looking.** "Ambiguous separator" is a complete, plausible explanation that
closes the question; "skipped, reason unknown" leaves it open. The same
asymmetry as the false-limit rule, inside a single diagnostic.

| condition | message emitted |
| --- | --- |
| separator occurs 0 times (unrecognised spelling) | "ambiguous separator" |
| separator occurs 2+ times (genuinely ambiguous) | "ambiguous separator" |

**What caught it was arithmetic, not reading.** 24 convertible, 21 converted, 2
skipped — and 24 − 21 − 2 ≠ 0. The reconciliation failed, so the message had to
be wrong about something. **A count that must balance is an instrument that
cannot be talked out of its answer**, which is exactly what a plausible message
does to a human reader.

**The guard:** any predicate of the form *"not exactly one"* has two failure
sides and must say which one it saw. Report the count, not the verdict — the
same rule as face twenty-three, arriving from the diagnostic side rather than
the harness side. And **make the tallies reconcile**, because a residual is the
one check no explanation can satisfy.

**Footnote from the same run, worth knowing before someone re-greps:** the
campaign's final count of 7 remaining bare assertions is really 6. The seventh
is a line of **prose inside a comment** that contains `test "$$(prog | tail -1)"`
as an example. The classifier counted a comment as code — the same category
error as reading ModRM bytes as `push rax`, one layer up.

## Face twenty-nine — a broken instrument produces exactly the artefact the observer was warned to expect, and the warning was correct

Found by pxx-a5, 2026-08-29, while building `tools/verify_assertions.py` — and
it is the most dangerous shape recorded here, because every part of it is
someone doing their job well.

**The setup.** frankB converted 2476 Makefile assertions, none suite-executed,
and warned — unprompted, before any sweep existed — that **a wide red against
those shas would be ONE systematic cause, not 2000 regressions.** The
coordinator relayed that to both Track T faces in advance. Correct warning,
correctly propagated, and it is the reason nobody would have wasted a night
bisecting.

**What nearly happened.** pxx-a5's sampler emitted FAILs while it was being
written. Every one was **its own aperture**, not a defect: a producer sitting
before the *previous* assertion; a `2>&1` read as an output path; an unexpanded
`$(PXX_STABLE)`; a compile buried inside a quoted `hyperfine --command-name`; a
`printf` producer filtered out as bookkeeping. Each printed an **empty `actual`
under a confident MISMATCH banner.**

> *"Had I sampled and reported without chasing them, I would have handed you
> four to six phantom conversion defects **in exactly the shape you were braced
> for** — uniform, empty-output, spread across targets. It would have read as
> confirmation."*

**Why this is worse than an ordinary false positive.** A prediction had been
issued and widely relayed: *a uniform, systematic failure across many sites.* A
buggy sampler produces uniform, systematic, empty-output failures across many
sites — because that is what a broken harness always produces, not because
anything was wrong. **The prior does not merely fail to protect against the
false positive; it certifies it.** Everyone downstream — including the
coordinator who issued the warning — would have read the artefact as the
predicted event arriving on schedule.

| condition | artefact |
| --- | --- |
| the conversion has a systematic defect | uniform empty-output failures across sites |
| the sampler has an aperture bug | uniform empty-output failures across sites |

And the correct warning is what makes the second row unquestionable.

**The invariant that fixes it, and its necessary counterweight.** *Never FAIL on
an input that was not demonstrably produced.* Paired with a guard named
`t_a_real_mismatch_is_still_a_fail` — because **an instrument softened until it
cannot fail is decorative, not safe**, which is the failure the softening itself
invites. Both halves or neither.

**And two of its own guards passed VACUOUSLY**, found in the same pass: `"FAIL"
in out` is true of *every* run, because the summary line reads `0 pass, 0 FAIL,
1 skipped`. The guard's substring matched the report of there being no failures.
The checking layer written with less suspicion than the layer checked, again, by
the person who had spent the day cataloguing exactly that.

**The result, stated with its own scope**, which is the discipline the face is
about: 60 sites sampled at HEAD in a fresh scratch root — **59 pass, 0 FAIL, 1
skip** (`hyperfine` absent; a real gap, nothing installed to paper over it). Plus
17 statically-flagged anomalies confirmed by execution to be the sampler's own
`shlex` parsing. **Read as "no uniform defect is visible", never as coverage:
2416 sites were not executed and nothing in that run speaks for them.**

## Face eighteen — when the compiler is its own test input, a diff cannot tell a CODEGEN change from a SOURCE change

Found by frankwasm, 2026-08-29, and it nearly cost twenty lines of inert code.

**The situation.** It had a working fix that widened the `IR_LEA` array arm and
refined its deref discriminator. To decide whether the widening was load-bearing,
it compiled `compiler.pas` with both compilers and diffed the `.wasm` bytes. **They
differed.** That reads as proof the widening changed codegen.

**It did not.** `compiler.pas` *contains the file being edited*, so the two runs
differed in their **input** as well as in their **compiler**. A source change was
being read as a codegen change. The real fix is **twelve lines** — delete the stale
refusal and let `WasmNodeIsDynArray` answer yes for an open-array parameter, so
`Length` reads the header word the indexing beside it already read. Both parts of
the rework were then measured **inert**: with the narrow predicate only `ArrLen =
-1` symbols enter the arm, so the refinement is a no-op, and open-array params fall
through to a generic path that already emits exactly the one deref they need.

**Why it is its own face rather than an instance of thirteen.** Face thirteen is
two arms sharing an upstream. Here **the shared upstream is the artefact under
test**: the thing you changed is also the thing you fed in. That is not a mistake
anyone makes carelessly — it is structural, and it is **specific to a self-hosting
repo**, where "compile the compiler and compare" is the most natural measurement
available and is offered by the build system itself.

> **Every "compile `compiler.pas` both ways and diff" measurement in this repo
> carries this hazard.** The output differing proves *something* changed; it cannot
> tell you *which side*. And it fails in the direction that flatters the change you
> just made — a diff is what you were hoping to see.

**The fix is cheap and exact: hold the source fixed and vary only the binary.**
Doing that gave a **byte-identical** `.wasm` and settled it in one run.

### The adjacent control, and it belongs with this face

frankwasm ran a **determinism control first** — same binary, same input, three
runs, one sha — **before** trusting any diff.

> A control that fires on the feature's total absence proves the instrument can
> *detect*. This is the other one: **a control that establishes the instrument is
> STABLE, run BEFORE the comparison rather than after it surprises you.** Without
> it, "the bytes differ" cannot be separated from noise, and — the part that
> matters — you have **no reason to go looking for a third explanation.** It is
> what made the second measurement readable.

## Face nineteen — targets agree because they SHARE the property that absorbs the bug, not because the code is right

Found by frankwasm, 2026-08-29, writing up its own three instances — and the
write-up corrected the claim it started from, which is the interesting part.

**The instance.** An open-array-of-string argument is spilled through a hidden
temp `ir.inc:11207` declares `tyAnsiString` but which actually holds an array
data pointer (`bug-a-open-array-of-string-arg-spilled-through-a-managed-string-temp`).
On every register backend the mistyped retain and the scope-exit release
**cancel**: the program is correct, and stays clean under `PXX_HEAP_DEBUG`
across 2000 iterations. wasm32 type-checks the store rather than emitting a
machine word, so it is the only target that can see it at all.

**The claim I first made, and why it was too narrow.** I reported this as the
third shared-frontend mistyping "visible only to wasm32". Checking the lane's
own tickets before writing it down, that is **not** what the other two say:

| ticket | absorbed by | visible on |
| --- | --- | --- |
| open-array-of-string temp (today) | every register target, via ARC cancellation | wasm32 only |
| `procedure of object` hard-sized 16 bytes | 64-bit targets, where 16 is correct | **all five** 32-bit targets |
| `in` truncates a 64-bit test value | 64-bit targets, where no truncation occurs | i386 and arm32 |

Only the first is wasm-only. So the honest face is not "wasm32 is the oracle" —
it is one level up, and it covers all three:

> **A defect is invisible on every target that happens to have the property
> which makes it harmless.** Those targets then AGREE with each other, and
> their agreement reads as verification. It is not: they are not independent
> witnesses, they are one witness with several names.

**Why this is not just face thirteen.** Thirteen is two arms sharing an
upstream in the *code*. Here the shared upstream is a **property of the
targets** — 64-bit width, a register calling convention, an untyped machine
word — that nothing in the test output names, and that no one chose. x86-64,
aarch64 and the 64-bit path agree about a 16-byte method pointer because 16 is
right *for them*; that is not four confirmations, it is one.

**The operational consequence, which is the part worth acting on.** "It passes
on the default target" and even "it passes on three targets" carry almost no
information about a width- or convention-sensitive defect, because the default
set is not diverse along the axis that matters. The cheap counter is to ask,
before believing a green matrix: **what do these targets have in common, and is
it the thing under test?** Where the answer is "yes", one target of the other
kind is worth more than three of the same kind.

**Why the wasm lane keeps finding these, stated without flattering the lane.**
It is not that wasm32 is more correct. It is that wasm is the only target where
the *machine* checks the type instead of the calling convention assuming it, so
it is diverse along exactly the axis the register targets share. That makes it
a useful oracle for one class of defect and no better than any other target for
the rest — the same bounded claim face seventeen makes about an instrument's
scope.

**And the priority note, because it is invisible from the `prio:` field.** The
open-array ticket is p30 by its symptom, which is a single refused body on one
target. Its actual value is the diagnosis: it says a whole class of argument is
mistyped in the shared frontend. **The honest case for fixing it is the
diagnosis, not the symptom** — and a ranker that reads only severity cannot see
that, which is worth knowing about every ticket whose value is what it reveals
rather than what it breaks.

**Nineteen faces, and the family is still open.**

## Face twenty — a remedy already in force is indistinguishable from a remedy that worked

Found by frank-coordinator, 2026-08-29, on itself. Every face so far is about an
OBSERVATION carrying no information. This one is about an INTERVENTION.

**The instance.** frankB reported two suite runs killed by SIGTERM at line 352
and line 103 of ~1198. The coordinator proposed a cause (the tool's own
wall-clock, which SIGTERMs the process group on expiry) and a remedy: run it
backgrounded instead. The next run went green.

The remedy was already in place. All three runs had been backgrounded from the
start, so the clock blamed was never running on any of them — the hypothesis was
not merely wrong but inapplicable in principle. The coordinator had not asked how
the runs were being executed, and built a mechanism on an unstated premise.

**Why the green is the trap.** Had the remedy been "applied" — it required no
action, because it was already true — the green would have arrived exactly on the
schedule the wrong story predicted, and would have been read as confirming it.
Two conditions, one reading:

| condition | evidence produced |
| --- | --- |
| the remedy fixed it | next run green |
| the remedy was already in force and the cause was something else | next run green |

**Why this is worse than the observational faces.** A wrong diagnosis predicting
a RED gets retested, because the red keeps arriving and someone keeps looking. A
wrong diagnosis predicting a GREEN is *retired* by the green. **Nobody audits a
success.** The failure mode is not that the check is weak — it is that the case
is closed, with a cause on the record, and the real cause is still live.

Here it stayed live: frankB's kills remain unexplained, and would have been
filed as solved.

**The cheap guard, which is one question.** Before proposing a remedy, establish
that it is not already in place. Not *"would this help"* — **"is this currently
true?"** A remedy's value is entirely in the delta, and a delta cannot be
computed without measuring the starting state. The coordinator measured neither.

**The generalisation past this incident.** Any fix whose "confirmation" is the
absence of a symptom inherits this shape, and intermittent symptoms make it
routine: the symptom's own duty cycle supplies a confirming green on a schedule
that has nothing to do with the fix. That is the same reason a control is not a
control until it has failed once — an intervention is not evidenced until you
have seen the world without it, deliberately.

**Related and distinct.** Face nineteen: several witnesses agreeing because they
share the absorbing property. Face thirteen: two arms sharing an upstream in the
code. Both concern what an observation cannot distinguish. Twenty concerns what
an ACTION cannot distinguish — and the action's evidence is generated *after* the
belief exists, which is the direction that admits the most self-deception.

## Face twenty-one — an append to a path that does not exist creates it, and reports success

Found by frank-coordinator, 2026-08-29, in its own week-old work. Face twenty is
about an intervention whose evidence is ambiguous. This is about a WRITE that
lands somewhere other than where it was aimed and says nothing.

**The instance.** Two appends were addressed to `devdocs/progress/backlog/<slug>.md`
while the ticket lived in `backlog_new/`. The shell created the file. Both
appends reported success. The content really was written — to an empty-headed
orphan with no frontmatter and no body, while the real ticket received nothing.

| condition | evidence produced |
| --- | --- |
| appended to the existing ticket | exit 0, file present, content in it |
| created a new file at the wrong path | exit 0, file present, content in it |

**Why it lasted.** Every downstream reading agreed with the wrong one. The
ranker offered the slug twice at the same priority and flagged nothing. The
checker validated ticket *content* and never asked about the ticket *set*. And
critically, **both files read as coherent when opened alone**: the orphan looked
like a complete analysis, the real ticket looked like a correctly-filed bug, and
neither could announce the other. A reader lands on whichever the ranker offered
and gets a consistent, wrong picture.

**The general shape, past shells.** *Create-if-missing is a convenience that
converts a targeting error into a silent success.* It is the same trade every
`mkdir -p`, every upsert and every `?=` default makes, and each is right in the
case it was designed for. What it costs is the ability to say "that destination
was not there" — and that sentence is the only thing standing between an append
and an orphan.

**The cheap guard**, and it is the one that generalises: **when a write is
supposed to MODIFY something, assert the target exists first.** Not "did the
write succeed" — the write always succeeds. `>>` cannot distinguish appending
from creating, so the check has to happen before it, or the distinction is gone.

### Amendment to face twenty — frankB, 2026-08-29, and it is the sharper form

> *"The remedy's evidence value was zero before the run started, and nothing in
> the outcome can tell you that. The test is not 'did it improve' but **did
> applying it change anything**, and that question is answerable BEFORE you look
> at the result, for free."*

This is better than the original framing and supersedes it as the operational
rule. The original said *check whether the remedy is already in place*, which
sounds like diligence. frankB's version says something stronger and cheaper:
**the reading's information content is fixed before the reading exists**, so the
result never needs to be examined at all. Once `run_in_background` was known to
be already set, lt6's green carried no information about the cause — and that
was knowable without waiting for lt6.

It is the aperture question of face seventeen, asked of an intervention instead
of an instrument: **what would this reading have been if I had done nothing?**

frankB then applied it against its own favoured candidate, which is the part
that makes it a method rather than a retort. Its TESTTMP-collision story has
exactly the same property — the kills stopped when it stopped running two makes
at once — and it noted that the stopping was a *side effect of the queue
emptying*, not a deliberate application, so no confirmation is available from it.
Cause remains unknown and is recorded in the ticket as a candidate only.

**A remedy that was never deliberately applied cannot be confirmed by the
symptom's disappearance, however exact the timing.**

**Related.** Face twenty: a remedy already in force and one that worked produce
the same green. Both are cases where the ACTION's own report is uninformative,
as opposed to an observation's. The pattern across both: **an operation that
cannot fail cannot inform.**

## Face twenty-two — naming the check you did not run makes the conclusion read as checked

Found by pxx-a5, 2026-08-29, in a ticket frank-coordinator filed the same hour.
Face twenty is a remedy already in force. This is a *precondition* named and not
performed — and the naming is what does the damage.

**The instance.** `bug-a-testtmp-defaults-to-a-path-every-checkout-shares` was
filed with a "Direction, not a prescription" section that said, in as many words:
*grep for hardcoded `/tmp/` consumers outside the Makefile first, including in the
tooling, before changing the default.* The coordinator wrote that sentence and
did not run the grep.

pxx-a5 ran it. It inverts the answer three ways:

- **testmgr already privatizes.** `RUN_TMP = "/tmp/testmgr-scratch-%d" % os.getpid()`
  (`tools/testmgr.py:1251`), applied by rewriting every recipe line at execution —
  so the ticket's central sentence, *two runs in two trees write the same absolute
  paths*, is **false for every testmgr-driven run**, which is how the watcher and
  every gate tier run. The real exposure is bare `make` by hand, which the
  full-suite hook already refuses for every lane but T.
- **The recipe half closed two weeks earlier** — `chore-makefile-testtmp-parameterize`,
  `b2cab6b6b`, 2026-08-14.
- **And the proposed fix would break the harness.** Four expressions in
  `make_dry_run()` hardcode the literal `/tmp` prefix, with a comment on them
  saying they *"all four go blind AT ONCE and fail silently"* if the default moves
  — no privatization and no producer/consumer merge. `/tmp` is **load-bearing**,
  not an oversight, and that comment is the guard.

So the recommendation would have removed isolation that already exists and broken
the job-dependency merge, both silently, both in the direction where a
collision-red and a real defect read identically. **It would have made the exact
problem the ticket is about worse, while looking like the fix.**

**Why the hedge is the mechanism and not the mitigation.** A flat recommendation
invites a reader to check it. A recommendation that names its own precondition
reads as one whose author already thought about that — and the sentence *"grep
for consumers first"* is indistinguishable, on the page, from *"I grepped for
consumers."* The care is what buys the credibility, and the credibility is what
suppresses the check.

| condition | how the ticket reads |
| --- | --- |
| precondition named and satisfied | a carefully-qualified recommendation |
| precondition named and never run | a carefully-qualified recommendation |

Same family as the false-limit rule — *a wrong reason is worse than none, because
it answers the question the reader would otherwise have asked* — but sharper:
here the wrong reason is **a correct instruction**, and it is wrong only in
whose desk it was left on.

**The guard.** A precondition you can state in one line is a precondition you can
run in one line. **If the check is cheap enough to name, run it before filing;
if it is genuinely too expensive, say "I did not run this" in the same
sentence** — the disclosure has to be adjacent, because the naming alone reads
as performance.

The underlying observation — `Makefile:49` really is `TESTTMP ?= /tmp` — was
true. **A correct measurement carrying a wrong causal story is more dangerous
than a wrong number**, and this is that rule with the story spelled out: the fact
was right, its consequences were wrong in three directions, and the ticket
priced it as a live fleet-wide hazard.

## Face twenty-three — a comparison with zero comparands succeeds, and reports the most reassuring number available

Found by frank-optimize-b4, 2026-08-29, in its own campaign harness. Recorded
here for the index; the working notes are at `50e931c4f` and the playbook entry
at `325213daf`.

**The instance.** Four steps of the -O3 campaign were cited as "48/48 corpus
hashes byte-identical". The harness did not export `PXX_HOME`, so the binaries
under test could not find their RTL and **all 48 rows FAILed on both sides**.
FAIL compares equal to FAIL. The diff was empty. An empty diff was read as total
agreement; it was total absence.

| condition | evidence produced |
| --- | --- |
| all 48 outputs identical | empty diff, "48/48" |
| all 48 runs failed identically | empty diff, "48/48" |

Note which way the ambiguity points: **the broken case produces the most
reassuring possible reading.** A comparison measuring nothing does not look
weak, it looks perfect — and the number it reports is the maximum.

Re-run against real binaries, every conclusion held, at 25 real rows rather than
48 (8 xtensa have no dynamic-symbol support; 15 are 3 corpus files that are
units and cannot compile standalone). So nothing landed on bad evidence — **but
it stood on nothing until the re-run, and that is luck rather than method.**

**The remedy is the general guard for this whole family, and it is one line.**
The harness now **counts its comparisons, prints the count next to the verdict,
and exits 2 rather than answering emptily.** Face seventeen says an instrument's
scope is invisible in its own output; this is the fix: **make the instrument
report its N.** A verdict with no denominator is not a verdict.

It was then verified by pointing it at a deliberately broken binary and at a
reconstruction of the original bug — so the control has failed once, which is
the only thing that makes a control a control.

**Where else this shape lives, already recorded:** `make compiler/pascal26` in a
tree seeded with a copied-in binary, which exits 0 having proved no fixedpoint;
a SKIPped corpus job read as green; a `for` loop over a glob that matches
nothing. Each is a zero-iteration success. **Any operation whose success is
defined over a set should report the set's size.**

## Face twenty-four — a checker built from the same model as the thing checked inherits its blind spot

Found by frankB, 2026-08-29, in its own verification script, at the end of a
session it had spent verifying by construction.

**The instance.** Converting 2476 Makefile assertions of the form
`test "A" = "B"`, frankB verified each rewrite by re-parsing it with a greedy
`"(.*)" "(.*)"` split and comparing the operands. Two lines reported DRIFT. The
transformation was correct; **the verifier was wrong, and wrong in the exact way
it was checking for** — those lines' expected operands contain `" "` inside them
(`printf '…' "'V'" "'V'"`), so the greedy split chose the wrong quote pair.

**The checker's failure mode was the checked transformation's failure mode.**
That is structural, not coincidence: the verifier was written out of the same
understanding of the problem that produced the conversion, so it inherited the
same model, and **a checker cannot see what its author's model omits.**

**And it failed LOUDLY, which is the trap.** It reported DRIFT — noise that looks
exactly like the check working. A checker that misfires in the direction of its
own blind spot produces evidence of diligence at the moment it is least
informative.

**The replacement, and the distinction worth keeping.** The first check
*inspected* the transformation by re-deriving it. The second establishes a
**property of the inputs**: the only thing splitting `test "A" = "B"` can get
wrong is the separator; that is possible only where a line holds more than one
`" = "`; and every original line converted this session contained exactly one.
Zero ambiguous splits.

> **A check that shares an author's model with the thing it checks is a
> repetition. A check over the inputs is a measurement.**

**THE REMEDY, found by the same worker two hours later: check by INVERSE, not by
re-derivation.** For the straggler conversions frankB stopped re-parsing the
rewritten line with the same regex that wrote it, and instead **reconstructed the
original** from the rewrite — drop the label, restore ` = ` — then compared
against what had actually been there.

> A checker that re-parses with the model that produced the line **cannot fail**,
> because it shares the model. One that **reconstructs the input** can, because
> the input is external to the model and disagrees when the model is wrong.

That is the general escape from this face, and it is cheap wherever the
transformation is reversible.

Corollary already recorded elsewhere and confirmed here: the checking layer is
written with less suspicion than the layer checked, because it is "just the
harness".

### Companion — a shape census measures the regex, not the file

frankB's second correction the same hour, and it stands alone. It filed 40 lines
as "standalone with a trailer after the expected"; 32 were plain shape A whose
expected operand contains double quotes, and the expected-side pattern was
`[^"]*`. **They were filed under a description of the regex's blind spot rather
than of the lines.**

> **A shape census is a claim about what a regex will match, and the only
> instrument that measures it is that regex.** Reading harder never finds this;
> running it does.

Third time this campaign's counts moved under measurement — 480, then 474, then
498; and separately 40 → 8+32. **A number over heterogeneous shapes is a guess
wearing a number's clothes.**

### And a subset relation is a claim about the filters, not the file

Same campaign: 376 exit-status checks were reported as being *within* 2007
convertible assertions. They are not — `test "$?"` does not contain
`test "$$(`, so the two greps count **disjoint** sets and the not-convertible
class sat entirely outside the convertible one. **A subset relation asserted
between two numbers produced by two different filters is a guess about the
filters.** Neither the worker nor the coordinator derived it before planning
against it.

---

## Faces 30-33, all measured 2026-08-29. The family is still open.

### 30. Two fields of one report disagree, and the authoritative-looking one is wrong

`regression-cascade-154d1aa3fba6` listed 18 newly-red jobs and a **Range**
section naming twelve commits — every one of them Track R's, the most
incriminating framing available. The *reasons* — `Could not open
'/lib/ld-linux.so.2'`, `TIMED OUT`, a Python traceback in the harness — decided
the question and **were not in the ticket at all**, only in the tstate JSON.

The range was correct. Its own caveat ("the named sha CANNOT be the cause") was
correct. And a reader who trusted it and did not go fetch the report would have
spent an afternoon bisecting Rust commits for a **missing loader on the test
host**. Machine-derived precision reads as authority; the field that actually
settled it looked like prose.

**Remedy: put each failing job's REASON next to its name.** A cascade whose
reasons are visible is triaged by reading; one whose reasons are a fetch away is
triaged by bisection. Generally: **when a report has a precise field and a
narrative field, check the narrative one first** — precision is a property of
the derivation, not of the relevance.

### 31. A gate that uses the artefact as its own oracle cannot see defects in what PRODUCES the artefact

frankwasm's, and it sits under the one loop CLAUDE.md makes mandatory.

`make compiler/pascal26` compiles `compiler.pas` **with pxx**. So the per-fix
loop — and the byte-identical self-host fixedpoint with it, our strongest
signal — is blind **by construction** to breakage only FPC can see, because the
only compiler it ever consults is the one under test. pxx resolves names across
the whole unit; FPC resolves in source order. A call above its declaration with
no `forward;` self-hosts green and makes `compiler.pas` **uncompilable by FPC** —
the path a fresh checkout with no trusted binary must take to exist at all.

Twice in two days, two unrelated frontends, every gate green both times:
`WasmDataAddr` (wasm, 08-28), `RExprRecId` (rust, 08-29).

Distinct from its neighbours, and the distinction is the useful part: face 18 is
input and compiler varying **together**; face 19 is targets agreeing because they
**share a property**; this is **a second witness that was never called at all.**

### 32. A DERIVED number standing in for a MEASURED one — and it reads as more rigorous

frank-optimize-b4's, self-caught: *"I reported 261 poison sites from dividing
2876 bytes by 11, and the actual count was 76."* The instrument could have been
asked for the count directly and was not.

Arithmetic **looks like work**. A number that shows its working carries an air of
derivation a raw count does not, so it draws less scrutiny, not more — which is
exactly backwards, because every input to the division is an assumption. More
common than the blank-output cases in this index, and quieter: the failure is
invisible rather than empty.

**Ask the instrument for the number. If you divided to get it, say so beside it.**

### 33. A capability that exists but nothing invokes — quieter than no check at all

`tools/forwardlint.py` had existed since 08-28, exited 1 correctly, and named
both seed breaks precisely. **It had exactly one caller** — `test/wasm/check_forwards.sh`,
21 lines that are nothing but its caller, **in a directory no other lane runs.**
Not `gate.sh`, not the Makefile, not testmgr. It caught both and told nobody.

**Corrected 2026-08-29 by frankwasm, who wrote it** (`c7690064e`). The correction
sharpens the face. This entry first called it an incumbent nobody grepped for; it
is worse than that:

> *"The tool was built once, placed correctly, pushed to master, and given
> exactly one caller in a directory no other lane runs. I had the capability, the
> placement judgement, and the reach, and I still left the trigger in my own
> suite."*

Not a discovery failure — a **follow-through** failure, by the one person who had
already reasoned out the correct placement and acted on it. Its author put it in
`tools/` *deliberately*, for exactly the reason it was later wired to `gate.sh`.

**The rule, in the author's words:** *putting a check in the shared tools
directory is not wiring it up; a tool with one caller in one lane's suite is that
lane's script wearing a shared name.* And the sting — **being findable by grep is
what makes it feel handled**, which is this same quiet failure one level earlier.

This is strictly worse than not having written it. A missing check is a known
gap; **an unwired one is a gap everybody believes is covered**, because the tool
is in the tree with a sensible name and a correct implementation. The defect was
never the check — *a trigger nobody is assigned to watch is not a trigger.*

Wired into `gate.sh` before the mode `case`, falsified in both directions
(unmodified copy exits 1; copy with the forward added exits 0) in a scratch tree.

**When you write a checker, the same push wires it to something that runs.**

### Instance of face 29, coordinator's own, same evening

Reading a lint's exit status out of a shell pipeline — `cmd | tail; echo $?` —
returns the exit status of **`tail`**. It printed `EXIT=0` beside output reading
`FAIL`, and the coordinator was one sentence from filing *"this checker reports
failures and exits 0"* against a tool that exits 1 correctly.

The broken instrument produced **exactly the artefact a full day of cataloguing
had primed the observer to expect** — and the prior was itself correct, which is
what made the false positive persuasive. Caught by re-running without the pipe.
**A result that confirms the thing you have been hunting all day is the one to
re-measure.**

### Correction to a coordinator inference rule (frankB, same evening)

Dispatch said: *"if it is still red, it is a genuine second cause."* **Wrong
under the pin boundary**, and wrong in a way that looks right — the job builds
with `$(PXX_STABLE)`, pin v390 landed 75 minutes **before** the fix, so the job
stays red at every sha until a pin includes it. Measured both ways, same source,
same flags: pinned RED, HEAD GREEN.

A `compiler/` fix is invisible to a `$(PXX_STABLE)`-gated job until the pin
moves. **"Still red" is not evidence of anything until you know which binary
ran.** And its sibling, from the same session: *"the fix is in HEAD" and "the fix
is in the binary I just ran" are different claims, and only the second is
evidence* — `merge-base --is-ancestor` was true of the sources and false of the
stale binary being executed.


### 34. A diagnostic that names a cause, is CORRECT about the fact, and points away from the fix

frankwasm's, and it is face 25 one turn further out — 25 is a *comment* that
justifies rather than warns; this is a **diagnostic** that is true and
misdirecting at once.

`Length` of a dyn array held in a slot refused with **`Length of Pointer`**. The
IR type `tyPointer` is *precisely the discriminator* the x86-64 backend uses to
select the very arm that was missing. The message had been naming its own answer
for as long as the arm did not exist.

Read as *"pointers aren't supported yet"* for weeks. It was saying **"this node
is a field."**

A refusal that names a type asserts the type is the reason. When that type is
also the **key the fix dispatches on**, the message is a signpost pointing at the
solution and reads as a wall. **When a diagnostic names a cause, ask whether it
is naming the discriminator** — and prefer refusals that say what *shape* was
seen over ones that say what *type* was found.

### 35. A warning placed where the reader who needs it will not be

`compiler/symtab.inc:2817` — `TypeSize`'s record arm:

```pascal
    5: Result := 8;  { tyRecord — caller must use RecSize() for full record size }
```

Correct, precise, and **on the callee's return-value line**, which a caller
writing `TypeSize(tk)` in another file never reads. The one person who needs the
warning is the one place it is not.

Cost: `Option<T>`'s payload was 8 bytes wide regardless of T for eleven rungs —
SIGSEGV on a four-`i64` record, and a silently wrong `4 0` on `Result<Pos,i64>`.

Distinct from face 25 (a comment that *justifies* rather than warns) and face 34
(a *diagnostic* that names a cause and misdirects). Here the content is right and
the **address** is wrong. A comment cannot warn across a call boundary, because
comments are read by whoever is editing the file they sit in.

**Remedy: make it unrepresentable rather than documented.** A name is read at
every call site; a comment is read at none. `TypeSizeWord` needs no comment.
This is `a-documented-trap-is-not-a-guard` with the location made explicit — the
trap was documented **at the trapdoor, facing inward.**

### 36. The bug that survives is the one whose wrong value is PLAUSIBLE

frank-rust, twice in one window, and it named the pattern itself:

- rung 8: a knight-attack table came back **48 of 64** squares occupied — a
  plausible number. The correct answer is 64.
- rung 12: `Pos { file: 4, rank: 2 }` read back as **`4 0`** — `file` right,
  `rank` landed outside the value.

Both latent, both found only while building the *next* feature. Its own reading:
*"I do not think that is coincidence so much as the only kind of bug that
survives to be found later — the loud ones are already gone."*

That is a selection effect, and it inverts the intuition about where to look. A
crash has a location and is the cheap case. **What survives to be found late is,
by construction, what looked reasonable** — which is why an expectation captured
from a running binary is so dangerous: it locks in a plausible wrong value as
green, forever, and every later change is measured against it.

**Operational form, and it is the one worth stealing:** *write the next feature's
test against the previous feature's edge, not just its own.* And hand-compute the
oracle wherever the right answer is independently knowable — 64 was knowable, and
knowing it is the entire reason the bug did not ship.

### 37. A guard watching for an ABSENT input does not see a MALFORMED command

pxx-a5's sixth aperture in its own harness, and the first its invariant missed.

`test_classparent26` reported **FAIL**; it passed when run by hand. Cause: make's
**`@` silent prefix** was left in, so the shell ran `@tools/expect_same.sh`, got
*command not found*, and the recipe's own `|| { echo "FAIL"; exit 1; }` fired.
**The tool faithfully reported a failure it had manufactured.**

The invariant in place — *never FAIL on an input that was not demonstrably
produced* — is a good guard and it was looking the wrong way. It covers the case
where **nothing ran**. Here **something ran and failed**; it simply was not the
command the recipe meant to run. So the aperture sat in the one place the guard
does not look, which is where apertures always sit.

**The general form:** a guard on the *inputs* of a step says nothing about
whether the *step itself* is the one you wrote. `@`, a typo'd binary, a stale
`PATH`, a shell builtin shadowing a script — all produce a real execution, a real
non-zero status, and a real-looking failure.

**And the direction analysis is the part that made the earlier greens
trustworthy**, so it belongs in the face: an unstripped `@` can only turn a
**pass into a FAIL or SKIP, never a fail into a pass.** When a harness defect is
found, the question that decides how much history to distrust is *which way can
this bias?* — not *how bad is it?* A defect that can only produce false negatives
leaves every recorded green intact.

### 38. When the property is a COUNTER, the instrument must make the counter cost something observable

frankwasm's, caught only because it falsified against a deliberately broken build.

ARC correctness is invisible in output: **a record copy with the retain/release
removed prints exactly what a correct one prints.** So the property needs a
memory probe. The first one repeated `b := a` in a loop and measured **flat at
1032 bytes against a build with the release deliberately removed** — a clean
PASS on a known-broken compiler.

Cause: repeating one assignment leaks a **refcount**, and a bump allocator cannot
see a refcount. For failing to release to cost *memory*, the destination has to
own something **new** each iteration. Rewritten that way: **18392/2712** against
the broken build, **1032 flat** at 1000/9000/50000 against the correct one.

*"I would have shipped it."*

**The general rule:** when the invariant is about a **count** — a refcount, a
handle table, a free list, an open-fd tally — an instrument that measures a
**resource** sees nothing unless each iteration allocates a *distinct* resource
the count is supposed to govern. Otherwise it measures the allocator, reports
PASS, and the PASS is about the probe.

This is the strongest available argument for the discipline that caught it: **run
the probe against a build you have broken on purpose, before you trust a green.**
A control is not a control until it has failed once — and here the control was
the *compiler*, not the test.

### 39. A defect-shaped check encodes the defect, then expires the day it is fixed — RED in the direction that reads as a new regression

Three of frankwasm's checks expired on one day, all three written *specifically*
to stop a known defect being silently encoded, and **all three encoded it anyway**
— as the number or the inequality they compared against:

| check | encoded | as |
| --- | --- | --- |
| `check_strop` | the string leak's magnitude | the constant `401032` it compared to |
| `check_managed` | the heap starting at 0 | `heap base < 1024` |
| `check_calls` | the missing arena | "the heap has no arena" |

Each went red **when the defect was fixed**, in the direction a reader parses as
*a new regression* — so a green board becomes red at the exact moment the news is
good, and the natural reaction is to look for what broke.

**What saved the pattern was that each `exit 1` named, in its own failure text,
the paragraph to rewrite.** A check that expires is tolerable; a check that
expires *silently*, or that expires while accusing the wrong change, is not.

**Write the check as a property claim, never as a comparison against the defect's
current shape.** "The heap does not overlap BSS" survives the fix. "The heap base
is below 1024" is the bug, written down as an assertion, waiting to accuse
whoever repairs it.

### 40. A ticket certifying a gap as harmless describes TODAY's reachability — and the fix is what changes it

frankwasm, 2026-08-29, wasm32 `EmitZeroFrameSlot`.

The ticket said the loud `Error` was the harmless half — *"fails open, but
demonstrably INERTLY."* It was not the harmless half. **It was the protection.**

`WasmEmitManagedLocals`, the prologue pass the ticket correctly identified as the
real owner, zeroed scalar AnsiStrings and dynamic arrays **and nothing else**.
Every other kind `ManagedLocalZeroBytes` knows about — a local record with managed
fields, a static array of string, a Variant, a COM interface, a promotable int —
was unzeroed on that target. They were unreachable *only* because the wide chain
refused them at compile time.

So the obvious fix — add the arm the ticket asks for, leave the pass alone —
**removes the refusal and the protection in one commit and ships a
use-after-free**, while closing a ticket whose own text says the failure is inert.

**The trap is that the reassurance was TRUE when written.** Inertness was never a
property of the code; it was a property of the refusal standing in front of it.
The ticket is therefore at its most misleading to the one person guaranteed to
read it: whoever is doing what it asks. A caveat that says "harmless" is read as a
statement about the defect, and it is really a statement about the guard.

**When a refusal is load-bearing, removing it is not a no-op — audit what it was
holding back before you take it out.** The repair is the one that keeps recurring:
the pass now asks `ManagedLocalZeroBytes`, the shared table its own callers use,
instead of restating a list of kinds. The release half deliberately keeps its own
narrower predicate — *what must start nil* and *what this backend knows how to
release* are different questions, and collapsing them into one predicate is
exactly what hid this.

Sibling of face 33 (a capability nothing invokes) inverted: there the check
existed and nothing called it; here the thing that called it was the bug.

### 41. When a cap is breached, measure every CONSUMER — the one in the report is just whichever ran first

frankA, 2026-08-29, `MAX_CODE` 16 → 32 MB.

The ticket named **aarch64** and recommended a floor around 21 MB. Measured at
HEAD, one compiler, one source, only `--target` differing:

| target | bytes | % of old cap |
| --- | --- | --- |
| x86-64 | 9 316 078 | 55.5% |
| i386 | 10 902 436 | 65.0% |
| aarch64 | 20 446 704 | **121.9% OVERFLOWED** |
| arm32 | 21 568 956 | **128.6% OVERFLOWED** |

`make cross-bootstrap` builds i386, aarch64 **and arm32**. **Had the recommended
~21 MB been taken, aarch64 would have fitted and arm32 would still have
overflowed** — the fix would have looked complete, the ticket would have closed,
and the next dispatch would have failed on the target nobody measured.

The reporter stopped at the first failure, which is correct behaviour and is
precisely what makes the report a biased sample: **a build aborts at its first
overflowing consumer, so the ticket names the one that ran earliest, not the one
that needs the most.** Sizing headroom from the reported instance sizes it for an
arbitrary member of the set.

Two corollaries earned in the same fix:

- **The hesitation was resting on a stale comment.** `defs.inc` said the cap
  "costs virtual BSS only", true when `Code[]` and `AsmDisProcAtPos` were fixed
  arrays. Both are `array of` now — `GrowCode` doubles on demand, and
  `AsmDisProcAtPos` is sized to actual `CodeLen`. The constant is a ceiling, not
  an allocation, and raising it costs zero bytes until a program emits them.
  Measured: BSS moved 76 206 356 → 76 249 388 across the bump, i.e. with the
  rebuild, not with the cap. **A cost note outlives the representation it
  describes, and every future bump inherits the false hesitation.**
- **This was the THIRD cap raise** — `MAX_CODE` 8→16, `MAX_STRS` 8192→65536,
  `MAX_CODE` 16→32 — and all three were found by a program failing, none by
  anyone looking, because **no cap's utilisation is reported at any verbosity.**
  The compile summary prints `code= data= bss= procs=`: raw counts with no
  denominator, so `procs=3401` never says it is 21% of `MAX_PROCS`. A number
  without its denominator is not a measurement of headroom, and the board cannot
  tell a cap at 20% from one at 99%. Filed as `feature-a-report-fixed-cap-headroom`
  [A p40], sorted by percent so the top row is the next to bite.

### 42. "The fix already exists one site over" is the most dispatch-accelerating sentence a ticket can contain — and therefore the one that most needs re-deriving

frankwasm, 2026-08-29, self-caught before touching the file.

Its own ticket claimed the codebase already handled this correctly one site away,
naming `ir.inc:11329` and the clause to copy. Re-checked on master before editing:
that line is a `tyVariant` default-parameter branch, and **none** of the four
`argIsManagedTemp` predicates or seven `hiddenArgSym` allocation sites tests the
clause at all. There was no correct sibling.

**Why this sentence is uniquely dangerous.** It converts a design question into a
copy-paste. A reader who believes it stops asking *how many mechanisms serve this
one concept?* — the question that would have found seven unguarded sites and a
missing shared predicate — because the answer is presupposed: at least one site is
right, so the concept is understood, so the job is transcription. It also reads as
the *most* diligent kind of ticket, the author having apparently already located
the fix. It survives review for the same reason it misleads.

The actual state was zero of seven guarded — a design flaw by
`root-cause-over-microfix`'s counting rule, where the right repair deletes six
copies instead of adding a seventh clause. **The microfix and the overhaul were
separated entirely by one unverified sentence**, and the microfix was the larger
long-term cost.

Distinct from face 40, and the author drew the line itself: face 40 is a claim
that was *true when written* and falsified by the fix. This is a claim that was
**never true** and was carried by nobody re-deriving it — including into a
priority and a dispatch. Same family as a wrong root cause recorded in a ticket:
not a missing fact, a present fact nobody diffed. The repo's standing rule already
covers it and it still happened — *before writing a conclusion into a ticket,
check it against a second source.*

**Cheap guard:** a ticket asserting that a sibling site is already correct should
cite it by content, not by line number. Line numbers move; a quoted clause that no
longer exists is visible, and `ir.inc:11329` is not.

### 43. A LEAK IS AN ACCIDENTAL LIFETIME EXTENSION — fixing it does not create bugs, it removes the padding that was hiding them

frankA, 2026-08-29, analysing `0d91dc88f` against pxx-a5's min/max alias.

`if F(x) = 'lit'` never released F's result: 40 bytes per evaluation, unbounded.
The fix emits the release. Within a 4-commit window a years-old aliasing bug in
an unrelated frontend became observable, and the fix was the obvious suspect.

**It was the cause, and it is correct, and it must not be reverted.** The
mechanism is not aliasing:

> For as long as that string was leaked, any stale reference to it kept reading
> **valid, correct bytes**, and the block was never recycled under anyone.
> Freeing it puts the block back in the allocator, so a pre-existing
> use-after-free — or an in-place mutation through an alias — stops being benign
> and starts reading a neighbour.

The alias did not become wrong on 2026-08-29. **It became observable.** A leak is
an accidental lifetime extension, and every latent reference into leaked memory is
being silently protected by the defect.

The ruling-out matters as much as the finding: the one way the commit could
genuinely introduce a dangling reference is an owned operand feeding a **second**
consumer, which cannot happen — there is no CSE or node-sharing pass, so the IR is
a tree and each node has exactly one consumer. The predicate also predates the
commit (`2f78eb737`). So the change adds no aliasing.

**Three consequences, and the third is the actionable one.**

1. **Do not revert to restore quiet.** The leak was unbounded with every answer
   correct — the shape that silently kills a long-running process. Restoring it to
   keep latent aliases benign trades a real defect for the *concealment* of real
   defects. "My fix exposed a bug" is an easy thing to over-correct on.
2. **Expect more, and expect them to look unrelated to strings.** Any latent alias
   whose target happened to be a leaked comparison temp. The population is defined
   by what the leak was covering, not by what the fix touched.
3. **Sweep the mechanism, not the shape.** A shape sweep — 52 const-param callees
   invoked with `CurTok.SVal`, 3 advancing the cursor — closes one family.
   `-dPXX_HEAP_DEBUG` stamps freed bytes `$DD` instead of leaving them readable,
   which converts the whole class from *"reads a plausible recycled value"* into
   *"reads `$DD` at the first touch"* regardless of shape. Face 36 says the bug
   that survives is the one whose wrong value is plausible; this is the
   instrument that removes the plausibility. Routed to Track T.

General form: **every memory fix is also a change to which latent bugs are
observable.** A defect that extends a lifetime is protective by accident, and its
removal is a reachability change — the same reasoning as face 40, one layer down
in the runtime rather than in the compiler's own refusals.

### 44. A NEW FRONTEND'S BUGS ARE MOSTLY UNCALLED SUBSTRATE — nine rungs in a row, and the streak is the finding

frank-rust, 2026-08-29, rung 14 of the Rust ladder.

Rust procs never called `EmitManagedLocalsZeroInit`, so a managed local's slot
started as **stale stack bytes** and its first assignment released whatever those
bytes happened to point at. Invisible for the frontend's whole life, because until
this rung it had no managed type.

The symptom is face 36 for the third time and deserves restating: a two-`push`
function returned the right answer in isolation and **segfaulted only once its
caller happened to hold a string local of its own.** The failing program was the
one that did nothing wrong. Byte-identical in mechanism to
`bug-nilpy-string-local-truncates-at-255`, and fixed identically — **the shared
helper already existed; this frontend had simply never called it.**

**That was the ninth consecutive rung whose fix was calling something already in
the substrate.** Nine is no longer a run of luck; it is a measurement of where a
new frontend's defects actually live, and it converts `ir-as-substrate.md` from a
design preference into an empirical claim: **when a young frontend misbehaves, the
prior should be "it is not calling the shared machinery", not "the shared
machinery lacks this".** The corollary is the standing rule, now with a number
behind it — *grep for the incumbent before building.*

Note what the streak does NOT license. The same rung produced a genuine
duplication call in the opposite direction: `format!` deliberately does **not**
share `println!`'s `{}` splitter, and that was written into the divergences doc
specifically so a later reader would not "fix" it. One emits WRITES, the other
builds a VALUE; all they share is scanning `{}` out of a literal, and sharing it
would hand back an ordered item list neither caller wants in order to couple an
output path to an expression path. **Share the AST and the IR; duplicate the
parser and its helpers** — the streak is about the substrate layer, and reading it
as "always share" inverts
`the-substrate-is-ast-and-ir-not-the-parser.md`.

Two more from the same rung, both worth their own line:

- **`String` and `&str` map to ONE managed AnsiString, and the argument is
  unusually strong.** They differ in exactly one observable — mutating a buffer
  while another name views it — and that is precisely what rustc's borrow checker
  makes unrepresentable. So this is not "unlikely to matter": **the reference
  implementation statically forbids the only experiment that could distinguish
  them.** That is a much better warrant for collapsing two types than "we have not
  seen a case", and it is the shape to look for whenever a frontend asks whether
  two source types need two representations.
- **Position, not content, separated the cases the gate had to split.** A string
  literal inside `println!("...")` is a const_str the write path consumes directly
  and needs no runtime; the same literal anywhere else becomes a value and does.
  A content-based scan would have pulled 60KB of runtime into all 18 existing
  tests; the position-based one kept every one of them byte-for-byte identical in
  code size, which is how the gate was verified rather than asserted.

### 45. A PHASE THAT CAN BE ENTERED BUT NEVER FINISH CONSUMES THE RESOURCE IT EXISTS TO PROTECT — and reads from outside as slowness

Track T, 2026-08-29, `twatch`'s `verify_pin`.

`twatch` has three long-run phases and three different treatments of preemption:

| phase | commitment point |
| --- | --- |
| reserved breadth | `commit_after=0` — commits at once |
| requested verdict | `commit_after=full_commit_secs` |
| **`verify_pin`** | **none — abortable at every moment** |

Measured on `seven`: **7 pin-verify attempts, 7 preemptions, 0 completions**, all
on the same pin. Every attempt consumed an idle slot and produced nothing — and
the slot it consumed is the one breadth needed. So the pin stayed unjudged **and**
the ladder kept paying for it.

**From outside, this is indistinguishable from a slow box.** The coordinator read
"full tier 104 testable commits behind" and diagnosed throughput, which would have
led to tuning tier composition against a cause that was not there. The arithmetic
refutes it: 115 commits/hour of which 36 buildable, a full tier at ~959s ≈ 16 min,
≈10 buildable commits per run — back-to-back that is a verdict every ~16 minutes
running ~10 behind. **A 71-commit debt is not what that cadence produces, so the
number was evidence of something other than speed.** When a queue is further behind
than the throughput arithmetic allows, the gap is the finding — do not tune the
throughput.

**And the defect is inside the mechanism built to prevent it.** `verify_pin`
exists because *"18 of the last 25 pins never received a full run"*. It reproduced
that failure one level down, in itself. The requested-verdict branch already
carries the fix **and documents this precise failure in its own comment** —
`verify_pin` is the sibling arm missed when that one was repaired. Textbook
`normalise-dont-special-case`: three phases serving one concept, each restating
its own preemption policy. Fixed in `5a5c7bc92`.

**Corollary — yielding a slot is not the same as ever completing.** `IDLE_YIELD_AFTER`
bounded the damage to phases *behind* the starving one, so the guard worked
exactly as designed and the starvation continued. A backpressure mechanism that
limits blast radius can make an unfinishable phase survivable, and therefore
permanent.

### 46. A FIX IS INERT UNTIL BOTH HALVES HAPPEN — and the restart alone looks like it worked

Same incident. `5a5c7bc92` landed and the watcher kept running the old code.

`trackt status` showed `code : STALE`, and the first restart **did not clear it**.
The watcher clone is **detached at the sha under test**, so `git pull` there fails
*by construction* — that is not a misconfiguration, it is what a bisecting clone
is — and a restart reloads `twatch.py` from the clone, not from origin. Correct
sequence is stop → fetch → `checkout master` → start.

**The failure mode is that the restart succeeds.** The daemon comes up, reports
healthy, publishes tstate, and serves the old binary's behaviour. Nothing in the
success path is false; the only tell is a `code : STALE` line that a healthy-looking
restart invites you to read as leftover.

Direct sibling of face 31 (a fresh tree's `make compiler/pascal26` is a silent
no-op when the seed was copied in) and of the pin-boundary rule *"the fix is in
HEAD" ≠ "the fix is in the binary I ran"*. Same shape in a third place: **an
artefact whose provenance is assumed rather than checked, where the assuming step
emits a success message.** For a lane whose whole output is verdicts, shipping a
fix and not restarting onto it means every subsequent verdict carries the old
code's bugs under the new commit's name.

### 47. THE SUMMARY SENTENCE A FIX INVITES YOU TO WRITE CAN BE FALSE WHILE THE FIX IS RIGHT

frank-optimize-b4, 2026-08-29, the `LowerCase` forward (`7aba316be`).

The natural write-up — *"the seed and self-hosted builds now agree"* — **is false.**
Measured by stash/rebuild isolation:

    seed-built, WITHOUT the forward:  9396c6dbb646f90d
    seed-built, WITH the forward:     9396c6dbb646f90d
    self-hosted:                      9396c6dbb646f90d

**They agreed before.** The forward did not cause the convergence, it **recorded**
it. What changed is that the agreement is now *stated* rather than coincidental —
which is precisely the defect the ticket described, so the fix is right and the
obvious summary of it is wrong.

**This is how a correct fix acquires a false rationale.** The title implies a
behaviour change; the value is entirely in removing a coincidence. Anyone reading
the summary later concludes the builds used to diverge, and will "know" a
divergence that never happened — the durable kind of wrong, because nothing
downstream ever contradicts it. Same family as face 32 (a derived number standing
in for a measured one) with the direction reversed: here the *measurement* was
taken and the *prose* was still going to be wrong.

Two more from the same fix:

- **Two methods that fail differently, agreeing.** Track T swept the input domain
  (0 differing over 256 bytes, 65 536 ordered pairs, 256 contextual cases) proving
  the two *routines* agree; b4's stash/rebuild proves the whole *artefact* is
  unchanged whichever routine bound. Neither shares an upstream with the other,
  which is what makes the pair a control rather than a repetition — see the
  standing rule about agreement between arms with a common upstream.
- **`forwardlint` reports only the EARLIEST site.** The ticket named one; there
  are **eight** (`pasparser_expr.inc:1927, :2881, :8383, :8386, :8389` and
  `cparser.inc:337, :395, :510`), all covered by one forward in
  `frontend_forwards.inc`. Exactly face 41's shape in a linter rather than a build:
  **the instrument names whichever instance it reached first, and the ticket
  inherits that as if it were the population.**

### 48. A CAPABILITY SWEEP THAT REPORTS "PRESENT" WITHOUT RECORDING THE SPELLING IT TRIED IS NOT A MEASUREMENT

pxx-a5, 2026-08-29, re-measuring `feature-nilpy-stdlib-coverage-gaps-measured`.

The ticket carried its own sweep from 2026-08-15 concluding *"os, time and
math.fabs are all present and exact now."* Re-measured at HEAD, it was **wrong on
two of three rows**:

| row | 08-15 sweep said | actually |
| --- | --- | --- |
| `math.fabs` | present | present |
| `os` | present | `os.path.*` worked; **`os.sep` / `linesep` / `listdir` did not** |
| `time` | present | **`time.time()` absent** |

Plus drift the sweep could not have known: `copy.copy` works now, `copy.deepcopy`
does not.

**The failure is not carelessness, it is granularity.** "`os` is present" is a
claim about a *module*; every probe is necessarily a claim about a *name*. The
sweep tried `os.path.basename`, concluded the module was reachable, and wrote
down the module. Nothing in the record said which spelling was executed, so
nobody could tell the claim was narrower than its wording — and a later reader
(including the same author) inherits a module-level "present" backed by one
name's worth of evidence.

**The structural cause here made it worse, and is worth knowing on its own:** the
dotted table only intercepts **call** forms. So every `os.path.*()` call worked
while `os.sep` failed as *"undefined variable (os)"* — an error that reads like
the module is unbound when in fact only the non-call spelling has no route. The
diagnostic pointed at the module; the defect was in the attribute path. Face 34's
shape (a correct diagnostic pointing away from the fix), and it is exactly what
turned one probe into a module-wide conclusion.

**Same family as face 41 and the `forwardlint` finding, one level up:** there the
instrument reported whichever instance it reached first and the ticket inherited
it as the population; here the instrument reported whichever *spelling* it reached
first and the ticket inherited it as the module. **Record the probe, not the
verdict** — a coverage claim should be readable as the list of names actually
executed, so its scope is visible without rerunning it.

Two silent wrong-value bugs surfaced in the same pass, both worth their shape:

- **`re.sub`'s count convention disagreed with CPython on exactly one input.**
  CPython reads `0` as "no limit" and **negative as "do nothing"**; the engine
  reads `-1` as "no limit" and treats every negative alike. `sub()` mapped 0→-1
  and passed negatives through, so a count meaning *replace nothing* replaced
  everything: `re.sub("a","X","banana",-1)` → `bXnXnX` where CPython gives
  `banana`. **Two conventions that agree everywhere except one value is the
  hardest kind to spot**, because every ordinary test passes. Normalised in one
  place (`ReLimit`) rather than at three call sites.
- **`PyParseSysStream` built the value without checking WHICH module was asked.**
  `PyIsStdlibMemberValue` gated on the base; the builder did not. So
  `sys.SEEK_SET` answered `0` where CPython raises `AttributeError` — **and that
  is not the harmless direction.** The `sys._MEIPASS` comment directly below it
  exists precisely *because* applications guard an absent `sys` attribute with
  `try/except AttributeError`; an arm that answers a value walks them down the
  wrong branch silently. A gate applied on one of two paths is not a gate.

### 49. A RED IS BOUNDED BY THE MACHINE THAT RAN IT TOO — the reproduction condition is a claim, and it is rarely measured

frankB, 2026-08-29, the reactor slot-0 aliasing.

The ticket said — and the coordinator repeated it in the dispatch — *"invisible on
every 12-core box, deterministic above 19 threads, found on `seven` (24 cores)."*
The coordinator went further and told frankB it **could not verify its own fix**
on a 12-core host, and to bank an honest "this still needs a big box".

**It reproduces on 12 cores.** `MAX_REACTORS` is exhausted by **worker threads**,
and the worker count only *defaults* to the core count. `palparallel` has exported
the override for as long as the bug has existed:

```pascal
PXXSetParForWorkers(20);   { PAR_MAX_WORKERS = 64 is the only ceiling }
```

One line, and the ticket's own program is **0/8 clean unfixed** on the 12-core box
— canary fatal, `err=37`, `err=50`, `err=59`, hard crashes with no output — and
10/10 after.

**The ticket's evidence was a correct measurement with a wrong inference bolted
on.** Its `taskset` table is real: vary the affinity mask, watch the failure
appear and disappear. But `taskset` changes the affinity mask, `QueryCpuCount`
*reads* the affinity mask, and the worker count follows from it. **The experiment
was dialling the worker count and reading the result as a property of the
hardware.** Every number in the table is right; the variable was misnamed.

This is the standing rule *a green job is a claim bounded by the machine that ran
it* — turned around. **"Only reachable above 16 hardware threads" was equally
bounded: true of every run anyone had made, and not a property of the code.** A
reproduction condition feels like a finding because it came from observation, but
it is an inference about *why* the observations differed, and that half is usually
untested. `seven` is what made this **noticed**, not what made it reproducible.

**Cost of believing it:** a fix nobody could verify without scarce hardware, a
regression test that would run almost nowhere, and — worst — a coordinator
instructing a worker not to trust its own machine. The check that dissolved it was
reading what the count actually depends on.

**Corollary on the fix, because the guard alone was not shippable.** `slot := -1`
plus an explicit refusal is right, but with `MAX_REACTORS` still 16 every ordinary
`parallel for` with async work on a 17+ thread host would then **halt** —
converting silent corruption into a guaranteed hard failure for exactly the users
on the hardware where it was found. Raising the ceiling to 64 (= `PAR_MAX_WORKERS`,
matching the other two tables in `lib/rtl`) is what makes the guard safe to ship;
the guard is what makes the raise honest. **A correctness fix that turns a silent
wrong answer into a crash for the affected population is not finished.**

And: **raising the ceiling made the guard unreachable from Pascal, and an
unreachable guard is an untested one** — hence `-dPXX_SCHED_TINY_REACTORS`
lowering it to 2 so three threads overrun it. Sibling of face 33.

### 50. ONE SAMPLE PER CELL READS EXACTLY LIKE A MEASUREMENT AND IS A COIN FLIP WITH A TABLE DRAWN AROUND IT

Same work, and the author caught it on itself.

Chasing a racing exit status, frankB sampled each width **once** — 216 / 0 / 0 —
and derived a clean deterministic rule: *"one refusal reports correctly, two or
more exit 0."* **That rule had already reached a source comment before it was
re-run.** Repeating the runs destroyed it, and the obvious minimal repro (six
plain `palthread` threads all calling `Halt`) does not reproduce at all — 6/6 at
216.

**A one-sample-per-cell table is formally identical in appearance to a measured
one**: same axes, same cells, same air of rigour, and it renders a coin flip as a
law. Nothing downstream can distinguish them, because the sample count is exactly
what a results table omits.

The honest resting state — **reproduced, bounded, NOT diagnosed** — went into
`bug-b-concurrent-halt-from-several-threads-exits-0` *with the negative result in
it*, and the source comment now says what was measured rather than what was
inferred. That is the correct disposal: the pattern was not confirmed, so the
claim shrank instead of the ticket closing.

What shipped instead is properly bounded: `Halt`'s exit path *joins* the workers,
so serialising the refusal hung the process (124 under `timeout`); calling
`exit_group` directly gives **216 in 30/30 runs at widths 3/4/8/20/64.** Note the
sample count is stated.

### 51. A BEHAVIOUR-PRESERVING CHANGE VERIFIES IDENTICALLY TO A NO-OP — prove the change happened, separately

frank-optimize-b4, 2026-08-29, the `EmitLoadVarA64` scratch collapse.

The verification was strong: 30 aarch64 differential pairs with 0 behaviour and 0
size differences, byte-identical output on x86-64 / i386 / arm32 / riscv32 at all
three levels, self-host fixedpoint converged. Every row is what a correct
refactor produces.

**Every row is also exactly what an edit that did nothing produces.** So b4 ran one
more: **332 bytes differ** in the aarch64 binaries at each level. *"Identical size
plus identical behaviour is also exactly what a no-op edit produces, and I have
already published a vacuous diff once in this repo."*

When the intended effect is *no observable difference*, the entire test suite
becomes a control with no treatment arm, and a change that silently failed to
apply — a stale build, a patch to a dead branch, an edit under a define nothing
sets — passes every check with full marks. **The instrument must be able to tell
"correct" from "absent", and a behaviour-preserving change requires a
counter-property that proves the code moved.** Face 38's counter-property idea
applied to a refactor rather than a counter.

Two more from the same verification, both about instruments hiding their own gaps:

- **The harness swallowed failed compiles** — `|| continue` meant a program that
  no longer built dropped out of the comparison, so a change breaking compilation
  outright would surface as a *smaller comparison count*, never as a failure. It
  was found only because b4 hardened the harness to report skips: 3 of 6 pairs
  were being silently dropped on the first run. **A count is not a result unless
  the denominator is stated** — the same defect as a census whose skips are
  invisible.
- **The aarch64 corpus is thinner than the census implies.** `jsondemo` does not
  build for aarch64 (`aggregate result with more than 8 params not supported` in
  `builtin/pylib.pas`, pre-existing), and `life` and chess are absent too — 3 of
  11 programs skipped. The census counted target-independent IR shapes and remains
  valid *as a census*; what does not follow is that the same list is available for
  **behavioural** verification. One table, two uses, and only one of them was
  checked.
- **b4 undercounted its own note, one day later.** It had written "skGlobal and
  tySingle" as the x1 users; the real count was four code paths across three arms,
  the by-ref-param deref being the missed one. Same inherit-the-population shape as
  faces 41 and 48 — this time the stale population was the author's own note.

**Face 42, sharpened by its own first test (frankwasm, 2026-08-29).** The
`:11329` citation was verified at the exact commit it was filed against
(`f018f4c86`): the line had **not moved**, and it was a `tyVariant`
default-parameter branch carrying a correct `IsArray` guard *on a different
question*. So the citation was never true — it was not staleness.

That makes the failure mode worse than first written. **A wrong line number does
not merely waste a lookup; it hands the next agent a plausible-looking guard on an
adjacent question and invites them to copy it.** The nearby code is real, it does
guard something, and it is guarding the wrong thing — which is exactly the input
that makes a microfix feel justified.

The author's statement of why the content rule works is the best form of it:
**a line number is checkable only against a tree you may not have; a sentence
about content is checkable against itself.**

And the measure-first condition attached to that grant paid out in the direction
nobody predicted. The ticket claimed *"only the CONSTRUCTOR spelling is
affected."* Measured with one call shape per procedure body — so first-refusal
counting could not hide the tail behind the head — **six of seven shapes were
refusing**: direct and virtual constructors, and direct, indirect, virtual and
interface calls taking a function RESULT. Wrong about which call kinds reach the
site *and* wrong about which argument spellings do. The lone survivor,
`Direct(av)` with a named variable, survives for a reason unrelated to `IsArray`
— an `<> AN_IDENT` exclusion beside each predicate catches it first. **Patching
the inferred shape would have fixed one arm of six and closed the ticket saying
so.**

### 52. THE POPULATION INHERITED FROM WHEREVER THE FIRST LOOK LANDED — third instance in two days, and the third was written by an author who had just banked the second

frank-optimize-b4, 2026-08-29, and it named the pattern on itself.

Three instances inside two days, all the same mechanism:

| where | the stated population | the real one |
| --- | --- | --- |
| `bulk-copy` ticket | "at least four more places" | eight |
| `forwardlint` / `LowerCase` | one site (the earliest reported) | eight |
| b4's own parked note | "the skGlobal and tySingle arms" use x1 | four code paths across three arms |

The first two are an *instrument* reporting its first hit — a linter that stops at
the earliest site, a build that aborts at its first overflowing consumer (face 41),
a probe that tries one spelling and concludes about a module (face 48). The third
is the one worth the face:

**b4's note was one day old, written by a session that had just banked the
`forwardlint` version of this exact error, and knowing the shape did not stop it
producing the shape.** The missed arm was a by-ref-param deref — not exotic,
simply not where the first look landed.

That kills the obvious defence. *Remember the rule* does not work, because the
author who remembered it best still wrote the undercount, one day later, about
their own code. **A note that names a set is a hypothesis about that set, and it
does not become a measurement by being written down — including when you wrote
it.** Your own prior enumeration is the least suspicious source available and
therefore the one that draws no check (the standing rule: *the check gets spent on
the candidate you doubt, not the one you like*).

**Procedural form, since the mnemonic form demonstrably fails:** before acting on
a count you did not just take, re-enumerate. Not "consider whether it might be
stale" — run the grep again. Every instance here cost one command to falsify, and
in frankwasm's case (six of seven call shapes refusing where the ticket claimed
one) the re-enumeration is what stopped a fix landing on one arm of six with a
ticket saying it was complete.

**The general shape across all of them:** an enumeration and a *sample* are
indistinguishable once written into prose. "The sites are X and Y" and "the sites I
found before I stopped looking are X and Y" render identically, and only the second
is ever true of a first pass.

### 53. A GUARD THAT HAS NEVER ONCE BEEN TRUE IS INVISIBLE TO EVERY TECHNIQUE EXCEPT CHANGING IT

frank-rust, 2026-08-29, `impl Trait for Type` in the Rust frontend.

Not "was broken" — **had never once run.** The prescan and the body parser both
tested `(Tokens[j+1].Kind = tkIdent) and (GetTokenStr(j+1) = 'for')`, and the
lexer classifies `for` as `tkFor`, whose name slice is empty. `''` against
`'for'`, never true. Every `impl Area for Sq` ever written was read as
`impl <Area>` and died with *"impl for unknown type Area"* — **and the `RImpls`
table it fills had been empty for the frontend's entire life.**

**This is a different class from face 36 and deserves its own name.** Face 36 is a
plausible wrong *value*. This is **plausible-looking code that never executes**:

> It reads correctly, it is commented correctly, it sits in the right place, and
> no test could have caught it because the feature it implements was simply never
> available to test.

Note what each technique misses. **Coverage sees the line as reached** — the
condition is evaluated, it is just always false, so a branch-coverage tool at
best reports one arm untaken among thousands. **Review sees correct code**, because
the defect is in the lexer's contract one file away, not in the expression.
**Tests cannot exist**, because you cannot write a test for a syntax the parser
rejects — the absence of the test is *caused by* the bug. And the diagnostic was
honest and specific (*"impl for unknown type Area"*), which sends you to the type
table, face 34 again.

It was found by trying to **extend** the feature. That is the general rule: a
never-true guard is falsified only by perturbing it, never by observing it.

**The cheap sweep for the class**, and frank-rust supplied it: grep for token text
compared against a word the lexer turns into its own token kind. Run across all
frontends here — **17 candidate sites: `rparser.inc` 11, `pyparser.inc` 4,
`zparser.inc` 2** — filed as
`bug-a-audit-token-text-compared-against-a-keyword-the-lexer-never-leaves-as-text`.
**Being on that list is not a defect**: `self` in `pyparser.inc` is very probably
correct, because `self` is an ordinary Python identifier and `GetTokenStr` is the
right test for it. The list is candidates, not findings — which is face 52's
lesson applied in advance, for once.

**Corollary, and it is the expensive half:** when a never-true guard is found, ask
what *silently never happened*. The fix is one line; the empty `RImpls` table is
the finding.

### 54. `make compiler/pascal26` DOES NOT COMPILE `pylib.pas` — the gate's scope is narrower than its name

pxx-a5, 2026-08-29, while adding syscalls to NilPy's PAL.

> I broke `pylib`'s interface section and **the entire self-host fixedpoint passed
> green.** It only failed when I compiled a `.npy`.

`pylib.pas` is linked into NilPy *programs*, not into the compiler, so the
compiler's own build never parses it. The one mandatory gate in the per-fix loop —
the thing CLAUDE.md correctly calls the single failure that would poison every
lane — **cannot see a broken NilPy runtime at all.**

Third member of a family that now clearly is one, all in two days:

| the gate | blind to | because |
| --- | --- | --- |
| `make compiler/pascal26` | FPC-only breakage (face 31) | it compiles `compiler.pas` with **pxx**, which resolves across the whole unit |
| `make compiler/pascal26` in a seeded tree | everything | `cp` stamps the seed newer than the sources, so make no-ops and exits 0 |
| `make compiler/pascal26` | a broken `pylib.pas` | the compiler does not link the NilPy runtime |

**In every case the gate is real, its name implies more than it covers, and the
success message is identical either way.** "Self-host fixedpoint converged" is a
true statement about the compiler reproducing itself and says nothing about the
runtime a NilPy program will link. A green whose scope nobody states is read at
the width of its name.

Same session, same shape one layer in: **`PyStdlibCallAhead`'s base whitelist and
`PyStdlibCallProc`'s table are one concept in two places.** `time.time` was added
to the table and did nothing at all until `time` reached the whitelist — **a table
entry alone is silently dead code**, with no error and no warning. Face 33's
"a capability nothing invokes", and the same normalise-don't-special-case rule:
two mechanisms serving one concept means one of them will be updated alone.

### 55. REDUCING TO A MINIMAL REPRO CAN DESTROY THE BUG — when the defect IS the disorder, ordering it away is what a clean repro does

frankB, 2026-08-29, `Halt(n)` exiting 0 from a multithreaded program.

The first pass ended at *reproduced, bounded, NOT diagnosed* (face 50) — and the
reason it stalled is the finding:

> The clean minimal repro **cannot reproduce it**: six `palthread` threads with
> explicit `PalThreadJoin` make main last *by construction*, so writing a tidy
> repro removes the race. I read 6/6 at 216 as "concurrency alone is not
> sufficient" — true, but the useful reading was that my repro had **ordered the
> thing whose disorder was the bug.**

Minimisation is the standard move and it is usually right. **Here it is the one
technique guaranteed to fail**, because the reduction step that makes a case
tidy — join your threads, remove the racing tail, make termination
deterministic — is precisely the property under test. The clean repro's green is
not weak evidence; it is *evidence for the wrong proposition*, and it reads as
"concurrency is not the cause".

The mechanism, once traced on the **messy** case: `Halt(n)` emits `exit` (thread
exit), not `exit_group`. A worker's `Halt(7)` does set main's exit code — but the
process status belongs to whichever thread exits **last**, and threads finishing
normally exit 0. `strace -f` shows the failing runs ending in `exit(0)` from a
worker that finished after the fatal was announced. **Nothing is overwritten; the
216 simply was not the last word.**

**Rule:** before minimising, name the property you believe is causal, then check
whether each reduction preserves it. If the bug is a race, a scheduling artefact,
or a shutdown-order effect, the minimal case is the *last* thing to trust — trace
the messy one.

And the root cause is `normalise-dont-special-case` yet again, with the drift
landing exactly where the family predicts. Five hand-written arms for one concept:

| backend | emits | |
| --- | --- | --- |
| **x86-64** | `SYS_EXIT` = 60 | **wrong — and it is the primary target** |
| i386 | 252 = exit_group, *commented as such* | correct |
| aarch64 | 94 = exit_group | correct |
| **arm32** | `mov r7,#1` = exit | **wrong** |
| riscv32 | 94 = exit_group, *commented as such* | correct |

**The correct answer was written down one line below the bug.** The no-argument
branch calls `EmitExit`, whose comment reads *"exit_group, not exit: terminate
every thread. A bare exit (60) only ends the calling thread, so a program that
started worker threads would leave the process alive after main returns."*
`Halt` with no argument obeys that comment; `Halt(n)` does not. Three of the five
arms name `exit_group` in a comment — **the drift landed on the arm nobody
re-derives, because it is the one that obviously works.** Single-threaded the two
syscalls are equivalent, which is why it survived.

**And the trap left behind for whoever fixes it:** `lib/rtl/scheduler.pas` now
calls `exit_group` via `__pxxrawsyscall` to work around this, so
`test_sched_reactor_exhaustion` **would pass with the bug still present.**
Reverting that to a plain `Halt(216)` is part of the fix — otherwise the repair
ships beside a green test guarding nothing. A workaround installed while a bug is
open becomes a blindfold the moment it is closed.

### 56. AN OPEN TICKET WHOSE TITLE MATCHES YOUR SYMPTOM IS A MAGNET FOR FALSE ATTRIBUTION

frankB, 2026-08-29, and it is a face about a *non*-finding, which is why it is worth
keeping.

Three `lib-test` background runs were killed mid-flight, at 386 and 665 lines, at
unrelated points, with no test failure in any of them. There is an open ticket
called `chore-t-unit-class-est-mem-is-below-what-lib-test-00-actually-peaks-at` —
*"lib-test admitted on a memory promise the box cannot keep."*

**"lib-test got SIGTERMed" plus a ticket titled "lib-test peaks above its memory
estimate" is a very inviting pair.** It explains the symptom, it names a known
defect, it is already filed so it needs no new ticket, and joining them costs one
sentence.

It is wrong. frankB checked instead: the box had **38 GB available**, `lib-test`
peaks around **600 MB**, and `dmesg` shows **no OOM kill**. The three runs also
stopped at three unrelated places, which independently rules out a specific test.
The actual cause was its own session's background-task handling stopping a long
command — **nothing in the repo, and specifically no new data point for that
ticket.**

**The hazard is structural and grows with the backlog.** With 336 open tickets,
almost any symptom has a plausible-sounding match by title, and attributing to an
existing ticket feels like *diligence* — you searched, you found the known issue,
you avoided filing a duplicate. It produces a confident wrong cause with no new
artefact to review, and it also **corrupts the ticket it attaches to**, which now
carries a fabricated data point that will be cited by the next person.

frankB's own statement of the rule: **an explanation that fits is not an
explanation that was tested.** Same family as the reproduction-condition error
(face 49) and the one-sample table (face 50), all three found by the same lane in
one evening — a fitting story, adopted before anything falsified it.

**The disposal here is the model:** it is written down as a negative result *so
nobody chases the wrong lead*, and explicitly says the memory ticket gains nothing
from it. A negative result nobody records gets rediscovered; a wrong attribution
nobody corrects gets inherited.

### 57. IDENTICAL CODE, OPPOSITE VERDICTS — when the contract lives in another file, a pattern is safe in one frontend and dead in the next

frank-rust, 2026-08-29, closing the face-53 audit. **17 candidates, 1 defect, 16
correct** — and the count is not the finding.

Whether `GetTokenStr(i) = 'word'` works at all turns on **one line per frontend**:
which token kinds get their source text copied into `TokChars`.

| lexer | stores token text for | text-vs-keyword compare |
| --- | --- | --- |
| `lexer.inc` (Pascal) | **every word token** — `CurTok.SVal := s`, unconditional after `Keyword(s)` | **SAFE** |
| `rlexer` / `pylexer` / `zlexer` / `clexer` | `tkIdent` + `tkString` (+ one or two each) | **DEAD** |

**Pascal is the outlier, and it is the outlier in the SAFE direction.** That is the
entire explanation for the bug's existence: the idiom is genuinely correct where
most of this codebase's Pascal was written, and it was carried into a frontend
where it silently cannot work. **A habit imported from the majority dialect of the
repo, into a file with a different contract.** It also predicts the next instance —
a new frontend written by someone fluent in the Pascal side. The reviewer's
question is therefore never "is this line right?" but "which lexer is this parser
paired with?", and the answer is not visible at the call site.

**The audit's own method is the second half.** The first grep covered one spelling
in three frontends. Widened to **all eleven**, across `GetTokenStr` /
`CurTok.SVal` / `Tokens[..].SVal` **and the `CaseEqual(text, 'word')` spelling the
first pass could not see** — each parser checked against **its own** lexer's table.
**561 comparisons scanned, one dead guard: a base rate of 1-in-561.**

**And the widening produced four phantom bugs that were caught only by running
them.** Four Pascal sites — `Byte(x)`, `LongWord(x)`, `Byte(p^) := v`,
`Integer(x)` — compare `CurTok.SVal` against words the Pascal lexer turns into
`tkInteger_T`/`tkLongWord_T`, and look **exactly** like the Rust defect. All four
are live. Verified by execution, not reading: **`Byte(321)` prints `65`, which
happens only if the `CaseEqual` branch was taken.**

> Had I stopped at the grep I would have filed four phantom bugs into Track A.

That is face 52's discipline paying out prospectively: the ticket was filed as
*candidates, not findings*, with `self`-in-`pyparser` named as probably correct —
and the warning caught four cases nobody had anticipated. **A list produced by a
grep is a list of places to look, and it stops being that the moment it is written
in a ticket's table format.**

**The expensive-half question (face 53's corollary) was answered, in both
directions.** `RImpls` was empty forever and is read *only* by the generic-bounds
machinery, which had no other way to be satisfied — so no third behaviour was
silently wrong and the damage stops at "`impl Trait for Type` did not compile".
The inverse was also checked: every one of `RKeyword`'s 14 tokens is matched
somewhere in `rparser.inc`, so there is no keyword the lexer emits that the parser
can never consume. **Asking the inverse is what turns "I found no more" into a
bounded claim.**

**Filed rather than built** — `feature-t-lint-token-text-compared-against-a-keyword`
[T p35], since `tools/**` is Track T's lane. The ticket carries the one design note
that decides whether it is worth having: **a lint that skips the text-storage half
turns those four live Pascal sites into false positives**, and a linter that cries
wolf gets scrolled past, which is worse than no lint. Priced at p35 against a
measured 1-in-561 base rate — a never-again lint, not a backlog of hits. **Pricing
a proposed check against its measured base rate is the right way to file one.**

**Face 55, sharpened by frank-optimize-b4 (2026-08-29) — and this is the better
form.** "When the defect IS the disorder, minimisation fails; trace the messy
case" is right as far as it goes, **and tracing the messy case still leaves you
sampling a race**, which is exactly how the original 3-sample table became a rule
that was not there (face 50). The stronger move was available all along:

> **Find the question whose answer is not a race.** Not *"what exit status do we
> get"* — that genuinely depends on which thread exits last — but *"does the
> process die at all"*, which has one answer.

That converted a flaky three-sample table into **10/10 deterministic in both
directions**, on x86-64 and arm32 alike:

| | exit status, 10 runs |
| --- | --- |
| reverted source + **fixed** compiler | **216**, 10/10 |
| reverted source + **pre-fix** compiler | **0**, 10/10 |

So the full rule is three steps, not two: minimisation can destroy the defect;
tracing the messy case finds the mechanism; **but the test you leave behind must
ask a question the race cannot answer differently.** `test_halt_from_worker_thread`
carries that reasoning in its header specifically so the next reader does not tidy
it into a joined repro and quietly disarm it — the same hazard as the workaround
that becomes a blindfold.

### 58. A COMMENT NAMING THE GAP, INSIDE THE FIFTH COPY OF THE THING THE GAP CAUSED

frank-optimize-b4, 2026-08-29, fixing `Halt(n)`'s five hand-rolled backend arms.

The riscv32 arm was **correct**. Its comment reads: *"EmitExit's own encodings only
cover a constant."*

> That sentence is what a missing abstraction looks like from inside the fifth copy
> of itself. **Someone saw the shape, wrote it down, and added a copy anyway.**

The author diagnosed the design flaw precisely — the shared helper handles only the
constant case — and responded by hand-rolling a fifth arm and *documenting why they
had to*. The comment is evidence the gap was understood at the moment it was
widened.

**This is the mechanism by which `normalise-dont-special-case` violations become
permanent.** A silent copy might be an oversight someone later notices. **A
documented copy reads as considered**, and the note that would have justified
fixing the abstraction instead becomes the artefact that makes the copy look
deliberate. Three of the five `Halt` arms carried a comment saying `exit_group` —
**a comment is what you write when the rule has nowhere to live** — and the two that
drifted were the two nobody re-derived, including the primary target.

**The repair shape:** b4 did not edit two constants. It added `EmitExitReg` beside
`EmitExit`, sharing its reasoning, and reduced every backend's `AN_HALT` arm to
"evaluate the code, then call it". The verification is the part to copy — a refactor
folding five arms into one routine, isolated against a compiler carrying the
evening's other work:

| target | change |
| --- | --- |
| x86-64 | 8 bytes, every one `0x3C` → `0xE7` (eight `Halt` sites) |
| arm32 | 8 bytes, every one `0x01` → `0xF8` |
| i386, aarch64, riscv32 | **byte-identical** |

**Changing the output of exactly the two arms that were wrong, while leaving the
three that were right byte-identical, is the strongest available evidence that a
five-into-one refactor preserved what it touched** — and it is the same
counter-property discipline as face 51, used here to prove a change did *not* do
something.

**And the revert was tested rather than assumed, against a real hazard.** The
scheduler workaround's comment recorded a second measured fact: `Halt`'s exit path
**joins** the worker threads, and two attempts to serialise the fatal HUNG (exit
124 at 4, 8 and 20 workers). So removing the workaround could plausibly have traded
a wrong status for a hang. It did not — the hang came from *serialising* the fatal,
which this arm does not do — but that was established by running it, and the still-
true half of the comment was kept.

### 59. A POPULATION COUNT IS NOT A FIRING COUNT — a census measures what COULD be affected and reads as evidence about what WILL be

frank-optimize-b4, 2026-08-29, W1 slice 5 (`81d2ec232`), and it is on the record
because **the census was the careful step** — the one taken specifically to avoid
guessing — and it still over-promised by two arms.

Before writing the pass, b4 added `PXXDBG=a.w1left` and counted resident-left
binops by what they feed. CMP was the biggest bucket everywhere: **2891 in
compiler.pas against 2649 for the whole ALU family**, CMP+MULIMM at 31–52%
across programs. A clean, measured, honest number.

Guarding the two `-O1` leaf-operand arms then fired on **11 sites**, and left
`three.pas` **byte-identical at -O3**.

The gap was two arms wide, and neither was visible from the population:

- most constant-right comparisons are already folded by the **`-O2`
  cmp-immediate** arm, so they were counted in the census and gone before the
  new arm could see them;
- the for-loop's own compare — the motivating case, the one the slice exists for
  — comes from the branch fold in **`IR_JUMP_IF_FALSE`**, not from the binop path
  the census enumerated at all.

Extending to those two folds is what made it real: −119 B on `three.pas`, −2772 B
on `jsondemo`, and a dynamic delta of exactly `2n` at n=2000/20000/50000.

**Why it belongs in this family.** A census is a *refusal to guess*, so its output
inherits the authority of having been measured — and the thing it measured is not
the thing the decision needs. "How many sites have this shape" and "how many sites
will this arm fire on" differ by every earlier transform that already consumed the
shape, and **nothing in the census names those transforms** because they are not
in the population it enumerated. Same structure as face 32 (a derived number
standing in for a measured one): here the number *is* measured, and it is measured
about the wrong set.

**The counter-move is cheap and b4 used it:** fire the guard, count the sites it
actually hit, and treat a byte-identical output as the census being refuted rather
than the pass being pointless. Distinct from the already-banked "a static sweep
understates W1" caution, which is the error in the *other* direction — that one
says the census undercounts, this one says it overcounts, and a lane holding only
the first will read a shortfall as noise.

### 60. AN EARLY RETURN MAKES A LATER, CORRECT ARM UNREACHABLE — and the correct arm's existence is what hides it

frankC, 2026-08-29, `bug-t-pasmith-calls-an-fpc-o2-bug-a-generator-contract-violation`
(`447232884`), found in a 452-program pasmith sitting whose terminal line read
**`452 programs, 1 divergences (1 = FPC-rejected/generator bugs, 0 = NEW)`** —
i.e. clean.

It was not clean. The one divergence was bucketed `fpc-reject_compile-fail`, noted
*"FPC REJECTED THE PROGRAM -- pasmith contract violation"*. FPC **-O0 compiles and
runs it**, and all three pxx levels agree with its checksum. Only FPC **-O2**
fails. The program is valid objfpc — FPC's own -O0 proves it — so the contract the
guard claimed was violated was not.

`classify()` uses `any(...)` over `(fpc-O0, fpc-O2)` and **returns**, short-
circuiting a `fpc-self` check thirty lines below that already carries the right
answer: *"FPC CONTRADICTS ITSELF (-O0 vs -O2) -- an FPC bug, no judgement needed;
pxx is not involved."* So FPC self-contradiction at **runtime** is classified
correctly, and the identical contradiction at **compile time** never reaches the
arm written for it.

**The part that makes this its own face rather than an instance of face 33.** Face
33 is a capability nothing invokes. Here the capability is invoked, the rule is
written **verbatim** in `tstate/fuzz/fpc-bugs/README.md`, and the destination
directory holds a rigorously reduced example. Everything a reviewer would grep for
is present and correct. **The bucket simply cannot be reached**, and the presence
of the correct arm thirty lines down is exactly what makes the wrong one look
handled — a reader who checks "do we classify FPC self-contradiction properly?"
finds yes, and stops.

**Two compounding properties, both worth naming:**

- **The misclassification was into the discard set.** `N = FPC-rejected/generator
  bugs` is *excluded from findings*, so the run reported the discard as noise and
  printed a clean line over a real FPC codegen bug. A filter that drops signal and
  reports the drop as noise is silent in exactly the way face 33's uninvoked
  capability is silent, but it also produces a **positive** clean verdict, which is
  worse: see the standing rule that a host green is the inverse of a host red and
  waits years.
- **Both recorded examples of the signature are this shape** (seeds 362 and 85029,
  replayed at HEAD). The bucket's entire history is upstream FPC bugs filed as "our
  generator is broken" — so the mislabel had already been believed twice, and the
  ledger it wrote is itself the evidence.

**The repair is the asymmetry, not a fourth bucket.** One predicate asking "do
FPC's own levels disagree?" regardless of whether the disagreement is a compile
failure or a checksum, routing to the `fpc-self` destination that already exists.
Adding a bucket would be a second path, and a second path is the thing that stays
broken — `normalise-dont-special-case.md`, one level up.

**The sibling, flagged unmeasured and therefore recorded as a lead:** the
`pxx-reject` guard immediately below uses `any` over the pxx arms the same way, so
one pxx level failing to compile while others succeed would be labelled a frontend
gap when it is an optimiser bug. Same double case, one branch away.

### 61. GREEN TESTS AND A GOOD STORY IS NOT EVIDENCE — a change that costs something and buys nothing measurable passes every gate

frank-rust, 2026-08-29, and it is here because **the author caught it on itself,
retracted in the next message, and kept the dead end rather than the change.**

Chasing `unknown type: TKey` in `generics.defaults.pas:46` while fixing the
Delphi cross-unit generic, it found that `isParamForm` tests an argument only
against **`ti`'s own** parameter names — so `TComparer<TKey>` inside
`TDictionary<TKey, TValue>` is treated as concrete where `TBox<T>` inside TBox's
own body is not. A real asymmetry, a plausible mechanism, and an obvious
widening: accept any template's parameter names.

It built it. **19 named generic tests green, 8 `.expected` diffs green, the
self-host fixedpoint verified.** Every signal a lane normally has said land it.

Then it measured the thing the change was *for*: `uses Generics.Collections`
produced **byte-identical output to `pinned`** — same error, same line, same four
errors. Reduced to 15 lines (`TCmp<T>`, `TDict<TKey, TValue>` with a
`C: TCmp<TKey>` field; FPC prints 5) and confirmed the widened build fails exactly
as `pinned` does.

**The reason is ordering and is obvious only afterwards:** when TCmp's sweep runs,
TDict has not been parsed yet, so `TKey` is not any *known* template's parameter
name. The fixed point re-runs every template once TDict registers — but
`TCmp<TKey>` was already minted as `TCmp$TKey` in round one.

**Why this is a face and not just a good retraction.** The change was **not
refuted by any gate the repo has.** It was correct-looking, self-host clean, and
regression-free; the only thing that could refute it was measuring the specific
outcome it was supposed to produce, against a baseline. A suite answers *"did I
break anything?"* — it cannot answer *"did I fix the thing?"*, and a change that
fixes nothing while touching a hot predicate is pure carried risk that reads as
progress. frank-rust's own line is the keeper: **"green tests and a good story is
not evidence."**

Compare face 32 (a derived number standing in for a measured one) and rule 59
(a population count is not a firing count): all three are cases where a genuinely
careful step produced authority that the decision did not earn. Here the careful
step was running the whole regression set.

**The disposal is the part to copy.** Instead of a silent revert, the dead end was
written into `bug-p-a-generic-argument-that-is-another-templates-parameter-is-
minted-as-a-concrete-type` (p65) as a **"what does NOT fix it, measured"**
section, with the 15-line repro — so the next holder cannot spend it twice. A
negative result with a repro is cheaper to record now than to rediscover, and it
is the single artefact most often thrown away.

**And it settled a stale ticket claim in passing.** That ticket's original
`unknown type: TKey` framing had been recorded as *"wrong"* during a rename. It
was not wrong — it was a **second, independent defect** that the rename walked
past, and the eleven-line repro had found a different one sitting in front of it.
"That framing was wrong" is the kind of line that survives unqualified for months.

### 62. A COUNTER CANNOT ASSERT AN ORDERING — and "I added a control" is not "I watched it fail"

frank-optimize-b4, 2026-08-29, and it is the strongest instance in this file
because **the author wrote the rule, then broke it, then caught himself with it,
about four hours apart.**

Building the for-loop init-temp elision, b4 added a call-bearing row to its test
**specifically** so that an accidental widening of the elision to call-bearing
bounds would be caught — and said so, in advance, in writing. Then it broke the
elision on purpose as a vacuity check.

**The row kept passing.**

Eliding a call-bearing bound *swaps* the two calls. Both orders make the same
number of calls and produce the same iteration count, so **the call counter and
the iteration count were both blind to the only thing that changed.** The row now
logs call **order** — `iL` correct, `Li` broken — and the deliberate break moves
it.

**Two rules come out of this and they are different.**

1. **A counter cannot assert an ordering.** Whenever the defect you fear is a
   *permutation*, a count is structurally incapable of seeing it — and a count is
   the cheapest assertion to write, so it is the one that gets written.
2. **"I added a control for this" is not the claim "I watched this control
   fail."** This is the standing rule *a control is not a control until it has
   failed once*, and b4's case shows the rule needs its second half: **it must
   fail in the specific way the defect would produce.** b4's control failed
   nothing under a real break and still looked green; frankA's test, on the same
   subject, failed a row.

**Why it belongs beside face 61 rather than inside it.** 61 is a change that
passes every gate and buys nothing. This is a *gate* that passes and proves
nothing — the same green, from the other end. Both are cases where the careful
step (running the suite; writing the control) produced authority the evidence did
not support.

### 59a. REFINEMENT — a census is only as good as the GRANULARITY it classifies at

Same session, same night, and it sharpens 59 rather than repeating it.

b4's `PXXDBG=a.forinit` reported `init=ident, limit=binop` as the dominant shape —
**87 of ~250** in compiler.pas — so widening the elision from "plain ident" to
"pure arithmetic" should have captured most of it. It recovered **14 B on
mandelbrot and 28 B on jsondemo.**

The blocker was invisible *in the table*: those binops mostly **contain calls**.
`Length(s) - 1` is a binop whose child is a call. **b4 classified by root node
kind; the disqualifying node was a child.**

Face 59 says a census counts what *could* be affected and is read as what *will*
fire. This says something narrower and nastier: **the census can be wrong about
membership itself, at a depth its own output cannot show.** The number was real,
correctly counted, and answering a question one level shallower than the one that
mattered — and nothing in a bucket labelled `limit=binop` hints that half its
members are disqualified by a grandchild.

**Counter-move:** before trusting a classifier's buckets, ask what it would have
had to look *at* to be wrong — and classify at that depth, not at the depth that
was easy to reach.

### 63. A TICKET THAT PROPOSES A FIX MUST QUOTE THE CODE IT PROPOSES TO CHANGE

frankwasm, 2026-08-29, **and it is here because the author broke it while holding
it** — it wrote a version of "verify your claims" into three separate artefacts
the same evening and then filed a ticket asking for a change that was already in
the file.

It filed `feature-lib-tkinter-grid-pad-accepts-a-two-tuple` [B p45] proposing that
`padx`/`pady` become `Variant` so they could take a `(left, right)` pair.
`lib/pcl/tkinter.pas:104` already reads:

```pascal
const padx: Variant = 0
```

with line 106 carrying a comment stating **the exact semantics the ticket
proposed adding**. frankB investigated, changed nothing in `lib/pcl`, and found
the real cause was an N binding bug.

**Why the obvious lesson is useless and this one is not.** frankwasm's own
diagnosis: it had the rule as *"verify your claims"*, which **has no trigger, so
it fires never**. The operational form does:

> **A ticket that proposes a fix must QUOTE the code it proposes to change.**
> Not cite it — quote it.

*"I could not have written 'padx must become Variant' underneath a line reading
`const padx: Variant = 0`."* The trigger is mechanical (am I proposing a change?)
and so is the check (is there a quoted line?). Compare "be careful", which is
advice, and rule 7 of the sibling-arm audit, which is the same defect one layer
over — a prescription contradicted by its own ticket body.

**How the wrong reading was available without opening a file:** *"no overload of
grid matches these arguments"* plus *"scalar works, tuple fails"* reads as **the
tuple form is unimplemented**. That is face 34 again — a diagnostic that names a
cause, is correct about the fact, and points away from the fix, because the thing
it names is the **discriminator** rather than the defect. Cost of checking: one
grep.

### 63a. THE SUMMARY LINE IS THE DANGEROUS PART OF A WRONG TICKET

Same ticket, and the sharper half. frankB dispositioned it correctly — moved it
to `blocked/` with a `blocked-by:` on the real N bug — and **left the body
intact**, which is the right courtesy toward another agent's work.

The result was a **blocked, owned, triaged-looking ticket whose one-line summary
still said the facade rejects the tuple**. So the next reader is handed a library
edit that must not happen, by a ticket that looks settled.

**This is the closed-ticket hazard wearing its opposite face.** Earlier the same
night: a ticket in `done/` matching a live symptom, which would have **closed a
live question**. Here: an owned ticket with a false cause, which would have
**opened a dead one**. Both are cases where *the disposition looks settled and the
content is wrong*, and in both the artefact's filing status is what stops anyone
re-reading it.

frankwasm corrected it in place (`abdd61a2d`) rather than re-filing or moving to
`rejected/`, on the grounds that frankB had already dispositioned and owned it —
**their placement stands; only the false cause was mine to fix** — and threw away
a `rejected/` copy it had written rather than leave two tickets with one slug.
That is the right protocol when two agents share a ticket.

**Verification worth copying:** it checked three rows before amending, and the
third settles it — `grid(padx=(8, 6))` **alone** also fails. The tuple theory
cannot explain that row; "an earlier default was skipped" predicts it.

### 64. A TOOL THAT SCANS PROSE IN ITS OWN DIRECTORY WILL READ ITS OWN DOCUMENTATION AS DATA — and the report just gets shorter

pxx-a5, 2026-08-29, fixing `check_test_wiring`'s directory-blanket bug
(`7ce500b51`, `5adfc8b85`). **Three instances of one shape inside a single
ticket**, and not one of them was visible in the output.

`check_test_wiring` scans `tools/**` for references to test files. It **lives in**
`tools/`. So:

1. its own `SKIP_DIRS` literal credited the directories it lists — harmless
   today, because those are skipped anyway;
2. the devtest **docstring explaining why `helloworld/main.pas` is an orphan**
   credited that orphan. `wired_paths()` strips full-line comments only, and says
   so — docstring prose is deliberately counted as a reference. **So the sentence
   describing the finding became the evidence that cleared it;**
3. the new stem rule descended a subdirectory: the devtest carries `test/gui/` in
   a **fixture string** and defines its own `def main()`, and that bare `main`
   matched `helloworld/main.pas` two levels down.

**The failure mode is what makes it belong here: the report simply got shorter.**
6 → 5, with nothing red, nothing warned, nothing to notice. pxx-a5's own account
of why it caught it at all: *"I would not have caught this one either if I had not
re-run the checker after committing the fix rather than before."*

**Same family as the census matching its own comment (face 60's neighbourhood),
but sharper**, because here the artefact is the tool's *documentation of the very
defect it is looking for* — the more carefully you write down what the orphan is,
the more thoroughly you erase it.

Fix worth copying: a truncated `test/gui/$name.pas` token ends at the variable
with `.pas` after it, so it can only name a **direct child** — stem evidence is
now restricted to those, with a guard that fails without the fix.

### 65. A CENSUS RUN WITHOUT THE FILTER THE REAL CODE APPLIES AGREES WITH ITSELF, NOT WITH THE THING IT MEASURES

Same session, and pxx-a5 flags it as **the third time in one session** with an
identical mechanism, which is what promotes it from a slip to a face.

Its ticket claimed **three** sources of a false directory token, one being "prose
in a comment". Wrong: `wired_paths()` has stripped full-line comments since the
csqlite fix. **The census had been pointed at the source text without applying
the filter the real code applies** — so it reproduced a defect the tool had
*already fixed* and reported it as live. Re-censused properly: two sources, and
only one with a victim.

**Why it is not merely "check your work".** A census is the step you take
*instead* of guessing, so its output inherits the authority of measurement — and
this failure produces a number that is internally consistent, reproducible, and
about a program that does not exist. It was caught only because reading
`wired_paths()` in order to write the fix put the stripping loop in front of the
author.

**Counter-move:** a census must run the target's own preprocessing, or state in
its output that it did not. Sibling of 59 (population ≠ firing count) and 59a
(granularity): those measure the wrong *set* and the wrong *depth*; this measures
the right set with the wrong *input*.

**And the correction was written into the ticket rather than quietly deleted**,
which is the only reason the pattern was countable at all.

### 66. A relayed NEGATIVE is a claim like any other — and the cheap test and the expensive test disagree about it in the direction that looks like diligence

frankwasm, 2026-08-29. The standing rule *verify a peer's report before relaying
it* was written entirely about **positive** claims. A negative reads as modest —
*"I checked, there is nothing there"* — which is exactly why it draws no
scrutiny.

The case. frankB checked three known RTL unit names (`math`, `netdb`,
`strings`) against gtk-3.0's include roots for the `-I`-capture bug and called
it clean. frankwasm re-checked by cross-producting **every** RTL unit name
against **every** header on those roots, and found a fourth match frankB's
narrower test could not: `lib/rtl/png.pas` vs `/usr/include/libpng16/png.h`.

**One message away from relaying that as a live second exposure.** Then it
compiled the thing: `uses png` under the IDE's own `GTK3_INC` works fine. The
name match is a false positive, frankB's conclusion stands — and the *reason* it
stands is the finding:

| header | on the `-I` path | captures? |
| --- | --- | --- |
| `lib/crtl/include/strings.h` | yes | **yes** |
| the same file, emptied | yes | no |
| `/usr/include/libpng16/png.h` | yes | **no** |

A name collision is **necessary but not sufficient**. The reading that fits all
three rows: capture happens when the header successfully compiles **as a unit**,
and falls back correctly when it does not — pxx's own crtl headers are written
to be parsed by cfront, libpng's is not.

**The negative became a test case instead of an assurance**, and it also names
what the fix must not break: whatever makes `png.h` fall back to
`lib/rtl/png.pas` is already correct, and a fix that made `png` start capturing
would be a regression **nothing else in the suite would catch**.

Pairs with the standing *a false limit is quieter than a false fix — a wrong fix
gets re-tested, a caveat gets believed.* This is the mechanism underneath it:
the grep and the compile disagree, and the grep is the one that feels careful.
**Checking a colleague's negative is not distrust.**

### 67. A probe that CHANGES the failure has not necessarily reached the defect

frankwasm, same day; the sibling of 63. Where **63** says do not diagnose
without opening the code, **67** says do not accept a probe result without
reading *what the probe now reports*. **A faster failure and a different failure
are each indistinguishable from progress.**

Two experiments on the non-terminating `render_backend.py` compile **passed**,
and both were decoys:

- deleting `_as_tk_photo` made the compile fail **earlier**, at `:329` — which
  read as a fix, because the symptom moved;
- the scratchpad truncations terminated, because they were measuring **import
  resolution** rather than the bug.

Both are now in the ticket **as rejected causes**, which is the transferable
part: a ticket that lists only the failed attempts teaches its next reader that
everything untried is promising. Listing the attempts that *appeared to succeed*
is what makes them cost nothing twice.

The trap that produced the second one is now a line in that ticket: **any bisect
of this file must run in the app directory** — with the `cmp` result showing the
inputs are byte-identical and only the cwd differs. Invisible from inside a
correct-looking experiment.

### 68. Prio propagation is only as good as the edges somebody drew — and a STRUCTURAL blocker is exactly the kind that never gets one

The coordinator, 2026-08-29, on
`refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed`.

The board ranks by *"one human `prio:` propagated down dependency edges — a
blocker inherits the priority of what it unblocks, so you rate goals and the
chain follows."* That mechanism was **inert** on the one ticket standing between
Track C and being an independently staffable lane. It sat at p45, ranked below
five tickets it blocks, because:

```
$ grep -rl "c-exclusive-lowering" devdocs/progress/{urgent,backlog,backlog_new,unfinished,blocked}/
$          # zero files
```

**No in-edges, so nothing to inherit.** And the edges were not merely forgotten:
adding them would be a *false claim*, because `blocked-by:` means *cannot
proceed* and those five tickets can proceed perfectly well — by an agent holding
the A slot. Marking them blocked would hide real Track A work from Track A's
queue to repair a ranking artefact.

**The general shape: a ticket that blocks a LANE rather than a TICKET can never
be ranked correctly by propagation, and no checker can see it** — from the
ranker's side, an in-degree of zero is indistinguishable from a leaf. Any ticket
whose beneficiaries are *"most of track X"* under-ranks itself permanently and
silently.

Same family as **33** (a capability nothing invokes is quieter than no check):
the mechanism is present, correct, and simply never fires — and its presence is
what stops anyone asking whether it did.

### 69. `git merge-base --is-ancestor` answers a question about the TREE, and the question was about the BINARY

frankD, 2026-08-29, retracting its own claim. It could not demonstrate the
xtensa ordered-string bug because *"hosted xtensa hangs on hello-world under
qemu"* — measured on **pinned v393, `1d69760deabe`, pinned 22:29**, while
frankS's hosted-xtensa fix landed at **23:21**.

The instrument is the interesting part. Asked whether it had the fix, frankD ran
`git merge-base --is-ancestor`, got **yes**, and let *a fact about the checkout
stand in for a fact about the compiler that ran*. Both facts are true. Only one
of them was the question.

`pxx --where` settles it independently of any timing argument: the pinned
compiler resolves builtin units from its own frozen
`stable_linux_amd64/default/builtin/`, which differs from the repo's
`compiler/builtin/builtinheap.pas` — so **no invocation of that binary could
have contained a builtinheap fix**, whatever the tree said.

This is the sharpest instance yet of the standing rule *"still red" proves
nothing until you know which binary ran*, because here the agent **did** check,
with a real command, and got a real answer. **The sha CLAUDE.md tells you to
name is the compiler's; frankD named the checkout's.** Ancestry is not
provenance.

Withdrawn **in place, with the reason**, rather than quietly edited — a
corrected record that hides the correction is worth less than the error, because
the next reader learns nothing from it.

### 70. Reproducing a METHOD reproduces its BIAS — agreement between two runs of one matcher is not corroboration

frankD, same day, undercutting its own pass 2 unprompted.

Pass 2 opened by reproducing claude-N's builtinheap census before trusting it —
45 reached by x86-64, 30 cross-only, **identical numbers** — and reported that
agreement as evidence the seam had been measured. It was worth nothing. The
census matches `FindProc('<name>')`, and xtensa reaches four helpers through
**name-taking wrappers**, which that matcher cannot see. Corrected: **46/33**.

Running the same matcher twice tests the matcher's determinism, not the
territory. It is the same defect as **65** (a census run without the filter the
real code applies) with the roles reversed: there the census was blind to a
filter the code applies; here the *verification* was blind because it inherited
the census's own instrument.

Note the symmetry with the census's own methodology warning, which is now a
matched pair worth keeping together:

| direction | effect |
| --- | --- |
| prose describing an absence | produced the appearance of **presence** |
| an indirection (a name-taking wrapper) | produced the appearance of **absence** |

The finding it was checking survives — `PXXStrCmp3` is absent from
`ir_codegen_xtensa.inc` under **any** matcher, re-checked before the correction
was written. **The conclusion held and the method did not**, which is the same
shape the coordinator hit on `rtlconsts.pas` and is worth stating as a rule:
*verify with an instrument the claimant did not choose, or you have tested the
instrument.*

### 71. The claims that HELD were about someone else's code; the claims that FAILED were about the author's own

frankD, 2026-08-29, across nine instances of the comment-invariant audit — and
it is **the opposite of the premise the audit started from.**

That premise was *distance*: the dangerous comment is the one asserting
something about a sibling arm far away that you cannot see. Nine instances say
distance is not the axis. What predicts catchability is whether the claim is
**falsifiable by a command** — and underneath that, a split nobody predicted:

| claim is about | outcome |
| --- | --- |
| **someone else's code** — `PXXStrCmp3` on x86-64's `repe cmpsb` twin; the InternKey twin; ManagedElemKind's doors | **held** |
| **the author's own** — instance 8; `ir.inc:12732`; `builtinheap.pas:2039` | **failed** |

**Writing about a sibling makes you go and look. Writing about yourself does
not.** You already know what your code does — so the sentence is generated from
memory rather than from the file, and memory is exactly what goes stale when the
scope widens under it (see the `--threadsafe` row: the comment saying "x86-64
only" is dated four days *before* the four-target condition one line below it,
and the widening commit edited that line without touching the sentence).

Consequence for where audit effort goes: **the cross-file assertion that looks
most alarming is the one most likely to be true**, and the throwaway line
describing the function it sits in is the one to check.

### 72. A control that could only ever produce ONE outcome is not a control — and it reads as the strongest kind

pxx-a5, 2026-08-29, resolving the `-I` capture bug by **disproving both of the
ticket's negative results**, either of which would have shaped the fix.

The control that killed the search-order theory was: *"`-I` at a dir holding an
**empty** `strings.h` does not capture, therefore it takes a header with
content, therefore it is not search-order precedence."* Sound-looking, and it
sent two sessions away from the actual mechanism.

**The unit search accepts a candidate on `Length(UnitContent) > 0` — on
content, never on existence.** So an empty header is indistinguishable from a
missing one **by construction**. The experiment had exactly one possible
outcome *whatever the cause was*. It produced a true observation and zero bits.

The mechanism it hid is three lines of existing code: `-I<dir>` calls both
`AddCIncludeDir` and `AddPasUnitDir`; the `PasUnitDirs` loop probes
`.pas/.pp/.c/.h` **per root in flag order**; and it runs before the
compiler-anchored RTL dir. No C-side behaviour is involved at all — the
"parseable content" refinement built on top of the bad control was a second
wrong story fitted to the same data.

Distinct from **62** (*a control is not a control until it has failed once*):
there the control was never exercised in the failing direction; here it
**cannot** be. Ask what result would have falsified it. If the answer is
"none", it is an observation wearing a control's clothes — and it is more
dangerous than no control, because everyone downstream stops looking.

### 73. A survey's negative can be a property of the COMMAND LINE rather than of the thing surveyed

Same ticket, same day, and the coordinator relayed this one to three lanes as
settled fact.

frankwasm cross-producted every RTL unit name against every header on gtk+-3.0's
include roots, found `lib/rtl/png.pas` vs `/usr/include/libpng16/png.h`,
**compiled it, and reported it as a clean negative** — the row that turned
"header with content" into "parseable content". Excellent method; the compile
was the expensive test and it was run.

**It inverts.** `png` captures exactly like `strings` under a bare
`-I/usr/include/libpng16` *and* under the full gtk+-3.0 flags. It survived only
because `-Fulib/rtl` preceded the include roots in that particular invocation,
and the loop is searched **in flag order**.

Two consequences, and the second is the general one:

- **`apps/ide/build.sh` was EXPOSED, not clean** — it passes `$GTK3_INC`
  *before* `-Fu"$ROOT/lib/rtl"`, which is the capturing order.
- **A collision survey run with `-Fu` first reports zero collisions however many
  exist.** The negative was not a weak claim about headers; it was a true claim
  about an argument order, mistaken for one about the code.

**66 said a relayed negative is a claim like any other. This is 66 turned on the
relay itself** — the coordinator carried frankwasm's row to three lanes with its
own authority attached, having verified nothing, one hour after banking the face
that says not to. *The rule you are enforcing is the one you will not apply to
yourself.*

Worth keeping: the finding was **preserved verbatim under a banner** rather than
deleted when it was overturned, because the fourth collision it found is real
and is now in the test's header comment. A retraction that erases the work
destroys the part that was right.

### 74. A test whose two arms are byte-identical cannot witness the thing it is named for

pxx-a5, same day, found only by poisoning a copy of the shadowed file.

The first cut of the fix deferred C behind **other C** as well, so
`-Futest/gtk3stock`'s `gtk3_c.h` lost to `lib/pcl/gtk3_c.h` — a real shadow,
silently defeated. `test_c_gtk3_stock` could not see it: **both headers include
the installed GTK surface, so the two builds are byte-identical**, and its own
comment already admitted its `readelf` row "structurally cannot" assert the
version. The test was passing on a property no arm of it could distinguish.

The remedy is the transferable part: **give the witness an asymmetry the
compiler must reveal from outside.** `test/uses_shadow/math_ext.h` declares
`abs` and omits `labs`, so a program calling `labs` answers *which file did the
`uses` resolve to* by whether it links — an observable that does not depend on
reading the compiler's mind. Five later C probes were guarded the same way.

Note the discipline that made it stick: the broken first cut was **rebuilt** to
confirm the new test goes red against it, then restored. A witness that has not
been shown failing against the defect it was written for is a hope (**62**).

### 75. A correct observation retracted on a coordinator's wrong theory leaves nothing behind to re-test

The coordinator, 2026-08-29. frankD reported *"hosted xtensa hangs on hello-world
under qemu (120s, killed)"* and could not demonstrate the xtensa string-compare
bug because of it. The coordinator noticed frankD's binary was pinned v393,
predating frankS's wall-3 fix, and told it the measurement was **stale**. frankD
retracted.

**The retraction was wrong.** frankS then demonstrated why: `HeapMmap` in
`builtinheap.pas` has arms for x86-64, aarch64, arm32, i386, riscv32, wasm32 and
bare-ESP and **no `CPU_XTENSA` arm at all**, so hosted xtensa fell through to
`Result := -1`, the heap base was `-1`, and the first allocation faulted at
`$FFFFFFFF`. *"That program could not have worked on any pin."*

**Two claims were bundled in one message and only one of them was sound:**

| claim | verdict |
| --- | --- |
| your *justification* is unsound — `merge-base --is-ancestor` answers about the tree, not the binary | **right** (face 69) |
| therefore your *observation* is stale | **wrong** — it was true, for a cause nobody had found |

The methodological correction was correct and is what made the substantive one
credible. **A right criticism carries a wrong one home.**

Why this is worse than a wrong fix and not merely equal to one: a wrong fix gets
re-tested by the next person to touch the code. **A retracted observation is
gone** — nothing points at it, no test covers it, and the retraction carries the
coordinator's authority. Same family as *a false limit is quieter than a false
fix*, one step further: here the limit was removed rather than added, and the
truth went with it.

Operationally: **when correcting someone's method, say explicitly whether the
conclusion also falls.** They are separable, they usually are separate, and the
person being corrected cannot tell which you meant.

### 76. The self-host fixedpoint is structurally BLIND to C lowering — the one gate everyone trusts cannot see Track C at all

frankC, 2026-08-29, refusing to hand up a green gate it knew proved nothing.

`make compiler/pascal26` is the per-fix loop's whole gate and is, for free, the
byte-identical self-host fixedpoint. **Compiling `compiler.pas` is compiling
Pascal.** `CProgramMode` is never set, so no C-exclusive lowering routine is ever
called. For the seven routines of the `cir.inc` slice-1 relocation, the
fixedpoint **goes green whatever is done to them — including deleting their
bodies.**

And the `parser.inc` precedent inverts here rather than transferring.
`compiler.pas:126` records that each `pasparser_*` slice is *"a contiguous range
re-included where it sat, which is what makes the carve-out provable by the
self-host fixedpoint rather than by reading it."* That argument works **because
Pascal parsing is what the fixedpoint exercises.** A C carve-out is the exact
case where it does not.

This is **31** (*a gate using the artefact as its own oracle cannot see defects
in what produces it*) with a sharper edge: the gate is not merely weak here, it
is **orthogonal**. And it is invisible, because the gate's output is identical in
both worlds.

**The remedy frankC built is the transferable part, and it is cheap.** For a
claim of *pure relocation*, output equality is too weak — relocation must
produce **identical machine code**. Ten C tests exercising all seven routines,
each compiled and `sha256`'d against the pre-move compiler `261e6cd2b58f`, all
ten required to rebuild byte-identical afterwards. The fixedpoint still runs, but
is reported as what it actually is here: a check that *the rest of the compiler*
still builds.

**Standing rule adopted for this refactor and for every per-arm extraction: a
C-side byte-identical gate, captured BEFORE the move.** Generalises past C — any
lane whose code the self-host build does not execute (C, NilPy, Rust, Zig, the
cross backends) is gated by something that cannot fail on its changes, and needs
its own oracle rather than the shared one.

### 77. A sentinel initialised by ONE entry point is not a sentinel — the hole is an absence, not a leak

frankA, 2026-08-29, root-causing the NilPy import-order type capture.

`ParsingClassBodyCi := -1` is set in exactly one place: `pasparser_prog.inc:569`,
inside **`ParseProgram`** — the *Pascal* entry point. **Every other frontend
enters elsewhere and never runs it**, so the global keeps its BSS default of
`0`. And `0` is not a sentinel; it is a **valid `UCls` index**. Class 0 is
`TGuid`.

So NilPy believed it was inside `TGuid`'s class body for the entire
compilation. `AddClassLikeType` calls `AddNestedType(ParsingClassBodyCi, …)`
unconditionally when it is ≥ 0, so **every top-level class in every imported
unit became a nested type of `TGuid`**; `ParseTypeKind` consults
`FindNestedType` before `IsClassType`; and class-scope lookup is deliberately
not visibility-gated.

| driver | `ParsingClassBodyCi` | `nestCi` | `SizeOf` |
| --- | --- | --- | --- |
| Pascal | **−1** | −1 → final else | 4128 ✓ |
| NilPy, good order | **0 (TGuid)** | 101 = the textfile *record* | 4128 ✓ |
| NilPy, bad order | **0 (TGuid)** | 74×101, **1×108 = the class** | **8** ✗ |

**The coordinator predicted the mechanism and got the KIND wrong**, which is the
part worth keeping: the prediction was *"an unbalanced restore leaks it for the
rest of the compilation"*. The save/restore pairs are **balanced** — there is no
`Exit` in either range, and every restore in the NilPy run returns to `0`
**including the first**, so `savedPCB` was already `0` before any class body
opened. Same symptom, opposite defect: **balancing a restore would have changed
nothing.** A leak is a value that escapes; this is a value that never arrived.

It also explains cleanly what had bothered three sessions: **the visibility
layer returned the correct verdict throughout and simply was not the layer that
answered** (`ci=101`, right, in both NilPy runs — `nestCi` overrode it). Nothing
in it was broken.

**The fix is shared, not a NilPy patch:** `ResetDeclScopeSentinels` in
`symtab.inc`, called once before the frontend dispatch, with `ParseProgram`
calling it instead of keeping its own copy of the literals. Exact precedent
three lines above — `EmitTlsMainInstall`, *"one call site rather than one per
driver"*, from `bug-a-threadsafe-segfaults-on-every-nilpy-program`. **Second
instance of the same shape at the same seam.**

And it fixes a **latent sibling nobody had reported**: `ParsingClassConstCi`, in
the same block, same `-1`-vs-BSS-0 problem, same single init. **ALGOL, Erlang,
Rust, Zig, C and asm all had the same hole** — the bug was reported by NilPy
because NilPy is the frontend with users, not because it was the frontend
affected.

**Generalisable:** a per-compilation global whose "unset" value is not its
zero value must be initialised where compilation begins, not where one
frontend begins. Grep for the *initialiser*, not the declaration — the
declaration is in the shared file and looks fine.

### 78. ADJACENT values make an operand observable; distinct, far-apart, memorable values make it invisible

frank-optimize-b4, 2026-08-29 — and it inverts the instinct, which is why it is
worth stating rather than assuming.

Writing a codegen test, the natural move is to pick values that are distinct,
far apart and memorable, so a wrong answer is obvious to a human reading the
output. b4 did exactly that, deliberately. **It produces maximally insensitive
rows.**

The row was `if a > b` with `b = -5000000001`. That comparison is true for
**whatever junk a wrong register holds**, so a genuine break — `r13` → `r14` —
passed. The value was easy to read and impossible to fail against.

**The fix is straddling.** With `blo = a-1` and `bhi = a+1`, the pair
`a > blo` / `a < bhi` is true **only** for a register holding *exactly* `a`, and
only for those two slots — so one shape catches a wrong reg field, a wrong rm
field **and** a wrong displacement together. Mirrored (`blo < a`, `bhi > a`) for
the reversed operand roles. Six deliberate breaks now move it: mem reg field,
mem displacement ±1 slot, both reg/rm forms, each REX bit.

Generalises past codegen: **a test value's job is to be adjacent to the wrong
answer, not far from it.** Far-apart values test that the program ran; adjacent
values test that it computed. The readable choice and the sensitive choice pull
in opposite directions, and readability wins by default because nobody is
checking sensitivity.

### 79. "The patch applied" is not "the behaviour changed" — and an edit-script assertion proves only the first

Same session, same day, and it is the reason face 78 was nearly missed.

b4's first deliberate break was
`$85 or ((lreg-8) shl 3)` → `$85 or (lreg-8)` — visibly a wrong ModRM reg field.
**For `r13`, the only register that occurs, it emits the identical byte**,
because `$85` already has bit 2 set. The break was an **identity**.

The edit script asserted the source matched **exactly once**, which is a
genuinely good hygiene check — and it proves the patch was applied to the right
place. It says **nothing about the encoding changing.** So a passing test was
read as *"the test is vacuous"* when in fact **the break was vacuous**, and the
diagnosis was pointed at the wrong artefact entirely.

Pairs with **62** (*a control is not a control until it has failed once*): here
the control did fail to fire, and the conclusion drawn was about the test rather
than about the control. **When a deliberate break does not turn a test red, the
break is a suspect too** — verify the injected fault actually changes the
artefact (the bytes, the output, the sha), not merely the source.

Third occasion in this campaign that a control looked adequate and was not,
which is why b4 moved it to the head of the ticket as a standing rule rather
than leaving it inside a slice write-up. **A lesson recorded where it was
learned is a lesson filed under the wrong subject.**

### 80. The predictor is whether the sentence and its TRUTH-MAKER can be changed independently — not distance, not authorship

frankD, 2026-08-29, after five passes and nine instances. **This supersedes
both earlier readings** (distance, then face 71's self-vs-sibling) and explains
why each looked right.

Pass 5 ran the `must never` single-site family specifically to give face 71 a
chance to **fail**. It did not — eight of nine hold — and the reason they hold
is the finding: a single-site `must never` is **not a claim about elsewhere**.
It is an *instruction with its enforcement two or three lines below it*. The
sentence and the thing that makes it true **cannot drift apart, because they are
the same edit.**

Everything that failed tonight could be changed independently of its sentence:

| the sentence | its truth-maker |
| --- | --- |
| "the four cross backends" | the backend list |
| "x86-64 only" | a four-target gate |
| "the one place they can" | three call sites |
| a documented frame layout | six prologues |
| "the gate that stands today" | a debug print |

Everything that held could not.

**Why the earlier readings looked right:** proximity usually *implies*
co-editing, so distance correlated with the real cause without being it. And
instance 8 is the exception that proves it — eleven lines apart, but describing
**a loop's behaviour**, which the loop's edits can change without touching the
words.

Operational form stays the short one, because the predictor is truer and the
rule is quotable: **a comment containing a count, a target list, or
"only"/"every"/"always" asserts something a command can check — write the
command in the comment, or write a sentence carrying no number.**

### 81. When ACCEPTING a correction, ask which half you are accepting

frankD's reciprocal to face 75, and it closes the loop from the other side.

75 says: *when correcting someone's method, state explicitly whether the
conclusion also falls.* frankD's addition: **the receiver has a duty too.** It
took a method correction as settling the substance, *"and that is how I ended up
replacing a wrong explanation with another one."*

A correction arrives as one message and is accepted as one act, but it almost
always carries two separable claims — *your reasoning was unsound* and *your
answer was wrong*. The first does not imply the second. Both parties defaulted
to bundling them, in the same exchange, in opposite directions.

### 82. A PROVENANCE line goes stale faster than any comment in the tree

frankD, same day, after being wrong about provenance **twice in one evening, in
opposite directions** — first citing a stale binary, then citing a working-tree
build that had since landed on master (`dc62fe3cd`).

Ordinary comment rot runs in days to weeks — the `--threadsafe` scope survived
54 days, the csmith backend count 7. **A provenance line can be false within
minutes**, because the thing it describes is moving *while it is being written*.

So it is the audit's own shape applied to the audit's own metadata, and the
remedy is not "be careful": it is to **leave superseded provenance visible
rather than editing it in place**. frankD kept both wrong citations in the
ticket, because *"it has now been wrong about provenance twice in opposite
directions and the pattern is more instructive than either correction."*

Corollary for anything with a `Verified at:` line: **re-check it at read time,
not at write time.** The correct citation for that finding is now master at
`dc62fe3cd` or later — verified by confirming the sha is an ancestor of
origin/master and reading the `CPU_XTENSA` arm at `builtinheap.pas:794`, rather
than by trusting the report that said so.

### 83. A file-scoped grep on a CROSS-FILE gate produces the exact signature of a forgotten gate

frank-optimize-b4 answering frankD, 2026-08-30 — and this is face 80's cost
seen from the other side.

frankD traced `RcProcHasExc` through `ir_codegen.inc`, where the comment calls it
*"the gate that stands today"*, and found it **assigned at `:10102`, printed in a
`PXXDBG a.resid` `WriteLn`, and tested nowhere** — no `if`, no `Exit`, nothing
reaching codegen. That is indistinguishable from a gate somebody forgot to wire,
and it was correctly escalated rather than guessed at.

**The gate is live. It is enforced in `compiler/symtab.inc`** — two
`if RcProcHasExc then Exit;` at `ResidentSlotIsDead:5337` and
`FloatResidentSlotIsDead:5393`, exactly the passes the comment says it gates.
`ir_codegen.inc` only sets and prints it.

**The inference was correct for the evidence; the evidence was file-scoped.**
Nothing in the search was wrong — the *boundary* of the search was, and a
file-scoped grep does not announce that it stopped at a file boundary.

**Why this belongs beside 80 rather than under it.** 80 says a sentence and its
truth-maker that can change independently will drift apart. Here they had **not**
drifted — the comment was true. The separation cost something else:
**unverifiability.** b4's own statement is the keeper:

> *"A cross-file gate that is described in file A and enforced in file B is
> readable exactly once — by whoever wrote it, on the day they wrote it."*

So separability has two costs, not one: the comment may go stale, **and** even
while true it cannot be checked by anyone who does not already know the answer.
The second is quieter, because the artefact is correct and the reader is the
one who fails.

Remedy is cheap and is being applied: **name the enforcing call sites in the
describing comment.** A cross-file claim that carries its own call sites is
falsifiable by a reader; one that does not requires its author to be awake.

**Note the near miss in the other direction.** The sibling
`SymWrittenInProtectedSpan` genuinely *is* instrumentation-only — and is still
not a hole, by containment rather than by intent: the coarse gate refuses any
body containing an `IR_EXC_ENTER`, the fine one would refuse only symbols
written inside a protected span, so **every symbol the fine gate would refuse is
inside a body the coarse gate already refused.** Wiring it can only relax.
An unwired check is usually face 33; this one is safe, and the argument that
makes it safe is exactly the kind that must be written down rather than
re-derived.

### 83a. Adjudicating two lanes' contradictory measurements — and the witness decides, not the seniority

Coordinator, 2026-08-30. Face 73 (`png` is captured; the negative was a
property of the flag order) came from pxx-a5. frankB then pushed back **with
measurements**, on the same pinned binary (v393, `1d69760deabe`):
*"`png` cannot be captured at all — not with libpng16 on `-I`, not with the real
`png.h` copied into a bare dir"*, and derived a rule from it: that the trigger
needs the name to be one **we** ship a header for (`lib/crtl/include`:
`math.h`, `netdb.h`, `strings.h`).

Two lanes, direct measurements, opposite answers. Adjudicated by measuring
rather than by deciding who to believe:

```
$ pinned -I/usr/include/libpng16 -Fulib/rtl w.pas     # -I first
  error: undefined variable (PngSignatureValid)        <-- Pascal unit NOT loaded
$ pinned -Fulib/rtl -I/usr/include/libpng16 w.pas     # -Fu first
  error: no overload of PngSignatureValid matches      <-- symbol EXISTS
```

**`png` is captured.** face 73 stands; frankB's counter-claim and the rule
derived from it are wrong.

**Why frankB got the other answer is the transferable part, and it is face 74.**
A bare `uses png` **compiles clean in both orders** — sizes differ
(`procs=1046` vs `293`, the C header's ~1000 declarations vs the Pascal unit's)
but nothing fails. A probe that only asks *does it build* has two
indistinguishable arms. **The witness has to name a symbol only the Pascal unit
provides** — `PngSignatureValid` — and then the two orders answer differently in
one line.

**And the correct verdict on the original exchange is a SPLIT, which is exactly
what face 81 demands be stated:**

| claim | verdict |
| --- | --- |
| coordinator: "your all-clear was wrong **because the survey ran with `-Fu` first**" | **wrong reason** — frankB's check was a *filesystem* test, so flag order could not affect it |
| coordinator: "`apps/ide/build.sh` was exposed" | **right** — it passed `$GTK3_INC` before `-Fu`, and `libpng16` is on the gtk+-3.0 `-I` path |
| frankB: "`png` cannot be captured" | **wrong** — measured above |
| frankB: "the trigger needs a header *we* ship" | **wrong** — libpng's header is not ours and captures |

So the coordinator relayed a right conclusion with a wrong reason, and was
corrected by a lane whose correction was itself wrong, on a point the corrector
had measured. **Nobody in the chain was careless; three of the four claims came
with evidence.** What separated the true ones from the false was solely whether
the probe could have produced a different answer.

### 84. A SUBSET measured as if it were the whole — and "does not reproduce" is the most expensive way to be wrong

pxx-a5, 2026-08-30, correcting a measurement the **coordinator** had written into
`regression-test-core-test-mgmt-operators` and dispatched on.

The coordinator's section said the red *"does NOT reproduce here"*, and offered
three hypotheses for the discrepancy: host-specific, non-deterministic, or fixed
by a later commit. All three were answering a question that had not earned
asking.

**`test-core#src:test/test_mgmt_operators.pas` is not one assertion.** The target
compiles the positive program and diffs it against `.expected`, **and then runs
three NEGATIVE rows** that each compile a program which must be *refused* and
fail if the compile succeeds. The watcher's log tail is one of those strings
verbatim.

| row | at HEAD |
| --- | --- |
| positive vs `.expected` | PASS |
| `..._array_refused.pas` | **COMPILED — must be refused** |
| field / copy refused | refused |

*"Compiles clean, runs, matches `.expected` byte for byte"* was true, is still
true, and **is about a different assertion.** `.expected` could not have absorbed
the failure, because the failure is not in that program at all.

**This is face 72 one level up:** not a control that could not discriminate, but
a **subset measured as if it were the whole**. And the failure mode is worse than
a wrong answer, because *"does not reproduce"* **redirects everyone else** — it
converts a live bug into a puzzle about test infrastructure, and the puzzle is
more interesting than the bug, so that is where the effort goes. Three
hypotheses were generated to explain a discrepancy that did not exist.

**The first move on a red job is to run the job, not to explain the difference
between two runs.**

### 85. A guard can read a field that was never about the thing it is guarding, and pass for years on RECYCLED memory

Same ticket, and the mechanism is the reason face 84 mattered.

`WrapManagementOpsRange` guarded on `SymTR[i].RecId`, set from
`Syms[i].RecName` — and **`RecName` is meaningless for an array symbol**: only
`AllocVar`/`AllocParam` write it, and an array's record id is `ElemRecName`. The
refusal was reading a field that was never about the element type, **and it
fired anyway, because slots are recycled and the stale value happened to be the
right record.**

`4a3c88532` — *"AllocArray/AllocDynArray must clear RecName on a recycled slot"*
— cleared it. The guard saw `REC_NONE`, the whole `if` was skipped, and an array
of a managed record started compiling with an `Initialize` that never runs.

**So the mechanistically-adjacent commit was adjacent in the opposite direction
from the obvious one: it did not introduce the bug, it removed the accident the
bug was standing on.** A correctness fix that makes a latent defect observable
looks exactly like a regression, and bisect points at it either way.

That commit **named this class in its own message** — *"the audit found 20 more
`RecName` reads guarded only by `TypeKind = tyRecord`, which is not a guard at
all for an array symbol; that is a separate ticket"*. This is one of the twenty,
reached from the other side: **not a read that returns the wrong record, a read
that returned the right one by luck.** First of that population to surface on its
own, and it surfaced as a **silently missing diagnostic** rather than a wrong
answer — which is why no test caught it.

**And the honest negative in the fix is worth as much as the fix.** pxx-a5
expected globals to be the shape the accident could not have covered, measured
both arms against the reverted build, and **found they were refused there too**
— so the new global arm is breadth across two code paths, **not** the witness it
was predicted to be. Recorded that way, *"because the reverse would have been
the better story and is not what the measurement showed."*

### 86. A control naming a TYPE FAMILY must name the BINDING FORM too — literal, local and parameter take different paths

frankwasm, 2026-08-30, and it is the third instance of face 72 in one night,
this time found in someone else's work rather than its own.

`19dc5586e` shipped **13 probes**, one of which was *"a str method on a
**literal**"*. That is a reasonable-looking control for the arm it was
changing — and it is **the single str-receiver shape that still works**, because
a literal never reaches the arm that is broken. The control was present,
plausible, and **could not have failed for this bug.**

The defect it missed: a str method whose return type is *not* a string, on a
receiver that is a **variable**, returned from a `def`.

```python
def f():
    y = "abc"
    return y.find("b")
print(f())          # SEGV
```

`.upper()`/`.lower()`/`.replace()` survive only because **the wrong answer
equals the right one**; `.find`/`.count`/`.startswith`/`.endswith` die. So even
the surviving cases are not evidence of correctness.

**The rule, and it generalises past NilPy:** when a control names a type family
("a str method", "an integer argument", "a managed record"), it must also name
the **binding form** — literal, local, parameter, field, temporary — because
those take different paths through the compiler and a control that picks the
easy one tests the path that was never in doubt. Three of tonight's findings
share this shape.

**Measured, not reasoned:** `PXXDBG=a.ir` shows both builds emitting the same
call, the crashing one opening with `zero_sym` on `$pyresult` where the working
one has `const_int` — the `def`'s result symbol typed `tyAnsiString` while the
call returns Integer/Boolean, so the caller reads a small integer as a string
handle. And the suspect commit was confirmed **by building both sides**
(`9c8e20c58` fixedpoint `100300ef2b3a` prints 1; `19dc5586e` fixedpoint
`ecf52e008b11` segfaults), not by reading the diff.

**The cause is a comment that already warned about this, one type-family over.**
`PyRetMethodType` resolves user-class methods only; for a string receiver it
returns `tyUnknown` *and* leaves `recvCi2 = -1`, so neither branch fires and the
expression chase claims the receiver's own type — **exactly what that function's
own header describes as "the defect"**. `PyStrMethodInfo` already tabulates the
right answers and is simply never asked.

**And the ticket's name is actively misleading:** neither `startswith` nor the
tuple is involved. A fix validated against `test_nilpy_startswith_tuple.npy`
alone passes while `.find` and `.count` stay broken — so the regression test
needs a str→int row, a str→bool row, a str→str control **and** a
literal-receiver control.

### 87. Branching on a boolean hides its magnitude — print `Ord(x)`, do not `if x`

frankS, 2026-08-30, and it is the fourth member of tonight's provenance family:
**trusting a rendering of a value instead of the value.**

Before writing xtensa's ordered-string arm, frankS measured the **equality** arm
it would be modelled on. On Call0 — **the default ABI** — ansistring `=`
returns a **heap handle** instead of 0/1. Non-zero, so `if a = b` was simply
always true: `'zz' = 'aa'` answered true, **and so did `<>`**, which is how two
tests contradicted each other.

**It was only visible because `Ord(a = b)` was printed rather than branched on.**
`545267744` and `true` are indistinguishable through an `if`. A boolean is the
one type where the language's own control flow destroys the evidence — every
wrong value renders as the same word.

Same family as *"I have the right tree" standing in for "I have the right
binary"*: the artefact was inspected through something that normalises it.

### 88. Four sites, one concept, and the ONE correct hand-written copy is what made the broken spelling look like house style

Same ticket, and the root cause underneath 87.

The managed-string arms addressed expression-stack slots as
`sp + argBase + 4*idx`. **That is the WINDOWED discipline** — windowed keeps
`sp` fixed and indexes upward. **Call0 moves `sp` on every push** and never
maintains `XtSpillDepth`, so `argBase` there is a stale counter and every offset
read a neighbouring **live** slot rather than faulting. *The wrong value was
always a plausible one.*

One defect, four symptoms, all measured: `=` returning a heap handle;
`s := s + x` in a loop SIGSEGVing and `Copy` bus-erroring (**frankS's own concat
ticket from two hours earlier, whose guessed cause — interior payload arithmetic
— was wrong**); `PXXStrSetLen` receiving its arguments reversed; and 12 bytes of
stack leaked per compare and per concat.

**The detail worth keeping:** the fourth site, `PXXDynSetLen`, **already had
Call0 right, by hand.** It was routed through the new helper anyway — *"one
correct hand-written copy sitting beside three broken ones is precisely what made
the broken spelling look like the house style."* A correct duplicate is not
neutral; it launders its neighbours.

And the ordered arm was deliberately **not** cloned from the equality arm: one
arm serving both, differing only in callee and tail, *"since 'a second path is
the one nobody visits' is how this bug happened in the first place."*

**The header was fixed by DELETING the count, not by correcting 4 to 5** —
*"correcting four to five would have left the trap armed for the sixth target."*
That is frankD's rule applied by a different lane within hours of it being
written.

### 89. "The other arm is the broken one" is a conclusion, not an observation

frankS, same day, flagging it against its own filed ticket.

Three windowed-ABI faults remain (frozen strings, `Copy`, dynarray
`SetLength`). The obvious read is *windowed is the broken arm* — and it is
wrong. **Call0 and windowed differ in two independent ways, and the defect
fixed today had Call0 wrong for months while windowed was right.** Neither arm
is the trustworthy one.

Confirmed as pre-existing rather than assumed: the change was **stashed**, the
pre-change compiler rebuilt, and the identical bus errors reproduced — so the
three are not fallout from this work and are not claimed as such.

Sharpened by the stakes: **windowed is the ESP-IDF ABI**, so on real hardware
those three would have been unexplained crashes with nothing to compare
against — which is the oracle argument again, from the third direction tonight.

### 83b. The DEFAULT search path cannot be ordered ahead of a flag, because it is not one

frankB, 2026-08-30, and it strictly strengthens 73/83a — which the coordinator's
own adjudication could not have found, because **both arms of that test passed an
explicit `-Fu`.**

Measured on pinned v393, witness `PngLastError` (a symbol only `lib/rtl/png.pas`
provides):

```
$ pinned n.pas                                   -> ok, procs=293
$ pinned -I/usr/include/libpng16 n.pas           -> undefined variable (PngLastError)
$ pinned -Fulib/rtl -I/usr/include/libpng16 n.pas-> ok, procs=293
```

**The middle row has no `-Fu` in sight and still captures.** So the rule is not
*"whichever of `-I` and `-Fu` comes first"* — it is:

> **Any `-I` root beats the default RTL path. Only an explicit, EARLIER `-Fu`
> can win.**

Which means **every build script that passes `-I` and relies on the default path
for the RTL is exposed**, and "we don't pass `-Fu`, so ordering is not our
problem" is exactly backwards.

**The coordinator's adjudication was correct and under-scoped for a structural
reason worth naming: a test that varies one factor across two arms cannot see a
third arm where the factor is ABSENT.** Present-early and present-late were
compared; *absent* was never run, and absent is the common case in real build
scripts.

**Consequence that closes the loop on the earlier disagreement:** frankC had
recommended passing the GTK3 include root *"to every probe, inert where
unneeded"*. It is **not inert — it is the capture mechanism.** Passing it to
every probe would have captured `png`, silently. Directory-scoping is right for a
second reason nobody in that thread could have given at the time.

**And the corrected split on the original exchange, per frankB's own narrowing:**
its filesystem check was genuinely not invalidated by flag order — that part
survives. **Everything built on top of it did not**, including its conclusion
that `apps/ide/build.sh` was safe. The reorder it had labelled belt-and-braces
was the actual fix. Recorded because a partial vindication is the easiest thing
to over-claim, and frankB narrowed it against itself.

**Two failed witnesses before the working one**, both saying "undefined" in
*every* arm including the control — `PngSignatureValid` needs an argument, and
`TByteArray` is not from `png.pas` at all. **A witness that fails identically in
every arm is 74 again**, and the tell had been sitting in its own output the
whole time: `procs=1046` versus `293`, printed and not read.

### 90. The comment that caused three bugs survived all three fixes — because each fixer corrected the CODE it was in

frankD, 2026-08-30, closing the comment-invariant audit on its own root cause.

`builtinheap.pas:2625-2631`, the `PXXStrUnique` comment, is the sentence that
produced **instances 1, 2 and 3** of that ticket. All three were fixed on
2026-08-29. `git blame` still dates all seven lines to `8a263f504`,
**2026-08-14**.

**Three agents found three bugs caused by believing it, fixed all three in one
day, and not one of them edited it.** Each corrected the code the sentence was
about and moved on. The comment is the only artefact in the chain that nobody
treats as changeable, because it is not what failed.

**It is still load-bearing, not merely stale.** *"The single choke point for byte
mutation"* tells the next author that a fifth mutation site needs no
invalidation as long as it routes through `PXXStrUnique` — **which is exactly
the reasoning that produced sites 2 and 3.** Site 3 postdates the fix.

**And the second clause is the subtler half, worth the whole entry:**

> *"`PXXStrSetLen` needs no such call: it always allocates a fresh block."*

That is **true of the routine it names and false of the thing it is used for** —
x86-64 does not call it, and its inline resize has an in-place arm. So **a reader
who checks the claim against `PXXStrSetLen` confirms it and stops.** The
verification succeeds; the conclusion is still wrong.

**Same mechanism as 88, in prose instead of code.** There, `PXXDynSetLen` having
Call0 right by hand made the broken spelling look like house style. Here, a
clause that is correct about the routine it names makes a false claim about the
operation survive checking. **The thing that gets checked is not the thing that
is load-bearing.**

Filing note that generalises: it must land **in one commit with the consumer
copy at `pylib.pas:3361`**, or the next reader finds whichever was left — which
is how this survived in the first place.

### 90a. A scope limit is worth most when it names the case that would have hidden the one real bug

Same ticket. frankD's differential closed the seam: `PXXStrEq` 13 cases,
the `PXXVarClear` family 10, the console-read family 8 — x86-64 inline twin
against the riscv32 portable helper, **all identical**, including `v := v`, the
shape that broke as `bug-a-a-variant-assigned-to-itself-becomes-empty`.

**And the limit is stated precisely where it hurts: xtensa was NOT tested.** The
pinned compiler resolves builtin units from its own frozen snapshot, which
predates frankS's `HeapMmap` arm, so hosted xtensa cannot allocate under the
sanctioned toolchain. **The one genuine divergence in this seam tonight was
xtensa-only and would have been invisible to exactly this diff.**

So the table means *"the portable helper and the x86-64 inline agree"*, **not**
*"all five cross backends agree"* — and a reader who takes the second reading
gets precisely the wrong lesson from a correct measurement. Compare face 8: a
survey will not name its own scope. This one does, and it names the scope that
matters rather than a generic caveat.

### 91. A prediction that matches on COUNT reads as confirmed — check the MEMBERSHIP

pxx-a5, 2026-08-30, rejecting `regression-cascade-154d1aa3fba6`.

The triage predicted the cascade would resolve to *"the four pre-existing
regressions and nothing else"*. **The count is four. The membership is not.**
Two of the predicted four have since been **fixed** (both tickets in `done/`),
and two others took their place from the "duration signals" and "pending
packages" rows.

*"Four, as predicted"* is what a reader sees, and it is the same reading whether
the set is right or entirely different. So the close states it **job by job**
rather than as a total.

Sibling of the miscounted-enumeration family (**frankD's** *"the four cross
backends"*, **frankS's** `HeapMmap` seventh arm) with the failure inverted: there
a count was **wrong** and read as complete; here a count is **right** and reads
as *correct*. **A matching total is evidence about the total and nothing else** —
and it is more persuasive than a mismatched one, which at least prompts a look.

### 92. A repair that is written but never read — gated behind a threshold the case it rescues can never reach

Same session, and it is face 33 with a mechanism rather than an omission.

`learn_timeout()` raises a timed-out job's recorded duration *"so the next run
gets room"* — and deliberately leaves `n = 0`. **Its only consumer is gated on
`n >= METRICS_MIN_RUNS`.** So for a job that has **never passed on this host**,
the raise is written and never read — **precisely the job it cannot rescue.**

It works perfectly for the case it was written for (`uforth`: n=5, used to pass,
got slower) and does nothing for the case that **looks identical from outside**:
a job that is red for want of budget. Two different states, one symptom.

`calibrate()` cannot cover for it either: `max(1.0, dt/0.35)`, and the fast box
measures 0.25-0.27s, so **the floor is the answer** — the slow box records scale
1.0 too. **A 2010 Westmere gets byte-identical budgets to a 2013 Ivy Bridge.**
The probe has no dynamic range in the region where it matters.

Consequence measured, not argued: `parallel_reduction` and
`sqlite-threads-aarch64` **pass on one box and have never once passed on the
other**, and cost triage cycles every sweep.

**And the fix was correctly NOT taken.** The `n`-gate is what stops a hang
ratcheting its own budget — `heal_latched_metrics` documents a real
90 → 2902 → 3522s climb. So *"how much may a never-passed job earn"* is a design
fork, not a patch. **The recommendation routes around the fork entirely: fix the
probe's dynamic range rather than take per-job risk.** Banking the diagnosis and
declining the patch is the right shape when the obvious fix re-opens a defence
that exists for a reason.

### 87a. Sharpened by its author — and it took a CONTRADICTION to make anyone look

frankS, 2026-08-30, narrowing face 87. The coordinator had generalised it to
*"print the value"*. The author's form is tighter and better:

> **A boolean that came from a helper call is not a boolean until you have seen
> it as a number** — because the one type whose wrong values all render
> identically is also the one the language will silently branch on.

And the trigger matters as much as the technique: *"I would not have looked if
only one of the two tests had been wrong."* `=` and `<>` **both answered true**,
so neither result was believable and the contradiction forced the measurement. A
single wrong boolean is indistinguishable from a wrong expectation; **two that
cannot both be right are what make the type itself a suspect.**

Practical corollary: when checking a predicate helper, assert on *both* the
predicate and its negation. One arm green proves nothing; two arms agreeing
where they must differ is a free, permanent detector for exactly this class.

**Confirmed the same night by the new xtensa differential's first sweep:**
`test_cross_var_string_param` prints `varlen=545267744` where the oracle says
`varlen=5` — a live heap address rendered as a number. `Length()` of a
`var string` parameter is handing back the handle. **The oracle's first run
surfaced another instance of the class its own construction had just
uncovered.**

### 93. A zero needs a denominator — otherwise "converted" and "no such sites exist" are the same number

frankA, 2026-08-30, re-measuring a stale blocker claim in `symtab.inc`.

```
Syms[..].PtrElemTk :=  outside symtab.inc :   0
SymPtrDepth[..]    :=  outside symtab.inc :   0
SetSymPointerType/To call sites outside it :  21
```

**The 21 is what makes the two zeros mean *converted*.** Without it, a bare zero
is equally consistent with *the migration is complete* and *this construct was
never used here*, and the two readings license opposite next steps.

Generalises to every absence claim in this repo: **report the population
alongside the count, or the count is unfalsifiable.** Same family as *an
existence claim survives one grep; a non-existence claim does not* — this is the
cheap fix for it.

### 94. A literal grep for a flag misses every site that passes it by VARIABLE — which is most of the sites that matter

frankB, same day, sweeping the repo for `-I` exposure.

Its first pass grepped for a literal `-I` and **missed every variable-form
site** — `$(GTK3_INC)`, `$GTK3_INC`, and `gui_suite.sh`'s constructed `$src`.
**Those were most of what actually needed fixing:** 14 sites hardened, six
Makefile recipes and eight `gui_suite.sh` invocations.

The reason it matters more than a normal miss: **a flag is passed by variable
precisely when it is passed from several places** — i.e. exactly at the sites
with the widest blast radius. A literal grep is therefore biased *against* the
important cases, not merely incomplete.

**And the negative was validated before being trusted**, which is what makes
"no live capture anywhere" a result rather than an assurance: a **positive
control at the pin** — `uses math` with `-Ilib/crtl/include` first fails loudly
(`undefined variable (Floor)`), while `-Fu` first and no-`-I` both build and
print 3. *The differential is provably sensitive*, so the clean rows are real
negatives rather than two indistinguishable arms (face 74, which this lane had
been caught by twice that evening).

Method note also worth keeping: the first cross-product was run through `comm`,
which emitted *"file 2 is not in sorted order"* — **unusable output, correctly
discarded rather than squinted at**, and redone as a Python set intersection.
Collation is a dependency; a set is not.

### 95. Three stale present-tense claims in one night, all written by someone who was RIGHT at the time

frankA's synthesis, and it is the humane reading of face 80.

Tonight's three: a ticket's `symtab.inc` ownership clause; a sentence carried
forward by another lane; and `SetSymPointerType`'s comment stating — **present
tense** — that twelve symbols carry an immediate pointee, *"and it is why
`feature-a-typeref-migrate-consumers` cannot re-point `TTypeRef.PtrBaseTk` at
the real base yet."* **That was the stated reason a migration could not
proceed.** It was written 2026-08-24, when 12 of 21 sites were unconverted; step
1 finished afterwards.

> *"All three were written by someone who was right when they wrote it. The
> pattern is not carelessness, it is that a comment or ticket body has no
> mechanism to notice the world moved — which is an argument for measuring the
> claim rather than for distrusting the authors."*

Corrected **in place with the old text kept as history**, because it is a true
record of 2026-08-24 and a false one about today — the same treatment frankD
gave its superseded provenance lines.

**And the second-order finding is the expensive one:** the decision that
comment's blocker depended on, `decide-typeref-gains-a-pointer-depth-field`, had
**been resolved since 2026-08-25 (`28c19f214`) and nobody noticed.** A resolved
Track U ticket does not notify the work that was waiting on it. **Prio
propagates down dependency edges; *resolution* does not propagate at all.**

### 96. A search for DUPLICATED logic cannot find the place where the logic is MISSING

frankS, 2026-08-30, tracing why `ir_codegen_xtensa.inc` was the one backend
that never adopted `ABIParamSlotHoldsValueAddr`. Verified in-tree by the
coordinator before relaying: `d68ff8d16` converted five backends and does not
list `_xtensa`; xtensa codegen predates it by two months (`bd49a5953`).

The sweep's own safety check is what hid it. Its commit message says, honestly
and **correctly**:

> *"an `IsRef or` chain inside `ir_codegen*.inc` now means someone grew a ninth
> copy. grep finds none."*

Measured at that commit's parent: each converted backend had exactly one such
chain. Xtensa had **zero** — not because it was correct, but because it had
**never implemented the rule at all**, open-coding a single row spelled
`(Kind = skParam) and (TypeKind = tyVariant)`, containing neither `IsRef` nor
an `or`. (Counted: `IsRef\s+or` xtensa 0, aarch64 1. The file's thirteen bare
`IsRef` mentions are an unrelated form, which is *why* the chain grep slid
past.)

**This is the exact inverse of this repo's own grep-for-the-sibling rule.**
That rule finds *divergent copies* and is structurally blind to *absent* ones.
Two failure modes, opposite searches, and the second wears the first one's
clothes — a check that a correct implementation and an absent implementation
both pass is not a check, and nothing in its output says so. **The file that
most needed converting is precisely the one that satisfied the invariant.**

Operational form: **for a sweep converting N sites onto a shared helper,
enumerate the sites that SHOULD call it and verify each does — do not search
for the pattern being replaced. The first list is closed and countable; the
second is defined by what already exists, which is the thing in question.**

Corollary that arrived with it: the same commit verified against x86-64,
aarch64, arm32 and riscv32 — **xtensa absent, because xtensa could not be
executed at all until 2026-08-29.** Both of the sweep's safety nets had a hole,
for unrelated reasons, pointing the same way. The oracle argument from a fourth
direction: the target with no oracle keeps the bug a conscientious sweep was
built to prevent.

### 97. The act of RELEASING a ticket is what made it look held

`c583c33c7` parked `feature-a-typeref-migrate-consumers`: moved it
`working/` → `backlog/` and cleared `owner:`. Correct, deliberate, one line —
and it left `status: working` behind in the ticket's own frontmatter.

Every agent here is told to **open a ticket at HEAD before claiming it**. So the
header reading `working` is read as *someone has this*, and the ticket is
skipped — **by careful readers especially, since a careless one never opened
it.** It ranked THIRD of 111 in `ready --track A` the whole time. The ranker was
right every single time it was asked.

**A ticket that looks TAKEN is more durable than one that is missing**, because
nothing ever re-checks a lock someone else appears to hold. Fixed at the
producer: `move_ticket` now syncs the self-described status, both spellings,
updating only fields that already exist.

Note the near-miss in the diagnosis, which is face 84's shape: this was first
written up as *"resolution does not propagate down dependency edges"*. It does
not — but that was never the mechanism here. **The ticket carries no
`blocked-by` edge and never has**; the dependency was stated in prose. A
notification feature built on that theory would have fixed nothing, and would
have looked like a fix.

### 98. One malformed byte in one record took the shared index down for every reader

`progress.py` read every ticket with a strict UTF-8 decode. One ticket pasted a
diverging program's **raw output** into a markdown table — exactly the evidence
that ticket should carry — and `ready`, `next`, `check` and `board-md` died for
**every lane at once**. The traceback named the codec and a byte offset and
never the file, so the blast radius was the whole fleet and the diagnosis was a
manual bisect.

**A shared reader must degrade per-record, not fail closed.** A ticket is prose
plus evidence, evidence arrives as bytes from a failing program, so this
recurs by construction. Now: replacement decode plus an `ENCODING` warning, so
the damage is reported without blocking a dispatch.

The general shape: **the record most worth keeping is the one most likely to be
malformed**, because it is the one carrying the raw artefact. Sanitising it to
`?` destroys the evidence; `\xNN` preserves it. Both fixes were attempted
concurrently by two lanes and the escaping one was kept.

`errors="replace"` was already the house pattern one function away, at
`progress.py:1399`. **The strict read was the outlier, not the hardening** —
worth checking before writing a new convention.

### 99. A DERIVED sentence rots with the number it was derived from, and carries no provenance

frankD, 2026-08-30. `docs/targets/esp32.md` published ~26 KB/~21 KB code and
~70 KB bss; measured at pin v393: **50,528/43,428 and 103,692**. But the table
was the cheap half. Underneath it:

> *"an ESP32-C3 has roughly 400 KB of usable SRAM; a minimal PXX image plus
> stack uses well under a quarter of it"*

**False at 104 KB of 400 KB before the stack is counted.** frankD's reading is
the finding: *a reader checking the table sees "about right, ish"; a reader
trusting the sentence sizes a project wrong.* A number invites re-measurement.
**A conclusion drawn from it does not carry the number's provenance, so nothing
invites anyone to re-check it** — and it is the conclusion people act on.

Same family: *"peaked at 79 tickets"*, where the word **peaked** was doing the
lying rather than the number (N's queue is 84 today). An ordering claim is
silently falsified by growth and reads as a fact about the past.

And underneath both: **nothing watched that number.** It moved 2x over months
with no test failing, caught only because a docs page quoted it and someone
re-measured. A size canary turns a four-month drift found by prose into a
one-line red on the causing commit.

### 100. An instrument that agreed with everything you could check was not TESTED

frankD, unprompted, about the tool built for the job it had just done:

> *"`factsheet.sh` agreed with everything I could count directly this pass, so
> it did not get tested hard. Its numbers were not the ones that mattered here —
> the rotted figures were footprint measurements and queue orderings, neither of
> which it prints. The sweep it motivated found its worst case outside its own
> coverage."*

**Agreement with an unexercised instrument is not evidence the instrument
works**, and it is the single easiest thing to write up as a validation. It
would have been reported as one had frankD not said this. Same family as
face 83b and the objdump-on-section-less-ELF null: *a null result and a null
instrument are indistinguishable downstream, and only the instrument can tell
you which you have.*

### 101. Asserting the exit status of a program written to be WATCHED

frankB, 2026-08-30, declining the obvious wiring for six orphan GUI tests.
`run_gui_test` asserts `rc`. All six print their result as prose on stdout:
`test_gtk_signals` exits 0 whether or not `clicked` was ever delivered;
`test_pcl_helloworld` exits 0 with `clicks=0` when the streamer fails to wire
`Button1`.

Wiring them rc-only satisfies "these tests are now wired" **in letter while
producing exactly the green-because-it-asserts-nothing rows the ticket
existed to prevent** — the warning defeated one level in, by the fix.

Two things made the alternative trustworthy rather than merely different: the
replacement checker was **seen to fail** (readable want/got diff on wrong
output) before being shipped, and `test_gtk_signals` was given a synthesised
click — *nothing had ever pressed that button, so the callback the file exists
to describe was asserted by nothing*, and wiring it without replacing the human
would have preserved the file and lost its purpose.

Its recorded limit is the model for how to state one: with `DISPLAY` and
`WAYLAND_DISPLAY` **both unset**, `gtk_init_check` still returns 1,
`gtk_window_new` still returns non-nil, and the test still prints *"window
shown, exiting"*. **That line is not a witness** — measured, not reasoned, and
written into the file rather than left for the name to imply.

### 102. A line that only prints when the probe found something can never report finding NOTHING

pxx-a5, 2026-08-30, on `calibrate()`. The scale line is now printed on **every**
run, with both components, and says out loud when the floor is the answer:

> `budgets x1.00 (native probe 0.58, emulated probe 0.89) — at the floor, so
> neither probe raised it`

**"The floor is the answer" is what went unnoticed for the life of the
function.** Silence on a no-op is indistinguishable from silence on a
never-ran, and the second is what it turned out to be. Same shape as face 33
(a capability nothing invokes is quieter than no check) and as the fresh-tree
`make compiler/pascal26` no-op that prints a success message in the wrong
dialect: **the absence of a line is not a signal, because nothing distinguishes
it from the absence of the code that prints it.**

Companion from the same message, on enrolling `test-xtensa` in `full`: the tier
comment **states the population** — 55 of 142 jobs, 21 measured divergences with
the ticket cited, 66 not compiling — and says explicitly that enrolment must not
be read as *"xtensa is covered"*. Face 8's remedy applied at filing time: a
survey that names its own scope, written by the person who knows the scope,
rather than by the person who later needs it.

### 103. A probe that tests the SHELL and reports the result as a property of the MACHINE

frankB, 2026-08-30. Two separate sweeps ran `command -v qemu-system-riscv32`,
got nothing, and wrote *"re-checked rather than assumed"*. **The command really
was run and honestly reported.** But ESP-IDF installs its tools **off `PATH` by
design**, under `~/.espressif/tools/`, reaching `PATH` only when you source
`$IDF_PATH/export.sh` — and `IDF_PATH` is unset in a fresh shell. **The probe was
structurally incapable of returning positive.**

An ESP ticket family sat blocked for about five weeks on a fact that was never
true. What was actually installed the whole time: Espressif QEMU 9.2.2 with
machines `esp32`, `esp32s3` and `esp32c3`, both toolchains, both gdbs,
`openocd-esp32`, and ESP-IDF v6.0.1.

**Operational form:** *to probe for a tool, look where its installer puts it, not
at whether the current shell happens to expose it.*

It caught the coordinator inside one minute of reading the report: verifying the
claim with `find ~/.espressif/tools -maxdepth 4` also found nothing, because the
binaries sit five levels down. **Same failure mode, different tool, while
checking that exact failure mode.** A negative from a search is a claim about the
search first and the world second.

Sibling of face 96 (a search for duplicated logic cannot find the place where
the logic is missing) and of face 8: **a check with no true arm reads exactly
like diligence from the inside** — a real command, really run, honestly
reported. Nothing about the output distinguishes *"absent"* from *"unfindable by
this query"*, and only one of those is a fact about the machine.

**The counterweight, from the same message, and it is what makes this a good
night rather than an embarrassing one:** the coordinator had told frankB that a
peripheral callback was not observable on this box and asked for that limit to be
**written into the code**. frankB checked it instead of recording it. Had it been
recorded it would have been a *false limit installed in source with the
coordinator's authority behind it* — believed, conscientious-looking, and
precisely the thing that stops the next person re-checking. **The rule you are
enforcing is the one you will not apply to yourself**, third instance in one
night.

What replaced it is a limit that survived measurement: a pass witnesses a genuine
`esp_timer` callback dispatched by FreeRTOS through the library's event surface
**on emulated silicon** — not real silicon, timing, analog, or xtensa. Flashing
stays blocked; there is no `/dev/ttyUSB*` or `ttyACM*`.

And the acceptance witness is the right shape: `status=0` where `status` is a
bitmask the app builds itself (1 start failed, 2 fewer than five ticks, 4 stop
failed). **A dead timer prints `status=2`** — the pass is a value only a live
callback path can produce, not merely a zero exit.

### 104. A harness's SKIP path is the easy half, and it is the half that gets tested by accident

frankB, 2026-08-30, correcting its own report of the ESP timer acceptance
script before anyone could act on it. The script **failed twice before it
passed**, and both failures presented as an **empty capture**, not an error:

- `idf.py set-target` wipes `build/`, and a regeneration line that looked right
  did nothing — QEMU booted with no image and wrote an empty serial log.
- An all-zero efuse block reports chip revision v0.0 against an image requiring
  ≥ v0.3, so the bootloader rejects it and reboots forever: **306 KB of boot
  attempts and not one app line.**

> *"'No PXX lines in the log' is indistinguishable from 'the program ran and
> printed nothing' — which, given I was testing a callback that might
> legitimately never fire, is precisely the wrong-conclusion-shaped hole."*

**The coincidence is the danger**: the harness's broken output is byte-identical
to the subject's most plausible real failure. And the general form:

> **"The negative arm was correct from the first cut; the positive one was broken
> twice. A skip-with-reason is easy to get right and proves nothing about the arm
> that matters."**

**The arm that has to be right is the one that only runs when everything else
already works** — which is exactly when nobody is looking at it. A skip path runs
constantly, on every box lacking the tool, and is debugged by accident.

Remedy applied: efuse defaults now come from IDF's own `QEMU_TARGETS` table
rather than a pasted constant, so the value and its source cannot drift
(face 80 applied to configuration).

### 105. One status column showed two different facts as one

pxx-a5, 2026-08-30, retracting its own report. *"The single red inside
`tools-devtest#00` on plexus per seven's tstate"* was wrong on the attribution
and, once re-read across both boxes, wrong about the phenomenon:

| box | reality |
| --- | --- |
| plexus | `fail` at one sha → **`pass`** at a later one, healed by a commit that changed the `/tmp` **literals the guard scans** — a different defect wearing the same three letters |
| seven | **`timeout`**, `job_last_pass` empty — **never passed there at all** |

The coordinator read the pair as *"green here, red there — host-dependent"*, the
failure mode that waits years. It is not. It is **one box that went red then
green, and one that has never finished the job.** A single `fail`/`pass` column
cannot distinguish *regressed*, *healed*, and *never completed*, and the three
license entirely different next steps.

**Note what did NOT happen: the healing commit did not fix the reported
defect.** Re-measured against source at HEAD rather than inferred from the
guard's colour, both original claims still stand. Which produces the sharpest
inoculation written into a ticket here:

> **This ticket's failure mode is the guard being GREEN while the defect stands,
> so a green guard is not evidence against it — it is the symptom. Anyone
> arriving because the devtest went green has REPRODUCED the finding, not
> refuted it.**

### 106. The obvious probe put the entire mass in the part that varies

Measured against `pinned` after the size canary added an empty-program row
nobody had asked for:

```
program e; begin end.                       61,276 B
program h; begin WriteLn('hello'); end.     61,350 B
```

**`WriteLn` of a literal costs 74 bytes on a 61,276-byte floor.** So
`bug-a-a-pascal-hello-world-is-63kb-after-emission-size-dce` is named after a
number whose subject is **0.1% of it**, and its open question — *"either the
pass is not reaching this, or the done ticket's scope was narrower than its
title"* — has a third answer: **there is no *this* to reach.** The body is empty
and the number barely moves. The subject is the RTL/startup floor.

Not the filer's fault, and that is the point: **a hello-world is the obvious
probe for code size, and the obvious probe is obvious because it is minimal —
which is exactly what makes the constant term invisible in it.** Anyone starting
there spends an hour on string machinery and concludes DCE is broken.

Remedy is structural rather than a correction: `x86_64-empty` is now a watched
subject, so the floor is a *measured baseline* rather than an assumption inside
someone's probe. **The generalisable move is to add the null case to the
measurement** — a row with none of the feature under test — because the
difference between the two rows is the only thing the feature can be blamed for.

### 107. Every signal said pushed, and the commit was gone

`sync.sh` dropped an entire commit and pushed another lane's instead, printing
`sync: pushed — <their subject>`. `git rev-list --count origin/master..HEAD` = 0,
exit code 0, clean tree. **Three independent success signals, all genuine, none
of them about the question** — because a healthy push produces exactly the same
three. The work existed only in the reflog.

**The success and failure outputs were byte-identical**, which is face 104's
empty-capture in the tool that moves work between machines. The only
discriminator is one nobody was running: **name what you expect to land, then
look for it on origin afterwards, BY CONTENT.**

Checking by **sha** is worse than not checking: an ordinary rebase rewrites every
sha, so a missing sha is the *normal* result and produces false alarms. The
coordinator nearly filed one against itself.

The guard is now in the tool, because **a guard that must be remembered is a
guard for the two hours after someone is burned by it.**

And the diagnosis was kept honest by the lane that lost the work: one of the two
mechanisms was its own (editing a tree under a backgrounded sync), and it refused
to let that explain the other. **A cause that explains most of the evidence is
the most dangerous kind, because it retires the investigation.**

### 108. A guard that has never been observed REJECTING is not known to be selective

frank-optimize-b4, 2026-08-30, on why W1 slice 8 self-hosted clean, passed every
test, and moved the target loop by **zero bytes**.

The guard `IRTk[left] <> IRTk[right]` was rejecting because the left node's IR
type is frequently **0 — unset, not different.** It was rejecting on **missing
metadata**, and it rejected precisely the for-loop limit compare the arm exists
for. It was not load-bearing and is gone; the real guard is identical TypeKind,
with the equivalence argument running on monotonicity rather than on an
invariant anyone must maintain.

> **"A correctness test can only see a guard that is too loose. An over-strict
> guard is invisible to every oracle you have — including FPC, including the
> fixedpoint, including a deliberate break — because DECLINING IS ALWAYS
> SEMANTICALLY SAFE. Only a decline log can see it."**

This is a **different failure class from vacuity**, and it is the one an
optimisation pass is most exposed to: every test passes, every oracle agrees,
and the pass does nothing. It is the exact reason face 102 (print on every run,
including the no-op) has to extend to *print why you declined*.

The probe repaid itself twice more in the same session: it proved the mixed-width
control is a control (exactly one `typekind` decline, the 8-vs-4-byte row), and
it is what turned "changed by zero bytes" from a mystery into a one-run answer.

**And the instrument failed before the subject did, again.** The first probe run
printed *nothing at all* from a program known to call the function — because the
redirect was `2>&1 >/dev/null`, sending stdout, where `WriteLn` goes, to the
void. Read naively that silence says *"the pass is never called"* and sends you
hunting in the wrong file. **When the instrument reports nothing, the instrument
is a suspect before the subject is** — face 79 one level out, and the same lane
had the break-was-the-bug and the probe-was-the-bug in one session.

### 103a. AMENDMENT — the docs were RIGHT and the probe contradicted the repo's own tooling

Face 103 above says an ESP ticket family sat five weeks *"on a fact that was
never true"*, and implies the knowledge was missing. **It was not.** The S lane
corrected this and the correction is sharper than the original:

- **`tools/esp_run.sh:42`** finds the emulator by
  `ls ~/.espressif/tools/qemu-xtensa/*/qemu/bin/qemu-system-xtensa`, and
  defaults to `--chip esp32s3`. That is *exactly* the "look where the installer
  puts it" generalisation face 103 draws — **already implemented, and committed
   2026-08-02** (`01c8cf7c1`), four weeks before the sweeps that concluded the
  toolchain was absent.
- `examples/esp32/hello-s2/README.md` already recorded that there is no
  `esp32s2` machine and that the S2 is therefore verified by building headlessly
  and running on a board.
- `make test-esp-idf` already loops `esp32c3 esp32s3`; `test-esp-softfloat`
  already runs an S3 probe under `qemu-system-xtensa`.

So *"nobody has tried the esp32s3 machine"* was true of one lane and **false of
the repo**, and the coordinator relayed it as a property of the machine — the
same error as face 103 itself, one level up.

**The corrected lesson, and it is cheaper than the original:**

> **A probe that disagrees with the repo's own checked-in tooling is the cheapest
> possible signal, and it was available for free.**

The `command -v` sweep did not merely fail to find a binary. **It contradicted a
harness in the same tree that had been finding that binary by glob the whole
time, and nobody diffed the two.** Five weeks were not lost for want of
documentation; the documentation was correct and unread, and one `grep -r
espressif tools/` would have settled it.

Generalisation: before concluding a capability is absent, **grep the repo for
something that already uses it.** A tool that ships with a finder is a tool
somebody already found.


### 109. A stated limit WITH A MECHANISM attached is the highest-yield grep in any doc audit

frankD, 2026-08-30, on hitting the third one in a night.

- `threading.md`: *"rejected at compile time"* on i386/arm32/aarch64, because
  *"the clone stub is x86-64-only anyway."* False for seven weeks —
  `compiler.pas:1604` accepts four targets and `__pxxclone` is emitted by four
  backends.
- `python-compat-tiers.md`: *"T1 shims only work for modules imported by a single
  bare name"*, because **a unit name cannot contain a dot**. The blocker was
  resolved weeks ago, the mangling shipped *exactly as that page proposed it*
  (`reportlab.pdfgen` → `mimic_reportlab_pdfgen`), and the corpus uses dotted
  imports routinely.

> **"It does not assert the limit, it EXPLAINS it. The mechanism is still true;
> only the consequence moved. The reader checks the mechanism, finds it sound,
> and never tests the conclusion."**

That is what makes this class durable, and it is why it is worse than a plain
false statement: a bare wrong claim invites a check, **an explained wrong claim
supplies its own defence.** A unit name still cannot contain a dot. Someone just
mangled it.

Compounding it, from face 2's corollary: **a doc that under-promises reads as
conservative, so nobody checks it** — and the cost is invisible, because a reader
who designs around a capability they believe absent never files a bug about it.

The near-miss the same sweep sets, also frankD's: `lib/py/reportlab/pdfgen.pas`
is absent **because that page successfully argued against building it.** *A path
that is missing because the doc won its argument looks identical to a stale
citation.* Labelled the road not taken rather than "fixed".

### 110. Embedding a ticket's DIRECTORY in a citation breaks it exactly when the work SUCCEEDS

frankD, mechanically sweeping every `path:line` citation in the 41 live docs.
**6 of 9 directory-qualified ticket citations were stale, and every one rotted in
the same direction: `backlog/` or `working/` → `done/`.**

Systematic, not six mistakes. **A ticket's directory IS its state**, so a
citation that names the directory is guaranteed to break at the moment the work
finishes — and it breaks toward the wrong conclusion: the reader gets *not found*
and infers the work was **abandoned**, when it was completed. Fixed by using
`[[slug]]` links, which the corpus already uses and which survive a move.

**Third distinct mechanism that night that hides COMPLETED work**, which nobody
predicted was a pattern: this one, `wasm-target-findings.md` citing four paths
that live only on `origin/wasm` (an agent greps master, finds nothing, concludes
the page is stale or the work was lost), and face 96's converted-sweep blind
spot. All three **mislead in the direction nobody double-checks, because "it's
gone" is the conservative-sounding conclusion.**

### 111. An A/B that rebuilds under a `git stash` leaves the wrong binary installed

frankA, self-caught. Eleven probes read 392 KB; the next reading said 367 MB and
looked like a refutation. **Neither number was wrong.** `compiler/pascal26` had
been rebuilt *under the stash* as the A/B baseline and never rebuilt after the
pop, so the second measurement used the unfixed compiler.

**The tell was timestamps, not either number.** Both readings were internally
consistent, and the artefact carried no marker of which tree produced it — the
same *path* held two different binaries at two different times, so there was not
even a second sha to notice. Nastier than a stale control for exactly that
reason.

Companion, from the same investigation: **a program that fails to run reports a
beautifully flat memory number.** Grepping RSS without confirming each program
still printed its output makes an early death look like the fix working
perfectly.

### 112. Filing a banked item is the first time anyone writes the ARGUMENT down — and that is when the better design appears

frank-optimize-b4, 2026-08-30, splitting two banked wins out of an umbrella.

Item (B) was banked as *"the `cdqe` is provably a no-op, delete it."* True today —
and **exactly the invariant-dependent elision the same lane had refused three
hours earlier**, depending on every resident write site re-normalising forever,
maintained in another file, with a silently-wrong-value failure mode.

> *"I did not notice that while it was a sentence in a log; I noticed it the
> moment I had to write down why it was safe."*

The filed version needs no invariant — `movsxd rax, r12d`, 3 bytes and one
instruction against `mov rax,r12` + `cdqe`'s 5 and two, correct whatever the
upper half holds. **The item got better by being filed.**

So the argument for splitting a banked item out is not only that it becomes
dispatchable: **a bank entry records a conclusion, a ticket forces the
justification, and the justification is where the design is actually decided.**
Same reason a park with the diagnosis banked beats a microfix, one step earlier.

Corollary from the same message, on a distinction most likely to make someone
think the work is done: the existing `-O2` mirror **swaps operands** and needs
commutativity; the filed item swaps **evaluation order** with operand roles
fixed. Different transformation, different legality condition, and only the
second covers `-`, `shr`, `div`, `mod`.

### 113 — a stated limit whose MECHANISM is still true and whose CONSEQUENCE moved

*frank-optimize-b4 and frankD, 2026-08-30, converging independently on the same
shape within an hour; five instances between them in one night.*

Face 109 says a limit with a mechanism attached is the highest-yield thing to
grep, because it supplies its own defence. This is **why that class rots
invisibly**, and it is the sharper half.

Such a claim has two halves under one tense:

> *"`--threadsafe` is x86-64 only — `builtinheap.pas:1555` states the refcount
> blob is non-atomic on other targets, so any parallel story is single-target."*
> *"Validated: 505 programs at -O0/-O1/-O2/-O3, plus a cross-target inline gate."*

A reader who doubts one of these spot-checks the **mechanism** — is the refcount
blob really non-atomic? did the validation really run? — finds it true, and stops.
But the mechanism was never the perishable half. **The consequence is what moved**:
aarch64 grew a residency pass, so "x86-64 only" became false while "the blob is
non-atomic" stayed true. The 505-program run really happened and is now a
historical measurement, while the neighbouring cross-target clause beside it under
the same "Validated" is a standing gate. One sentence, two lifetimes, one tense.

So the check that feels responsible — verify the *because* — is precisely the one
that cannot fail. Four of frank-optimize-b4's audited claims split this way: one
false, one rotted, one true-but-now-incomplete (written before the `-O3` tier and
silent about 24 later gates), one whose "byte-identical" had **no object at all**
and survived in an internal doc because internally everyone knew what was meant.

**The tell is a limit and its justification sharing a tense.** Ask which half
would change if the world changed, and date *that* half, not the sentence.

**Corollary, and the reason this outranks a docs nit:** the same false limit costs
differently by where it sits. A stale comment only a compiler engineer reads is a
nuisance; **the identical claim in a live doc is what a lane plans around** —
`threading-model.md` told readers the parallel story was single-target for seven
weeks, and one of its three sites was filed as an *Open question* (*"hard limit or
unfinished work? nobody has asked"*) that had been answered seven weeks earlier in
`07fee0844`. A question parked as open when it is answered is a decision that
cannot be made. Price the comment by the docs it feeds, not by who reads it.

**And two docs on one subject are a DOUBLE CASE** — the sibling rule applies to
prose. `threading.md` and `threading-model.md` disagreed for seven weeks because
nothing about "the threading doc" suggests there are two of them, so a reader who
finds one has no reason to look for the other. Fixing one arm and closing is the
same defect the parser rule names.

### 114 — a CITED limit looks already-checked, and the citation is the part that rots

*frankD, 2026-08-30, same sweep — the escalation of 113 and the worse case.*

A bare claim invites a check. An explained claim supplies its own defence (109).
A claim citing **a file and line number** looks like the check has already been
done by someone with the file open — and it is the *most* likely of the three to
be wrong, because a line number is the only part of the claim that decays without
anyone touching the claim.

Measured, both directions, in one night:

- A doc cited `builtinheap.pas:1555` for "the refcount blob is non-atomic on other
  targets". **Line 1555 today is string-append capacity doubling** and says nothing
  on the subject. Chain: stale comment → doc cites the comment as evidence → doc
  states a false limit → a whole parallel story declared single-target. Every link
  looked like diligence.
- Then frankD turned the finding on **its own ticket**, which reports comment rot,
  and four of its six cited lines had drifted **within two days** —
  `builtinheap.pas:2039`→2066, `ir.inc:12730`→12521, xtensa `322`→359. Line 2039
  today is the middle of `PXXStrLoadFile`: real Pascal, plausible, unrelated.

That is the failure mode. A drifted line number does not dangle or 404 — **it
lands on other real code**, and there is no signal to the reader that anything is
wrong. Compare face 110, where embedding a directory in a citation breaks it when
the work *succeeds*: same family, different clock.

**Cite by grep, not by line.** A pattern that survives drift is worth more than a
number that was exact once. This applies to tickets with the same force as to
docs — a ticket citing line numbers rots exactly the way the comments it reports
rot, and a ticket *about* rot that rots is the defect one level up.

**Calibration note worth keeping, from the sweep that found these:** 15 scoped
candidates across 41 live docs, of which 3 were live defects and 2 more were
confirmed *correct* limits worth knowing are correct. frankD's own standard for
the grep: *"a pattern that finds 15 and confirms 3 is worth running; one that
found 15 and confirmed 15 would mean I had written the grep to match what I
already knew."*

### 115 — a HANG and an INERT SUBJECT produce the same artefact, and the wrong reading is the natural one

*frankB, 2026-08-30, probing ESP ADC under QEMU after establishing GPIO was inert.*

Third appearance in one night of one signature: **a raw capture with none of the
probe's own output in it.** The two causes are unrelated and want opposite
responses:

- the subject is **inert** — the calls return, the probe runs, nothing happens;
- the probe **never ran** — `adc_oneshot_new_unit` does not return, the image
  stops before `app_main`, and the last line is an unrelated eFuse warning.

The artefact is identical: zero `PROBE:` lines. And the *available context*
pushes you toward the wrong one — frankB had just proved GPIO inert, so "ADC is
inert too" was the reading with momentum behind it, and it would have been filed
that way. What separates them is that an inert subject is a **finding about the
peripheral** and a hang is a **finding about the call**, which is a different
bug with a different owner.

**The control arm is the whole method, and it is cheap.** Same project, `esp_adc`
still in `REQUIRES` so still linked, running the *GPIO* probe body instead: it
reaches `app_main` and completes. That one run separates "the ADC call hangs"
from "adding the esp_adc component breaks the build" — indistinguishable from the
outside, different lane, different owner. Without it the ticket is filed against
the wrong thing with full confidence.

**Related to 102 and sharper than it.** 102 says a line that only prints on
success can never report finding nothing. This is the case where the *absence of
all output* is itself ambiguous between two live hypotheses, so even a
correctly-designed probe needs a second arm to disambiguate its own silence. An
empty capture is not a result; it is a question.

**And the hypothesis discipline is the other half.** The calibration eFuses are an
obvious suspect — burned on real parts, absent from QEMU's default blob — and
frankB wrote it into the ticket **flagged as a hypothesis, not established, with
an explicit line saying not to record it as the cause without measuring.** That
is the correct handling of a plausible story, and this repo's history is that a
plausible story adjacent to something the author genuinely knows is exactly what
gets promoted to a finding by the next reader in a hurry.

**Note what has no expiry.** The GPIO block carries one — a `qemu-assert` that
fails the day QEMU grows a GPIO model. The ADC block carries none, because **a
hang has no natural tripwire**, and frankB declined to invent one rather than
pretend otherwise. A block with no expiry is worse than one with an expiry, and
saying so is better than manufacturing a tripwire that does not test anything.

### 116 — a rule enforced only by hardware is not enforced

*frankS, 2026-08-30, root-causing the `Write`-of-a-real SIGBUS to a shared frame
layout rather than to the xtensa backend.*

`ir.inc` reserves a fixed-array return slot with `AllocArray('', tyUInt8, ...)`.
Element kind `tyUInt8` → `TypeAlign` = 1 → `symtab.inc:4151`'s
`AlignTo(FrameSize + sz, align)` rounds to **nothing**. The slot lands wherever
the frame happened to reach, and the `SymIsHiddenArgTemp` prologue nil-inits it
with a **four-byte store**. Odd offset, unaligned word store, in **all six
backends** — proven, not assumed, by disassembling one source for two targets and
finding identical offsets.

Five backends are never asked to notice. x86-64 and i386 permit unaligned access
in hardware; `qemu-riscv32` and `qemu-arm` emulate it silently in user mode.
Xtensa traps. So the alignment invariant was real, was violated everywhere, and
its **enforcement had been silently outsourced to whichever machine ran the
code** — which meant it was enforced nowhere until a target that traps could run
anything at all, which xtensa could not until the day before.

The general shape, and why it is not just an alignment story: **when a rule's only
consequence is a fault on some subset of platforms, the rule is not part of the
system — the platforms are.** Ask of any invariant: what artefact fails if this is
violated, and does that artefact exist on the machines we actually run? If the
answer is "the strictest target notices", the invariant is a hope with a
distribution attached.

Note the routing consequence, which is the expensive half. Filed from the symptom
this is *an xtensa bug*, goes to the xtensa backend, gets fixed there, and the
other five targets keep the latent defect **plus** a now-divergent backend. It was
the two-target disassembly that turned it into a shared-layout ticket with the
right owner. **A defect that only one platform reports is the one most likely to
be filed against that platform.**

Corollary the lane got right: making the xtensa nil-init store bytes would have
**hidden** it and looked like a fix. The slot is memcpy'd, field-accessed and
pointer-read elsewhere, so it must be pointer-*aligned*, not merely writable a
byte at a time. That is the compiler-appeasement workaround CLAUDE.md forbids,
wearing the costume of a targeted fix.

### 117 — a stated absence about THIS BOX is a claim about a search, not about the box

*Twice on 2026-08-30, by two lanes, in the same directory tree, from the same
wrong reflex.*

- frankB recorded that a callback firing on a peripheral was not observable here.
  **ESP QEMU had been installed the whole time**, and the doc that said so was
  right; a glob in `tools/esp_run.sh:42` had been finding the emulator since
  `01c8cf7c1` on 2026-08-02.
- frankS recorded *"there's no xtensa objdump on this box"*, worked around it, and
  took a weaker verification for it. `xtensa-esp-elf-objdump` and
  `xtensa-esp-elf-gdb` were under `~/.espressif/tools/**` — off `PATH` until
  `export.sh`, which is not the same as absent.

Both were **environment** claims, which is why they slipped past everything. The
fleet checks code claims against the code and ticket claims against the board;
nothing checks a claim about the machine, and a claim about the machine feels like
observation rather than assertion. It is not: it is the output of a search whose
scope nobody stated, and `which` against an unsourced PATH is a narrow search.

The cost is asymmetric in the usual direction (face: *a false limit is quieter
than a false fix*). A wrong capability claim in the *positive* direction fails
immediately when you try to use it. In the negative direction it silently
downgrades the method — frankS did not get a wrong answer, it got a **weaker one**,
and nothing in the result says so.

**Operationally:** a toolchain ships binutils for its arch; look inside its tree
before concluding. And write environment absences the way you would write any
non-existence claim — name what you searched, so the next reader can see what the
search could not have found.

### 118 — co-location makes drift VISIBLE; only an oracle makes it FAIL

*frankS, 2026-08-30, and it is the counterexample to the remedy the five previous
instances all pointed at.*

`0f48fa6a9` (2026-08-21) gathered six per-target managed-cleanup blocks into one
procedure **specifically to stop them drifting**. Its own commit header: *"it does
put them where a reader sees all six at once."* That is the textbook fix, it was
done deliberately, and it was done well.

Managed kinds each arm actually releases, counted by parsing the procedure at two
revisions rather than by reading it:

| arm | at `0f48fa6a9` | at HEAD, nine days later |
| --- | --- | --- |
| i386 | 4 | **7** |
| arm32 | 6 | **7** |
| aarch64 | 7 | **7** |
| riscv32 | 3 | **7** |
| **xtensa** | **1** | **1** |

i386 went 4→7 and riscv32 went 3→7 in those nine days — **both edited inside this
procedure, twenty lines from xtensa's one-row arm.** Four separate times someone
had the short arm on screen while lengthening the arm beside it. Nobody added a
row.

So: **seeing that an arm is short and being made to care are different events.**
The other arms grew because a test went red. Xtensa's could not, because nothing
in this repo could execute an xtensa binary until the day before.

This is the sixth instance tonight of *the target with no oracle keeps the bug*,
and it **narrows the rule instead of repeating it.** The first five were gaps a
search could not SEE — a grep blind to an absent copy (96), a sweep whose
verification list excluded the target, an alignment rule outsourced to hardware
(116). Every one of those has "put the copies next to each other" as its natural
remedy. This one was in plain view, four times, and drifted anyway.
**Visibility was never the binding constraint.** Co-location is necessary and it
is not sufficient; what closed the other four arms was a failing test, and what
kept xtensa's open was not having one.

**Practical consequence for how we file:** a per-target `case` or arm chain with
no per-target oracle is not a maintained construct, it is a **snapshot of which
targets were testable when each row was written**. Treat an arm count as a
measurement — parse it, as above — not as something a reader will notice. And when
a new target becomes executable, the first work item is not "look for bugs" but
**"count the rows in every arm chain that mentions it"**, because that set is
knowable in advance and is where the bugs already are.

### 119 — every commit here has the same author, so `git log` cannot answer "who holds this file"

*The coordinator, 2026-08-30, caught by frankC after routing a ticket on it.*

Asked which lane held `symtab.inc`, the coordinator ran `git log -3 -- compiler/symtab.inc`,
saw *"feat(A): TTypeRef gains PtrDepth"* 76 minutes old, and attributed it to the
lane working on a **ptrdiff** cell. Same prefix, adjacent topic, confident routing
message sent naming that lane as the holder.

It was not that lane. And the check that would have caught it does not exist:
**every commit in this repo is authored `yoctobyte <rene.tegel@gmail.com>`,**
because every agent commits as the owner. Author is not a discriminator, `%an` is
a constant, and the session-id trailer some lanes add is not universal — the very
commit in question carries none.

So the attribution was made from the only field that varies, **the subject line's
topic**, which encodes what the work was about and says nothing about who did it.
That is inference dressed as measurement: the command was real, the output was
real, and the field being read did not contain the answer.

**The general form is the one this index keeps returning to** — *a correct answer
to the wrong question looks exactly like a correct answer.* `git log -- <file>`
answers "when did this file last change and what for". It does not answer "who is
in it now", and nothing in its output says so.

**The instrument that does answer it is `devdocs/progress/working/`** — the live
lock, in both directions, plus the roster. That is what it is for, the coordinator's
own tick instructions say to read it, and it was skipped because git felt faster.
The lock ticket for this file had in fact already been **released**
(`c583c33c7`, *"park(A): release the typeref lock — PtrDepth landed green"*), so
the correct answer was one `ls` away and was the opposite of the one sent.

**Cost, and why it is not merely embarrassing:** routing on a wrong holder sends
work *away* from whoever actually knows the file's current state, and it manufactures
a phantom collision that blocks a real one. Both failures are silent — the lane you
named will usually just accept.

### 119a — the amendment, filed within the hour, and it is the same failure again

The paragraph that stood here said: *"authorship questions are unanswerable from
git here."* **That was false, and it was a false limit — the quiet kind.** frankA
supplied the discriminator immediately: the **`Claude-Session` trailer**. It named
the orphan ticket's owning session (`session_01GxBTsUxqQoxjTF7Hafn9nG`) and proved
it was not frankA's (`session_01WHtwEmBLfifGPtMtHgErvU`) in one command.

So the corrected claim, measured over the last 200 commits on origin/master rather
than asserted:

- `%an` / `%ae` are **constant fleet-wide** — every agent commits as the owner.
  That half stands.
- `%(trailers:key=Claude-Session)` **does** discriminate, across 5 distinct
  sessions in that window.
- It is carried by **42 of 200 commits — 21%.** Present, it is authoritative.
  Absent, you have nothing. `f74535b12`, the commit that started this, carries none.

Note what the original error and its correction have in common: **both were
non-existence claims made without stating the search.** I searched `%an`, found it
constant, and generalised to *git cannot answer this* — the exact move face 8 and
face 117 both name, committed inside a face about committing it. Writing *"if a
session-id trailer is ever made universal, that changes"* made it worse, because a
hedge about a hypothetical future is what a reader takes as confirmation that the
present was checked.

**The operational rule, corrected:** read the `Claude-Session` trailer first — it is
free and decisive when present. `working/` remains the authority, because it is the
only source that covers the 79%. And **put the trailer on your commits**: it is the
one field that makes ownership answerable after the fact, and four lanes in five
are currently not carrying it.

### 120 — an equivalence oracle over thousands of real decisions beats reading the arms

*frankA, 2026-08-30 — the constructive counterpart to 118, and the answer to
"how do you safely restructure an arm chain nobody can see is wrong".*

Face 118 says a per-target arm chain with no oracle is a snapshot, not a maintained
construct. This is what to do about it, and it is not "read more carefully".

Restructuring the managed-local zero-init table, frankA added a `PXXDBG=a.mlzero`
channel that prints the table's answer **for every local it sees**, flagging `MISS`
— a local of a handled kind that still came out 0. Two properties make it work:

1. **It is an equivalence oracle for the refactor.** 8,919 decisions byte-identical
   before and after the restructure, plus 34/34 examples byte-identical. *Diffing
   ~9,000 real decisions beats reading ten arms*, and it is the only way to make a
   merge-the-arms change safe when the arms differ in ways no test covers.
2. **It converts the next instance from an autopsy into a grep.** Both prior bugs in
   this family were found from the *outside*, as a use-after-free several layers
   from the cause. A fourth is now one command away.

The judgement it enabled is the point. Two `not IsArray` guards looked identical;
they had **opposite** answers. The promo-int one was an omission and reachable — a
static array of `promoint64` zero-inits **nothing**, and the cleanup arm then calls
`PXXPromoClear` on element 0, whose own header says it cannot run on uninitialised
memory, so the pre-fix compiler **segfaults**. The NilPy `tyClass` one was a real
decision: NilPy has no static-array syntax, its lists are dyn arrays claimed by an
earlier arm — measured as 19 dyn-array locals all answering 8 and zero static
`tyClass` arrays. **A guard is not self-describing; only its inputs are**, and the
instrument is what makes the inputs visible.

It also told frankA where *not* to merge: the record arms keep their own `IsArray`
because they read different rec ids and fall **through** to the COM arms when
`RecordNeedsZeroInit` says no. A merged record arm would have swallowed that
fall-through and answered 0 for a COM interface. The oracle found the hazard the
tidy-up would have created — which is the same save frankC got by *reading* the
seventh reader it did not touch.

### 121 — a self-differential's REFERENCE is not an oracle

*frankC, 2026-08-30, after fixing the frame-alignment SIGBUS and finding the
"remaining" divergence was two bugs, one of them on the reference side.*

`test-xtensa` compares the xtensa build against the **x86-64 build**. That is a
self-differential: both arms come from the same compiler, so the suite can only
ever report *"the targets disagree"* — never *"both are wrong."* **The reference
cannot be wrong by construction, so a defect the two targets share, or one living
in the reference arm, is invisible on every run of the suite since it was
written.**

It took a third arm to see it. frankC had a sentence half-written saying *"xtensa
diverges from the x86-64 oracle"*, then put **FPC** beside both, and the direction
inverted:

| expression | FPC | x86-64 | xtensa |
| --- | --- | --- | --- |
| `s1+s2` (Single op Single) | Single | **Double** | Single |
| `i * s1` | Single | **Double** | Single |
| `i / 2` | Double | Double | **Single** |

Both targets pick `Write` float widths FPC does not, **in opposite directions on
different lines**. The x86-64 half had been reachable on every run of the suite
and could not be reported, because it was the yardstick.

**This is a property of every cross-target suite here, not a fact about one test.**
Naming one arm "the oracle" is a *role assignment*, not a measurement, and the role
is usually assigned to whichever arm was written first. The moment two arms
disagree, the interesting question — *which one is wrong?* — is exactly the one a
two-arm comparison cannot answer.

**Two operational rules:**

1. When a self-differential goes red, **add a third arm from outside the system
   before assigning blame** — FPC, gcc, CPython. `differential-probes.md` indexes
   them; the cost is one run.
2. When it goes **green**, remember what that green means: the arms agree. It is
   not evidence about correctness, and it is silent on every defect they share.
   Compare the sibling rule for a HOST GREEN — a pass is a claim bounded by
   something nobody stated.

**And the shape-variation half.** An isolated `WriteLn(s)` for a plain `s: Single`
agrees across all three: the divergence needs the *expression*, not the type. So
the first probe reached for reported everything fine. Vary the shape before
believing a probe that agrees with you.

### 121a — and the alignment fix was face 118 again, one day later

The same session's fix is a second instance of 118 inside twelve hours.
`AllocArray` has five branches; **four already set `align := TARGET_PTR_SIZE`
outright** — dyn-element, string, frozen string, record. Only the scalar branch
asked `TypeAlign` about the *element*, and got 1 for a byte.

So the SIGBUS was never a missing rule. It was **one branch not following a rule
stated four times immediately beside it** — the rule was on screen, four times,
for anyone editing that procedure. Exactly xtensa's one-row cleanup arm sitting
twenty lines from arms that grew: co-location makes drift visible, and visibility
was again not the binding constraint.

Note the payoff of fixing it at the allocator rather than at the two `ir.inc`
call sites: it covers both **by construction**, so there is no pair to keep in
step. `normalise-dont-special-case` satisfied structurally instead of by
discipline — which is the only version of it that survives the next editor.
`AllocVar` needed nothing (`TypeAlign(tyRecord)` is already 8), checked rather
than assumed, which is why the fix is one site and not two.

### 119b — a signal that is ALWAYS present and NEVER discriminating is worse than an absent one

*frankS, 2026-08-30, sharpening 119 from a third side — and this is the sentence
to keep from the whole authorship episode.*

> *"Absence prompts a search and a constant does not."*

`%an` is on every commit in this repo. It is never wrong, never missing, never
malformed — and it identifies nobody, because every agent commits as the owner. It
has the *shape* of an ownership signal at every glance, and a glance is all it
gets. Nothing about reading it feels like a gap.

Contrast the `Claude-Session` trailer at **42 of 200 commits**: missing four times
out of five, and **missing is a state you can see**. The honest instrument is the
one that visibly declines to answer.

frankS's connection to 118 is the right one: co-location made the short arm
visible and did not make anyone care; an author field is present on every commit
and identifies nobody. Both are cases where **the artefact you would point to as
evidence of diligence is the one carrying no information** — the arms were on
screen, the author field was populated, and neither could fail.

**So when auditing an instrument, ask what it looks like when it has nothing to
say.** If the answer is "the same as when it has something to say", it is not an
instrument. Prefer a field that is empty 80% of the time over one that is
plausible 100% of the time.

### 122 — a fork can dissolve when you sit down to write it up, and that is a result

*frankB, 2026-08-30, sent to file a Track U decision and correctly refusing to.*

The coordinator instructed: file the `read`/`write` keyword-token question for A
with *"both options, the trade-offs, and your recommendation"*. Reasonable — it is
a language-surface call. But going to write option 2 down, the lane found **option
2 is a description of a shipped feature.** `external name 'sym'` parses today and
`pasparser_proc.inc` documents exactly the wished-for semantics: *"sets the LINK
symbol, NOT the Pascal routine identifier."*

The real defect was one layer down: `--emit-obj` **silently discards the clause**
and emits the Pascal identifier as the undefined symbol.

    $ readelf -sW alias_esp.o | awk '$7=="UND"{print $8}'
    PalSysOpen   PalSysRead   PalSysWrite      <-- wanted: open / read / write

And the control that makes it a diagnosis rather than a guess: the **same source**
built as a host executable emits a dynamic import named `write` and dies with
`undefined symbol: write`. One back end honours the clause, the other discards it —
so it is the relocatable-object writer, not a target quirk, confirmed identically
on x86-64 and hosted riscv32.

**Three things worth carrying:**

1. **"Grep for the incumbent before building" applies to DECISIONS too.** A fork
   about whether to build X is void if X ships. The coordinator's instruction sent
   a lane to write options for a feature that already existed, and only the act of
   writing option 2 down surfaced it. Compare face 112 — filing a banked item is
   the first time anyone writes the *argument* down, and that is when the better
   design appears.
2. **It is the silent-wrong-behaviour row.** Compiles clean; breaks later in a
   foreign build system as an undefined reference to an identifier appearing in no
   C source. For ESP that reads as *"the Pascal object is broken"* rather than
   *"a directive was ignored"* — the diagnostic points away from the cause.
3. **The regression must assert the symbol NAME, because "it compiles" passes
   today.** That is why this survived: **every existing check of that path is
   satisfied by an object that is wrong.** Same family as face 108 — a guard never
   observed rejecting — and as 121, where the reference could not be wrong.

The lane also noted the workaround was *genuinely tempting*: renaming two PAL
routines would have unblocked it in five minutes and hidden a bug affecting every
`--emit-obj` consumer. Worth recording that the platonic-code rule pays off most
exactly when the workaround is cheapest.

### 123 — the repair was ready before anyone confirmed there was damage

*pxx-a5, 2026-08-30, declining a backfill the coordinator dispatched it onto.*

The coordinator relayed: 7 PENDING-COMMIT tickets, 2 false positives, **5 real**,
please backfill them — with careful advice about matching shas by unbounded
exactly-1 subject grep, since a windowed miss would write a *wrong* sha.

The queue was **empty**. `progress.sh pending` → nothing. `check --strict` → 0.
All 7 were prose *discussing* the machinery — `PENDING_RE` excludes every one
deliberately, and a `prose-mention-is-not-rewritten` guard already pins that
direction. **0 real / 7 false**, inverted.

`fill_pending` **rewrites the file**. Run on the reported set it would have written
shas **into the middle of sentences** in four tickets documenting this exact
machinery, including the one that fixed it.

**The careful advice was precision about the wrong step.** It addressed *how to
find the right sha* — never *whether anything was owed one*. What saved it was
checking the queue was non-empty before filling it, which no amount of rigour
about the matching rule would have reached.

**So: before applying a repair, confirm the damage exists — in your own
measurement, not in the report that dispatched you.** A repair procedure is
persuasive: it implies its own precondition, and the more carefully it is specified
the more it does. Note the shape against 108 and 121 — those are guards that cannot
fail; this is a *fix* that cannot fail, because it will happily run on nothing and
report success.

**And the relay is the coordinator's half.** The claim was passed on unverified,
with authority attached, when `progress.sh pending` would have settled it in one
command. The profile is the standing one: plausible, load-bearing, adjacent to
something the reporter genuinely knew. The vivid detail inside it — *"the ticket
describing the sha-filling failure is itself one of the five unfilled"* — was
**false** (it carries `commit 65b2512ef`), and it is the part that would have been
repeated, because a good story travels further than a count.

**The inverse residue, which is the real one:** a ticket resolved by a hand-written
Log line never gets a placeholder, so nothing fills it and nothing counts it —
**uncited and silent.** Strictly worse than PENDING-COMMIT, which at least greps,
counts, and has a tool that knows how to repair it. The visible defect had a name,
a count and a fixer; the invisible one had none, and the visible one is what got
the dispatch.

### 124 — "present but rejected" and "absent" are different states, and only one looks solved

*frank-optimize-b4, 2026-08-30, on the coordinator's own new tool.*

`whoholds.py` printed *"1 of them carry NO session trailer"* for a commit that
**carried one**. The value `frank-optimize-b4 (c1d9983f-…)` failed the name
pattern, and the tool reported it identically to a commit with no trailer at all.

The lane had written the field, reasoned about it in a paragraph of commit message,
and gone on believing it was attributable. **The remedies are opposite** — *add the
field* versus *fix the value* — and the tool named the one that was already done.

frank-optimize-b4's placement of this is right and is why it earns its own number:
tonight's family is mostly *a wrong thing that looks checked*. This is one turn
further in — **a fix that looks applied.** A correct intention nobody parses, next
to face 33's correct capability nobody calls.

**General rule for any validator: silent rejection is a bug in the validator, not
in the input.** If a field can be present and inert, say so, because the author is
the one person who cannot discover it — they have already done the work and have no
reason to look again.

**Two independent instances of the enclosing bug in one hour**, which is what
settles it as a design fault rather than carelessness: `git` parses trailers only
from the **last contiguous block**, so a `Lane:` or `Claude-Session:` line one
paragraph too high is invisible to `%(trailers:…)` **with no error**. Both the
coordinator and frank-optimize-b4 lost the trailer on the very commit that
introduced their use of it. The fix is not a placement rule taught to eight lanes —
*a documented trap is not a guard* — it is scanning the whole body.

### 125 — PESSIMISM IS THE DIRECTION NOBODY DOUBLE-CHECKS

*frankD, 2026-08-30, after four instances in one night — and this is the sentence
the whole index has been circling.*

Four findings, apparently unrelated:

- a ticket cited by its `backlog/` path after moving to `done/`;
- a doc citing paths that live on `origin/wasm`;
- an Open question answered seven weeks earlier;
- a revert queue — `track-b-workarounds.md`, "Waiting on an open bug" — where
  **7 of 8 rows cite a ticket now in `done/` or `rejected/`**.

Every one reads as **conservative**: *not done yet*, *not found*, *still open*,
*still needed*. And that is the whole mechanism. **Caution looks like rigour, so it
is exempt from audit.** A claim that something is unfinished never gets the
scepticism a claim that something is finished receives automatically, because
doubting it feels like carelessness rather than diligence.

This is face 113's asymmetry one level out. A wrong *fix* is re-tested by the next
person who touches the code. A wrong *limit* is believed, and a wrong limit phrased
as caution is believed hardest.

**The specific mechanism here is worth separating, because it explains why a
written lifecycle rule did not save it.** The entry is not wrong about the
workaround and not wrong about the bug — **only about the bug's STATE, which is the
one part that changes without anyone touching the file.** The ledger's own opening
instruction is the check that was never run: *"When the listed bug moves to `done/`,
revert the workaround and drop the entry. Verify the bug ticket is still in
`backlog/`/`blocked/` before assuming the workaround is still needed."* The rule
requires a person to re-derive something **the document cannot know about itself**,
and nothing fires when it goes stale. Same shape as the ticket lock (a claim about
the present made by an action in the past) and as a rotted line-number citation
(114): the artefact is fixed, the world moves, and the artefact cannot tell.

**Two corollaries earned in the same finding:**

**Rank the code debt, not the misfiled row.** frankD verified the workarounds were
still live in source before filing — `math.pas:702` and `:1216` still reading
`Double(Trunc(x))` where `Int(x)` is natural, `ed25519.pas` still with no `TPoint`
— and said explicitly which rows it had *not* checked. *"The ledger is stale"* and
*"the library carries dead workarounds"* are different tickets and only one
deserves prio. The number that matters is **how many reverts are available**, not
how many rows are wrong. Each revert is then framed as a measurement **whose
failure is a new finding**, not as a reason to leave the row alone.

**A section that is 7/8 wrong stops being read as a queue** — which is partly why
the live reverts sat there. Three of the eight rows are *correctly* kept forever
(row 4, `aesgcm.pas`'s `BlkCopy`, where a full revert still segfaulted at the GCM
path with no minimal reproducer — kept, with the measurement written down). Those
three do not belong under "waiting on an open bug" either: **they are not waiting
on anything.** Parking permanent decisions under a heading that means *pending* is
what converts a queue into scenery.

### 126 — an instrument that CANNOT SEE a defect reads exactly like one reporting its absence

*frankA, 2026-08-30, fixing `--emit-obj` and finding the ticket's scope was short
by one writer.*

The reported bug was `--emit-obj` discarding `external name 'sym'`. The cause was
**five hand-rolled copies of one decision** in `elfwriter.inc` — two correct, three
wrong — and **each wrong writer was wrong twice**, because sizing the string table
and writing it are separate loops. Ten call sites for one rule.

The fifth copy is `writeELFSharedX64`, i.e. `--shared`, and **the ticket did not
know it was affected.** Not because anyone was careless — because the obvious check
cannot see it:

> The `.so` this writer emits has **no section header table**, so
> `readelf --dyn-syms` prints *"Dynamic symbol information is not available"* and a
> symbol-level check sees **nothing at all** — not a wrong name, nothing.

That is the face. A blind instrument and a clean instrument produce the same
output, and the natural reading of "no wrong symbols reported" is "no wrong
symbols". `strings` showed the three `PalSys` names present before the fix and
absent after — a cruder tool that could actually see.

It was found only because the **sibling grep** found the site and the lane then had
to prove the site *mattered*. Note the order: the site came from the duplication
rule (*if you fix a bug on one arm of a double case, grep for the sibling*), and
the *significance* came from picking a different instrument once the first one
returned nothing. **"My check reports nothing" is a claim about the check until you
have seen it report something.**

**The fix is the structural one, not the ten-site one.** One resolver,
`ExternalLinkName`, with all ten sites routed through it, so sizing and writing
**cannot drift apart again** — the same move as flooring alignment in the allocator
(121a) rather than patching two callers. And the regression asserts the name in
both directions and was confirmed as a **control**: against the pinned pre-fix
binary it fails on both riscv32 and xtensa *while compiling cleanly*, which is
exactly why the defect survived.

### 127 — a confident MECHANISM attached to an uncounted number

*frankA, 2026-08-30, retracting its own PENDING-COMMIT report — and this is a
better statement of face 123's cause than the coordinator's.*

> *"A confident mechanism attached to an uncounted number is worse than the number
> alone, because it explains away the very check that would have caught it."*

The report was: 7 PENDING-COMMIT tickets, 5 real. The 7 came from
`grep -rl PENDING-COMMIT` — **a line count reported as a ticket count**, when
`progress.sh pending` is the thing that defines the set and returns **empty**.

But the count alone would have invited a check. What suppressed the check was the
*explanation* bolted to it: a correct, well-argued account of why these five could
never clear — `sync.sh` fills at push time, these already landed, so no future sync
will reach back for them. Every clause true. The mechanism made the number feel
**derived** rather than counted, and a derived number does not get re-measured.

Same family as face 32 (a derived number standing in for a measured one reads as
*more* rigorous — arithmetic looks like work), but sharper: here the derivation was
not of the number, it was of the number's *permanence*, which is the property that
made it actionable.

**And the lane named its own general fix:** *"I read the count and never asked what
the population was."* It already carried that discipline for zeros — a
non-existence claim demands you state the search — and did not apply it to a
**non-zero**. **Same failure, opposite sign.** A count of 7 is as much a claim about
a population as a count of 0, and only one of the two triggers the habit.

### 128 — when the fix makes detection and substitution AGREE, it removes the symptom that revealed the class

*frankC, 2026-08-30 — the sharpest structural finding of the night, and it is
about a fix that worked.*

`sync.sh` once had two `sed` literals covering fewer spellings than `progress.py`'s
`PENDING_RE` knew about. That **disagreement** is what exposed the bug: `check`
counted resolves that `fill` could not fill, and the mismatched numbers were the
alarm. The fix aligned them.

Now they agree perfectly — **and are wrong together.** A resolve citation that
wrapped onto a continuation line (ordinary formatting) matches *neither*. So:

- `check` reported **no** pending resolves;
- `sync.sh` printed *"pushed 1 commit(s), all verified on origin"* with no `filled`
  line — **which is exactly what a ticket with nothing to fill looks like**;
- the file still contained the literal `PENDING-COMMIT`.

**All three places a person would look read as healthy.** The placeholder was
*unseen*, not merely unfilled.

This is the general hazard in unifying two implementations of one rule, and it
cuts against the repo's own `normalise-dont-special-case` doctrine in a way worth
stating precisely: **normalising is still right, but it retires an accidental
oracle.** Two divergent implementations of one predicate constitute a differential
test that runs for free on every input, and consolidating them deletes it. Face 121
says a self-differential's reference is not an oracle; this is the mirror — *a
duplicate you are about to remove may be the only oracle you had.*

**So when you unify two implementations of a rule, add a check that does not share
their assumptions.** frankC's recommendation, and it is right: not a wider regex —
that only moves the boundary — but **a second, dumber guard**. After fill, grep each
resolved ticket for the literal string and fail if it survives. *A substring search
cannot be defeated by line wrapping.* The new instrument must be **independent, not
adjacent**; a better version of the same idea inherits the same blind spot.

Pairs with the manifest check: one catches a commit that did not land, the other a
resolve that landed citing nothing.

### 128a — and the guard it nearly shipped could not fail

Same session, same ticket. The recipe checks a bad soname is **absent**, first
written as:

    readelf -d … | grep -qv libhdrstatic.so

which passes whenever *any* line fails to match — i.e. every ELF, i.e. always.
Caught, rewritten as a negated `grep -q`, and then **validated in both directions**:
passes on the fixed binary, fails on the pre-fix one.

Worth recording for where it happened: **inside the very test proving a silent
failure had been fixed.** A guard nobody has seen fail is not a guard (108), and
`grep -v` in a negative assertion is the canonical way to write one — it reads as
"check it's not there" and means "check some line isn't it".

### 129 — the SMALLER number is the one nobody questions

*frankD, 2026-08-30, catching its own new check over-suppressing — and it is the
mirror of the over-fitting rule, not a repeat of it.*

Writing `docaudit slugs`, frankD added a suppression list for slugs named **in
order to say they are dead** ("absorbed into X", a correction note quoting the
wrong text it replaced). That class is real: **a slug named to declare it dead is
indistinguishable from a live dead pointer by name-matching alone.**

But the marker list included `not`, `read` and `instead of` — words that appear
constantly in prose. **Findings went 11 → 1, and five real abbreviated citations
vanished with the noise.** A near-clean run, from a brand-new check, on a corpus
already known to contain defects.

It was caught by the author's own calibration rule **running backwards**. The rule
was *a check that confirms everything is over-fitted*. The mirror: **a suppression
list wide enough to guarantee a clean run is a check tuned to agree with its
author.** Same fault, opposite sign, and only one of the two directions has a name.

**The asymmetry is why this needs its own entry.** Twice in one night frankD's
tooling failed in the *reassuring* direction — the suppression list, and earlier a
markdown filter that would have handed a lane a tidy sweep over files carrying six
known-false claims. **Both times the failure produced a SMALLER number, and a
smaller number is the one nobody questions.** An over-reporting check gets triaged
into correctness within an hour because every false positive is annoying and
visible; an under-reporting check is *pleasant*, and its silence is
indistinguishable from success. Exactly the docs' own asymmetry (125), now in the
instruments built to audit them.

**Corollary, measured immediately afterwards on the coordinator's side:** verifying
the same file with a deliberately loose pattern — treat every backticked hyphenated
string as a ticket slug — gave **7 findings of which 4 were false** (three were
`devdocs/dev/` doc names, one a test-case name). But it also found a **sixth real
abbreviation frankD's tighter check had missed**
(`task-o-hand-w2stress-to-the-corpus` → `…-so-optdiff-sweeps-it`). So the loose and
tight instruments each found what the other could not, and **neither was
trustworthy alone**. When the cost of a false positive is one `ls`, run loose and
triage; save tightness for checks whose findings are expensive.

### 129a — a dead slug in backticks is a live citation, whatever the sentence says

Same session, and it is the self-referential case. frankD's own correction note
quoted a dead slug **in backticks** — so *the note announcing a dead pointer read
as a live citation* to the very checker written to find dead pointers.

**Quoting the wrong text is right; quoting it in the same markup as a live
reference is not.** Convention adopted: a slug named in order to say it is dead is
written **plain**. Applied the same day to the roster's
`bug-t-nothing-exercises-o3-so-its-clean-record-is-empty`, a ticket that genuinely
existed and was withdrawn as a duplicate — annotated in plain text rather than
repointed, because the citation is *historically correct* and only its markup was
making a claim about the present.

### 130 — a guard built from the UNION of the cases you thought of is blind to their INTERSECTION

*pxx-a5, 2026-08-30, after its new guard failed on the very push that introduced
it — and the guard is what reported it.*

The guard checks that a resolve citation actually got filled. Condition (a) was
written as: *`pending` named this file **before** the fill, and the literal is
present **now**.* Both halves individually correct, both individually tested.

A ticket that carried a real placeholder **and quotes the placeholder in its
write-up** satisfies both while being entirely healthy — the citation filled, the
prose stayed. The ticket in question quotes it five times. It was **the first file
the guard ever looked at and the first thing it got wrong.**

**19 guards, 0 FAIL, on a broken condition.** Not one fixture had both properties,
because the natural way to write fixtures is **one property each** — a file with a
placeholder, a file with prose. The defect lives only in their *intersection*, which
no single-property fixture can express, and nothing short of running it on real
data could have caught it.

**So: when a condition is a conjunction, the fixture set must include a case
satisfying every clause at once**, not one case per clause. A suite that covers
each condition separately reports full coverage of a predicate it has never
actually exercised.

**The narrower sibling, and it is the cause:** *before-state plus present-state is
not the same question as after-state.* `pending`'s answer was already in hand from
the fill, so it got reused — **the wrong reading of the right variable**, cheaper
to reuse than to re-ask, and the difference is invisible until one file satisfies
both halves. The honest form is to re-ask `pending` **after** the fill, which is
the only thing that means "still owed".

**And it lands one turn past 128, which is what makes it worth its own number.**
128 says unifying two implementations deletes an accidental oracle, so build an
*independent* one. pxx-a5 did exactly that — then wrote the new oracle's first
condition **against state it already had** rather than against the state it was
asking about. Independence at the level of the instrument, re-coupled at the level
of the variable. The guard was right to exist, wrong on its first input, and the
thing that caught it was the guard.

**Trap footnote, and it is the same shape:** the failing run's exit code read as 0,
which briefly looked like the `exit 1` had not fired. It had — `sync.sh` was piped
to `tail`, so `$?` was `tail`'s. That is the trailing-command trap `push_or_die`'s
own comment documents, walked into **while testing the tool that documents it**. A
documented trap is not a guard, one more time.

### 131 — bank what you ELIMINATED; the exclusion set is the durable half

*frankwasm and frankA, 2026-08-30, converging independently within two hours — two
lanes, two languages, same practice, neither prompted.*

- **frankwasm**, on a compiler hang: reproduced the cycle it believed was the
  cause, and **it compiled clean**. Added the real ingredients back one at a time —
  arithmetic on a member, `split`/`len`, a module function returning None-or-float
  through two `try/except` arms. All clean. *"My main suspect was wrong and the
  exclusion set is now six shapes long, written into the ticket so the next attempt
  does not repeat mine."*
- **frankA**, on a generics wall: banked five inline reductions that did **not**
  reproduce — plain cross-unit `IComparer<TKey>`, plus `constref`, plus a method
  impl, plus a macro-supplied parameter list, plus nested type sections. *"The
  obvious mechanism is therefore insufficient, and without that list the next holder
  re-derives it the expensive way, which is most of the hour this took. Negative
  results were the more useful half here."*

**The asymmetry that makes this a practice rather than a courtesy:** a *positive*
finding is self-preserving — it becomes the fix, and the fix is the record. A
**negative** finding evaporates unless deliberately written down, and it is the more
expensive of the two to produce, because you have to build each shape and watch it
*not* fail. So the cheaper-to-recreate half is the half that survives by default.

**And an exclusion set is what makes a park honest.** Both lanes stopped without a
fix. A ticket parked with a live hunch invites the next holder to test the hunch —
which is exactly what the parker already did. A ticket parked with *six shapes that
do not reproduce* starts the next holder past the hour that was actually spent.
frankwasm's park was accepted on that basis: **the durable value was never the
hypothesis, it was the disproof.**

**Corollary — a disproved leading suspect is a result, and it should be stated in
the ticket's own voice.** frankwasm wrote *"NOT MINIMISED"* in capitals and said it
plainly rather than dressing it up; frankA distinguished *"a changed failure mode on
already-failing code, not a working case broken"* on evidence that could have been
written as a regression report instead. Both refused the flattering reading of their
own results, which is what makes the negatives trustworthy enough to build on.

Contrast face 125: pessimism about the *world* goes unaudited and rots. Pessimism
about **your own hypothesis**, measured and written down, is the cheapest thing you
can leave behind.

### 132 — a heuristic cannot tell the SUBJECT of a test from the MECHANISM by which it reports failure

*pxx-a5, 2026-08-30, sweeping for rows that assert stdout when the subject is an
exit code.*

The obvious instrument is a scan for `Halt(n)` with nonzero `n`. It finds 117
programs and 32 rows that do not capture `$?`. **All 32 are wrong**, and they are
wrong for one reason:

- `lib_dns_resolve` does `Halt(1)` on failure and `Halt(0)` on success. That is an
  **assertion mechanism** — how the test says it failed — not the thing under test.
- `crtl_atexit` is the best-looking candidate in the list and still isn't one: its
  subject is LIFO handler **order**, and `exit()` is merely one of two paths that
  must produce it. The ordering is on stdout, where the row already looks.

So a nonzero exit appears in a test for two opposite reasons — *because the exit
code is the observable*, or *because the harness needed a way to fail* — and *no
syntactic property distinguishes them.* The heuristic gets 100% of them wrong while
looking exactly like diligence, and 32 findings that cost nobody anything is the
calibration failure that teaches people to scroll past a check (129, and
`STALE-EDGE-HIDDEN`'s own comment).

**Hence: the family is an explicit list with a reason per entry, not a pattern.**
When the distinction you need is *intent*, enumerate and justify; a regex over
free text will always find something, and finding something is what makes it look
like it worked.

**And the real result was a number, not a list.** All 10 rows whose subject is an
exit status or signal **do** capture `$?` — including xtensa's, now fixed — and
across all 603 programs with per-arch rows there are **zero** cross-arch splits.
frankS's was the only one. The exposure is instead: **536 cross-target differential
rows, 5 capture the exit code, 531 compare stdout alone.** Both operands are runs
of the *same program*, so the exit code is free to add and unchecked everywhere.
**That is a property of how rows are written, not an audit list** — which is
precisely the habit-versus-guard distinction, quantified.

### 132a — a ratchet on the part the guard CANNOT check

The same devtest's section 3 holds the **531 at its measured size**. The guard
cannot verify those rows; what it can do is ensure the ungoverned set does not
**grow** while the governed one stays green.

That is the move to copy whenever a fix is correct but too large to land safely:
**freeze the remainder's size.** It converts an unbounded liability into a fixed
one, costs one assertion, and fails loudly the first time someone adds a 532nd —
which is the moment the decision is cheapest to revisit.

### 132b — and the deferral was right, on a risk reading could not settle

`run_target.sh` returns the **emulator's** exit status, and a signal death does not
encode identically through qemu-user and through a native shell (`128+n`
conventions, with qemu's own failure statuses in the same range). **A blanket
append manufactures diffs on exactly the rows most worth checking: a crash whose
stdout already matched.**

The pilot order filed with it has the load-bearing step second: **classify every
new red before continuing** — a real exit-code divergence goes to the owning lane,
an encoding artefact gets fixed in `run_target.sh`, *never papered over at the
row*. If the pilot arch yields more artefacts than findings, the normalisation
belongs in `run_target.sh` before any further row changes.

The lane's own sentence is the one to keep: **landing 531 blind, ungated edits
would be the same class of act as the row that started the ticket — something that
looks like coverage.**

**Footnote, twice in one file, in a session about exactly this.** The guard's own
coverage check read **5 of 10**, then **9 of 10**, and both were the instrument:
`\b` matched nothing because native binaries carry a `26` suffix and `6` is a word
character; then attributing each row to its *longest* match hid that a row naming
`test_halt_exit_code` also names `test_halt_exit`. **Both would have been reported
as findings about the Makefile.**

### 133 — when you convert silence into checks, the risk moves to the SUCCESS path

*frankB, 2026-08-30, routing twelve unchecked pdfgen call sites through one
`PdfCheck(doc, rc, what)`.*

The ticket was "errors are discarded". The obvious danger is missing a site. The
**actual** danger, once you start checking, is the opposite one: **a check that
fires spuriously on success is worse than the silence it replaces.** Silence loses
information; a false alarm takes working code red and teaches people to disable
checks — and it lands on the paths that were fine before you touched them, which
is where nobody is looking for a new failure.

So the control that matters is the **positive** one, and it is the one that gets
skipped. The negative control is easy to want and easy to build: unsupported font,
then a missing file, proving failure 2 reports its own reason instead of echoing
failure 1's parked message. Everyone builds that. The positive control needs a
case that **must still work today**, and here the bug's own shape supplied one —
BMP and JPEG are untouched by the endian defect (PNG is the only one of the three
with big-endian 32-bit header fields), so both were embedded with real
`/Image /XObject`, read back with pdftotext, and driven through every newly-checked
site. Then `reportlab-diff` made it independent of the author's expectation: three
documents glyph-box-compared against real reportlab, all driving checked calls, so
a spurious check takes that job red without anyone having predicted where.

Note also **the exemption is where the defect hides.** `stringWidth` still answers
0 rather than raising, deliberately — reportlab calls it speculatively during
layout and a zero is usable. But it now **clears** the error, because pdfgen parks
its message until acknowledged, and the next genuine failure would otherwise have
reported *stringWidth's* reason and sent the reader to the wrong line. The one call
being kept silent on purpose contained the exact defect the ticket was about.
**Audit your exemptions with the rule you are applying to everything else** — 63,
73 and 5 again, and it keeps recurring because an exemption is justified once and
then never re-read.

### 133a — a wrong answer wearing the costume of a right one

Same ticket, and the reason inspection could never have closed it. `ImageReader.getSize`
returned `134217728×67108864` from byte-swapped PNG header fields.

**`0×0` announces its own shape** — nothing is a zero-by-zero image, so a zero is a
wrong answer that reports itself as wrong. A byte-swapped dimension **looks exactly
like a large dimension**. There is no reading of the code that distinguishes them,
and it came from the accessor that was *supposed* to be authoritative, so it was the
thing other code trusted. Only `identify` saying 1024×1024 could catch it: an oracle,
not an inspection (118, 121, 128).

Footnote worth keeping because it stops a future misfiling: the `No such fil`
truncation in the error text is **pdfgen's own `char errstr[128]`**, reproduced
identically by a C-only probe — not our rendering. Establishing whose bug a symptom
is, before it becomes a ticket in the wrong lane, is the cheap half of this work.

### 134 — declining a well-argued pattern because the SHAPE does not match

*frank-optimize-b4, 2026-08-30, offered face 132a for its `-O3` campaign.*

It refused, and named the reason: 132a applies where a fix is correct but the
ungoverned set can **grow behind a fence**. Its case has the opposite shape —
`-O3` is a free tier with nothing gating it, so an unpromoted pass is not an
unbounded liability accumulating out of sight; it is fully live for anyone passing
`-O3` and fully absent otherwise. *"A good shape, and I want to be honest that it
does not fit here, rather than adopt it because it is well argued."*

**A pattern arrives with the authority of the argument that produced it**, and that
authority is about the *original* case. Adopting it elsewhere because the reasoning
impressed you is how a good idea becomes ceremony — and ceremony is the thing people
learn to route around, which costs the pattern its real applications too.

Then it did the valuable half: **relocated it to where the shape does match.** Its
aarch64 gap — x86-64 15 gate sites, aarch64 4 — *is* an ungoverned remainder, and it
grows by one every time a slice lands on one arm, as slice 8 just did. Its umbrella
already required recording the per-backend gate count per slice; that is a
**measurement**, and 132a says make it an **assertion**. Freezing the delta so the
next one-armed slice fails loudly beats a number in a log nobody diffs.

**Declining a pattern and relocating it are one act, not two.** A bare refusal loses
the insight; a bare adoption misapplies it.

### 134a — and the check you were about to build may be a fix

Proposed the same night, from a real instance: *a re-triage that moves frontmatter
leaves the ticket's own prose contradicting the ranker — worth a sweep.* True
instance, sound reasoning, and the finder had just fixed one.

Measured across all **380** ranked + `working/` tickets: **1 states a prio in prose
at all**, and that 1 disagrees. **One finding, ever, is not a check — it is a fix.**
The cost of measuring was one script; the cost of not measuring is a permanent scan
that fires once and thereafter teaches people it has nothing to say.

Note the shape, because it is the inverse of the usual error and therefore rarer:
not *a check that fires too often*, but **a check whose entire population is one
row.** Both fail the same way — the guard stops being read — and both are caught by
the same habit of counting the population before writing the guard.

### 135 — a ticket's STATED blocker and its ACTUAL blocker are independent claims

*frankwasm, 2026-08-30, NilPy user-defined decorators.*

The ticket's own central premise was that three callable representations had to be
reconciled — *"the first thing to measure, not to assume"* — and that this made the
feature not-small. Measured: `g = deco(g)` written by hand works today, rebinds the
def's own name, and **chains**, so a second one gives `W(W(g))` — stacked-decorator
semantics for free. **The stated barrier does not exist.**

A different one does, and it is now located precisely. Same `return g()` in a later
def: the hand-written form emits `AN_CALL ival=1635 tk=22`, the decorated form emits
`AN_CALL ival=1860 tk=23` — **`g` itself, called directly.** Global exists, is a
variant, funcvalue built, assignment built, and the call site consults none of it.
The hypothesis is a **token-position** key, because every neighbouring rule has that
shape (`PyUserShadowsProc` tests `ProcPyDefTok[i] - 1 <= TokPos`; `PyRedefBindingAt`
takes the last binding whose def token *precedes* the reference) — and **a
synthesised assignment has no token index, so no such test can ever see it.**

**Disproving the stated blocker is progress even when the feature does not land.**
The ticket is worth more now than when it was opened: one barrier deleted, one
located, one design ruled out by experiment (swapping `FindSym` for
`PyAssignTargetSym` with a kind check — unchanged), and a third proposed (register
the decorated def under a hidden name, closer to what CPython does).

### 135a — and it reverted WORKING code to avoid shipping the half

`@deco / def g / print(g())` compiled clean and printed `g` — **the undecorated
answer.** The decorator ran and its result was discarded. Today's `unsupported
decorator` error is worse ergonomics and **strictly better behaviour**, so the half
was unshippable: it is the silent-wrong-answer class, which the same session had
filed three tickets about that night.

The pull toward shipping it is strongest exactly here — it *works*, it took real
effort, and the failure is invisible in the demo. **A feature that is silently wrong
is a defect with a changelog entry**, and the changelog is what stops anyone
re-checking it.

### 136 — 132a freezes a set too large to FIX; re-scoping fixes a set too large to REPORT

*pxx-a5, 2026-08-30, offering the other side of 132a.*

Same underlying quantity, opposite move, and **in both cases the answer is to change
what the guard is allowed to look at rather than to make the guard cleverer.**

31 uncited resolutions in the freshest six days are worthless as a standing report
over the tree — that is a muted guard by construction. **The same 31 are valuable one
at a time, addressed to the person who just resolved the ticket, at the moment fixing
it costs one line.** So the check moved from `check()` over the tree to `sync.sh` over
`manifest_resolved`, and **the hardest caution dissolved rather than being satisfied:
there is no date floor to get wrong, because "this push" is the floor.**

Two of its three cautions now hold **by construction rather than by care**, which is
the right end state for all three. A caution that must be remembered is a caution that
will eventually not be.

### 136a — the grant I filed rested on a number its own author had retracted

Mine. The grant cited *"3 of 681"*, and the commit rejecting that number was pushed
**before** my grant landed: the count came from an ad-hoc test that scored a ticket
merely *discussing* a `commit range 8fb3f776..b3fd1c76` as cited. Under the house
definition the freshest six days give **31 of 328**, and the pre-August window **456
of 1123** — so the date floor I wrote in as a caution was **falsified by the same
data that motivated it**.

I verified the *design* and not the *number*. The design was good, which is exactly
why the number went unexamined — and I had spent the preceding hour telling other
lanes that a plausible, load-bearing claim adjacent to something the author genuinely
knows is the profile of a claim that goes unchecked. **An authorisation quotes its
premise, and quoting freezes it**: the retraction had already landed on master, and
my grant re-published the dead number with the coordinator's authority behind it.

The lane returned the grant unspent rather than working inside it. **That is the
system working** (operating rule 3), and the tell was in the grant itself: the ticket
it cited was in `rejected/` at the moment I wrote the citation.

### 137 — an AUDITOR's stated danger deserves the same scepticism as a doc's stated limitation

*frankD, 2026-08-30, sweeping the live docs for unexecuted re-check obligations.*

The mirror of the false-limit rule, and the half that was missing. A doc saying *"this
is not possible"* reads as conscientious and stops anyone re-checking. **So does an
auditor saying "this is dangerous."** Both are unfalsified claims wearing the costume
of rigour.

Concretely: bare-name shims (`re`, `configparser`, `tkinter`) sit beside `mimic_*`
ones, and the resolver probes `<name>` **first**. The alarming reading is immediate —
a bare-named shim shadows a user's own `re.py` — and it had a plausible mechanism and
a real code smell behind it. The ticket was half-drafted.

**It ran the test instead.** A local `re.py` defining `compile()`, beside `import re`,
built with `$(PXX_STABLE)`: prints **`USER-RE`**. The user's module wins. Two minutes.

The asymmetry that makes this worth banking: *"mine would have been more expensive
than the doc's, because it would have arrived in frankB's queue wearing the authority
of a measurement I had not taken."* An auditor's finding is **routed**, and routing
converts it into someone else's premise. So the scepticism must be spent **before**
filing, not after — and per the compat table's own rejection row, what actually
survived here is expectation cost with no program behaving differently, which is a
note in the doc, not a prio-10 ticket sitting in the ranker's scan forever.

### 137a — WHICH docs to sweep, stated mechanically

The selection criterion under 106 (*a documented trap is not a guard*), and the
reason it is not merely restating it:

> **The rule was written by someone who could execute it once, for a reader who has
> no way to know whether anyone has.**

So: **every such rule needs either a command that re-derives its own status, or a
named owner who is asked.** `track-b-workarounds.md`'s *"verify the bug ticket is
still in backlog/ before assuming the workaround is still needed"* had neither — 7 of
8 rows cited closed tickets. `python-compat-tiers.md`'s *"should move behind the same
mapping **when it lands**"* had neither — it landed, the three units have not moved,
and `lib/pcl` now holds `tkinter.pas` beside `mimic_tkinter_font.pas`: **the
convention applied inconsistently inside one package family.**

That is a grep-able shape — *"when X lands"*, *"revisit once"*, *"until Y"* — and it
separates obligations from aphorisms, which are the same sentence in a different mood.
Yield on 18 of 42 docs: mostly aphorisms, one real, one **verified negative** worth
recording (`nilpy-semantics-divergences.md`'s *"parked in rainy-day/, not rejected"* —
still exactly there). Note that the real one was **the second instance in a file the
same auditor had corrected two hours earlier**: the sibling rule bit twice in one
night, in the same direction both times.

### 138 — the SHAPE of the evidence was produced by the HARNESS, not by the defect

*frankS, 2026-08-30, correcting the coordinator's retrack of `regression-test-emit-obj`.*

The log showed three objects emitting `ok:` and **only the riscv32 link failing**. I
read that as a discriminator and wrote a bounding argument on it: *a frontend bug
cannot be target-specific, so the cause is below the frontend.* The rule is sound. The
premise was an artefact:

- the three `ok:` lines are object **EMISSIONS** (`pxx --emit-obj`), not links;
- all three objects carry `UND ext_aliased_link` **identically**;
- `_xt.o` against the same shim fails with the **same** error at a different offset
  (`.text+0x3340c` vs `.text+0x3b418`).

**The xtensa link never ran, because make aborted at the riscv32 line first.** One
failure appeared because the runner stops, not because one target is special.

Pair it with the exit-code sweep, because they are the same defect in opposite
polarity: **there, a green meant "the row asserted the wrong thing"; here, a
single-target red meant "the runner stopped".** Both invite a target-specific story,
and in both cases **the second data point is what kills it** — linking the *other*
object, capturing the exit code as well as stdout. Before reading a pattern across
targets, ask whether the harness could have produced that pattern by itself: `make`
stopping, a tier not running, a job never scheduled.

And the sting: **a right destination reached by a false argument does not
self-correct**, because the destination keeps looking like evidence for the argument.
The retrack put the ticket in the right lane by luck. Had frankS accepted it, the
next holder would have gone hunting in riscv32 emission with my sentence as their
warrant.

**The defect underneath is worth its own line:** `1a7658326` made the object reference
the link name and added two readelf assertions demanding exactly that — and thirty-five
lines down, the same recipe generates a shim defining only `ext_notify`. **A recipe that
asserts a symbol must be undefined and then links without providing it**, the
contradiction introduced by the commit that made the test correct. The refusal that
mattered was frankS's: *do not keep the readelf assertions and delete the link check* —
the assertions are the subject, the link check is what proves the object is usable.

### 139 — writing up a NEIGHBOURHOOD as a MECHANISM

*frankA, 2026-08-30, correcting its own ticket; the correction is larger than the fix.*

Two failures — `unexpected token` and `unknown type: TKey` — both near generics, both
after the same bisect. **"Both fail near generics after the same bisect" was allowed to
stand in for "same bug"**, and the author had written a memory about that exact error
four hours earlier.

Underneath it, a textbook confound: the repro's support unit **reused a template name**
left over from an earlier experiment in the same directory, so the include and the name
reuse **varied together** — and the one with a story attached got reported as the cause.
Four experiments to separate them: include without reuse clean, reuse without any
include fails, same-unit-different-arity clean, same-unit-same-arity fails. So
*cross-unit* was wrong too, and the real condition is **same name AND same arity as an
already-registered template, wherever written.**

**A wrong repro attached to a real wall is more expensive than no repro**, because it
reads as progress and sends the next person to a bug that is already fixed. Marking the
corpus wall **UNREDUCED, with no repro at all**, and telling the next holder not to
reuse the old one, is the correct disposal. What survives is the measurement — cut@438
clean, cut@474 reproduces — separated from the story built on it.

### 139a — the assertion that could not have failed, caught BEFORE it landed

Same session. The planned assertion was *zero injections before the declaration*. It
measured first, via a new `p.dgen` channel printing every in-place injection, and the
file printed **zero injections total** — concrete specializations take the alias path
and never reach that arm. **A passing assertion whose subject the test never
reaches** (130, 33), caught before landing rather than years later.

The repair is the general recipe for this: add a case that **must** produce the thing
(`TPairU`, a real paramform use) and assert a nonzero count *alongside* the zero, then
**remove the guard and rebuild** — 2 injections and a failed parse — then restore: 0 and
clean. **A control is not a control until it has failed once.** Then `shadow 12 10`
matching FPC makes it an oracle rather than a self-comparison (121).

The sibling check that is usually skipped, and was not: the `:` half of the guard is
load-bearing, because a typed constant `x: TFoo<Integer> = (V: 1)` is *also* followed by
`=` and **is** a genuine use — so typed consts, vars and aliases of an imported generic
were all verified to still compile and run. That is the positive control (133) on a
guard whose whole job is to refuse things.

And the discipline of **not folding in** the name-resolution defect (`b.Local` answers
"no such member" where FPC prints 42, reachable only because the parse now succeeds):
token rewrite and template registration are different mechanisms, and merging two
mechanisms is what made the first filing wrong in the first place. Its regression
sidesteps that bug deliberately — both records declare the same member — so the result
cannot depend on which template wins. **A test must not silently depend on an open bug.**

### 140 — a BY-CONSTRUCTION claim is legitimate exactly when the construction is a property of the ARTEFACT, not a role somebody ASSIGNED

*frankD, 2026-08-30, sweeping the live docs for bounding arguments
(`by construction`, `structurally`, `can never`, `guarantees` — 35 candidates).*

The test, and it is sharp enough to apply without re-deriving it:

| claim | construction | verdict |
| --- | --- | --- |
| *"pxx emits zero `syscall` instructions, so every syscall originates inside libc"* (OpenBSD `pinsyscalls`) | a property of **what we emit** | **legitimate** |
| *"the x86-64 side cannot be wrong by construction — it is the reference"* | a **role assigned** to one arm | **not a bound at all** |

The second is a definitional claim doing empirical work. Nothing about being *called*
the oracle constrains the code, so the sentence carries the grammar of a proof and none
of the force (121: a self-differential's reference is not an oracle).

**And the second data point was already in the repo, months older than the first.**
`Int()` of a large double was wrong on the 32-bit targets **and** on x86-64, in
different ways, fixed months apart — the later ticket says it in its own summary:
*"The i386/arm32 half of this was fixed under [the other]; **x86-64 was never in scope
and is still wrong.**"* So there was a **documented window in which the cross targets
were correct and the reference was not**, and any cross-target red read by the
blame-the-cross-target rule during that window was attributed exactly backwards.

The detail that earns it a place: **the x86-64 defect was found by Track B from a
library, not by the cross sweep that ran over it the whole time.** The sweep could not
find it, because the sweep's rule named that arm correct.

**Verified by behaviour at HEAD, not by folder** (rule 10): both tickets are in `done/`,
and the pinned binary now answers `Int(1e300) = 1.0000000000000001E+300`,
`Int(-0.5) = -0.0`, `Frac(1e300) = 0.0` — FPC agrees on all three. So the window is
**historical, and correctly described as such**. The remaining digit-count difference
against FPC's `1.00000000000000005250E+0300` is float FORMATTING, which is **F, low prio
by definition** — not a defect and not to be filed.

### 140a — ADD a second measurement rather than CORRECT the first

The section frankD examined already carried the right conclusion, measured that same
day. It did not need correcting; it needed a **second, independent** support.

> **An argument resting on one measurement is one retraction away from collapsing.**

Which is exactly how face 138 failed hours earlier: one bounding argument, one
data point that the harness had manufactured, and the whole inference went with it. The
`Int()` case and the `test_cross_float` case come from different periods of the repo,
different lanes, and neither depends on the other — so retracting either leaves the
claim standing.

**And the best-looking hit was a false positive.** The `by construction` sentence was
the *setup being demolished two paragraphs later*. Caught by reading the context
instead of acting on the grep hit — the same trap as a path that is absent because the
doc won its argument. **Grep finds the sentence; only the paragraph says whether it is
asserted or quoted.** Mention versus use, third costume in one night.

### 141 — ADJACENCY APPLIES TO AN ORDERING EXACTLY AS IT DOES TO A REGISTER

*frank-optimize-b4, 2026-08-30, the control for the `-O3` operand-order pass.*

The pass reverses evaluation order, so the control must prove a wrongly-early read is
visible. First draft used `gV = 100` — and **the unsafe build passed**, because
`100 shr 1` and `101 shr 1` are both **50**. At `gV = 101` correct gives 51 and
reordered gives 52.

**A control for an ORDERING needs the reordered read to differ from the correct one**,
and round numbers are exactly where it does not — the same reason a fixture value must
differ from its neighbour, from the register case, now wearing its third disguise in one
night. A vacuous control was one value away from shipping, in a session that had already
banked two of these.

### 141a — the estimate was wrong in the direction that flatters the pass

Filed as **-2 instructions**, from reading a disassembly and counting two moves that
looked removable. Writing the pass showed only **one** goes: the obvious version —
right into `rcx`, then left into `rax` — is **unsafe**, because `ScratchSafeSubtree`
explicitly admits emissions using rax/rcx/rdx and a nested BINOP loads its own right
operand into rcx. That version is safe only for a **leaf** left, which is precisely the
case the `-O2` mirror already handles. The remainder is the both-complex case, worth one
move: park the **right** value, and the restore vanishes because the left is produced
last and is already in rax.

Legality is stricter than filed too: the arm below needs only `ScratchSafeSubtree(right)`
because it evaluates left first; **reversing the order needs both sides pure**, since a
left with side effects must not be moved after a right that can read them.

**Filing (B) made it better; filing (C) made it smaller. Both times the justification
was where the design actually got decided** (112), and both times a banked estimate
would have carried the wrong number forward — **this one into a promotion argument**,
where the number is the whole case. Measured result: `three.pas` loop 18 → 17, campaign
cumulative 22 → 17, six programs byte-identical at -O0/-O1/-O2 and all smaller at -O3.

### 142 — when a bug is TARGET-SPECIFIC, your default build is a CONTROL arm, not a TEST arm

*frankB, 2026-08-30, reverting four workarounds whose blocking tickets had closed.*

Row 1's bug — `Int()` of a large double saturating to 32-bit — was **i386/arm32 only**.
So every probe available on the developer's machine (the box, the pin, the default
build, `make lib-test`) **passes identically whether the fix is present or not**.

> *"I tested it and it works" would have been a true sentence and worthless evidence.*

That is the whole trap, and it is not carelessness — the sentence is true, the test
really ran, the result really was green. **The default build was green before the fix
too**, which makes it a control arm that happens to be labelled a test arm. The revert
is licensed only by cross-compiling the repro and running it under qemu **on the two
targets that actually had the bug**, then checking Sin/Cos at ten magnitudes straddling
2^31 byte-identical across five targets and exact against CPython/libm.

Sits with 138 and with the host-green rule as one family: **before reading a green,
ask which arm could have produced it** — this machine, this tier, this target. A green
from an arm that never had the defect is a control, and controls are only informative
next to a test.

And the positive control was built rather than assumed (133): mutating the reverted
lines back to 32-bit saturation blows three rows up to ~1e158 while the sub-2^31 rows
stay correct. **That is what licenses reading the passing run as coverage rather than
as "nothing crashed."**

### 142a — the five-link chain, and why four live reverts sat for weeks

The answer frankB extracted, now in `track-b-workarounds.md`, and each link has been
the false one at least once in this repo's history:

> **fixed on master** ≠ **in the pin** ≠ **the reverted code runs** ≠ **the capability
> works at all** ≠ **it works on the target that was broken**

*"Checking looked like one question and is five."* That is the mechanism behind 137a —
a rule with no self-deriving command goes unrun — stated as *why* it goes unrun. It is
not laziness; it is that the cost was misjudged by a factor of five, so nobody budgeted
for it and everyone assumed someone had done the one-question version.

### 142b — row 6: a ticket in `done/` whose capability does not work

`bug-aggregate-member-array-as-var-param` names four acceptance cells: 2D-array row and
array-typed record field, each `var` and `const`. **Three pass. The fourth — a 2D-array
row as a `const` param — segfaults on all five targets**, and it is the exact cell
ed25519 needs (`AddF(var o: TGf; const a, b: TGf)` and eleven more).

Confirmed independently by the coordinator with a probe written from the description
rather than from frankB's source: `var` on the row prints correctly, `const` on the same
row dies with SIGSEGV on the **first** element access, and `SizeOf` is correct at 128/256
— so the element mis-sizing the ticket diagnosed as its root cause genuinely *is* fixed.
**A different defect was living behind the same acceptance test**, and the ticket closed
on three cells of four.

Rule 10 paying out exactly: *"filed as done" and "the capability works" are different
claims.* The routing note that makes it cheap for A: **`var` on the identical row, type
and call-site shape works**, so it points at the const-aggregate argument path, not at
address-of for aggregate members in general.

### 142c — a LANDMINE THAT OVERCLAIMS steers code away from a form that works

The subtlest of the four, and a genuinely new direction. Rewriting the ledger, frankB
**narrowed** the aggregate-member landmine from *"keep every sub-array standalone"* to
the single surviving cell — because a record of arrays now has **no** restriction at all.

> *A landmine that overclaims steers code away from a form that works, which is the
> same failure as the section header that overclaimed — one costs you reverts, the
> other costs you designs.*

**The cost of a too-broad caveat is designs not taken, and that cost is invisible.** A
stale *restriction* leaves no artefact to find: no failing test, no red, no workaround
to revert — just code that was written the awkward way, by someone who never learned
there was an alternative. This is the false-limit rule (rule 2, third corollary) applied
to engineering guidance rather than to findings, and it is worse there, because guidance
is read by people who have no reason to re-derive it.

Note the disposal: both landmines were **rewritten, not deleted**. A deleted landmine
takes its history with it and invites the original bug's re-discovery.

### 142d — and one deliberate NON-revert

`examples/bignum/bigmath.pas`: both cited bugs fixed, the revert available, **and not an
improvement.** In a checker, `chk := BigAddSigned(prod, r); if BigCompare(chk, a) <> 0`
names the intermediate that the FAIL message is about; nesting the calls reads worse.
The stale thing was the *header claiming a constraint*, so the comment was corrected and
the code stood.

**"The workaround is no longer necessary" and "the workaround should be removed" are
different claims.** A revert-when-fixed lifecycle that cannot record *"kept on merit"*
turns into a ratchet that degrades code every time a bug closes.

### 143 — a lane told to TAKE THE QUEUE HEAD will always be MAPPING, and that is the dispatcher's doing

*frank-coordinator, 2026-08-30, after frankwasm parked three N tickets in a row and
asked, unprompted, whether it was mapping when it should be building.*

Its three parks were individually defensible — one was my own call, one disproved a
ticket's central premise and reverted working code that printed a silent wrong answer
(135a), one banked a nine-hook implementation map before spending on emitters. But three
in a row is a pattern, and the pattern is mine:

> **I told it to take the top of `ready --track N`. The top of a mature lane's queue is,
> by construction, where the big undone features are — high prio *and still open* means
> hard.** So a lane that always takes the head will always be mapping, and its dispatcher
> will keep reading the result as a disposition problem.

The failure is invisible from the worker's seat: every individual choice looks right,
because every individual ticket really was too big to finish. It is only visible from
the queue, which is the coordinator's view — the same asymmetry as *an idle worker is
the coordinator's only output going to zero* (rule 6), arriving from the opposite side.
Rule 6 says do not let a worker idle; **this says do not mistake a dispatch policy for a
worker's temperament.**

**The remedy is a dispatch change, not an instruction to build:** deliberately take a
*completable* item down the queue, land it, then return to the head with the map already
banked. Mapping and landing alternate; they do not compete. A lane that never lands
capability stops being able to tell a hard ticket from a hollow one, because it has no
recent calibration of what finishing costs.

And the worker's own pushback was the load-bearing half, so it goes in verbatim: **do
not do the easy half.** Enum member access without iteration or lookup would compile
`for c in Color` into something plausible — *"the decorator failure with a different
name"* (135a). **A partial feature that answers is worse than one that refuses**, and
"land something" is exactly the pressure that produces one.

### 143a — it reported what it had SAID it would do, then did something better, and flagged the gap

Same session: it told me it would *"carry on down `ready --track N`"*, then finished a
ticket it already held instead — the right order, since abandoning a just-claimed ticket
to take another is the churn it had itself flagged. It corrected the record anyway:
*"that isn't what I said I'd do, and you were reading my message not my queue."*

That last clause is the whole point. **The coordinator's model of a lane is built from
messages, not from the tree**, so a divergence between what a worker said and what it did
is a defect in *my* state even when the worker's action was better. Worth naming because
the instinct is to wave it off as harmless — and it is harmless to the work and not to
the coordination.

### 144 — a diagnostic that cannot name its SUBJECT merges distinct defects into a BUCKET, and a bucket is what nobody picks up

*frankS, 2026-08-30, taking xtensa from 69 to 96 of 129 differential rows.*

The stale message:

```
target xtensa: builtin calls not supported in bare-metal stage 1
```

reached under `--platform=posix`, where **there is no bare-metal stage**, naming **no
builtin**. Fixing it to print the id immediately split **six programs that read as one
category into five distinct builtins** — `-210` (fixed on the spot, two lines), `-55`,
`-100`, `-50`, and `-999`, which turns out **not to be an xtensa gap at all**: riscv32
refuses the same source with `builtin id 999`. Verified by compiling it there, not
assumed.

**So the cost of an unspecific diagnostic is not one wasted build. It is that six
defects become one bucket, and a bucket is what nobody picks up** — its size makes it
look like a project, its uniformity makes it look like one cause, and neither is true.
One of the five was two lines away; one belonged to a different backend entirely.

Third instance tonight, and the generalisation is the same each time — `IROpName`
reporting `unsupported node in IR codegen: **unknown**` for seven ops on every target,
the binop message, and this:

> **A message that says nothing sends you looking. A message that names a cause it no
> longer has sends you somewhere, and it is wrong.** In all three, the *misdirection*
> cost more than the *absence* would have.

That inverts the usual instinct to prefer any diagnostic over none. A wrong-but-specific
message is the worst of the three states, because it is the only one that spends
someone's time confidently.

### 144a — THE ORACLE DID NOT MAKE THEM FINDABLE; IT MADE THEM FAIL

The count from one night on a backend that had never been executed: the ordered string
compare, the Call0 expression stack, `HeapMmap`, the ABI predicate, the aggregate string
stores, the managed-string index, the frame alignment, six of seven scope-exit kinds,
`Halt(n)`, the whole-array store, the set parameter — **eleven**, and **every one was
reachable by reading the source at any point in the preceding three months.**

That is the entire case for differential testing in one sentence, and it is not the
usual one. The oracle did not reveal anything that reading could not have. It **changed
the cost of not looking** — turning a defect that required someone to suspect it into
one that announces itself. Availability was never the constraint; *attention* was.

Corollary that explains the whole shape of the backlog: **nothing on xtensa had ever
called `ParamCount`.** Not one of the eleven was hidden. They were unvisited.

### 144b — naming the two ops NOT done instead of shipping them

`IR_FRAME` and `IR_SET_SIGNAL` were left unimplemented, deliberately, because **no
program in the 129-source corpus reaches either**:

> *Writing them would be unverifiable code in a backend whose entire problem was
> unverifiable code — the thing this campaign exists to stop.*

The pull is real: two more ops is a better-looking number, the code would probably be
right, and nothing would fail. **Unverifiable code that happens to be correct is
indistinguishable from unverifiable code that is not**, and it is added to the arm whose
whole defect was that nobody had run it. `IR_FRAME` additionally needs an xtensa frame
layout that riscv32's one-line `mv a0, s0` does not carry, so the port would have been a
guess wearing a port's clothes.

### 144c — and a residue item that is not what it looks like

`ParamCount` (`-55`) reads like a same-file port from riscv32. It is not. riscv32's arm
reads `BSS_INITIAL_RSP`, and **every hosted target's entry stub saves the
kernel-provided sp there — except xtensa's, which sits in the same procedure and does
not.** The value the builtin needs is never stored, so no amount of backend work reaches
it.

Two lessons stacked. First: **a missing consumer hid a missing producer** — the entry
stub gap is three months old and invisible because nothing on xtensa had ever asked.
Second, on scope: the fix touches `EmitProgramEntryForTarget`, **a different procedure
from the granted one**, so it was filed as a new ticket rather than taken as an
extension. A grant scoped to a procedure means that procedure, and a lane that widens
its own grant by one adjacent function is how a scoped grant becomes a file claim.

### 145 — a comment that ASSERTS the invariant its implementation lacks

*pxx-a5, 2026-08-30, root-causing the shard-0 conformance regression (T → P).*

`f12a62815` tells a template **header** from a **use** by one token, and its comment
states the rule it relies on:

> *"a HEADER is followed by `=`; a use never is."*

A typed constant is `Ident < Ident > =` — **that shape exactly.** So the discriminator
the comment asserts as a property of the language is not one, and:

```pascal
type generic TTest<T> = record x: T; end;
const P: ^specialize TTest<LongInt> = Nil;   { fails }
var   P: ^specialize TTest<LongInt>;         { compiles }
```

`LongInt` gets harvested as a template parameter name — **unscoped, every such name in
the file** — `isParamForm` goes True, the pattern-B rewrite added for this very
construct is suppressed, and `^specialize` parses as the pointed-to type.

**The comment is the bug's disguise, not its documentation.** This is distinct from *a
documented trap is not a guard* (106): there the doc correctly describes a hazard nobody
acts on. Here the doc **states the property that would make the code correct**, in the
confident register of an invariant — and that is precisely what stops the next reader
checking whether it holds. A wrong comment asserting a *fact* gets caught when the fact
is checked; a wrong comment asserting an *invariant* is read as the reason no check is
needed.

Grep-able shape for a future sweep, and it belongs beside 140's test: **a comment of the
form "X is always followed by Y" or "a use never is" is a claim about the grammar, and
the grammar is checkable.** If the comment is load-bearing for a discriminator, it is a
test, not a sentence.

### 145a — attribution by MECHANISM, with the bisect it did not run named

The honest scoping, stated by the author unprompted:

> *"f12a62815 landed 2026-08-29 and shard0 went red the same day; the other five shards
> last passed at 0b6f1ffe9419. Nothing else in that range looks implicated, but
> attribution is by mechanism, not by a build bisect at `f12a62815^` — I did not build
> the parent."*

Mechanism attribution is *stronger* evidence than a bisect when it explains the
behaviour — a bisect names a commit, a mechanism names a cause — but it is a different
claim, and the two are usually conflated in a ticket's Log line. Naming the check **not**
run is what makes the claim usable: the next holder knows exactly what would upgrade it,
and knows they are not re-deriving something already done. Compare 108's inverse, where
an unnamed scope let a survey read as exhaustive.

**And the sharding artefact was rejected by measurement, not by argument:** tgeneric87 is
entry 337 of 550 → idx 336 → 336 mod 6 = 0 → shard 0, which holds exactly the 92 tests
the report counts. *The one red shard is the one holding the test.* The plausible
alternative story — "sharding is flaky" — dies on arithmetic that took a minute.

### 145b — and the successor ticket is the SAME mechanism

`bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument`
is the same unscoped blacklist. Routing note, and it is `root-cause-over-microfix`
verbatim: **one repair likely closes both, and taking the microfix here re-splits a
concept that already has two mechanisms.** Two is a smell, three is a design flaw.

The blacklist was also confirmed **independently of the `=`** — a second template with a
parameter literally named `LongInt` breaks the `var` form too. That case is the cost
`f12a62815` *knowingly* accepted; the typed const is not. Separating the accepted cost
from the unintended one is what makes this a fix rather than a revert.

### 146 — a control that BOUNDS the defect, not one that confirms the fix

*frankB, 2026-08-30, widening the tkinter pad retirement test while the ticket stayed
pin-gated.*

Enumerating the at-risk shape over `lib/pcl` — a **method** with a Variant parameter
reachable while an earlier default is unbound — found eight declarations and **four**
failing methods, not one. Four more FAILS is the kind of result that writes its own
conclusion, and the conclusion would have been too big.

The row that stopped it:

```
askopenfilename(filetypes=[(...)])   COMPILES   <- control
```

**Identical parameter shape, object-valued argument, and it compiles TODAY at the
unfixed pin** — because it is a unit-level *function*, not a method.

That inverts what a control usually does. The familiar one (133) proves a fix works by
showing something that must still pass. **This one proves the defect stops somewhere.**
Without it, four extra FAILS were equally consistent with a far broader defect, and the
scope claim would have been overclaimed with real measurements behind it — the most
durable kind of wrong, because every row in the table is true.

**So: when you enumerate instances of a defect, the load-bearing row is the one that has
every property of the failing set and does not fail.** An enumeration without one
measures how hard you looked, not how far the defect reaches. And note it was already
available — `askopenfilename` was sitting in the same façade the whole time; what it
took was asking *what would falsify the scope*, not more searching.

Every failing row also has its own passing row differing **only** in whether the earlier
defaults are named — same diagnostic, same mechanism. A paired table like that is a
mechanism claim; a list of failures is an anecdote count.

### 146a — an acceptance test aimed at the REPORTED SYMPTOM closes on the symptom

Third instance of this shape in one night, and now it has a name. frankB, on its own
earlier test:

> *The retirement test I wrote checked one method. That is an acceptance aimed at the
> reported symptom, which is precisely how the const-array cell survived its parent
> ticket.*

- `bug-aggregate-member-array-as-var-param` named four cells, passed three, closed —
  and the fourth is the one ed25519 needs (142b).
- The tkinter retirement test checked one of four failing methods.
- `test-emit-obj` asserted the symbol is undefined and then linked without it (138).

**A ticket reports a symptom; its acceptance test is written from the ticket.** So the
test inherits the ticket's scope, which is by definition the part someone already noticed
— and the cells nobody reported are exactly the cells nobody will check. The repair is
cheap and mechanical: **before writing the acceptance, enumerate the shape rather than
the report** — every method with this parameter form, every cell of the var/const ×
row/field grid — and make the ones you are *not* covering explicit.

### 146b — and a lock over work that cannot proceed is a FALSE LOCK

The ticket stayed pin-gated (`v393` at HEAD, four spellings behaving exactly as
recorded), so it was **left in `unfinished/` and not claimed into `working/`**.

`working/` means an agent is actively on it. Occupying it to signal *interest* in blocked
work makes the folder's staleness signal unreadable for everyone — the same conflation
`bug-t-a-campaign-umbrella-has-no-safe-status-to-sit-in` reports from the other end, where
a live campaign has nowhere to sit. **Both are the status vocabulary answering "is someone
on this" when the question is "can this move".**

### 147 — a PROSE error the accompanying COMMAND routes around, and why it outlives a broken example

*frankD, 2026-08-30, auditing `valgrind.md`.*

The doc's quick start passed `--proc-map` and its prose said that flag writes `<out>.map`.
Both false: `<out>.map` is written **by default** (`EmitMapFile := True`; `--no-map`
suppresses), and `--proc-map` goes to stderr computing `LOAD_ADDR + CODE_OFFSET +
BodyAddr` with the **static** offset — while the profile the doc prescribes,
`-dPXX_LIBC_HEAP`, is a **dynamic** build, which the doc itself says two paragraphs up.

| build | `<out>.map` | `--proc-map` stderr |
| --- | --- | --- |
| static | `0x40efb0 Foo` | `0040efb0 Foo` — agree |
| `-dPXX_LIBC_HEAP` | `0x40eb61 Foo` | `0040eaf1 Foo` — **0x70 low** |

0x70 is exactly `DYNAMIC_CODE_OFFSET - CODE_OFFSET`.

**And it does not fail, it lies.** `vgsym.py` resolves with `bisect_right - 1` under a
0x20000 tolerance, so a shifted address binds to the **preceding** routine whenever 0x70
crosses a boundary — and most emitted routines are shorter than 0x70.

**The shape: the doc's printed pipeline was always correct.** It fed `vgsym.py` the
`.map` file, not the stderr. So **anyone who copy-pasted got right answers and anyone who
read the sentence got a wrong model** — and the flag they were told to add spewed 123
wrong lines nobody ever looked at.

> **A prose error that the accompanying command silently routes around cannot be caught
> by running the doc — only by reading it against the code.**

That is the exact inverse of an unrunnable example, and it **survives longer precisely
because the thing works**. Every use of the doc confirms it. This is why a docs audit
cannot be replaced by "do the examples still run": the examples running is compatible
with the prose being wrong in a way that will mislead the next person who reasons instead
of pasting.

Filed as `bug-a-proc-map-emits-static-addresses-for-a-dynamic-build` [A p30] with the
one-line fix and a delete-the-flag option, since `<out>.map` already does the job.

### 147a — a FIRST-WALL SURVEY under-counts systematically, and reports the SHALLOWEST remaining gap as the DEEPEST one left

*Same session, `fpc-lcl-compile-probe.md`.*

Its method was compile-until-the-parser-stops. **That instrument cannot see past the
first wall**, so its output is *the order in which the parser trips* — not a ranking, and
not a count. The doc read it as both, and ranked three blockers by it.

Measured against reality: `fgl` needed **six or more** fixes across **three layers**, and
the last was invisible to every parse-level probe — after all syntax walls cleared,
`ifclist` failed **at runtime** on missing method hiding, storing a VMT word.

> **A first-wall survey under-counts systematically and reports the shallowest remaining
> gap as the deepest one left.**

Same family as 140 and 108: **the ranking was a property of the instrument, not of the
work.** And the tell is generic — any survey that stops at the first failure produces an
*order*, and an order is one `sort` away from looking like a priority list.

Note what did **not** rot: the doc's *conclusion* ("pxx is not blocked on core Pascal
syntax for real FPC code") was right and stayed right. **Only the ranking decayed.** So
the disposal was a banner plus an intact body, not a rewrite — the conclusion still has
its evidence, and the reader is told which half to distrust.

### 147b — and the coordinator's own dispatch hazard, handed over rather than filed

`feature-pascal-corpus-fgl` sat in `backlog/` at **p55** with every item complete. frankD
deliberately did **not** file a ticket — *"a ticket saying 'resolve this ticket' costs
more to process than the ~5 minutes of waste it prevents"* — and passed it to dispatch,
where closing it is one command.

Correct call, and the reason it matters is rule 7: **a ranked queue says a ticket is
unblocked, not that it has work left in it**, and p55 is high enough to be dispatched to
a worker who would then have found nothing. Verified before closing rather than taken on
the report: `test/fgl/pxx.skip` has zero non-comment lines, `fpc-rtl` is in `twatch.py`'s
`CORPUS_EXPECTED`, `testmgr.py` records the 2026-08-26 enrolment, and the ticket's own
"Not done here" delegate — `task-t-enrol-the-fgl-corpus-rung` — is in `done/`. Both
halves of its residue were genuinely closed.

**Not every finding should become a ticket.** The filing threshold is whether processing
the artefact costs less than the waste it prevents, and for "a done thing is still open"
handed to whoever runs dispatch, it does not.

### 148 — THE INSTRUMENT NEEDS THE SAME ADVERSARIAL PASS AS THE FINDING

*frank-optimize-b4, 2026-08-30, correcting a number it had reported to the coordinator
twice.*

The per-backend gate count was measured by `grep -c 'OptLevel >= 3'`. **About a fifth of
the campaign's gates are spelled `if OptLevel < 3 then Exit;`** — the early-return shape
that slices 7, 8 and 10 all use — and that grep cannot see it. Reported ratio **23 : 7**, not the 15 : 4 previously
recorded — **and 23 : 7 is ALSO WRONG. See 159.**

**The tell was that adding a gate did not move the count: 17 before the slice, 17 after.**
A measurement that fails to respond to a change you know you made is the cheapest
available refutation, and it is only visible if you look at the number *after* an action
whose effect on it you can predict.

> **"Count arms by parsing, not by reading" buys nothing when the parse matches only one
> of the two ways the arm is written.**

That is 140 and 147a arriving in the tooling: the output was a property of the
instrument. And the disposal is right — the *conclusion* (x86-64 far ahead of aarch64) is
unchanged and slightly sharper, so the **slug stays** (slugs are cited by resolved
commits) and the correction of record goes **inside** the ticket.

### 148a — a measurement instrument that lives in /tmp is not committed

`three.pas`, the benchmark whose loop-instruction count anchored a running "18 → 17 →
…" chain across a dozen sessions, **was never committed and is gone.** Recreated from the
umbrella's own prose description, the recreation is **measurably a different program** —
a 21-instruction loop where the log's last recorded figure was 17.

> **Deltas survive a recreation; absolute counts do not.**

So the chain **stops at slice 9** and was marked stopped rather than silently extended
with an incomparable number — which would have been the easy move, since the new figure
still decreases. The recreation is now committed as `bench/w1_three_locals.pas` with that
history in its header, so the next slice **re-measures a file instead of re-deriving one
from prose**.

Generalises past benchmarks: any artefact a chain of results is keyed to — a fixture, a
corpus file, a seed input — is part of the result. If it is not in the repo, the numbers
are not comparable across the sessions that produced them, and nothing will say so.

### 148b — and I nearly retracked five tickets on a NAME, two ticks after banking 138

Mine. Five auto-filed regressions named `test-c-gtk*` sat at Track **P**, and the tick's
own new rule says to check auto-filed track guesses. The prefix reads as C; I was one
command from re-laning all five.

**The bounded fact refutes it: every one of those sources is a Pascal file.** The prefix
means *C-interop*, not *C-language* — they are Pascal programs binding gtk3 through
`gtk3_c.h`. The watcher's guess, made from the source extension, was **right**, and my
correction would have moved five p70 tickets into a queue whose owner cannot fix them.

Two ticks after banking *"retrack on a bounded argument, never on a story"* (138), the
story was simply wearing different clothes — a filename instead of a truncated log. **The
rule was not enough; running the check was.** One `ls` of the source paths, and it cost
nothing.

What the check *did* buy, once run for the right reason: all five share one red sha, one
last-good, and one 3-commit range holding exactly two code commits — **one defect wearing
five tickets**, now consolidated, with the confirming build named and not performed.

### 149 — A REGRESSION TEST WRITTEN WITH THE IDIOMATIC CHOICE WOULD HAVE BEEN GREEN ON A BROKEN COMPILER

*frankB, 2026-08-30, bisecting the typed-const generic regression.*

The attribution held at the exact commit. The finding underneath it is worth more:

```
TSolo<LongInt>  FAIL      TSolo<Boolean>  ok
TSolo<Int64>    FAIL      TSolo<Integer>  ok
TSolo<QWord>    FAIL      TSolo<Byte>     ok
TSolo<SmallInt> FAIL      TSolo<LongWord> ok
TSolo<Cardinal> FAIL
TSolo<TMyAlias> FAIL      (any user alias, whatever it aliases)
```

`tgeneric87` catches this only because it happens to use `LongInt`. **An author reaching
for the more idiomatic `Integer` would have written a passing test over a live defect** —
and would have had every reason to believe the bug was fixed.

So the fix must gate on the **failing set**, not on one name. And the split is itself a
hole in the mechanism story: **a harvest that keys on token shape has no business caring
whether the token is `Integer` or `Int64`.** That is not a quibble about test style; it
says the stated mechanism is incomplete, and the incompleteness would have been invisible
had the test used the common spelling.

Pairs with 146a from the other side. There the acceptance inherited the *ticket's* scope;
here it would inherit the **author's habit** — and habit is a narrower and less visible
filter than a ticket, because nothing records that a choice was made.

### 149a — a bracket is not an attribution

frankB built **`f12a62815` itself** as well as its parent, deliberately:

> *Parent-passes plus HEAD-fails is a 400-commit bracket, not an attribution.*

Parent clean + the commit itself red is a one-commit bisect with no neighbour, and it
upgrades pxx-a5's mechanism argument (145a) to mechanism **and** bisect — two supports
that do not share an upstream. Both conditions the coordinator named were required and
met: all three builds printed `converged after 2 round(s)` with shas differing from the
seed, which is the fresh-tree no-op trap closed rather than assumed. And HEAD's diagnostic
is character-for-character the one the ticket recorded, so the error path has not drifted
since filing — a check nobody asks for and which is what makes an old ticket's repro
trustworthy.

### 149b — ACCEPTED-AND-NEW can be un-accepted; ACCEPTED-AND-ALWAYS-WAS cannot

`d_poison` was **clean at the parent**. It is described in the ticket as the cost
`f12a62815` knowingly accepted — right about intent, and wrong about kind: it is a
behaviour change *that commit introduced*, not a pre-existing limitation being written
down.

The distinction decides scope. **A cost accepted when introducing a change can be
un-accepted by whoever fixes it; a limitation that always existed is somebody else's
ticket.** The word "accepted" flattens the two, and a reader in a hurry takes it as *out
of scope* — which is how a fixable defect acquires a permanent exemption from the
sentence that recorded it.

### 149c — and it STOPPED characterizing, on purpose

Two more boundary rows were recorded as **data, not as characterization**: the poison is
file-scoped and reaches **backwards** (a one-argument const on line 7 makes a
two-argument const on line 6 fail, reported at line 6, though line 6 does not match the
header shape), and the `=` is genuinely required (swap the poisoner for a `var` and it
compiles).

Then it stopped:

> *Past that point I would be doing P's diagnosis by enumeration rather than by reading
> the harvest code, and handing frankA a pattern I inferred from ten data points is
> exactly how a plausible-but-wrong root cause gets recorded.*

**Ten data points will always suggest a mechanism.** Labelling the rows explicitly as
not-a-mechanism is what stops the suggestion becoming the ticket's answer — 139 caught
after the fact; this is the same discipline applied *before*.

### 150 — A CHECKABLE OBLIGATION IS CHEAPER TO RECOVER, BUT IT IS NOT SELF-EXECUTING

*frankD, 2026-08-30, completing the obligation sweep — and correcting 137a, which was
mine.*

137a said an obligation needs *either a command that re-derives its status, or a named
owner*. **The counter-example was in the same directory.** `name-resolution.md` wrote down
its own acceptance test — *"those ten going back to their real names, with the `#define`s
deleted"* — in a form **one `grep` settles**. It went stale for two weeks anyway.

> **Nothing scheduled the grep.**

Corrected ordering, which is now the rule: **file a ticket** (the ranker re-reads; prose
does not) → else **name a lane and a trigger** → **add the command either way**, because
it makes the *audit* cheap even when it cannot make the discharge automatic. The command
is necessary and was never sufficient.

**Measured: 37 candidates, 4 real** — a better ratio than either of us expected. The four:
`autonomy.md`'s H1/H2 deferred to `claudecap`, **which is not reachable from this repo at
all** (not in `tools/`, not on `PATH`, one copy under `/data/borg-rescue/`, and that file
is the only mention), so the deferral is *permanent*; `track-b-workarounds.md`'s
"re-check each session", **addressed to every session and therefore owned by none**;
a `c-linking` optimisation idea with no ticket, invisible to the ranker; and a
"revisit later" with no done-criterion. The other 33 are prose *about* obligations or
hedges carrying their own escape. **`differential-probes.md`'s "pick an area nobody has
covered" is the healthy form** and was excluded deliberately: addressed to whoever is
reading, needs no state, cannot go stale.

### 150a — A STALE OBLIGATION IS PESSIMISTIC, AND PESSIMISM IS NEVER CONTRADICTED BY USE

The rarer failure was the unowned obligation. **The common one is the opposite**, and it
is where the corpus actually rots: five stale *restrictions*, all corrected in one day,
all wrong for weeks.

> **An over-tight rule costs its reader ten minutes and produces nothing wrong, so nobody
> files a bug about it. A doc claiming a capability it lacks fails the first time someone
> tries.**

That asymmetry selects for pessimism in every long-lived document — the optimistic errors
are removed by use and the pessimistic ones accumulate. It is 125 (*pessimism is the
direction nobody double-checks*) with the mechanism attached, and it is why both stale
rules found in `autonomy.md` were **tighter** than current policy: a full-suite Track A
gate the hook now denies outright, and a "land only green" guardrail superseded by the
`dev` collapse. **Being tighter than policy is what let them survive.**

Two more shapes worth the grep: **a heading is an assertion no ticket state can
contradict** (`eliah-m4-m5-prompt.md`'s `TODO` heading over five discharged items), and
**a directory embedded in a citation is a claim about state** — that file's citations were
stale in *both directions at once*, `(backlog)` and `unfinished/` for work that was done.

### 151 — A GUARD SUITE THAT AGREES WITH ITSELF PROVES THE MECHANISM IT SAMPLES, NOT THE BEHAVIOUR

*pxx-a5, 2026-08-30, fixing the shared-`TESTTMP` default.*

Its first cut passed **seven guards**, and it had verified each one **fails on the
condition it names** — the exact discipline this file has been pushing all night (*a
control is not a control until it has failed once*). **It was still wrong.**

Every one of those seven exercised `job_env()`. **None exercised `make_dry_run()`** — a
second `make` that passes no `env=` at all. `gate.sh quick` caught it in **30 seconds**,
RED, with a compile succeeding under the scratch path and the exec then failing to find
the binary.

> **Verified-to-fail is necessary and is not sufficient.**

This is 130 (*a guard built from the union of your cases is blind to their intersection*)
with the missing dimension named: **a suite can be adversarial on every axis it samples
and still sample one mechanism.** Each guard's negative control tests *that guard*; nothing
tests *the sampling*. And the sampling is invisible from inside the suite, because a suite
has no way to represent a call site it does not know about.

The cheap independent run is what closes it — a different instrument, not a better guard
(140a's second-support rule, arriving in test design). The repair generalises the same
way: setting `TESTTMP` on testmgr's own **process environment** covers all four `make`
call sites **and the next one nobody has written**, where an allowlist entry covers only
the ones enumerated today.

### 151a — the guard-comment was satisfied by the half that is EASY TO SEE

The prerequisite, marked done, was half landed — and the missing half was the failure it
was written to prevent. `chore-t-teach-testmgr-the-testtmp-value` taught the **matchers**
(`TMP_RE`, three `make_dry_run` expressions, `_REASON_TMP_RE`, `RUN_TMP` all derive from
`TESTTMP`). It did not teach the **producer**: `job_env()` is an allowlist and `TESTTMP`
was not on it, so setting the variable moved the matchers and was then stripped from the
environment of the `make` those matchers read.

```
parent TESTTMP=None       matchers=/tmp       make says=/tmp       AGREE
parent TESTTMP=<scratch>  matchers=<scratch>  make says=/tmp       NO
```

Precisely the state testmgr's own comment forbids — *"all four go blind AT ONCE and fail
silently."*

> **Reading a value shows up in a diff. Passing it on is a one-line absence in a list
> somewhere else.**

So the visible half gets done, the comment reads as satisfied, and **nothing fails while
both defaults are `/tmp` and agree by coincidence. The coincidence was load-bearing** —
the system was correct only because two independent things happened to hold the same
wrong value, and the first change to either exposed it. Same family as 33 and 130: absence
in a list is the quietest defect shape there is, because a list looks complete from any
angle except the one that enumerates what should be in it.

### 151b — an instrument error that produced a FALSE RED, and why that is the dangerous direction here

Recorded in the devtest's docstring rather than quietly fixed: the harness restored the
parent environment in a `finally`, **deleting the pin it was measuring**, so both new
guards went red **against a correct tree**.

> *Trusting that red would have meant "fixing" working code.*

Most instrument errors banked here produce false **greens** — quiet, and they wait. This is
the inverse and it is *actively* expensive: a false red recruits someone to change correct
code, and the change will be justified by a measurement. Writing it into the docstring
instead of silently repairing it is what stops the next person re-deriving the same red and
believing it.

### 151c — and the leftover was declined as a BATCH, correctly

Four recipe lines still name a literal `/tmp`. *"Convert the rest to `$(TESTTMP)`"* was
refused as a blanket follow-up because **at least two are pinned to a literal baked into a
compiled test SOURCE** — `rm -f /tmp/test_nilpy_sqlite_crud.db` must keep matching what the
`.npy` writes — so a sweep would **silently stop a cleanup rather than move it.**

Same shape as the 531-row refusal (132b): the blanket edit is wrong on exactly the members
whose correctness is load-bearing, and its failure is silent. **Dispatch it as per-line
work, not a batch** — which is now recorded on the ticket rather than left as a tempting
one-liner for whoever reads it next.

### 152 — A GATE IS THE ONE KIND OF CLAIM THAT IS ALMOST ALWAYS PESSIMISTIC, SO GATE DOCS ROT UNIFORMLY

*frankD, 2026-08-30, closing a 41-of-42 sweep of the live docs.*

**150a was stated and then confirmed on a fresh set within the hour**, which almost never
happens here and is the strongest thing that can be said for a rule. It predicted:
*an over-tight rule costs its reader ten minutes and produces nothing wrong, so nobody
files a bug about it.* The closing sweep then found **six stale gates**, and **every one
is tighter than the rule that replaced it.** None had ever been reported.

The mechanism, now specific: **a gate is a claim about what you must do before you are
allowed to proceed, so its errors are almost always in the pessimistic direction** — and
pessimism is never contradicted by use. That is why the *gate* docs rotted uniformly
(`parallel-tracks`, `autonomy`, `fpc-optional-workflow`, `debugging-tips`,
`ir-as-substrate`, `optimization-architecture`) while the *principle* docs came back
clean. Not a coincidence and not six separate lapses: one selection pressure acting on one
category.

**And the worst copy sat where readership is highest.** `parallel-tracks.md` said, in
bold, *"the **authoritative gate is unchanged**: [the full suite] + self-host fixedpoint.
A feature is not 'done' until it passes that"* — while CLAUDE.md names that file directly
and tells every agent to **read it before starting your track**. So the first thing a new
agent read about gating asserted as authoritative a command the hook now **denies
outright**. Its pin recipe also led with plain `stabilize` (~25 min, repo lock held) where
`stabilize-fast` (~35s) is the default.

**High readership preserved the error rather than exposing it**, and that is the part
worth carrying: everyone obeyed, obedience cost ten minutes and a denial, and neither
produces the failure that would make someone check. The docs most likely to be stale are
the ones most likely to be read.

### 152a — and TIDYING the stale gate language would have DELETED the only check that catches a real hole

The near-miss inside the fix, and the reason two files were **reframed rather than
corrected**. `optimization-architecture.md`'s "per-pass rhythm (never skip a step)" names
denied targets — and its **step 3 closes a hole nothing else does**:

`make compiler/pascal26` builds `compiler.pas` at the **default** `-O` level, so the
ordinary fixedpoint proves self-compilation at **one** level. A `-O0`-only self-compile
failure **passed the entire gate on 2026-08-19** and was found by a benchmark.

> **Deleting that step to tidy the gate language would have removed the only check that
> catches it.**

A cleanup pass aimed at *stale text* is aimed at a property of the words, and it cannot
see which of them is load-bearing. Same shape as 142c's over-broad landmine, inverted:
there an overclaiming caveat cost designs not taken; here an under-considered *deletion*
would have cost a live guard — and both are invisible afterwards, because a removed check
leaves no artefact either.

`fpc-optional-workflow.md` got the same treatment for the same reason: its subject —
which checks need a system FPC — is still exactly true, so it became a description of what
the targets *contain* rather than instructions to run them. **When only the framing has
rotted, reframe; correcting the content would have been the error.**

### 152b — and the auditor declined the one file it was best placed to audit

`session-roster.md` was the 42nd, and the reason given was *"auditing it would be
auditing you."*

**That reason is exactly backwards, and it is worth stating because the instinct is a good
one pointed the wrong way.** The coordinator is the one seat whose context is guaranteed
not to persist across the work it coordinates — so the roster is precisely the artefact
carrying what the seat cannot, and its author is *the worst available auditor of it*: it
was written by a session that no longer exists, and re-read by sessions that assume it.
18,339 lines, 1.1 MB, 209 sections, rewritten continuously by design.

**Deference to the party who cannot check their own work removes the only check
available.** By 150a it should be among the most rotted files in the tree, and by 152 the
same readership argument applies — every tick reads it, and reading is what preserves an
error rather than exposing it.

### 153 — WHEN A CONSTRUCT HAS N SYNTACTIC ROADS, FIXING ONE ROAD AND TESTING ONE ROAD IS INDISTINGUISHABLE FROM FINISHING

*frankwasm, 2026-08-30, `list.sort(key=…, reverse=…)`.*

The first fix wired the callable coercion into the argument loop it had found. A **local**
receiver worked. A **field** receiver worked. `nested[0].sort(key=f)` still segfaulted —
same construct, different loop. **NilPy method calls have SEVEN arity-driven argument
loops** (local, field, indexed, dynamic, star-unpack, collect, class-method), spread
across files two other tracks own.

> **Not a partial feature that answers *wrong*, but one that answers *right* often enough
> to look finished.**

That is the third name for the decorator failure (135a) and the most dangerous of the
three, because the demo passes. It is 146a with the scope moved again: there the acceptance
inherited the *ticket's* scope, then the *author's habit* (149), and here the *road they
happened to walk*. **A receiver/shape matrix is the cheap defence — not more careful
reading.** The seven loops were only found because a probe on each candidate site came back
**silent**, forcing instrumentation of `PyKwArgIndex` itself to find who actually called it.

**And the fix was PLACEMENT, not more code.** All seven funnel through `PyBindKwArgs`, so
the coercion goes there, after its reorder: one site, every loop — and no Track A or P file
touched, which is also how a Track N ticket avoided needing a grant on `pasparser_lval.inc`.
`root-cause-over-microfix` paying out twice: fewer cases *and* fewer lanes.

Standing note for every lane touching NilPy method calls: **seven argument loops, one choke
point, `PyBindKwArgs`.**

### 153a — A TICKET WHOSE BLOCKER IS "X CANNOT REACH Y" AGES BADLY, BECAUSE THE REPO KEEPS ADDING BRIDGES

The queue-wide half, which the worker correctly said it could observe and not act on.

The ticket was priced by its own last pass as *"needs a new pyeval routine plus a frontend
dispatch table that does not exist yet."* Actual cost: **one parameter, one extracted
helper, one call site.** The overpricing came from a blocker **dissolved by unrelated work
eleven days earlier** — `pyeval` installs `PyCallKey1` into `PyIterCallHook` precisely to
invert that dependency, because map/filter cursors in pylib had the identical problem — and
nobody re-read it.

**Distinguish the two blocker kinds, because they age in opposite directions:**

| stated blocker | ages |
| --- | --- |
| *"feature F is missing"* | **well** — F is still missing until someone builds it |
| *"X cannot reach Y"* / *"there is no mechanism that…"* | **badly** — it is a claim about the shape of the code, and the shape changes under it |

An architectural cannot-reach is a **false limit** (rule 2's third corollary) with a
delayed fuse: true when written, quietly false later, and *never re-checked because it
reads as structural rather than contingent.* Worse, it prices the ticket — so the queue
carries an inflated estimate that keeps it un-dispatched, which is the mechanism by which
it stays un-re-read.

**Measured 2026-08-30, ranked tickets (`urgent`/`backlog`/`backlog_new`/`unfinished`):
16 state an architectural cannot-reach.** Some are noise — the pattern also matches prose
*about* unreachability, this file included — but the shape it is looking for is real, and
the two oldest at p65 are both Track N (`feature-nilpy-thirdparty-libraries-as-targets`,
12 days; `feature-nilpy-cpyext-c-api-from-source`, 3 weeks), in the lane that has been
adding bridges fastest. **Dispatched as a re-measure rather than filed as a sweep** — one
lane, two tickets, evidence before a broader pass (134a: the check you were about to build
may be a fix, and 16 is not yet a population).

The third blocker, incidentally, was one **neither** earlier pass had: the frontend never
coerced the callable into the raw `Pointer` the slot wants, and a callable value is a
16-byte variant whose first word is the **tag**, taken as a code address. `sorted()` was
immune only because the plain-call path had that coercion inline — so **the working sibling
was working for an accidental reason**, which is why it could not serve as the model.
Moving the sort to `pyeval` as the ticket directed would not have prevented one row of it.

### 154 — A CONTROL DRAWN FROM THE SAME IDEA AS THE GUARD TESTS THE IDEA, NOT THE CODE

*frankA, 2026-08-30, on a guard of its own that reached origin and widened the bug it fixed.*

The guard asked *"is this group followed by `=`, and NOT preceded by `:`?"* — the `:`
meant to spare a typed constant. **It spares exactly one spelling of one.**
`const P: ^specialize TTest<LongInt> = Nil` is also a use, is also followed by `=`, and is
preceded by **`specialize`**. So the guard fired on it and killed the rewrite: the failure
went from *a handful of type names* to **every type name**, and sat on origin for about an
hour.

And the author **had** tested typed constants when writing it — with
`cb: TBox<Integer> = (V: 7)`, *the one spelling its own blacklist already handled*.

> **My control passed against a compiler I had just broken.**

This is 151 with a sharper edge. There a suite sampled one mechanism; here **the control
was derived from the same mental model as the fix**, so it could only ever confirm the
model. A control has to come from somewhere the design did not — a second author's table,
an oracle, a shape the implementer did not think of. It was caught only by running
**frankB's** trap table and getting FAIL on all six rows where frankB had four passing:
**a discrepancy with someone else's data, which is exactly what a control drawn from your
own idea cannot produce.**

The repair also stops enumerating: a declaration's left-hand side can only follow the
`type` keyword or the `;` ending the previous declaration, so it is a **whitelist** now.
*Enumerating the ways a use can be spelled is unbounded; enumerating where a declaration
can begin is not.*

### 154a — and the unexplained half was solved, PREDICTIVELY

The open question was why a harvest keying on token *shape* cared whether the token said
`Integer` or `Int64`. **It does not. It cares whether the token is an IDENTIFIER.**

The collector records only `tkIdent`. The lexer gives dedicated token kinds to exactly ten
spellings — `boolean`, `byte`, `char`, `double`, `extended`, `integer`, `longword`, `real`,
`single`, `string`. **Every other type name** — `longint`, `cardinal`, `int64`, `qword`,
`smallint`, `word`, `shortint`, and every user alias whatever it aliases — stays `tkIdent`,
is harvested as a bound name, and poisons.

**That reproduces frankB's observed table and then makes predictions frankB had not run:**
`Word` and `ShortInt` must fail; `Char`, `Double`, `Single` must pass. **Measured 8 of 8**,
including all four previously recorded as ok.

**An explanation that only fits the data you already have is a story; one that predicts
rows you have not measured is a mechanism.** So the fix's boundary is now *knowable* — it
is "which names lex as identifiers", not "which names are aliases", which was the first
guess and was wrong. It also dissolves frankB's backwards-reaching row with no new
mechanism: the harvest is a whole-file pre-pass into one flat unscoped array rebuilt each
call, so a const on line 7 is in the set before line 6 is rewritten — flagged as
data-consistent rather than proven, which is the right weight.

### 155 — I PICKED THE CORPUS FROM THE LANGUAGE I WAS EDITING, NOT FROM THE PATHS THAT REACH THE CODE

*frankC, 2026-08-30, reverting `eefa85d70` after it took five gtk tests red.*

37 named C tests byte-identical, self-host fixedpoint, `gate.sh quick` — all green.
**Not one of them is a Pascal program binding a C header.**

> *I chose the differential population by grepping C sources for string content and node
> shapes; the affected population was `.pas` files, so my instrument could not have seen it
> however many cells I added.*

That is "a green is silent on every defect the two arms share" one level out, and the rule
is cheap to apply: **select the corpus by the PATHS that reach the code you changed, not
by the language you are writing it in.** A C-frontend change exercised only by C programs
is a gate that cannot fail for the reason you most need it to.

**And the actual divergence was not where either of us guessed.** Not "a Pascal binding
reaches the importer by a different route" — **the header walk is not entered only by the
user's `uses <header>`: crtl's own modules flow through it.** `uses gtk` pulls `gtk.h`
pulls `stdlib.h`, which brings `lib/crtl/src/stdlib.c` into the same token buffer and the
same single-pass walk, which never reserves file-scope `static` variables (every
declaration goes to `ParseCSubroutine`, never `ParseCGlobalVarDecl`). Harmless **for
exactly as long as the bodies were being thrown away.**

### 155a — TWO deeper dependencies on TWO successive patches is a scope signal, not a patch signal

Patch 1 fixed the unreserved statics. The body then needed `__pxx_open`, a pxx-internal
runtime symbol the crtl two-pass supplies and the header walk does not. **It reverted
rather than patching a third time.**

> *I was one attempt into "microfix as a consolation" before I stopped.*

**The count of successive deeper dependencies is the measurement.** One is a bug; two in a
row says the boundary is wrong, and each patch makes the next one feel more justified
because you are closer. Naming the threshold — and admitting the second patch was already
one too many — is what makes it repeatable rather than a matter of taste. The reopened
ticket carries the diagnosis, the options, and the test material, and the next attempt
scopes by token **provenance** (`CModuleOfTok`) rather than by mode.

### 156 — SOMETIMES THE BLOCK *IS* THE SAFETY PROPERTY

*frankS, 2026-08-30, landing the xtensa syscall table.*

The inverse of *a missing op hides every bug in the programs it stops from compiling* — and
the more dangerous direction, because the remedy looks obviously safe.

Filling in the scheduler's six syscall numbers is a two-line change anyone would wave
through. It would replace **six honest compile errors** with **six programs that build and
jump into a `CoSwitch` that was never emitted for xtensa, from a stack primed with the
x86-64 frame layout** (`SpawnSized`'s `{$else}` chain falls through to x86-64).
**The compile error was the only thing preventing that.**

> **On finding a hole in a table, the move is not "fill the table". It is: fill it, then
> ask PER ROW whether the error was CONCEALING a defect or PREVENTING one.**

The measured numbers went into the Track A ticket precisely so nobody fills them in without
the `CoSwitch`. Note the shape — this is a **documented trap becoming a guard** only
because the person who found it wrote down *why* the obvious fix is unsafe, where the
table itself says nothing.

**And the headline is the same lesson:** 14 syscall rows bought **one** green row, not
fourteen. MATCH 96 → 97, CFAIL 25 → 23. **The other twelve did not stay one problem — they
became five distinct filed defects that no ticket could have named that morning**, including
a call0 displacement ceiling of ±512 KiB that caps the *whole corpus* (a riscv32 test is
758 KiB), not five odd tests. *A blocked population is not a homogeneous population.*

### 156a — GREP THE SIBLING, and the sibling was silently wrong

The `Double` typed const that misaligns the **next** const array: measured by **printing
addresses from the program** rather than reading the emitter. `@ 3 (mod 8)` on xtensa,
**4 on arm32**, 0 on x86-64/i386/aarch64/riscv32.

**Four right, two wrong in the same direction by different amounts — and arm32 has the
defect silently, because two 4-byte loads never fault.** Fixing it in
`ir_codegen_xtensa.inc` would have left arm32 quietly emitting under-aligned constant
arrays. Filed as A at prio 55 because it is a **live silent under-alignment on arm32
today**.

**And it is NOT Track F.** The program that dies sums an array of `Int64` and contains no
float arithmetic: the `Double` is the **trigger**, the subject is a data-section cursor
ending on an odd byte, and the observable is a **crash**. *Rank the mechanism, never the
datatype* — mis-tagging this F is exactly how a real bug disappears.

### 156b — a define that names a SHAPE, read as a NUMBERING

`PalBackendVforkAndExec` hardcoded `93` in the `PAL_GENERIC_SYSCALLS` arm. **That define
names a calling SHAPE** (clone, dup3, direct sockets), **not a syscall numbering** — it was
correct only because the two arches sharing that shape also happen to share the asm-generic
table. **A coincidence doing load-bearing work**, exactly like 151a's two defaults agreeing
at `/tmp`.

On xtensa `93` is `socket`. So a child whose `execve` failed would **open a socket, fall
out of the `if pid = 0` block still being the child, and hand its caller pid 0 to read as
"I am the parent"** — a fork bomb wearing the costume of a failed exec. All four literals
replaced with a per-arch `SYS_exit`.

**The regression surface was PROVED, not argued:** a program that actually reaches
`PalBackendVforkAndExec`, built with `$(PXX_STABLE)` for all five existing targets before
and after, **sha256 matching on every one.** And the split was named rather than glossed —
the xtensa half necessarily used the HEAD compiler, because `pinned` predates two days of
xtensa work and cannot produce a working xtensa binary at all. **Stating which half could
not use the pin, and why, is what makes the other half's byte-identity meaningful.**

### 157 — A DEFERENCE CLAIM LOOKS LIKE A CHECK SOMEBODY ALREADY PERFORMED

*frankD, 2026-08-30, auditing `session-roster.md` — the 42nd file, and the one it had
declined on the grounds that auditing it would be auditing the coordinator (152b).*

The worst-placed stale rule in the tree was not in `parallel-tracks.md` after all. The
roster's Branches section said *"Since 2026-08-25 work happens on **`dev`**"*, with `master`
advanced by `git merge --no-ff dev` and a never-rebase rule. The owner retired `dev` on
2026-08-26 (`8b2a6bae6`). Two things make it worse than a wrong date:

**It sits under a heading reading "Branches — read CLAUDE.md, not this file."** A pointer
elsewhere reads as *vetted* — someone thought about the relationship between these two
documents and told you which wins. **It is the same costume as a cited line number**: an
artefact of diligence standing in for the diligence.

**And the rule did not merely go stale — it INVERTED, and its stated rationale inverted
with it.** Its own closing sentence: *"this line exists only so a coordinator reading the
roster first does not land work on master out of habit."* **A line written to stop a
coordinator reaching for `master` by habit now stops them reaching for the only branch
there is.** A rule that states its purpose is usually *more* trustworthy; here the purpose
statement is what makes the inversion convincing.

### 157a — A DISPATCH RECORD IS MEMORY; A SESSION LIST IS OBSERVATION

The finding with a live safety consequence, and it was aimed squarely at how this
coordinator works. The worktree paragraph tells you the sole-A question is answered **only**
by your dispatch record — *"not by the table above and not by `ListAgents`."*

That was correct when lane holders were invisible worktree agents. `.claude/worktrees/`
does not exist; `git worktree list` shows one entry; **every lane holder today is an
ordinary session in its own clone, named and visible to `ListAgents`.** So a correct rule
became **advice to ignore the one instrument that works.**

> **Prefer the list when they disagree.** A dispatch record is what I believed; a session
> list is what is true.

Which is 152b's argument arriving with teeth: the coordinator's memory does not survive its
own context, so a rule privileging that memory over live observation is precisely backwards
for this seat.

### 157b — "LIVE" IN A HEADING IS A WORD NO DATA CAN CONTRADICT

**Roles — LIVE, 2026-08-25: none of its five sessions exists.** `frank1-72`, `pxx-aa`,
`neo-4a`, `cA`, `frank2-99` — all gone. The **13** that do exist appear nowhere, and two of
them staff lanes the table never mentions.

**The heading is the defect, not the rows.** A who-holds-what table is stale between ticks
*by construction*, and that is fine, because `ListAgents` is authoritative and free. It is
`LIVE` that makes it a lie — the same shape as a `TODO` heading over five discharged
tickets (150a). **A word in a heading asserts a property the body can never update**, so
the body decays and the heading keeps vouching for it.

### 157c — the near-crisis CHECKED rather than relayed

`origin/dev` is **7 commits ahead of `master`** — the exact shape that gets relayed as an
emergency at 4 a.m. **Four minutes disproved it:** all five tickets those commits filed are
present on `master` by another path (three `backlog/`, one `done/`, one `unfinished/`, plus
one in `urgent/`), so only duplicates are stranded; the other two are watcher `tstate`
publishes.

*Verify a peer's report before relaying it* is a rule this file already carries. This is the
same rule applied to **your own alarming discovery**, which is harder, because the discovery
arrives with urgency attached and urgency is what suppresses the check.

### 157d — and the audit's DISCIPLINE is the reusable part

**135 of 142 changed lines are additive.** The 7 deletions are the retired-branch
instruction, **whose full text is quoted inside the correction that replaced it.** Nothing
about what a past session observed was altered.

Two judgements inside that are worth copying. The stale *Current assignments* section was
**bannered, not trimmed**, because the coordinator-error retrospectives inside it are the
durable part of the file — *never tell a stopping session to revert; a session that says it
should stop is not made safe by easier work; a standing prio ruling is not re-litigated by
finding another category the ticket also fits.* And the unverifiable-action-claim class was
**declined on principle**: it lives entirely in the tick records, and verifying it would
mean re-deriving events only the participants observed. **That is what records are for.**

### 158 — DISSOLVE THE FORK: BOUND THE OFFER AND THE DISTINCTION STOPS MATTERING

*pxx-a5, 2026-08-30, on a ticket that had escalated as an open question.*

The ticket escalated because **nothing in the stored data distinguishes a slow box from a
hung job on a first encounter.** That is true, and it reads as a decision someone must
make. The answer was to stop needing it:

> **One grant, then the class figure forever.**

The slow job passes at the raised budget and starts earning real metrics; the hung job is
killed at the second budget, the grant is spent, nothing grows. **Being wrong costs one
class-length run, once, named in the report both times.** The unanswerable question is
still unanswerable — it has simply been made not to matter.

**That is why it landed as work rather than a `decide-*`**, and it is a test worth applying
before every escalation: *is this a fork the human must choose between, or a fork I can
bound so both branches are affordable?* A bounded wrong answer is often cheaper than a
correct decision procedure — and far cheaper than the ticket sitting in Track U while the
queue behind it waits. Same family as 136: **change what the mechanism is allowed to cost,
rather than making it cleverer.**

Four leak points, each closed deliberately, and the third is the one that generalises:
only the **budget** comes from an unproven metric (so an unproven metric cannot reserve
memory); the **grant** is counted, not the timeout that prompted it (counting timeouts
spends the offer on the run that merely *discovered* the job was slow, so a job would go
from "no data" to "exhausted" without ever receiving one); **a timeout at a granted budget
records NO duration** — that number is the budget *we* chose, not something the job
revealed, *and recording it is exactly how 90s became 3522s*; and a pass clears the counter.

### 158a — the ticket's TITLE named the wrong set

*"a job that never passed"* is `n == 0`. The set that matters is **`n < METRICS_MIN_RUNS`** —
the set the main gate actually excludes. A job rescued by the grant passes once, reaches
`n = 1`, **is still below the gate, and falls into the identical trap one step later.**

**Scope to the set the mechanism excludes, not to the set the symptom named.** The title is
written from the first observed instance; the boundary is a property of the code. Sized
before writing rather than after: 2818 local metrics, 1 at `n=0` and **79 at `n=1`**, at
most 17 ever seeing a raised budget, and the raise is a ceiling only — it cannot turn a
passing job into a failing one. **The 79 is the whole argument**, and it was invisible from
the title.

### 158b — THE APPARATUS'S STATE IS A MEASUREMENT TOO

Third instrument error of one session, and now a pattern with a name. A chained shell ran a
negative control against a file **the previous control's restore had not replaced**, so it
reported the *previous* control's two failures while the guard actually under test stayed
green. Re-run with the file state asserted before and after the edit: exactly one red, the
right one.

The session's three instrument errors: **a `\t` in a BRE, a harness tidying away the thing
it measured (151b), and a stale file under a negative control.**

> **None were in the code under test. All three were caught only by re-measuring, never by
> reading.**

So the apparatus needs its own preconditions asserted — *state the file's contents before
and after the edit you are testing* — because a control suite silently inherits whatever
the previous control left behind, and a chained shell makes that invisible.

**And 151 was applied rather than merely recorded**, which is the part I most wanted to
see: 9 guards each verified against its own broken condition, then the observation that
they exercise `unproven_budget()` and the learn methods and **not the wiring in
`Manager.__init__`** — the same sampling gap as last time. So a **second instrument**:
inject a metric, run a real `testmgr --tier quick`, and watch it print the grant with live
numbers, pass the job, and leave the metric at `n=1` with the counter back to full.
**Success path observed, not modelled.** Restoring only the injected key — because the
run's other learning was real and discarding it would have been worse than the injection —
is the same care one level down.

### 159 — A FINDING WHOSE SUPPORTING NUMBER KEEPS CHANGING WHILE ITS DIRECTION HOLDS IS ONE NOBODY RE-CHECKS

*frank-optimize-b4, 2026-08-30, correcting the correction in face 148. **148's `23 : 7` is
wrong; the number is `22 : 6`.***

Three counts of the same quantity, three wrong answers, **every one of them the
instrument**:

| count | what it got wrong |
| --- | --- |
| **15 : 4** | missed a spelling — `grep -c 'OptLevel >= 3'` cannot see `if OptLevel < 3 then Exit;` |
| **23 : 7** | counted **comments** — a raw grep counts prose |
| **22 : 6** | the first that needs no asterisk |

Both files carry exactly one continuation line *inside* a `{ }` block mentioning a gate in
passing — `ir_codegen.inc:4434`, `ir_codegen_aarch64.inc:1280` — and **neither starts with
a comment marker**, so no per-line filter removes them.

**And the sibling ticket's original figure already carried the footnote "(a 5th match is
prose)". The footnote was the defect, read as a footnote.** A caveat attached to a number
does not protect the number; it documents that someone once knew better, and then travels
with it as decoration.

> **The conclusion never moved through any of it — and that is the danger, not the
> reassurance.**

x86-64 far ahead of aarch64 was true at 15:4, at 23:7 and at 22:6, so every re-count
*confirmed the direction* and nobody had a reason to distrust the arithmetic. **A number
that keeps being wrong in a way that never changes the conclusion is a number that will
never be audited** — its only consumer is a claim it cannot falsify. This is 129 (*the
smaller number is the one nobody questions*) generalised: **it is not smallness that
protects a number, it is irrelevance to the argument it decorates.**

The repair is the right one: the checker now comment-strips for real, and `--census` prints
every match with file and line, **so the fourth number is checkable by a reader instead of
trusted.**

### 159a — `lib/**` IS A BUILD INPUT TO THE COMPILER, so "compiler/ is clean" does not mean the binary held still

Slice 10's published shas do not reproduce at HEAD. `1055347eb44a` / `c8303ca1f5b2` were
taken **before `sync.sh` rebased**; `de276c8f5` (xtensa) and `d2a61a524`
(`lib/rtl/math.pas`, `bignum.pas`) landed underneath. **`compiler/` was untouched by both
and the binary still moved — because the compiler links the RTL.**

Re-measured at landed HEAD: baseline `1bca19929e04`, new `46ff97f32ed7`, **deltas
byte-for-byte identical** (−2 / −10 / −6, all lower levels byte-identical).

**That is exactly what a HEAD-minus-only-this-hunk baseline buys: the delta survived a
changed tree; the absolute shas did not.** Second time this campaign has quoted a sha the
rebase invalidated, which puts it beside 148a as one rule in two costumes —
**an absolute number is only as portable as the tree it was taken on.** Operationally:
**re-measure after the push, not before**, because `sync.sh` rebases nearly every sync here
and the sha you cite pre-push exists only in your reflog.

### 159b — and the checker was DECLARED, not just landed

It added a step to `tools/gate.sh` — **not in its file-lane, and not obviously anyone's**:
the pin gate every lane runs. One additive `step` line plus a comment, no change to existing
steps, `bash -n` clean, quick gate green before it, and it **said so and offered to move
it.**

That is the right handling, and the coordinator's answer is that it stays: `tools/gate.sh`
is shared tooling rather than the owner's permission machinery, a checker nothing runs is
face 33, and **the alternative to landing it in the gate was landing it nowhere.** The
precedent worth recording is the *declaration*, not the placement — an unfiled change to a
shared gate reads as covered, exactly like an unfiled grant (operating rule 5).

Note what the check does **not** do: it does not forbid a one-armed slice — most
legitimately are — it forbids **one nobody noticed was one-armed.** Widening the delta is
now an edit to that file, in the same commit, in the diff, with both honest resolutions in
the failure message. Verified by breaking it three ways, including that a **prose mention**
of a gate does not fire it, which is the exact defect it was built to end.

### 160 — MAKE THE FAILURE OBSERVABLE RATHER THAN MERELY SURVIVABLE

*frankB, 2026-08-30, measuring the boundary of the const-array segfault — and disproving
its own routing note, which the coordinator had already relayed as fact.*

The trick that turned *"it segfaults"* into a table: **a callee that takes `@g` and never
dereferences does not crash.** The failing case becomes *observable* instead of only
survivable, and a crash with no information becomes a printable number:

```
standalone     @s          = 4301824   const arg addr = 4302184
record field   @r.a        = 4301856   const arg addr = 4302224
rec-in-array   @q[0].a     = 4302080   const arg addr = 4302264
array row      @p[0]       = 4301888   const arg addr = 0    <-- NULL
row via record @r2.rows[0] = 4301984   const arg addr = 0    <-- NULL
```

**NULL, not a wrong address** — and `@p[0]` is *correct at the call site*, so the value is
lost between there and the callee. That also explains the coordinator's own observation that
it faults on the first element access: **the parameter is 0 on entry, so the extent was
never the question.**

Generalises past this bug: when a defect's only symptom is a crash, look for a way to
**reach the same code path without the dereference that kills you**. A crash reports one
bit; the same path instrumented reports the value. The whole boundary table exists because
of that one change of probe.

### 160a — the routing note was wrong on BOTH axes, and the coordinator had relayed it

The note said: *`var` on the identical row works, so it points at the **const**-aggregate
argument path rather than at address-of for aggregate members generally.* **Both halves are
false**, and it was narrower than the truth on one axis and wider on the other:

- **It is not `const`.** By-value and open-array arguments fail too. **`var` and `out` are
  the only modes that pass — and they are the two that MUST hand over an address.** *Every
  mode free to form a copy fails.*
- **It is not aggregate members.** A record field works in every mode, **and so does a
  record field inside an array element** — `q[0].a`, an array subscript in the access path,
  an aggregate member, passed `const`, **green**. What matters is that the **final step
  yields an array-typed value by subscripting.** Irrelevant, all measured: element type,
  element count, literal vs variable subscript, and `array[0..2] of TG` vs
  `array[0..2, 0..3] of Int64`.

`q[0].a` is the control the note needed and did not have (146) — it has every property of
the failing set except the one that matters, and it passes.

**The coordinator relayed the note to frankA without a hedge**, having flagged it as
*"a claim, not a measurement"* when dispatching the test. **Stating a caveat to one
recipient does not attach it to the claim**; the claim travelled to a second lane stripped
of it, with the coordinator's authority added. That is operating rule 2 failing in the gap
between two messages rather than inside either one.

The note was **superseded in place, not deleted** — a boxed note saying what was wrong and
why it is kept. *A superseded guess is more useful visible than gone*, for the same reason a
landmine is rewritten rather than dropped (142c): it is what the next reader would otherwise
have re-derived and acted on.

### 160b — and a lead offered explicitly as NOT a claim

The same shape one level deeper fails at **compile** time with an untrue diagnostic:
`@b[0][0]` on a 3-level array is *"wrong number of array subscripts"*, while `b[0][0][1]`,
`@b[0]` and `@b[0][0][1]` are all fine. **Forming a reference to a partially-subscripted
array is the operation both get wrong, in two different ways.**

Two symptoms of one operation is a hypothesis, and it is labelled as one — *"I did not read
the lowering code, and the ticket says so"* — **which is also why the 3D row is absent from
the tables rather than silently omitted.** An unmeasured row left out without comment is
indistinguishable from a row that passed; saying why it is missing costs a sentence and
prevents exactly the 149-class error where the reader assumes the untested spelling behaves
like the tested one.

### 161 — I FIXED ONE ARM OF A DOUBLE CASE AND CLOSED THE TICKET WITHOUT GREPPING FOR THE SIBLING

*frankS, 2026-08-30, reporting its own miss from four hours earlier — unprompted.*

`in` is reachable through **two shapes**. `x in someSetVar` is an `IR_BINOP` with a `tkIn`
arm — implemented, measured green, ticket closed. **`x in [a, b, lo..hi]` with constant
items never becomes a set at all**: the parser emits a builtin call with
`procIdx = -SPECIAL_IN` and the backend compares and accumulates inline.

> *I fixed one arm of a double case and closed the ticket without grepping for the sibling,
> which is the one thing `normalise-dont-special-case.md` tells you to do before closing.
> The sibling was two programs away the whole time.*

That doc's rule is stated in one line — **if you fix a bug on one arm of a double case,
grep for the sibling before closing the ticket** — and it was still missed by a lane that
had spent the night finding exactly this shape in other people's code (156a's arm32
under-alignment, found by grepping the sibling). **Knowing the rule and applying it to
yourself are different acts**, and the second one has no external trigger: nothing fails,
the ticket closes green, and the sibling waits.

**What made it visible was classifying the tail rather than guessing at it.** All 23
remaining xtensa compile failures partitioned into seven named categories — 5 call0
displacement, 6 scheduler, 5 builtin-with-no-arm, 3 `SA_SIGINFO`, 2 by-design refusals, 1
`IR_SET_SIGNAL`, 1 non-scalar result. **A bucket you have counted is a bucket whose members
you have looked at**, which is the direct antidote to 144: an unspecific diagnostic merges
defects, and a forced partition un-merges them.

### 161a — AND THE FIX FOR A DOUBLE-CASE BUG MUST NOT ITSELF BE APPLIED TO ONE ARM

`SPECIAL_IN` is missing from **both** 32-bit backends. `ir_codegen.inc`, aarch64, arm32 and
i386 carry it; **riscv32 and xtensa do not**, confirmed failing on the same two programs on
each — measured on riscv32, not assumed.

The lane owns `ir_codegen_xtensa.inc` and not `ir_codegen_riscv32.inc`, so the obvious
correct move is: fix xtensa, file riscv32 as a Track A ticket with the arm32 model cited.
**That is the same defect one level up.** It leaves riscv32 as *"the next lane's
surprise"* — and the ticket being repaired exists precisely because one arm was left.

**So the grant was given rather than the work split.** A repair for a
fixed-on-one-arm-only bug that is itself applied to one arm is not a partial fix; it is the
bug, re-committed by someone who has just read the rule. The two 32-bit backends land the
rule together, by the lane holding the model.

**CORRECTED 2026-08-30, by frankS, measuring the thing I asserted.** I wrote that
riscv32's diagnostic is the generic *"standard builtin calls not supported in bare-metal
stage 1"* bucket and called it face 144 still live. **It is not an unspecific bucket: it
appends `(builtin id 999)`, so the subject IS named.** What is wrong with it is different
and smaller — the sentence promises a bare-metal stage that does not exist under a hosted
cross compile, i.e. a stale message, not an unidentifiable one. My claim came from the
category label in a classification table rather than from the emitted string; **I read the
bucket's name and reported the bucket's contents.** Left in place with the correction
attached, because the mis-citation of face 144 is itself a face-144 shape: I merged a stale
diagnostic into the unspecific-diagnostic bucket because both are "bad message".

### 162 — NINETEEN OF FIFTY CELLS PASSED BY ARITHMETIC, AND A PASS BY ARITHMETIC IS INDISTINGUISHABLE FROM A PASS BY CORRECTNESS

*frankB, 2026-08-30, `c01047d70` — measuring the typed-const alignment defect across ten
preceding shapes × five targets.*

The ticket said arm32 mis-aligns a typed-const array and named four other targets as
correct. The grid says **31 of 50 cells are misaligned**, residues 0/1/2/4/5/6, on every
target — x86-64 9, i386 9, aarch64 7, arm32 5, riscv32 1. With **nothing before it**:

```
const A: array[0..3] of Int64 = (1,2,3,4);   ->  mod 8 = 1 on x86-64, 4 on i386, 4 on arm32
```

No `Double` is required. No preceding declaration is required. **Nothing is the trigger** —
the typed-const data path does not align, ever.

**The nineteen passing cells are the finding.** `Int64 before` on arm32 gives residue 0 —
correct, and correct *by coincidence*: the preceding bytes happened to land right. Every
zero in the grid is that kind of zero. Four targets read as correct in the original ticket
for exactly this reason, and **a green produced by arithmetic accident carries the same
signature as a green produced by a working alignment path.** There is no field in the
observation that distinguishes them. This is the "host green is worse than a host red"
family at its sharpest: the red got the ticket, and the four greens got a per-backend theory
that sent the investigation to the wrong layer.

**The control is what localises it**, and it is the kind that earns its keep: `var V: array[0..3] of Int64`
is `mod 8 = 0` in **all fifty cells** — same element type, same size, same program, same
shapes, same targets. Same everything except typed-const versus `var`. So the var/BSS path
aligns correctly and the typed-const path does not align at all; the defect is shared
data-section accounting, not a backend arm. frankS called that early and understated it —
it is all six, not two.

**And the ticket's per-target table is not reproducible by construction.** Re-run at v393 on
the ticket's own five-line program: i386 4, riscv32 4, aarch64 4, **arm32 0** — three
"correct" targets misaligned and the "broken" one clean, with nothing changed but the
compiler binary. The offset is a function of everything emitted earlier, so any compiler or
RTL change shifts every number. **A fix must not be validated against those numbers**, and
that sentence is now in the ticket.

Not-Track-F stands harder than the ticket argued it: the array misaligns with **no `Double`
in the program at all**, so the mechanism has no float content whatsoever. And `sum of an
array of Int64` returned the right answer at residues 2, 4, 5 and 6 on every runnable
target — the silence on five targets is **hardware tolerance, not correctness**, which is
the same coincidence one level down.

### 162a — TWO LANES REPORTING DIFFERENT NUMBERS FOR ONE OBSERVABLE IS EVIDENCE ABOUT THE OBSERVABLE, NOT ABOUT EITHER LANE

*mine.* frankS and frankB reported different per-target alignment figures. I read that as a
discrepancy to resolve and routed a confirming build to settle which was right.

**Neither was wrong. The quantity is not stable enough to disagree about** — it is a
function of every byte emitted before it, so two lanes on two binaries *must* differ, and
the size of the difference says nothing about either measurement. The disagreement was
itself the datum, and it was pointing at the instability that dissolves the ticket's whole
table. I spent a dispatch determining which lane to believe when the answer was *the
question does not have a lane-shaped answer.*

The tell was available before the build: **the two reports differed on a quantity neither
lane had claimed was reproducible.** Before adjudicating between two peers, ask whether the
thing they differ about is one that *could* hold still. When it cannot, the correct
coordinator action is not a tiebreak — it is to stop treating the number as evidence, for
both of them at once.

### 162b — THE ABSENT CELL WAS LEFT VISIBLY ABSENT, AND THE ODD RESIDUE IS WHY THAT MATTERED

xtensa does not build in frankB's lane — the plain `writeln` probe hits `target xtensa:
external (dynamic)`, needing ESP platform flags it is not set up for. It said so rather
than quietly shipping a 50-cell grid that was really 40 plus assumptions.

That mattered immediately: **`mod 8 = 3` is the only odd residue anywhere in the corpus**,
it is frankS's, and **nothing in fifty cells reproduces an odd residue on any target.** So
it may be a *distinct additional effect* on that backend rather than the same defect worse —
untested either way. A grid that had silently absorbed xtensa would have buried the one
number that does not fit its own model, and a fix declared complete on the grid alone would
have left it live. **An anomaly is only visible against a background that admits it is
incomplete.**

### 163 — A STALENESS SCAN THAT KEYS ON CITATION DENSITY POINTS AT THE BUSIEST LANE

*frankwasm, 2026-08-30, triaging the first eleven STALE-PARK findings.*

I built a scan for parked tickets whose prose names a now-resolved ticket next to a
blocking phrase — the stale-resume-condition shape, after three lanes hit it in one night
from three different sides. Eleven findings over 35 parked tickets, and I dispatched an
agent at the **two loudest first**, because they named **six** and **four** resolved slugs
where the rest named one.

Both were `status: working` with an `owner:`, being actively edited by frankA while I read
them. **The slugs they cite are that lane's own landed fixes, cited by the notes recording
them.** A ticket that names six resolved tickets is usually a ticket whose author has been
resolving tickets.

**So the scan's signal strength was inverted.** Citation density tracks how much work a
lane has LANDED, which means the loudest findings systematically point at the busiest lane
— and at files nobody else may open. Ranking by strength of evidence sent me at exactly the
tickets where a second agent was least welcome, and it nearly put two agents in one file:
frankA had claimed it four minutes earlier, staged locally, **so the lock did not exist to
anyone else and I dispatched on the absence of evidence.**

frankwasm did not touch either one, on its own read, before my warning arrived. The
exclusion is now in the scan — `status: working` or a non-empty `owner:` — and 11 drops to
7 with better precision than the 11 implied.

### 163a — AND THE DISCRIMINATOR WAS NEVER "NAMES A RESOLVED SLUG"

frankwasm's real score, over the six it could open: **one dissolved, one mispriced, four
genuinely parked.** Not the 29% the raw count implied — because *most parked tickets citing
done work are citing their own history, which is what a ticket is for.*

The rule that actually separates them:

> **names a resolved slug as a PRECONDITION, in a sentence that has not been revised
> since.**

`feature-pascal-corpus-fpc-testsuite` names four resolved slugs and is completely fine — it
recorded its own unblocking on 2026-07-14, so the citation *is* the revision. The scan
cannot see that difference, and I do not think a scan can. Which sets the honest ceiling on
this instrument: **it produces a short list worth a human read, not a verdict** — and its
report says so rather than implying a finding.

### 163b — TWO CHECKS COMPOSE, SO DO NOT TEACH THE SECOND ONE TO WORK AROUND THE FIRST

After the exclusion landed, `feature-pascal-corpus-expansion` **still fired**. Its `working`
status is written in the ticket's **body** and not its frontmatter — which `check` already
reports separately as `STATUS-DRIFT`.

The tempting fix is to make STALE-PARK also read prose status. That is wrong: it would
silence the symptom of a defect the other check exists to report, and leave a ticket whose
header lies to every tool that reads headers. **The scanner reads the header; the drift
check says the header is wrong; fixing the header fixes both.** A scanner taught to route
around bad metadata removes the pressure that gets metadata fixed — and the ranker reads
frontmatter, so a header that lies is not a cosmetic problem.

### 164 — A NUMBER THAT IS TRUE ONLY UNDER A FLAG WILL BE QUOTED WITHOUT THE FLAG

*frankS, 2026-08-30, handing back the hosted-xtensa corpus — flagging its own headline
number, to the seat that was about to quote it.*

The result is **99 of 129 matching the oracle**, up from 69, with divergences 21 → 8. True,
measured at a named HEAD with a verified fixedpoint whose sha differs from `pinned`.

And it is true **under `--xtensa-soft-mulhigh`**, which **labels** the multiply divergence
rather than removing it — no qemu-xtensa core implements `MUL32HIGH`. So:

> *"99 of 129 match the oracle"* is true, and is **not** the same claim as *"xtensa is
> correct on 99 programs"*.

frankS's reason for telling me specifically: **I am where the number will be quoted from.**
The lane that measures a flag-qualified number knows the flag. The seat that relays it holds
a figure and a lane name, and the qualifier is the first thing a one-line summary drops —
which is CLAUDE.md's own claims-discipline warning (*"terse styles drop the qualifying words
first"*) arriving one layer out from the docs it was written about. Tonight frankD found
that exact warning had itself been tersely edited, losing the scope column. **The
compression failure reaches the warning about compression failures.**

Same structure as the two "byte-identical" claims the repo already separates: both strong,
strong for different reasons, and identical once shortened. The general rule this generalises
to: **a measurement taken under a flag must carry the flag into every restatement, and the
restatement most at risk is the coordinator's.**

### 164a — A FULL PARTITION IS A HANDBACK; A SUMMARY IS AN INVITATION TO RE-MEASURE

The handback names **every one of the 8 divergences and all 21 compile failures**, each with
a ticket or explicitly marked as needing one, at the bottom of the divergence ticket with a
pointer from the `test-xtensa` header — so a lane arriving cold hits it from either
direction. Not "the remaining failures are mostly X".

**A partition can be checked for completeness; a summary cannot.** 8 + 21 against a stated
129 either accounts for the corpus or does not, and the next holder can verify the handover
before trusting it. This is the antidote to face 144 applied to a *handover* rather than to a
diagnostic: an unspecific summary merges the remaining work into a bucket whose members
nobody has looked at, and the next lane re-derives the classification that already existed.

**Where I overturned it, and the reason is tonight's own evidence.** frankS left three
divergences unticketed on purpose — *"a ticket I do not work is worth less than a row
someone reads, and I would rather hand over an honest gap than four thin tickets that look
like coverage."* That rule is right, and it is wrong for the two that are **wrong-VALUE**
bugs, because **the ranker reads frontmatter and a prose row has no owner.** Three
independent instances of prose-declared state going unread landed tonight alone. The table
stays; the two wrong-value rows also got frontmatter. The third, which is a genuine gap
rather than a defect, stays a row.

### 165 — A HOLD ENFORCED BY A NUMBER IS ERASED BY THE NEXT BULK RE-PRICE

*mine, 2026-08-30, chasing the fourth instance of prose-the-ranker-cannot-see.*

On 2026-08-14 the user held `bug-nilpy-except-tuple-binder-is-typed-by-the-first-arm-only`:
*"maybe we do need another approach after all"* — do not build the join fix. The ticket
recorded it in prose and enforced it by **pricing down to 20 to keep it out of `next`.**

On 2026-08-25, a bulk re-triage — *"prio now spans 3-88, not a 25-45 blob"* — swept it to
**55**. It has ranked in `ready --track N` ever since. An N agent asking the board what to
do next would have been handed a ticket the user explicitly said not to start.

**Nobody overrode anybody.** A bulk re-price operates on frontmatter across hundreds of
tickets and cannot read a paragraph. The defect is that **the hold's only enforcement was
the number it set**, and a number is precisely what a re-triage rewrites — so the hold was
destroyed by an operation that had no way to know it existed, while looking like ordinary
triage in the diff.

**The mechanism that survives already existed and the hold had not used it.**
`_NODISPATCH_RE` matches `NOT DISPATCHABLE` / `do not claim`, prints `[!! DO NOT CLAIM]`,
and drops the ticket from `ready`/`next` **regardless of prio**. Grep for the incumbent
before inventing enforcement: the durable marker was one line away, and the author reached
for the number because the number is what `next` reads *today*.

Rule: **when the user says stop, record it with the marker, not with the price.**

### 165a — THE THING BEING SEARCHED FOR IS CONSUMED BEFORE IT CAN REACH THE THING BEING SEARCHED

*pxx-a5, same night, on the measurement it had itself named as decisive.*

Its own ticket said the one thing that would move the TESTTMP-collision prio off 50 was to
grep tstate for `Text file busy` / `: not found` against the 15 frozen names. It ran it over
1155 reports: 3, 0, and 1 — and none of them this race.

Then it found why the negative was worthless. `tools/testmgr.py:352`:

```
RUN_RETRY_SIGNATURES = ("Text file busy", "ETXTBSY")
```

**The harness already retries exactly this event and scores the job GREEN with `flaky` set.**
The signal is consumed upstream of the record being searched. And `twatch`, the publisher,
**never read the field** — `grep -n flaky tools/twatch.py` returned nothing, and not one of
1155 reports mentions a retry.

> **A suppression with no counter makes its own population unmeasurable.** Any "has this
> ever fired?" gets a confident NO from a record that could not have said otherwise.

That is the strongest form of the false-negative: not a search that missed, a search that
*could not have hit*. `flaky: N` now sits in the report **header** beside `skips:` — for the
same reason those are there, that a field appearing only when it has something to say cannot
report finding nothing.

**Second blind-spot proxy from the same lane in one night** (the first: counting `.expected`
siblings to find unwired tests, which could only see subjects that had one and would have
answered "three" for any true number). Both found by running the real instrument instead of
the stand-in.

And the relationship it surfaced is worth watching for on its own: `done/bug-t-etxtbsy-race-
reds-single-shot-selfhost-jobs` closed by **adding** that retry, leaving a source comment
saying *"Root cause belongs in the recipe (write under a temp name and rename into place)."*
**A closed ticket that names its own unfinished root cause in a code comment reads as done
from the board, and the comment is the only place the remainder lives.**

### 165b — AND THE CHECK I WAS BUILDING FOR 165 DID NOT EARN ITS PLACE

Having found four instances of prose the ranker cannot see, I measured a scan for the
general case: ranked tickets, no `blocked-by`, whose prose argues against being worked.
**14 hits, roughly 5 genuine.**

Two of the false positives are **mention-versus-use** — `bug-p-an-unknown-compiler-directive-
is-silently-ignored` and `bug-p-fatal-directive-is-silently-ignored` both matched on the
*quoted example string* `"this configuration is unsupported, do not build"`, which is the
thing they are about. That is the **third** independent instance of mention-versus-use
tonight, after frankD's `docsnip.py` expected-fail regex and frankC's census.

Several more matched prose describing the *work's* method (*"each needs a decision, which is
why this is not a scripted sweep"*) rather than a hold on the ticket. And `decide-` tickets
are *supposed* to say "I recommend against this" — that is their job.

So: **not built.** At ~35% precision it is below the bar NEAR-DUP was calibrated to, and a
check that cries wolf earns the habit of being scrolled past. The genuine hits were few
enough to fix by hand, which is 134a again — **the check you were about to build may be a
fix.** One of the five was live and is now repaired; that was the whole yield, and it did
not need an instrument.

### 166 — SECOND LANE, SAME NIGHT, SAME FILE, ONE HOUR APART: THE SIBLING WAS NOT GREPPED FOR

*frankA, 2026-08-30, hours after frankS banked face 161 for the identical mistake.*

`ParseGenericTemplateNamed` detects bodyless class forms up front — no `end` for its depth
loop to count down to — but its test looked at the token after `class` **without skipping
`abstract`/`sealed`**. So `class abstract;` read as *having* a body, the depth loop took it,
and it swallowed every following declaration until it hit somebody else's `end`.

> *I fixed the identical omission in `CollectNestedTypeNames`, in this same file, earlier
> tonight.*

**Face 161 was frankS. This is frankA. Different lanes, same night, and this one is two
functions apart in one file with an hour between them.** One instance is a lapse. Two
instances, by two agents who had each read `normalise-dont-special-case.md` and one of whom
had banked the rule *as a face* the same evening, is a statement about the rule: **"grep for
the sibling before closing" has no mechanical trigger, so it is applied exactly when
somebody happens to remember it.** Nothing fails. The first fix is green, the ticket closes,
and the second copy waits — here, as the corpus wall the lane spent the rest of the night on.

The cost is measurable in this case: the sibling *was* the wall. rtl-generics 4 errors → 1
(pinned was 20) once it was found.

### 166a — AND FIVE REDUCTIONS AIMED AT THE REPORTED LINE, BECAUSE THE REPORTED LINE WAS NEVER THE DEFECT

The trigger is `generics.collections.pas:144`. **The error comes out at line 120** — on
`function DoGetCurrent: T`, a line with nothing wrong with it, in a class that compiles
cleanly on its own.

So **five** reductions aimed at line 120's *text* failed to reproduce: four already recorded
in the ticket by earlier sessions, one written tonight. The ticket's own standing advice —
*"start by asking why `generics.defaults` parses cleanly alone"* — pointed at the symptom
and had been quietly costing every session that followed it.

What worked was ignoring the text entirely and **truncating at real declaration
boundaries**: `cut@125` clean, `cut@141` clean, `cut@144` fails. A swallowing bug reports at
wherever the swallow *ends*, which is unrelated to where it started, so the one field
everybody anchors on is the one field that carries no information.

Durable form, now leading the ticket: **do not trust any error line in this unit without a
truncation bisect.** The reported line has been wrong twice.

Both obvious suspects were ruled out **by measurement before touching anything** — `p.dgen`
shows injections at 133/137/139/144/152 and **none** at 120 or 135; the harvest was
`names=293 cap=512 overflow=0`. Both would have made plausible stories.

### 166b — THE ORACLE CLAIM WAS ABOUT THE DRAFT, NOT THE PROGRAM

frankA's first regression test carried the control `TFwd<T> = class;` with the header line
*"Oracle: FPC prints the same line."* **FPC rejects it** — *"Type TFwd$1 is not completely
defined"*. pxx accepting it is the ordinary accept-more divergence and not a defect, so the
code was fine and **the header would have shipped a false oracle claim.**

Caught only by running FPC on the **finished file** rather than on the draft that had been
reasoned about. The control still earns its place — it is what isolates the modifier as the
variable — so it moved into the header table instead of the program.

A false oracle citation is the worst kind of stale claim available: it reads as *"someone
compared this against a reference implementation"*, which is precisely the check nobody
repeats.

### 167 — REDUCING A WALL MADE THE TRAP MORE ATTRACTIVE, NOT LESS

*frankA, 2026-08-30, after taking rtl-generics from 20 errors to 1.*

The last remaining error is `TCustomPointersCollection<T, PT> = object` — a generic **object**
type. `feature-p-legacy-value-object-types` [P p15] is `gated-by`
`decide-old-style-object-types`, **decided 2026-08-25, option A: we do not implement `object`
types**, on the principle that *a corpus is a measuring instrument, not a dependency.*

> **A one-error corpus is a much stronger invitation to that mistake than a twenty-error one
> was.**

Twenty errors reads as a campaign nobody finishes tonight. **One error reads as the last
mile** — and here the last mile is reversing a standing decision at prio 15 to make a
measuring instrument read zero. So the night's work *increased* the pressure toward the one
move the project has explicitly refused, and the person most likely to make it is whoever
next sees a nearly-clean corpus and wants to close it.

frankA also checked the thing that makes the refusal safe rather than assuming it: a plain
non-generic `type TObj = object F: Integer; end` fails identically (`Expected: begin, but got:
F`), so **pxx has no `object` type at all** and adding `tkObject` to the generic path buys
nothing. Without that check the wall looks like a narrow generic-path gap somebody could
reasonably just fix.

Written into the ticket **in the imperative, ahead of the temptation** — an explanation is
read after the urge, an instruction before it.

**And the polarity is the new part.** The stale-blocker family is *stale records making
finished work look open*. This is a **live record making a refused thing look like the last
mile** — worse, because nothing on the page is stale. Every fact is true.

### 168 — THE FORK DISSOLVES WHEN THE PROPOSED PROCEDURE CANNOT DELIVER THE CONFIDENCE IT IMPLIES

*pxx-a5, same night, on auto-close-on-one-green.* **Both of the ticket's own proposals
fail**, and establishing that was the decision it asked for.

*"Require N consecutive greens"* cannot work at any affordable N. At the measured ~12%
failure rate, **three greens still leave a 68% chance the bug is live** (0.88³); reaching 5%
needs about **24**. No sweep cadence pays that. **Absence of a failure is not evidence for a
race**, so the answer cannot be a bigger N — the procedure is not underpowered, it is
measuring the wrong thing.

*"Reuse `RUN_RETRY_CLASSES`"* would **not have caught the incident that produced the
ticket**: that set is {qemu, corpus, conformance, opt} — variance from the *environment*, not
a test's own concurrency — and `test_sched_reactor_exhaustion` classes **`unit`**, measured
through `classify()` rather than assumed. Kept as one arm because it is right about what it
covers; it is simply not the arm that matters.

**What discriminates was already in the record.** The stub is a **repeat**:
`stub_slug_for_filing()` opens `-2`/`-3` only when a resolved predecessor exists, so **the
suffix IS the structural record that this job went red, was closed, and came back.** No new
state, no tuning, no guessing at test semantics.

**The guard to copy:** its failure message states *why the obvious fix is insufficient*.
Remove the repeat arm and it says *"the reactor case is NOT covered: it classes `unit`, so
only the repeat arm can catch it, and that arm is gone."*

> **A ticket's own suggested shape is the thing most likely to be re-adopted later, so the
> guard that refutes it should say so in its own voice rather than just going red.**

A red teaches "something broke". A red that names the refuted proposal teaches why the
tempting fix was rejected — to a reader who does not have the ticket open, which is everyone
who will hit it.

### 168a — A CONTROL THAT DESTROYS ITS SUBJECT PROVES NOTHING, AND FAILS IN THE FLATTERING DIRECTION

Sixth instrument error from that lane in one night, recorded rather than quietly fixed. Its
negative control deleted a line **range** instead of an exact string, cut into the function,
and failed all six guards with `no attribute one_green_cannot_close`.

**Six of six red looks exactly like a working guard suite.** That is the whole danger: a
control that removes the subject reports maximum sensitivity, and the failure mode is
indistinguishable from success unless you read *why* each guard failed. Redone as an
exact-string removal, syntax re-validated, sha checked on restore.

Companion fix, same instinct: `twatch` does not import `testmgr`, so `RETRY_CLASSES` is
duplicated — the copy is now **checked against the original** rather than left to a comment,
because *"keep these in sync"* is the shape this fleet has been finding all night.

### 169 — A MIS-SCOPED GRANT IS UNDETECTABLE FROM THE GRANTEE'S SIDE, AND AUDIT-ONLY IS WHAT MADE IT A NULLITY

*frankD, 2026-08-30, after I corrected a grant of mine that named the wrong tree.*

I granted `devdocs/dev/*.md`. The work was in `devdocs/developer/` — **two different trees**,
53 and 58 top-level pages. frankD swept the second, edited nothing, and filed a ticket.

**Neither of us could have caught it from inside the task**, and frankD's diagnosis of why is
the part worth keeping:

> the error was invisible from my side precisely because the instruction and my reading
> agreed on **intent** and differed only on **extension**. The words *"internal reference
> docs"* fit both trees, and nothing in the task would have felt wrong if I'd swept either.

That is the failure mode a scope check cannot cover, because there is nothing to check
*against*: the grantee is not verifying a path, they are executing an intent they share with
the grantor. A wrong extension of a right intent produces no friction anywhere.

**And the consequence is the finding:**

> it was harmless only because the sweep was audit-only. Had the grant carried edit rights, a
> scope that names the wrong tree is **a licence to edit files nobody authorised**, and I'd
> have had no way to detect it.

**AMENDED by frankD, and its version generalises one step further than mine.** I framed
read-only-by-default as protection against *the grantor's scope being wrong*. It equally
protects the case where the scope is right and **the grantee's reading is wrong** — same
shape, roles swapped, no extra mechanism. Both are invisible for the identical reason:
shared intent produces no friction at the point of divergence. So the rule is not about who
is likelier to err:

> **intent is not checkable and extension is, so the default should be the posture where
> extension gets named out loud.**

The four-paths-in-a-table amendment already does exactly that; "the grantor is likelier to
be wrong" is one instance of the rule rather than its reason.

**So audit-only earned its keep for a reason neither of us picked it for.** It was chosen to
keep a docs lane out of code; what it actually did was **convert a mis-scoped grant from an
incident into a nullity.** Generalises: the default posture of a grant should be read-only
not because the grantee is untrusted, but because *the grantor's scope is the thing most
likely to be wrong and the least likely to be checked.* Edit rights should be named per file,
which is how the amended grant ended up listing four paths in a table.

### 169a — A SILENTLY CORRECTED PAGE IS INDISTINGUISHABLE FROM A PAGE THAT WAS ALWAYS RIGHT

Each of the four repaired pages carries a dated `Superseded 2026-08-30` note saying **what the
instruction used to be**, not merely the corrected text.

> in a tree where ~40 others are unclassified, that difference is the only signal available.

A tree of unknown freshness has no way to distinguish *checked and fixed* from *never looked
at* — both render as plausible current text. The dated note is the cheapest possible
classification, applied to the pages that happened to get attention, and it is the same
one-line move `plan-rtti-streaming-lfm.md` already demonstrates (*"Status (2026-05-31):
delivered. This document is retained as the design record."*).

**Two boundary calls in the same commit worth copying.** `threads-todo.md` was **annotated,
not cut**: items 2-4 stand and only item 1 moved, and *deleting item 1 would have destroyed
the information that the rest still stands.* Then, from writing it: item 1's substitute
—`make compiler/pascal26`— **is item 2**. The ladder did not need a new item, it needed to
notice it already contained one.

And `esp32-support.md` **kept** its `make test-esp-bare` sentence as a *description* of what
the target runs, dropping only the *prescription*. The 24-vs-4 scoping applied at line
granularity rather than page granularity: **the same command is a fact in one sentence and an
instruction in the next, and only the second kind is harmful.**

Premise verified before acting, not assumed from the report: the hook's rule 1 is
`make[[:space:]]+(...)*(test|check)([[:space:]]|$|-[a-z0-9-]+)`, so `test-esp-bare` matches on
the **trailing-hyphen branch**. Without that branch the fourth site would have been a
near-miss and the fix a report on a non-problem.

### 170 — A LIVE EDGE WHOSE JUSTIFICATION IS UNREACHABLE IN THE CURRENT COMPILER

*frankA, 2026-08-30 — the third polarity of tonight's dependency-record campaign.*

`compat-pascal-four-type-sizes-disagree-with-fpc` is filed `prio: 25` and shows **p70** at the
head of Track P. All of that comes from one edge: `feature-pascal-typed-and-untyped-files`
[P p70] declares `blocked-by` on it.

And that ticket's strongest argument for the sizes mattering is a **`file of TRec` round-trip
against FPC** — while **`file of T` does not exist**, refused outright with *"file types are
not supported (use TextFile for text I/O)"*. Which is what the blocking ticket is *for*. So
the two hold each other up: sizes rank high because typed files need them, and typed files
are the main reason sizes are worth fixing.

**Ruled: the edge stays.** Propagation is the designed behaviour — rate goals, the chain
follows — so the real question is whether typed files are correctly p70, and they are:
`file of T` is standard Pascal that real code uses heavily, which is the axis the compat
table says to rank on. And sequencing layout *before* committing to an on-disk format is
right, because settling sizes afterwards silently invalidates written data.

**The defect is that none of that is visible.** A reader opens the ticket, sees `prio: 25`
against a p70 ranking, and the obvious tidy-up is to make one number match the other — which
either drops it out of the queue or overstates its intrinsic worth. **An effective rank with
no stated source reads as a mistake**, and the repair is one paragraph naming the edge.

Not a stale edge (163a) and not a live record making a refusal look like the last mile (167),
but a **live, correct edge whose justification cannot be reached from the current compiler.**
Not circular reasoning — the sequencing is sound — but a circle a reader can walk without
finding ground.

**Found by the probe failing to compile.** frankA went to write the `file of TRec` round-trip,
`file of T` did not exist, and the probe uses `Move` for that reason. Measurement found the
gap; reasoning would have accepted the justification at face value.

Three probes cut against the author's own prior, all reported: `packed` **is** honoured
(offsets 0/4/8, `SizeOf` 12, exactly the sum — the subrange fields are simply 4 bytes wide,
the opposite of the assumption going in); the byte-exact layout **is** expressible today
(`packed record a: Byte; b: ShortInt; c: Byte` = 3, matching FPC); and `Move` round-trips
pxx's own bytes. So the cost is **memory footprint and cross-toolchain layout, not a wrong
answer** — neither the bug row nor the defer row, and `prio: 25` is right on its merits.

### 170a — "THREE LINES" PRICED THE CAPABILITY AND THE BINDING CONSTRAINT WAS THE LOCATION

*frankwasm, same night, disproving its own ticket's note.*

`decide-how-the-sys-intrinsics-reach-wasi` lists `tkArgStr` (ParamCount/ParamStr) under
**"What does NOT depend on this"**, at *"3 lines"*, marked **Not verified**.

**The capability half is true; the linkage half is false; the linkage half was always
binding.** `args_sizes_get`/`args_get` genuinely need no preopen and no rights — verified, an
implementation against them compiles. But "3 lines" assumed the code could live in the WASI
PAL, and it cannot, for two independently sufficient reasons, both measured:

1. `compiler.pas` links **no PAL at all** — `uses SysUtils, Math, BaseUnix`, and nothing in
   that chain reaches `platform.pas`.
2. Even with an explicit `uses platform`, **a PAL routine nothing calls is dead-code
   eliminated before the backend can ask for it.** Confirmed against `strings` on the module:
   `PalBackendPlatform` and `PalBackendHasFiles` are present because `platform.pas` calls
   them. **A routine whose only caller is a call the backend synthesises later has no Pascal
   caller when DCE runs.**

So the code is removed by a pass that is *correct*, for a reason the estimate had no way to
anticipate, and writing the three lines would never have worked. **An effort estimate prices
the work; it does not price the place the work has to live** — and the place was the whole
problem.

163a from the inside: *"X may be independent"* is a shape claim about our own code, written
once, never re-read — here on the author's own ticket, which is the hardest place to notice
one.

**And the half that worked was declined.** A *frozen*-only `ParamStr` would have cleared all
4 refusals today (all three anchor sites are frozen), but `s := ParamStr(i)` with `s: string`
is the common spelling, takes the managed path, needs a strlen, and this backend has **no
hand-emitted loop anywhere**. So it **works in the program we measure and refuses in the
program a user writes** — the decorator failure wearing a fourth name. The no-loop shortcut
(`argv[i+1]-argv[i]-1`), which every host satisfies and preview1 does not specify, is recorded
**REJECTED** so the next reader does not adopt it as a clever find.

### 171 — THE CONVENTION WAS ALREADY WRITTEN, IN THE OUTPUT OF THE TOOL THAT WOULD HAVE CAUGHT IT

*frankwasm, 2026-08-30, reading `check`'s own closing NOTE after violating it.*

Five instances of prose-the-ranker-cannot-see landed tonight across five lanes. `check`
already prints, on every run including a clean one:

> *"prose stating a blocking relationship must also carry the frontmatter edge, and the
> commit that closes a blocker marks its dependents' prose."*

**So this is not an unknown failure class. It is a documented convention with no
enforcement**, and every one of tonight's instances is a violation of a rule already written
down — in the output of the tool that would have caught them if it had been checkable.

That reframes the whole campaign: **not a new check, but making an existing convention
checkable.** Which is a much smaller and better-specified job, and it is the same shape as
`a documented trap is not a guard`, one level up: here the trap, the rule, and the tool that
prints the rule were all present, and the only missing piece was enforcement.

### 171a — AND `working/` WAS OUTSIDE BOTH APERTURES, WHICH IS WHERE THE LONGEST-LIVED ONE SAT

frankwasm's own ticket had been in `working/` for two days with a dependency stated in prose,
in a plan file, on a side branch — and *"that is precisely why nothing caught it."*
`STALE-PARK` scanned `unfinished/` and `blocked/`; the stale-edge scan reads frontmatter.
**Neither aperture contained an active lock.**

I had excluded held tickets **deliberately**, and for a good reason that was about the wrong
verb: the scan's two loudest hits were tickets a lane was actively editing, and dispatching a
second agent at them nearly put two agents in one file (163). That reason is about
**dispatch**. Applied to **reporting** it was wrong, and it excluded exactly the population
where the defect lives longest:

> **A long-lived lock is not evidence a ticket is healthy. It is where a stale prose
> dependency hides longest, because the holder wrote the park and has stopped re-reading
> it.**

Fixed by splitting the verb rather than the aperture: `working/` is now scanned, and
everything held reports as `STALE-PARK-HELD` — *tell the holder, never claim it*. Both
properties kept. It immediately surfaced one that had been invisible.

**The general form: an exclusion justified by one consumer's needs silently applies to every
consumer.** "Do not send an agent here" and "do not look here" are different instructions,
and a single `continue` cannot tell them apart.

### 172 — A COST THAT DOES NOT SCALE WITH THE THING YOU THINK CAUSES IT IS NOT THAT COST

*frank-optimize-b4, 2026-08-30, declining to write slice 8 for aarch64.*

| compare rows | 32-bit | 64-bit | delta |
| ---: | ---: | ---: | ---: |
| 3 | 130228 | 130220 | 8 |
| 9 | 130348 | 130340 | 8 |
| 27 | 130708 | 130700 | 8 |

**The delta is constant.** A narrow operand costs 8 bytes *once* — two `sxtw` at residency
init — and **zero per compare**. `cmp Wn, Wm` and `cmp Xn, Xm` are both one four-byte
instruction; what slice 8 actually bought on x86-64 was the **memory** form, since dropping
REX.W is what makes `cmp rNd, [rbp+d32]` legal — and **aarch64 has no memory operand for
`cmp` at all**, so the half that paid has nothing to port.

> A single measurement at 3 rows reads as *"8 bytes of slack, go get it"*. **Varying the row
> count is what turns it into proof.**

One data point cannot distinguish a fixed cost from a per-item one, and the per-item reading
is the one that justifies work. b4 measured despite already having the right answer by
reasoning — *"both are one instruction is right for the wrong reason often enough to check"*
— which is the same discipline that caught 162's coincidental greens.

**And the failure mode it avoided is specific:** a pass that fires and saves nothing would
have **closed the backend parity gap numerically while buying nothing.** The gate counts
passes, not bytes. That is number-versus-conclusion drift with a guard actively rewarding it.

### 172a — PORTING A PASS IS A SECOND READING OF IT, BY SOMEONE WHO MUST STATE ITS SHAPE IN ANOTHER LANGUAGE

Slice 10's aarch64 twin fused **both** flavours of leading widen (`sxtw x0, w0` signed,
`mov w0, w0` unsigned). On x86-64, slice 10 had fused the `cdqe` and **left `mov eax, eax`
alone** — a gap nobody had seen, found because writing the aarch64 helper with a two-valued
result forced the question. Filed as its own x86-64 ticket.

A port is not duplication; it is a re-derivation under different constraints, and the
constraints ask questions the original never had to answer.

### 172b — AND MY OWN ADVICE ABOUT THE CONTROL WAS WRONG

I told b4 to *"confirm it goes red against the baseline binary."* It cannot: the test is a
**correctness** control, so it must **pass** on the baseline — which is correct code without
the fold. What proves such a row can fail is a **perturbed expectation**, and that is what b4
did: extracted the recipe into a scratch makefile so real `make` performed the expansion, ran
it green, then re-ran with only the aarch64 expectation off by one digit.

**AMENDED by b4, and its version is the useful one — the general rule, not my misapplication
of it.** *A control is not a control until it has failed once* is right; what it does not say
is **where the failure has to come from**, and that differs by kind:

| control kind | the baseline must | the perturbation comes from |
| --- | --- | --- |
| performance | **fail** | the old binary |
| correctness | **pass** | the expectation, or a deliberate break in the code |

> Same rule, two opposite baselines — *which is exactly the sort of thing that survives as a
> slogan and then gets applied to the wrong side of the pair.*

That is the failure mode, and it is mine: I had the rule, compressed it to one clause, and
the clause I kept was the one that only holds for half the cases.

**"A control is not a control until it has failed once" does not mean "make it fail against
the old binary."** For a performance control, the baseline is the thing that must fail; for a
correctness control, the baseline is the thing that must pass, and the perturbation has to
come from somewhere else. I had one rule and applied it to the wrong kind of test.

Root cause of that red, one level below my reading of it: `$$$$(...)` where a make recipe
needs `$$(...)`. Make collapses `$$`→`$`, so the shell received `$$` — **its own PID** — then
a literal `(printf ...)`. I called the absolute `/tmp` path an independent second reason the
row could never match; it was **a symptom of the same bug**, part of the command text rather
than of any output.

### 173 — A GREP SHAPED LIKE THE LINE YOU JUST READ FINDS ONLY THAT LINE'S SHAPE

*frankA, correcting its own claim within the hour.*

It reported *"`MatchParamCompatible` is the only consumer — I grepped."* The grep was shaped
like the line it had just read (`si := Procs[i].Params[j].SymIdx`). A broad `\.SymIdx` search
finds reads across **nine files**, ~90 sites.

The accurate claim is narrower and better: **`MatchParamCompatible` is the only site that
reads a parameter's symbol from a *caller's* context, after the callee's scope has closed** —
and frankA stated explicitly that it had *not* audited the other sites and was not claiming
they were safe. An existence claim survives one grep; a **non-existence** claim does not, and
a grep patterned on the instance you are holding is structurally blind to every other
spelling of the same access.

### 173a — AND THE HAZARD WAS DOCUMENTED THREE TIMES, IN THE SAME FILE, WITH THE MECHANISM ATTACHED

`defs.inc` already carries `ProcParamRecId` (*"param syms are reused across procs, so this
must persist"*), `ProcParamSetEnumId` (*"A PARALLEL ARRAY rather than a TParam field... a
param symbol does not outlive the callee's scope"*), `ProcParamProcSig` (same rationale
again), and at `:2018` the identical measurement in the identical style — *"the params are
rolled back when the operator body finishes (measured: SymIdx 93, SymCount 92)."*

> **The fourth instance of a hazard this codebase has hit, measured, and documented three
> times — and the new consumer reached for the non-durable mechanism anyway.** The durable
> one was in the same file, three lines away, built for exactly this.

Which converts the fix from a design question into a mechanical addition: one more column in
an existing family, no new concept. And it is `a documented trap is not a guard` with a
count: three separate authors each wrote the warning down, and none of them could make the
next author read it.

Related, and left un-"fixed" on purpose: those comments say *"RegisterProc leaves
`Params[].SymIdx` = -1"*, while the Pascal path measures **363**. The premise is narrower
than the comment's conclusion; the conclusion (*don't trust it*) still holds. frankA noted
that rather than editing a comment whose history it had not traced.

### 174 — THE PROBE'S FORMATTER COULD NOT REPRESENT THE ANSWER

*frankC, 2026-08-30. Three wrong measurements preceded the right one, each of which would
have become a confident sentence in the ticket.*

1. **Reasoned about `CModuleOfTok` instead of printing it** — the exact thing the debugging
   playbook exists to prevent, by a lane that had read it.
2. Then printed it through **`IncSmallIntStr`, whose contract is *small NON-NEGATIVE int***.
   It renders `-1` as `0`. So **the one value meaning "no module" was indistinguishable from
   a real module id** — the probe was working, the formatter was lying, and the output looked
   entirely reasonable. `differential-probes.md` has this exact warning (*"a probe that
   FORMATS its output can answer a different question than you asked"*) and frankC had read
   that section **earlier the same night**.
3. Then a full round of *"every include defeats it, even one placed after the static"* that
   was **the harness**: the test program and test header shared a stem, so `uses foo`
   resolved to `foo.pas` — the program itself. **The compiler was reporting a real error and
   it was read as the bug under investigation.**

Only the third attempt, with distinct names and a formatter that can represent the answer,
produced the table that localised the defect. Note the ordering: each failure was *further
from* reasoning and *closer to* measurement, and each still produced a plausible wrong
answer. **Reaching for the instrument is necessary and not sufficient — the instrument has
its own aperture, and a formatter is part of it.**

### 174a — "THE LAST `.c` WE ENTERED" AND "THE MODULE THAT INCLUDES THIS TOKEN" AGREE UNTIL THE FIRST RETURN EDGE

The defect: `CMarkTokModule` is called only for a path ending in `.c`, so **returning from a
crtl impl into the enclosing header never resets the attribution.** `CModuleOfTok` is *the
last `.c` we entered*, not *the module that includes this token* — and those two agree
everywhere except across a return edge.

Which is why it looked correct to the duplicate-definition check that consumes it today:

> **Today it gets that right the way a stopped clock does.**

The boundary is visible in the measurement and nowhere else — `stddef.h` fine, `stdio.h`
broken, `stdio.h` **placed below the static** fine — and the two headers differ in exactly
one thing: whether crtl has an impl to auto-pull. Nothing about the static changes.

Filed as a Track A ticket rather than worked, because the table lives in `dbg_filetable.inc`.
And the argument that the fix **improves** the consuming check rather than trading against it
is carried with it: `stdarg.h` pulled from `fcntl.c` attributes to `fcntl.c`, from `unistd.c`
to `unistd.c` — still two modules, still no false warning.

### 174b — AND IT PRICED MY SUGGESTION DOWN, BY MEASURING

I suggested the nested-include cliff (`case depth of 0..15` with no `else`, guard erroring at
128, so the 17th header vanishes into an **unset function Result** with no diagnostic) was
worth p60 rather than its filed p45, on the reasoning that *nothing nests 17 deep by accident,
so the blast radius is unknown rather than small.*

frankC set it to **50**, having measured instead of leaving it unknown: `gtk/gtk.h` reaches a
modelled (deliberately over-estimating) depth of **15 against a cliff at 16**, and the one
header the model flagged at 18 does not actually take that chain — gcc shows the same macro
absent. **Severe failure mode, one level of margin, and "real code hits this today" is not
supported** — so the ticket now says that rather than implying it.

My reasoning converted *unmeasured* into *high*. That is the right default under uncertainty
and the wrong answer once someone spends ten minutes removing the uncertainty. **An unknown
blast radius is an argument for measuring it, not for assuming the worst and ranking on the
assumption.**

### 175 — A CONTROL THAT *CREATES* ITS SUBJECT — the mirror of 168a, and mine

Building the `UNFILLED-PLACEHOLDER` guard, I ran a positive control: back up a ticket, append
the placeholder Log line, confirm the check fires, restore. The `cp` failed — I had the wrong
path — and the `printf >>` **created a new file**. The check then fired on a two-line file I
had just manufactured, with no frontmatter, and reported it at a defaulted prio.

**The control passed. It proved nothing**, because its subject was an artefact of the control
rather than a real ticket perturbed. And it left an untracked stray in `backlog/` that also
created a duplicate-slug condition, since the real ticket was in `unfinished/`.

168a is a control that **destroys** its subject and shows maximum sensitivity. This is a
control that **creates** its subject and shows a clean fire. **Both fail in the flattering
direction, and both look exactly like a working guard.** The shared cause is that a control's
own setup is unverified — I never checked the `cp` succeeded, exactly as pxx-a5 never checked
its deletion had removed the right lines.

Redone properly: backup verified by line count before perturbing, control run against the
real ticket in `unfinished/`, 0 → 1 naming it correctly → 0, and a clean `git status`.
**Verify the apparatus's state, then measure** — 158b, on the fourth encounter tonight.

### 175a — A CODE SET THAT COMPILES, LINKS AND RESOLVES CORRECTLY, THEN MISREPORTS EVERY FAILURE

*frankB, same night, binding lwIP's `getaddrinfo` on ESP.*

lwIP's `EAI_*` codes are **positive 200-204**; glibc's are **negative −2…−5**, and the sets
differ — no `EAI_AGAIN`, no `EAI_NODATA`. A binding that reused glibc's numbers *compiles,
links, and resolves every valid name correctly*, then misreports every failure: `EAI_NONAME`
misses every arm of `EaiToRcode`, falls out as `DNS_ERR_LIBC_UNAVAIL`, and drops the facade
back to `dns_wire` — which on ESP has no nameserver config.

**A name that does not exist would be reported as "resolver unavailable."** Plausible, wrong,
far from the cause, and **it would have passed any test that only resolved names that exist.**

It was caught by a line added as a *diagnostic*, not planned as proof: `nx-rc=2` — lwIP
returning `EAI_FAIL` (202), mapped to SERVFAIL. With glibc's table the same run prints −22.
frankB added it precisely because the EAI mapping was the one place this could be silently
wrong, and it became the evidence.

Controls, because `status=0` is the shape to distrust: the riscv32 object carries
`U lwip_getaddrinfo` and **no bare `getaddrinfo`** (a wrong external name compiles identically
and fails only at link); `liblwip.a` defines it, so both sides are checked; and the smoke
calls the **backend directly**, because the facade falls back on unavailability and a
facade-level green cannot distinguish *"lwIP answered"* from *"lwIP was skipped."*

**And the scope note is in the README, not just the report**: the smoke resolves numeric
literals, which `getaddrinfo` converts locally with no query and no server — *which is exactly
why they work under QEMU with no network.* This is the binding and the ABI, **not "DNS works
on ESP".** A green invites over-reading, and the place to stop that is where someone stands
before trusting the example.

### 176 — I NOTED THE CONSTRAINT IN THE PROSE OF THE TICKET I WAS FILING, AND IT DID NOTHING

*frankB, 2026-08-30, on its own ticket, hours after being told about the prose/frontmatter gap.*

It filed `feature-dns-esp-wire-nameservers-from-lwip` at p15, **noted the ESP park in the
ticket's prose**, and the ticket was dispatchable within the hour. It is one of the 23.

> Noting it **in the ticket I was filing** felt like diligence at the time and did nothing at
> all.

That is the prose/frontmatter failure caught **at the moment of authorship**, by an author who
knew about the failure class, and it still happened — because writing the caveat *discharges
the feeling of having handled it*. The ranker never read it. Same night, sixth instance.

The repair frankB then made is the one to copy: `blocked-by:
decide-is-the-2026-07-12-esp-park-still-in-force`, confirmed to have left `ready --track B`,
and — the part that makes it safe — **it does not presume the ruling.** It says only *not
dispatchable until the question is answered*, which holds either way: park lifted, the edge
clears and it ranks; park stands, it should never have ranked. **A gate keyed on the open
question rather than on a guess at its answer is correct under both outcomes.**

### 176a — AND IT GATED ONE ROW, NOT TWENTY-THREE

frankB gated **only its own** ticket, deliberately:

> The other 22 aren't mine to gate, and how they get gated is part of what the ruling has to
> settle — **a coordinator applying markers across four lanes' tickets ahead of the decision
> would be the same erosion in the opposite direction.**

That is a check on *me*, and it is right. Having found that a user decision was being eroded,
the reflex is to enforce it immediately and everywhere — which would pre-empt the ruling just
as thoroughly, in the other direction, and across lanes that never agreed to it. **The
correct scope of a unilateral repair is the thing you yourself broke.**

### 176b — AND THE PARK HAD BEEN UNOBSERVED SINCE THREE WEEKS AFTER IT WAS WRITTEN

Checking frankB's chronology against files neither of us chose for the purpose: ESP work was
**actively progressing on 2026-08-02** — `feature-esp-hardware-flash-validation.md` records
*"Everything except the board is now in place"* and *"The peripheral half is unblocked too"*,
both dated; `feature-a-promoint-variant-esp-targets.md` carries a dated diagnosis the same day.

So **tonight's staffing is the largest instance, not the first.** The park has been invisible
to every session since roughly three weeks after it was made. That is consistent with *both*
readings — superseded, or never seen — and the two are indistinguishable from the tree, which
is precisely what makes it a decision rather than a lookup.

Note the direction the check ran: frankB cited a *2026-08-02 user correction* recorded in its
own ticket. I could not independently find that ruling's text, so it is relayed on frankB's
citation and labelled as such — while the *activity* on that date is corroborated from
elsewhere. **Verifying a claim against a source the claimant did not choose does not always
confirm or refute it; sometimes it returns a different, better fact.**

### 177 — A SHA CHECK ON THE SOURCE PROVES NOTHING ABOUT WHAT WILL EXECUTE

*pxx-a5, 2026-08-30. The most transferable finding of the night, and every lane writing a
Python negative control is exposed to it.*

Its negative control edited `testmgr.py` in place, ran, restored the file, and **confirmed the
restore by sha256.** Guard 1 then failed against a correct tree — **three runs in a row**,
with the right source open in front of it.

CPython validates `__pycache__` against the source's **`(mtime, size)`**, with mtime at
**one-second resolution**. The edit was `if stepf:` → `if False:` — **five characters for
five.** Size-preserving, and inside one second. So the cache stayed valid and **every later
run executed the control's bytecode.**

> **A restored tree reporting a defect that is no longer in it.**

The sha check was not sloppy; it was *correct and irrelevant*. It answered "is the source
what I think it is" when the question was "is that the code that will run". Those are the same
question only when nothing caches between them, and Python caches by default.

Note what makes it nearly undetectable: **it needs a size-preserving edit inside one second**,
which is exactly what a careful minimal negative control looks like. A sloppier edit — adding
a line, taking two seconds — invalidates the cache and behaves correctly. **The discipline
that makes the control minimal is what makes it invisible.**

Fixed by having the devtest compile what it measures from text and write no cache.

**Alongside 168a and 175, this completes a set: three ways a control's own apparatus produces
a finding.** 168a destroys its subject (all guards red, reads as maximum sensitivity). 175
creates its subject (guard fires cleanly on a fabricated file). 177 restores its subject and
runs the old one anyway. **All three fail in the flattering direction and all three look
exactly like a working guard.** The shared cause is that the apparatus's state is never itself
measured — 158b, four times over now.

### 177a — AND IT REFUTED THE TICKET'S FIRST PROPOSAL STRUCTURALLY, NOT BY PREFERENCE

The ticket asked for the slug to be built from the failing step. **The slug cannot move**, for
two reasons that are facts about the code rather than taste:

1. It is the dedupe key when **filing**, and is recomputed as `reg_slug(r["job"])` when
   **closing** — where no step is in scope, because *the closing run is the one where the job
   went green*. A step-derived slug is unfindable at close time, so **every stub leaks open,
   silently** — the exact failure `feature-t-autoticket-must-close-its-own-stubs-when-fixed`
   existed to end.
2. `progress.py` derives a ticket's `type` from the slug's first token, so
   `regression-lib-units-pcl-gtk3` becomes a ticket of type `lib`.

Second time this lane has refuted its ticket's own suggested shape and **written the
refutation into the code and the guards** rather than only the write-up — because *a ticket's
own suggested shape is the thing most likely to be re-adopted later*.

### 177b — THE BOUND MATTERS MORE THAN THE RULE

A blanket *"never fall back to the job's src"* would have swept the entire single-test
majority to Track T: `compile foo.pas` then `diff foo.expected -`, whose failing step names
only the `.expected`. So the refusal is **bounded to multi-source jobs** — where a job names
one source, first-source and only-source are the same file and no other lane is in frame.
Guard 5 is that bound, and its control shows `test-core#src:test/alpha.pas` going P → T
without it.

> **Fixing a mis-routing by installing a bigger one is the easy failure here.**

The number that carries it: `lib-test#00` is **198 recipe lines naming 39 source files across
four lanes**, and `src` is the first two of thirty-nine. Step 28 now routes B — that is
crtl-reachability-4, the red that cost the C lane an evening.

### 177c — AND IT SAID THE FIX DOES NOT COVER THE CASE I GAVE IT

`test-threads#src:test/test_cmp_both_in_place.pas@2` fails in step 3 of 14, **whose text
legitimately names `test/test_cmp_both_in_place.pas`** — so the step-derived track is P, the
same wrong answer. b4's ownership is not derivable from any path, and **no rule over filenames
will find it.**

Of the four facts that name could not carry, the fix delivers two: the **arm** is now in the
H1 (`for o in 0 3; do ./compiler/pascal26 --target=aarch64 …`) instead of being reconstructed
from the log tail, and a first-ever run is headed **`first-ever red`** rather than
`regression`. The step kind and the owner are the honest residue, stated as residue.

**A fix reported with the half of the motivating case it does not solve is worth more than one
reported as complete**, because the next person knows where to start rather than discovering
the gap by trusting it.

### 178 — A WHITELIST FAILS IN TWO DIRECTIONS AND THE TEST ASSERTED ONE

frankA, 2026-08-30. A generic-bound-name whitelist regressed `TKey` resolution
under objfpc: the comment asserted *"a declaration's left-hand side can only follow
the `type` keyword or the `;` that ended the previous declaration"* — true of Delphi,
false of objfpc, which writes `generic TDict<TKey, TValue>` behind an ordinary
`tkIdent`. Every objfpc header failed the header test, parameters were never
harvested, and `specialize TCmp<TKey>` was minted concrete instead of deferred.

The regression is not the face. **`test_generic_bound_name_harvest` asserted only the
OVER-collect direction** — a use must not donate its arguments. The **under**-collect
direction, that a genuine header's parameters must still *be* collected, was never
asserted, so a whitelist rejecting **every** objfpc header passed it clean.

> **A whitelist has two failure directions; a test written while fixing one of them
> will assert that one.** The assertion you need is chosen by the *shape of the thing
> under test*, not by the bug that prompted the test.

Closed correctly: the new arm was checked to **fail on the broken binary**
(`22c67e5ea61e`, `69: unknown type: TKey`) rather than merely to accompany the fix.
That step is the whole difference between a control and a passing test — cf. 168a,
172b, 175, 177.

Why it hid, measured: the **Delphi spelling of the identical shape** passes on all four
binaries and on FPC. Every control frankA had came from that one surface.

### 178a — TWO CAUSES WEARING ONE ERROR STRING, AND THE AUTO-FILED RANGE POINTS AT THE EARLIER ONE

Same incident. The watcher filed the red at 02:19; the commit that caused *this*
instance landed at 04:08. The error text was identical both times and the bug had been
**broken, fixed by someone, then re-broken**. Trusting the ticket's implied range would
have bisected the wrong window.

Generalises to every auto-filed regression: **the ticket's timestamp bounds when the
symptom was OBSERVED, not when the cause landed**, and a recurring error string makes
those two look like one claim. Pairs with the standing rule that a ticket's stated
blocker and its actual blocker are independent (135).

Consequence for a live ticket, acted on rather than relayed:
`bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument`
has had its repro move **twice in one night** — `unknown type: PT` (pxx-a5's reduction)
→ moved by `8e4d175d2` → now `35: unknown type: TPair`. **Fewer symptoms sit behind it
than believed.** Re-reduce; trust no error text currently in it.

### 179 — THE ENFORCEMENT WAS DESTROYED WHERE IT WAS LOAD-BEARING AND PRESERVED WHERE IT WAS INERT

frankB, 2026-08-30, from a `git log --follow` nobody had run. The 2026-07-12 ESP park
(`ad649f55f`, *"park ESP family (user: Pascal has prio)"*) attached its reason to three
tickets as a comment on the `prio:` line. The 2026-08-25 bulk re-triage `ab584382e`
rewrote `prio: 30  # ESP parked (user 2026-07-12)` to a bare `prio: 20` and **deleted the
comment**; its message does not mention ESP, and nothing about it was a decision to
unpark anything.

**Both tickets that had reached `done/` kept the comment. The only one still live had it
deleted.** Not targeting — a re-triage re-prices *open* tickets and never touches closed
ones. Which is worse: the mechanism guarantees that **every surviving copy of the record
is, by construction, a copy that no longer mattered.**

> **"We still have the record" is not evidence the record survived where it was needed.**
> Ask where the surviving copies are, not how many there are.

And the fix follows from the mechanism rather than from taste: **one commit swept two
separate owner rulings** — the same `ab584382e` moved the held NilPy ticket from
`prio: 20` to `prio: 55`. One commit, two rulings, one cause is a far stronger case than
two incidents of a class. It would do it again, and `NOT DISPATCHABLE` / `gated-by:`
survive it **precisely because they are not prices**.

Two-phase erosion, and only the second phase is about tooling: the park sat intact and
readable in a live ticket's frontmatter from 2026-07-12 to 2026-08-25 — **a span that
contains the 2026-08-02 ESP activity.** So that work happened with the park visible.
**Unobserved, then unrecorded.** The coordinator's first write-up collapsed the two and
made the missing mechanism carry weight that belonged to plain not-reading.

### 179a — THE UNCHOSEN SOURCE ANSWERS A QUESTION NOBODY ASKED

The standing rule was *verify against a source the claimant did not choose*, justified
defensively: two arms sharing an upstream agree for free. Three checks in a row on
2026-08-29/30 say the payoff is not defensive at all. The coordinator checked frankB's
2026-08-02 claim and landed on ESP activity three weeks after the park; frankB then
checked its **own** claim and landed on `ad649f55f`/`ab584382e`. **Neither check confirmed
or refuted the claim it was aimed at.** Both returned a different, more useful fact.

> An unchosen source is the only kind that can answer a question nobody asked.

Reframes the discipline from adjudication to discovery, which is a much better reason to
actually spend the minute.

### 180 — A LANE'S QUEUE CANNOT SEE THE TICKET THAT UNBLOCKS THE LANE

frankC reported Track C's queue as *"nothing above 50 that is a unit of work"* — true of
`ready --track C` and false of the board. The p60 unit of work in C's own interest is
`refactor-a-c-exclusive-lowering-has-no-carved-out-file-so-track-c-cannot-be-staffed`,
filed **`track: A`** because A owns `ir.inc`. That filing is **correct** — file-lanes are
about the file, not the topic — and its consequence is that the one ticket whose entire
purpose is to make Track C staffable is structurally invisible to Track C.

It compounds an in-edge problem already written into that same ticket: no `blocked-by:`
edge points at it, because the five C tickets it unblocks *can* proceed by an agent
holding the A slot, so adding the edges would be a false claim and it inherits no
priority. **Invisible to the ranker by in-degree, invisible to its beneficiary by track
letter. Two independent mechanisms, same direction.**

> The tickets that unblock a **lane** rather than a **ticket** are the ones no query
> surfaces, because from the ranker's side an in-degree of zero is indistinguishable from
> a leaf, and from the lane's side another letter is indistinguishable from not-my-work.

Nth instance of the night's dominant theme — load-bearing state in a place no tool reads
(129, 134a, 165, 179) — but the first where **every individual filing decision was right**
and the invisibility is emergent. Nothing here is a mistake to correct; it is a query
that does not exist.

### 180a — THE COUNTER-EXAMPLE THE SOURCE ITSELF PRODUCED

Same ticket's table reads *five of seven ranked C tickets need an A file*. Hours later
frankC resolved `bug-c-an-include-nested-deeper-than-16-is-silently-dropped` **entirely
inside its own lane**, filing the `defs.inc` follow-up as an A ticket at p40 rather than
editing it. That is a counter-example to its own measurement, produced by the measurer,
within a day.

The measurement still holds overwhelmingly — which is the point. **A table that has met
its counter-examples and states them is worth more than one that has not**, and the
author is the only person positioned to notice when the ratio moves. Left uncorrected, a
measurement decays into a slogan of exactly the kind 173 describes: more quotable than
accurate, and quoted.

### 181 — A GUARD THAT HAS ALREADY BEEN HARDENED ONCE IS MORE DANGEROUS THAN ONE THAT HAS NOT

pxx-a5, 2026-08-30, refusing a flake story the coordinator had handed it.
`tools/bench_timing_devtest.py` is load-dependent — green three runs at load 3.8, red
at ~9.5 — and the coordinator's diagnosis was *"a correct measurement of the wrong
subject; change what it measures."* **That is one abstraction level above the defect**,
and it would have sent the repair to the wrong place. a5 read the captured red instead.

The guard **had already been hardened for exactly this**. `c194b01e9` replaced a spread
with an on-grid count, on this stated reasoning: *"a scheduling stall can only push a
sample to a LATER poll wakeup, never off the schedule."* **That sentence is false, and
it is the sentence that failed** — the stall lands in the **parent**, between the poll
wakeup and the clock read after it, and nothing quantizes that delay.

    old [169.4, 119.0, 115.8, 119.1, 117.1] -> 2/5 within 4ms of a grid point  FAIL
    min(old) = 115.8, i.e. +2.3 from 113.5

**The claim the guard is named for was true and the guard said FAIL.**

> **A count of contaminated samples and a spread are both properties of the box, one
> abstraction apart.** The hardening changed the guard's abstraction level without
> changing its subject, so it bought nothing and looked like progress.

And the general form is worth more than the file: **a previously-hardened guard reads
as evidence the question was settled**, so the *stated reason* for the hardening is
precisely the thing nobody re-reads. Same family as 137 (a stated danger deserves the
scepticism of a stated limitation) and the standing rule that a false limit is quieter
than a false fix.

The fix (`8c592615d`) argues from a property rather than a threshold: **scheduling noise
is one-sided and additive, so the minimum is the least-contaminated estimate and the
only statistic here that does not degrade as the box gets busier** — more samples improve
a minimum and make a count and a spread worse. Verified three ways, and the middle one
is the one almost nobody writes: replay of the recorded load-red data (v2 fails, v3
passes), a **vacuity check** (a continuous 70ms path scores `near_grid=False`, so v3
cannot be satisfied by what it must reject), and a negative control reddening both halves.

### 181a — A TICKET OUTLIVES THE ARGUMENT IT CITES, AND NOTHING CHECKS THE CITATION

Immediate consequence, caught only because a5 kept reading. `chore-a-re-include-bench-timing-in-tools-devtest`
[A p30] tells Track A the guard is now load-invariant and to delete the one-line skip —
**citing `c194b01e9`, the argument just refuted.** Taken as written, Track A would have
re-armed a load-sensitive guard into the limited and full tiers, and the resulting reds
would have read as new breakage in whichever lane happened to be pushing.

Correction written into the ticket (`e2182cf2a`) rather than relayed. The ticket is still
actionable — **for a different reason**, and it stays A's.

Pairs with 178a: a ticket's stated range and a ticket's cited justification are both
claims with dates on them, and the board checks neither.

### 182 — A CORRECTLY-FORMED INVARIANT OVER THE WRONG POPULATION

frankA, 2026-08-30, correcting a gate the coordinator had just praised. The coordinator
endorsed *"same key ⇒ same bytes, different key ⇒ a miss"* as the invariant for a
compiled-unit-image cache. As a **single-program** check it would pass a serialiser that
forgot 170 of its 176 arrays, because **a missed array is only observable if some
program's output depends on it.**

The logic was right and the population was wrong. Real gate: cold-vs-cached byte-identity
over a corpus, with Track T's 719 NilPy jobs as the instrument.

> The same defect as 178 wearing different clothes — there the assertion's *direction*
> was wrong, here its *range* is. **Both are the control failing to be a control while
> reading as one.**

Found against praise, which is the hardest direction to find anything in. Same rule as
172b from a third arrival: this feature's subject is performance and its control's
subject must be correctness.

### 182a — THE HAZARD IS THE TENSE, NOT THE COUNT

Same survey. The design names five things to serialise; frankA counted **176 parallel
arrays** (100 proc-indexed, 44 sym-indexed, 32 field-indexed) before `Code[]`, the string
pool, RTTI and fixups, against 242 `array of` globals in `defs.inc`.

176 is not the finding. **Every array any future Track A commit adds must be added to the
serialiser, or the cache silently emits stale code** — a permanent tax on every future
commit in the lane, paid by people who will not know they owe it. `symtab.inc:3932`
already names this class (*"the 'one of six parallel arrays not written' class"*) with a
measured instance behind it.

> A cache converts a **known recurring bug class** into a **maintenance obligation with
> no by-construction defence.** That is a different kind of cost from "a big job", and it
> is the half a scoping estimate never contains.

Note which half the coordinator had called the sharp edge: the **key** — which turns out
to have a by-construction fix (hash the whole normalised argv plus the compiler build
sha; an unrecognised flag changes the hash, so there is no allowlist to forget). *The
scary-sounding half had a mechanical answer and the dull-sounding half did not.*

Recorded with it, and the reason the 60%-dead-bodies measurement is trustworthy: three
qualifications attached **to the number itself** — live bodies average larger (653 live =
749KB vs 998 dead = 510KB, so 60% by count is 40% by size), the measured program does
nothing so it is a best case, and interface parsing is untouched and unavoidable. Face
164 is the failure this avoids: the bare number is what gets quoted downstream.

### 183 — THE GATE NAMED THE STALE BINARY INSTEAD OF REPORTING A MISCOMPILE

Coordinator, 2026-08-30, attempting the pin that unblocks the grid-pad answer.
`gate.sh quick` failed the self-host fixedpoint with *"the fixedpoint reached from PINNED
differs from compiler/pascal26"* — two distinct self-reproducing fixedpoints, which reads
as the worst thing in the repo. It then said:

> `compiler/pascal26 is OLDER than the last commit touching compiler/`
> `That is a STALE BINARY, not a miscompile — a sibling landed a compiler change and this`
> `checkout has not rebuilt.`

Correct, and nothing was blessed. **This is the exact inverse of the fresh-tree trap** —
there, `make compiler/pascal26` is a silent no-op that exits 0 because a copied-in seed is
newer than the sources, and the absence of `converged after N round(s)` is the only tell.
Here the same mtime relation runs the other way and the gate is loud about it.

> The pair is the lesson: **the same clock skew produces a silent pass in one direction
> and an alarming-but-wrong failure in the other.** The alarming one is safe. The quiet
> one is the one that ships.

Worth keeping because the diagnosis is *not* derivable from the failure text alone — two
divergent fixedpoints and a stale checkout are indistinguishable at the point of failure,
and the gate distinguishes them only because someone thought to compare the binary's
mtime against the last `compiler/` commit. A guard that explains which of two very
different causes it hit is rarer than one that fires.

### 184 — A WRONG COMMAND READS AS VERIFICATION

frankD, 2026-08-30, third pass over `docs-devnotes-ai-assisted-build`. The draft's whole
advice is *quote the invocation, not the table* — so it printed a re-measure command
beside each of ten figures. Cross-checking those commands against `tools/factsheet.sh`,
**two of the ten were wrong, both undercounting**: `ls devdocs/progress/backlog/*.md`
misses `backlog_new/` (338 against 351), and `ls devdocs/progress/decided/*.md` misses
the one resolved decision sitting in `done/` (116 against 117).

> **A stale number is wrong once and looks it. A wrong command is wrong on every run,
> agrees with itself every time, and therefore reads as verification** — the reader does
> the responsible thing and is reproducibly misled.

That is the worst place in the document for the defect to sit, and the section's own
virtue is what makes it durable: it invites re-running, and re-running confirms it.

**Neither method is the oracle — the disagreement is.** An earlier log entry on the same
draft recorded the *reverse* result, the script losing to a hand count on three numbers.
So "the script won twice" is not a ruling for the script; the finding is that two
independent instruments disagreeing is the only thing that located either error. Same
shape as 179a from the other side: the value is in the second, unchosen instrument, not
in which one wins.

Both replacements were **run before being written down**.

### 184a — THE SECTION STATING THE RULE IS THE SECTION BREAKING IT

Two smaller ones from the same pass, and the pattern is becoming that draft's signature.
Its header stamped a **date** while a bullet two paragraphs below says stamp a **sha** —
and the cost landed immediately: how far apart the two measurements were is now
unrecoverable. And its qualifier section, which correctly identifies that raw counts rot
and promotes the agent-trailer ratio as the durable figure, **then quoted that ratio to a
precision that rots too** — "held at 46%", measured today at 45%. It states a band now.

The recursion is not a coincidence. **A section about a hazard is written by someone
thinking about the hazard in the abstract**, which is a different cognitive act from
applying it to the sentence being typed. Cf. rule 5 in the coordinator's own operating
notes — *the rule you are enforcing is the one you will not apply to yourself* — and
tonight's third instance of it on the coordinator's side.

### 184b — A DELTA MEASURED ACROSS A CHANGED METHOD IS NOT A DELTA

Same pass, and it is the refusal that is worth banking. The backlog had grown +35 since
the morning, the most quotable number available and directly in service of the draft's
thesis about drift. frankD **declined to quote it**: 13 of the 35 are the undercount
being fixed in the same commit, not tickets anyone filed.

> A before-and-after across a **method change** measures the method, not the subject.

Note it declined the number that supported its own argument, which is the direction
almost nothing gets declined in.

### 185 — KILLING A RUN IS CHEAPER THAN A RESULT WITH MIXED PROVENANCE

frankB, 2026-08-30, mid-`lib-test` when the pin moved v393 → v394. Pulling would have
swapped `stable_pinned` underneath a running suite and produced **a mixed-pin result that
looked like a clean green**. It killed the run and restarted against v394 — and noted
that a v393 result had no value anyway, because nothing ships against it again.

The pair with 183 is the point, and it is frankB's framing: 183 is the provenance rule
biting in the **alarming** direction (a stale binary makes the gate scream), this is the
same rule biting in the **ordinary** one, where nothing announces itself and the only
tell is knowing what you swapped. **A green whose inputs changed halfway is
indistinguishable from a green.**

Recorded with it, because self-reporting is the rare half: frankB flagged that face 181
lands on its own current work — it has been citing a header in `lib/rtl/mimic_xml_dom.py`
all evening as settled reasoning for its `weakref` refusals, rather than re-reading
whether the header's stated reason applies to its case. It does. But it got there **by
argument**, and 181's whole claim is that the argument is what stops being re-run once a
header looks authoritative. **Flagged as a thing done, not a thing avoided**, which is
what makes it usable.

### 186 — A SWALLOWED FAILURE IN A TIMING HARNESS REPORTS A SPEEDUP

frankA, 2026-08-30, catching a live instance of the exit-status hole in its own work
minutes after the warning arrived. It had claimed *"the stripped pair compiles"* on the
strength of an `echo "exit=$?"` placed after a `| head -20` — **that was `head`'s
status.** The claim happened to be true (the `ok:` line carried it), but *the evidence
cited was not evidence*.

The sharpening is frankA's and it is worse than the general form:

> **In a timing harness a silently-red configuration does not merely report success — it
> reports a SPEEDUP.** A compile that fails reports a beautifully fast time. The
> swallowed failure manufactures exactly the result you were hoping for.

So the general rule (*anything appended after the thing you are measuring becomes the
thing that reports*, frankC) has a polarity term: **wherever the measurement's units make
failure look like success, the hole is not neutral, it is confirmatory.** Same family as
the RSS sweep where eleven probes read a flat 392 KB because the programs were not
running — the number was stable, plausible, and produced by nothing.

Re-run with `rc=$?` captured immediately and an assertion that each compile printed
`ok:`. Note which half was fixed: not the conclusion, the **evidence for** the
conclusion, on a claim already known to be true.

### 186a — MEASURING THE ARM YOU RECOMMENDED, AND REFUTING IT

Same session. frankA had recommended the defer-bodies route (**B**) over the
serialise-the-image route (**A**) on the grounds that B's ceiling was large enough to be
worth avoiding A's 176-array permanent maintenance hazard (182a). Given a time-boxed,
measurement-first, explicitly-not-a-landing authorisation, it **prototyped B at the
source level and killed its own recommendation.**

A 2.78s compile of a zero-byte `.npy` decomposes as:

| band | cost | who can reach it |
| --- | --- | --- |
| routine bodies (parse+lower+emit) | **1.63s / 59%** | B's entire territory |
| runtime declaration + interface parsing | **0.78s / 28%** | **invisible to B by construction** |
| fixed compiler floor | 0.37s / 13% | neither |

B claims only the *dead* share of its 59%: ≈0.98s / ~35%, and optimistic, since dead
bodies are the smaller ones. A removes bodies and declarations together — ceiling 2.41s /
**87%**. *A's realistic reach is roughly twice B's ceiling*, and **the 28% band is
precisely what makes A unconditional and precisely what B cannot see.**

> The recommendation was not wrong about B. It was wrong about the **band it had not
> partitioned** — and no amount of care about B would have surfaced it, because the
> missing band is defined by being outside B's reach.

Method worth copying: measured under load 15.6 against the ticket's baseline of 2.76, so
**the recorded absolutes were thrown away** and everything re-measured interleaved
(full, stripped, full, …), with only within-sweep differences claimed. Fidelity checked
rather than assumed — both configurations report `procs=1859`, so every symbol still
registers and only bodies vanish. One confound measured (comment text of the same byte
volume costs the same as stripping, so the 1.63s is parse+lower+emit and not I/O) and one
declared uncovered (tokenisation — both variants skip it, a real B would not, and it can
only make B worse, so it does not rescue the comparison).

**Nothing implemented, nothing to revert, `compiler/builtin/**` restored byte-exact by
sha256 against pre-experiment copies.** A measurement that changes a recommendation is a
cheaper deliverable than the implementation it prevents.

### 184c — THE FIX FOR 184a IS PROXIMITY, NOT DILIGENCE

frankD, 2026-08-30, correcting the coordinator's over-generous read of 184b. Declining
the +35 backlog delta was *not* an act of unusual discipline:

> *"It was cheap in the moment, because I'd just spent two paragraphs arguing that a
> wrong method reads as verification, and the number would have been produced by a method
> I was mid-way through changing. The discipline that made it easy was having written the
> rule down thirty lines earlier."*

**That is 184a with the sign flipped.** Writing about a hazard reliably fails to protect
the sentence being typed *in the same breath* — but it does protect a sentence typed
**immediately afterwards about the same subject.**

> Narrow window, and worth knowing it exists, because it suggests **the fix for 184a is
> proximity rather than diligence.** Put the check next to the claim it guards, in time
> as well as in the file; do not rely on having understood the rule.

Consistent with everything else in this index that works: `_NODISPATCH_RE` fires where the
ticket is read, the gate's stale-binary note fires at the failure, `progress check`'s
scans fire on the board. Nothing that depends on someone recalling a rule at the right
moment has survived here.

### 184d — THE NULL RESULT AN AUDIT IS LEAST LIKELY TO REPORT

Same audit. Its commissioned subject — public copy conflating the two byte-identical
claims — **was not there.** Not one sentence in `docs/**` or the README claims or implies
that PXX emits gcc's machine code; every gcc mention outside `--doctor`'s toolchain list
is one of the two correct disclaimers, and `status.md:71` goes out of its way to deny
FPC-indistinguishability.

frankD reported it plainly, noting *"a null result is the outcome an audit is least likely
to report"* — because an audit that finds nothing reads as an audit that was not needed,
and the incentive is to promote a near-miss into the finding.

**The real defect was the qualifier the ticket mentioned second: five of six self-host
claims did not name their `-O` scope.** `features/index.md`'s was the predicted shape
exactly — *"Byte-identical fixedpoint builds are part of the development gate"*, one
clause in a bullet list of selling points, naming neither the scope nor which of the two
claims it is. **The shortest version of the sentence really is the wrong one.** And
`status.md`'s omission mattered for the opposite reason: being the *definitional*
passage, it **taught** the gap rather than merely having it.

Third: frankD's own new sentence said "output parity against gcc- **and FPC**-built
references", so it checked that FPC is actually run as an output oracle
(`tools/fpc_diff_probe.sh` — it is). **The claim it was most likely to get wrong was the
one it had just written itself**, which arrives already believed. Same asymmetry as 184.

Nothing was weakened: every edit adds a qualifier or a distinction, none hedges.

### 187 — TWO IDENTICAL LITERALS INTERN TO ONE ADDRESS, SO THE BROKEN TEST PASSES

frankS, 2026-08-30, fixing shortstring equality on xtensa. The equality guard was gated
on `tyAnsiString` only, so **both-sides-frozen fell through to the INTEGER compare and
compared buffer addresses.** `b = 'BBBB'` for `b: string[4]` answered FALSE.

The comment above the broken guard said *"frozen equality already works"* — and that was
**a measurement that passed for the wrong reason**, not carelessness:

> `'BBBB' = 'BBBB'` really does answer true, because **two identical literals intern to
> one address**, so address equality and string equality agree. Check frozen equality
> with two literals and a broken compiler is correct. Check it with a variable and it
> never worked.

Direct sibling of 162 (nineteen of fifty cells passing by arithmetic): **a pass by
coincidence is indistinguishable from a pass by correctness**, and here the coincidence
is structural rather than numeric — interning makes the two relations agree on exactly
the inputs a careless test uses. It hid for the life of the backend.

The Makefile row frankS wired uses the **variable** form with a comment saying why,
*because the obvious simplification of that row reintroduces the blind spot.* A test
whose natural tidying restores the bug needs the reason attached to it, not near it.

### 187a — A REPRO BUILT FROM A TEST'S FAILURE MESSAGE INHERITS THAT MESSAGE'S ERROR

Same session, an hour later, same blind spot, and this one is the transferable half.

`test_shortstring_trunc` printed `b-CLOBBERED`. **Nothing was clobbered** — `b` prints
`BBBB`, `Length(b)` is 4, the neighbour is intact, the write truncates correctly. The
message named a *cause* it had inferred, and the cause was wrong.

The message propagated **four hops**: frankS repeated it in a handback table, a commit
message, and a message to the coordinator; the coordinator **filed and ranked a ticket on
that framing**, titled it `…corrupts-a-neighbouring-variable`, and ruled the ESP park
inapplicable *on the strength of it being memory corruption.*

Then it got frankS again: the first minimal repro assigned an oversized literal, printed
`a`, printed `b` — and **passed.** *"I had reproduced the write and dropped the
comparison, removing the actual defect from my own repro while believing I had bounded
it."*

> **A test's failure message is a hypothesis with a date on it.** Reproduce the
> OBSERVABLE, never the message's account of it — a repro derived from the message
> inherits its error and, worse, *confirms* it by being bounded the same wrong way.

Coordinator's note on its own hop: **the ruling survives on a different premise** — the
escape rule is *silent wrong behaviour*, which a comparison answering FALSE is — but it
was **stated** as memory corruption, and per 138, *a right destination reached by a false
argument does not self-correct.*

### 187b — THE TWO-GUARD SPLIT WAS THE SAME DEFECT COMMITTED AGAIN INSIDE ITS OWN FIX

Same fix. riscv32 **already carried** this repair with the identical root cause spelled
out in its comment — *"Was gated on tyAnsiString only, so frozen = frozen compared
ADDRESSES"* — and the sixth backend was skipped again anyway.

frankS merged the two guards into one covering all six operators **rather than adding the
missing terms beside the existing guard**, noting that the two-guard split *was itself the
same defect committed a second time inside its own fix*, three lines under `PXXStrCmp3`'s
note about being miscounted.

That is `normalise-dont-special-case.md` applied to the *shape of the fix* rather than to
the code being fixed: **adding a second arm beside the first is how the double case is
created, including when you are creating it in order to close a double-case bug.**

### 187c — A BYTE-IDENTICAL RESULT READS AS "MY CHANGE DID NOTHING"

Same session, bug 2 (a by-value wide record on xtensa). After landing two of the three
spots, the repro was **byte-identical to before** — which reads exactly like a no-op and
would have sent frankS hunting a wrong predicate in the two arms it had just written.

A **one-line `Error` probe** in the call-arg arm answered it in one build: the arm fires.
The caller was already correct; **the callee was the half nobody had visited.** Probe cost
two minutes; re-reading a correct guard would have cost an afternoon *and produced a wrong
root cause in a ticket* — which is the exact outcome `PXXDBG` exists to prevent.

And the disposition was right: **reverted rather than left half-applied.** arm32's ticket
for the identical bug says a subset fix *"turned the data loss into active corruption"*,
and frankS measured exactly that — with two of three spots in, rows change value rather
than become correct, because every parameter after the record shifts by a word. Patch
banked in a scratchpad, diagnosis banked in the ticket, tree clean. **Park rather than
microfix, in the one lane where a half-applied change can poison every other.**

### 188 — A CAVEAT ABOUT A BINARY THAT EXISTED FOR ONE HOUR IS UNFALSIFIABLE

frankD, 2026-08-30, sharpening the coordinator's own re-run-don't-hedge rule after the
v394 pin was blessed at ~06:40 and reverted at ~07:40.

The rule had been about **caveat quality**. frankD's version is about **caveat
survival**:

> A wrong caveat about a **live** binary is at least falsifiable by someone re-testing.
> A caveat about a binary that existed for one hour is **unfalsifiable, because nobody
> can reproduce the conditions to disprove it.** It would have become permanent by being
> **unverifiable**, not by being believed.

Strictly worse than 184's wrong command, which at least keeps agreeing with itself in
public and can therefore be caught by anyone who runs it. **A claim whose subject has been
withdrawn cannot be checked by anyone, ever** — and it reads exactly like a claim that
simply has not been challenged yet.

Three live citations of the withdrawn pin were found, and their gradient is the lesson:

| citation | status after the revert |
| --- | --- |
| `feature-lib-tkinter-grid-pad-…` — *"CLOSED against the pin. v394 carries the fix."* | **ground withdrawn**; reopened, banner added |
| `refactor-a-c-exclusive-lowering…` — six C tests built with `e2ea9034a65e` as the pre-move compiler | **comparative, so still valid**; only the sha names a ghost |
| `bug-n-property-works-as-a-decorator…` — *"Both pins say the same thing."* | **stronger than before**, because it named two |

**The one that named two pins is the only one the revert could not touch.** That is the
operational rule, not a moral: a measurement anchored to one binary is a claim with a
date on it; anchored to two, it is a claim with a range.

And frankD **appended rather than corrected in place**, keeping the v394 Gate line that
records what was actually run: *"overwriting it would falsify a session record for the
sake of tidiness… a reader who finds the v394 line and wonders whether it was ever true
now gets the answer in the next paragraph instead of an inconsistency."* Same call
CLAUDE.md's precedence rule makes about handoff notes, arrived at independently.

### 184e — THE SESSION DOCUMENTING HOW UNOWNED THINGS ROT SHIPPED TWO UNOWNED THINGS

frankD, 2026-08-30, on parking, unprompted and explicitly *"not a ticket and not a
request"*:

> *"`tools/docsnip.py` and `tools/doclinks.py` are named in no README, no CLAUDE.md, and
> nothing runs them but me. Two unowned tools shipped in a night I spent documenting how
> unowned things rot. They are fine today because I am the only reader."*

Verified: both appear **only inside progress tickets** — no live reference doc mentions
either. Now indexed in `devdocs/dev/differential-probes.md`, which CLAUDE.md points at,
under a new *Docs-verification probes* section; and that page's own "enumerate before you
trust this index" grep (`ls tools/ | grep -iE 'diff|probe|oracle|sweep'`) is noted as
**unable to match either name**, so the instrument for finding probes could not have found
these two.

Third instance of 184a in one session and the largest scale yet — not a section breaking
its own rule but **a whole night's work breaking it.** With 184c's correction that gives
the useful shape of both:

> Writing about a hazard protects the next sentence and **not the artefact.** Proximity
> in *time* helps; proximity in *kind* does not. The rule was about documents, the breach
> was in tools, and the author was the same person on the same night.

The fix is indexing, not diligence — consistent with everything in this index that works.


### 178b — THE INDEX'S OWN "ENUMERATE BEFORE YOU TRUST ME" INSTRUCTION WAS A WHITELIST

frankD, 2026-08-30, on the coordinator's fix rather than on its own finding — and it is
better than either. `differential-probes.md` carries the instruction *"This index is not
self-maintaining; enumerate before you trust it"*, with the enumeration being
`ls tools/ | grep -iE 'diff|probe|oracle|sweep'`. The coordinator, having found that
neither `docsnip.py` nor `doclinks.py` matches those words, **wrote an exception into the
grep.** frankD's objection:

> *"That grep is a whitelist of words someone already thought of, so it can only ever find
> tools named the way its author expected — the next tool with an unanticipated name lands
> in the same blind spot and earns its own exception. Inverting it is cheaper: enumerate
> `tools/*` and mark what is NOT indexed, so the default is 'visible until classified'
> rather than 'invisible unless named'."*

**This is 178 one level up** — a whitelist fails in two directions, and here the whitelist
*is the instrument prescribed for auditing the whitelist*. Patching it with an exception
fixes the two instances and leaves the mechanism.

**Measured before adopting, because the inversion has its own failure mode.** 15 indexed,
210 tools, 195 unindexed, **71 after dropping `devtest`** — mostly installers, generators
and `gate.sh`. That is noisy enough that it would have been killed on precision if it had
been proposed as a routine check (as one was earlier the same night, at ~35%).

**It found three real omissions anyway**, and they are not marginal: `pasmith_run.py`,
whose own docstring says *"differential driver for tools/pasmith.py"*; `optfuzz.sh`,
*"O-level SELF-differential fuzzer"*, belonging to a section this page already has; and
`pasmith.py` behind them. **All three are named in CLAUDE.md's Track T section** and were
absent from the index CLAUDE.md points at.

So the disposition is neither: **the whitelist stays as the fast path with an explicit
warning that a negative from it is not an answer, and the inversion is written down as the
audit path with its measured noise stated.** A check too noisy to run daily is not too
noisy to run once.

> **Do not filter the 71 cleverly. The filter is what created the blind spot.**

**The provenance of the catch is the transferable half, and both parties missed it
independently.** frankD, closing: *"Worth noting it came out of arguing about the METHOD
rather than the subject — I had no reason to think anything was missing, and neither did
you."* Nobody was auditing the index. The three fuzzers surfaced because two people
disagreed about **how to enumerate**, and running the disputed instrument to settle the
argument *was* the audit.

> **A method dispute is a free audit of the thing the method is about.** Neither side has
> to suspect the subject — the check gets run because each wants to be right about the
> instrument, which is the one motivation strong enough to make anyone actually run it.

Note this is the inverse of the standing warning that *the check gets spent on the
candidate you doubt, not the one you like*: here the doubt was aimed at a **method**, and
it paid out on a **subject** nobody doubted at all. Cf. 179a — the unchosen source
answering a question nobody asked, arriving from a third direction.

And frankD's refusal to take the obvious shortcut is the other half: it **declined to
rename the two tools** to match the grep's pattern, because *"their names are cited in
resolved tickets, and a citation that stops resolving is a worse defect than a grep that
needs an exception."* Making the artefact fit the instrument is always available and is
almost always the wrong direction.

### 189 — I ASSERTED AN ANCESTRY FACT THAT ONE COMMAND WOULD HAVE SETTLED

Coordinator, 2026-08-30. frankA suspected its own `MatchParamCompatible` narrowing was the
cause of the alias bug, and worried that this conflicted with frankB's measurement that the
same-unit arm fails on **both** pins. I resolved the tension by writing:

> *"Your narrowing is not in v393 — v393 predates tonight's work. So `same-unit fails on
> v393` cannot be your narrowing… two independent causes producing one error string."*

**Every clause of that is false, and the command that settles it is one line:**

```
8b75fcabd  08-28 00:46  fix(pfront): a class instance no longer binds a pointer-to-record parameter
d3f9dee6c  08-29 22:29  chore(stable): pin v393
$ git merge-base --is-ancestor 8b75fcabd d3f9dee6c   →  YES
```

The narrowing landed **a day and a half before** v393 and is in it. The pinned v393 binary
reproduces the same-unit repro with the identical error text. **There was never a second
cause to look for.**

**Third instance tonight of 138 on the coordinator's side, and the worst-shaped.** The
*conclusion* was right — both arms, and frankA fixed both — but it was reached by a false
argument, so it did not self-correct; it got broadcast to two lanes as settled reasoning,
with "third instance of face 178a tonight" attached to make it more convincing. **A wrong
premise decorated with a correct pattern is more durable than a wrong premise alone.**

The failure is not carelessness about git. It is that **"predates tonight's work" felt like
context I already had** rather than a claim needing a check — the same profile as every
unchecked relay in this index: plausible, load-bearing, and adjacent to something I
genuinely knew.

**What actually caught it was self-suspicion, and that is not a mechanism** (frankA, same
day, unprompted):

> *"I did not catch it by being sceptical of you. I went to check whether **my own**
> narrowing was the cause, because that was the uncomfortable possibility, and the ancestry
> check fell out of that. Had the story implicated someone else's commit instead of mine, I
> would very likely have taken it — it was well-formed, it named a real pattern, and it
> arrived from the session with the widest view."*

> **Self-suspicion only fires when the false claim happens to point somewhere the reader has
> a personal stake.** A relay that exonerates its recipient is checked by nobody, and this
> one *was* checkable in a single command. The command got run for a reason unrelated to
> doubting the relay.

That is the missing half of 138. The index has said for weeks that a wrong argument reaching
a right destination does not self-correct; this says **who** the correction depends on — not
the sceptic, but whoever the claim happens to accuse. The coordinator's relays are the worst
case, because a coordinator's account of events usually assigns cause to a lane *other* than
its reader.

**Corroborated from a source frankA did not choose**, because "your commit broke it" is
exactly the claim that should not be relayed unchecked: `gate.sh quick` ran **green,
including `-O3 backend parity`**, on the v394 pin commit `cc5e02d6c`, and
`git merge-base --is-ancestor 823f1c85b cc5e02d6c` says **NO** — the slice landed *after*
that pin. An independent green at a known sha, from a run made for another purpose entirely.

### 189a — ONE CAUSE, TWO ERAS: A FIX THAT MADE A GARBAGE CHANNEL DETERMINISTIC

The real mechanism, and it is worth more than the bug. `RegisterGeneralAlias` recorded
`AliasElemTk := tk` — conflating *"what kind is T?"* with *"what does T point AT?"*.
Invisible for non-pointer aliases because nothing reads the element; for pointer aliases
every general alias recorded a `tyPointer` element regardless of target:

| alias | recorded | correct |
| --- | ---: | ---: |
| `= Pointer` | 17 | 0 |
| `= PChar` | 17 | 3 |
| `= PRec` | 17 | 5 |
| `^Pointer` | 17 | **17 — right by coincidence** |

On v393 the overload symptom was **position-dependent**: alias formal at parameter index 0
accepted, at index 1 or 2 rejected, cross-unit accepted regardless. That is the signature of
a recycled-symbol read — the matcher reading a slot `SymRollbackTo` had handed back, which on
some paths happened to hold the untyped sentinel.

> **The p65 fix did not introduce this defect; it made a garbage channel DETERMINISTIC.** A
> shape-dependent wrong answer became a consistent one, so Synapse went from *accidentally
> passing* to *reliably failing.*

**A determinism fix converts intermittent passes into consistent failures and is
indistinguishable from a regression** — including to the person who wrote it, and including
to a bisect, which will land on it every time. The coordinator's "two causes" and frankB's
"cross-unit used to lose the alias" were **the same event described from opposite ends**,
and frankB's end was the closer one.

### 189b — THE THIRD SYMPTOM WAS THE SILENT ONE, AND THE LOUD TWO WERE MASKING IT

Three symptoms of the single conflation. Two were loud: `p^.field` through an alias of
pointer-to-record did not compile, and the overload rejection took Track B's gate red. The
third had no ticket and nobody had seen it:

> **`c[i]` through a `PChar` alias printed `378951523` instead of `pxx`** — on **v393**,
> silently, for the entire life of the defect.

Found only by varying the spelling across the boundary, which is 187's lesson paying out
directly and within the hour. The loud symptoms were not merely louder; they were **drawing
all the attention to a compile-time story about overload resolution**, while the same wrong
element type was quietly producing wrong *values* at runtime.

**Two controls that could have failed and did not**, both aimed at the vacuity trap:
`^Pointer` must **stay** 17 (an over-propagating fix would have made it the untyped
sentinel), and the `atpos` arm exists because a fix verified only at parameter index 0 would
have been tested exclusively on the shape that was **already green on the broken binary** —
the interned-literal vacuity of 187, recognised in advance this time.

### 189c — AN AGGRAVATOR IS NOT A CAUSE, AND THE FINDER SAID SO AGAINST ITS OWN INTEREST

`bug-a-tyunknown-is-both-untyped-pointer-and-i-read-garbage` [A p40] was frankA's own
ticket, and the coordinator had offered to re-price it as a live cause. frankA **declined
the promotion and narrowed its own claim**:

> *"The dual meaning is not why the alias was wrong. But it is why the stale read **failed
> open**: a recycled slot reading 0 means 'untyped pointer, permit', so the garbage was
> silently permissive rather than noisy. So the honest edge is 'made a wrong read
> undetectable', not 'caused the rejection'. I would not want it filed as the parent of
> this one."*

**That distinction is the whole value.** A dependency edge asserting cause where the truth
is *aggravation* inflates the parent's priority on false grounds and — worse — tells the
next reader the mechanism has been explained when it has not. The aggravator claim is still
serious: **failing open is why a wrong read survived two days and a pin.**

Process note from the same fix, same direction: frankA's first test header asserted each arm
had been individually verified on v393; on actually running them, the single-param overload
arm **passed** there. It corrected the header to the measurement rather than keeping the
tidier claim — **and that overclaim is what led to the position dependence**, so making it
visible was worth more than dropping it quietly.

---

## 190 — THE FIXEDPOINT PROVES SELF-CONSISTENCY, NOT THAT CODEGEN IS UNCHANGED

*(frankA, 2026-08-30, increment 1 of `--rtl-libc`, `b778c6078`.)*

Every lane on this fleet reads `make compiler/pascal26`'s `converged after N round(s)` as
"my change did not disturb anything". It does not say that. It says **the compiler
reproduces itself** — and a change that perturbs default codegen and perturbs it
*consistently* passes by construction, because the binary and the sources move together and
convergence is preserved. The gate's oracle is the artefact under test.

frankA checked the thing the gate cannot: emitted output of two test programs, **byte-identical
to the pinned binary's output**, and said outright that the fixedpoint would not have shown
it. That oracle is **disjoint** — a binary blessed before the edit, which cannot move with the
author.

> *"It proves the compiler reproduces itself, which is self-consistency, not that the default
> codegen path is unchanged versus before my edit."*

The general shape, and it is the one this index keeps arriving at from new directions:
**a check whose reference moves with the thing it checks is not a check.** Compare 184b (a
delta across a changed method is not a delta) — same defect, different instrument. The
remedy is the same too: hold one side fixed at a version that predates the work.

Note what this does *not* say. The fixedpoint is not weak; it is the cheapest possible proof
of the one property whose failure would poison every lane at once, which is exactly why
CLAUDE.md makes it mandatory. The error is reading a **narrow** proof as a **broad** one —
and it is invited by the fact that the line prints on success and says nothing about scope.
Same reading error as the `-O` scope note at the top of CLAUDE.md's claims table, arrived at
independently: *"it passes the self-host gate"* is evidence about **one property at one
optimisation level**, not about the compiler.

### 190a — an instrument that COULD NOT have failed accumulates evidence at zero rate

Same session, the `objdump` baseline. The check had been passing for a long time, and was
passing for a reason unrelated to its subject — frankA's term is a **host green**. The
asymmetry that makes it durable: **a red gets triaged within a day; a pass is never
re-examined by anyone.** So a dead check does not merely fail to catch things, it actively
*purchases confidence* — each run reads as another data point on a growing record, and the
record's growth rate is exactly the rate at which nothing is being learned.

Sibling of 186 (a swallowed failure in a timing harness reports a *speedup*) and of the
`cat-file -e` finding (a test that answers LIVE in the author's own tree because the objects
are still local). All three are instruments that answer a question adjacent to the one asked,
and all three answer it *reassuringly*.

### 190b — the one-command tell: a constant that never moves is stable or unmeasured

The cheap distinguisher, and the reason this one got caught at all. frankA re-derived the
baselines from scratch and **they had moved on their own** — 57 → 73, from ordinary RTL
growth. A number that has not changed in weeks is either genuinely stable or **not actually
being computed**, and those two states are indistinguishable in every report that prints it.

> **Re-derive the baseline. If it moves, the check is live; if it cannot move, you have
> found a dead one.**

This is worth running as a sweep rather than waiting to stumble on the next one: we almost
certainly have more, and the population is enumerable — every hardcoded expected value in
`tools/**` and `test/**` that no commit has touched in a month. Cost is one re-derivation
each. **Do not assume the ones that moved are fine either** — moving proves the number is
computed, not that it is compared.

---

## 191 — ASSERT ON POSITIVE OUTPUT THE SUBJECT EMITS, NOT ON THE STATUS OF WHAT RAN LAST

*(frankwasm, 2026-08-30, in reply to the coordinator's exit-status broadcast — and it is a
better statement of the fix than the broadcast was.)*

The coordinator had been relaying the **diagnosis** fleet-wide: `cmd > log 2>&1; tail log`
gives the exit status to `tail`; `{ …; cmd; echo "rc=$?"; }` gives it to the `echo`; `cmd |
tee` reports `tee`. General form: *anything appended after the thing you are measuring
becomes the thing that reports.* All true, and all of it invites the wrong remedy —
`PIPESTATUS`, `set -o pipefail`, restructuring the pipeline. Those fix the **instance**. The
class survives, because the next harness written under deadline grows a new tail.

frankwasm's version removes the dependence instead of repairing it:

> *"Assert on positive output the measured thing emits, not on the status of whatever ran
> last."*

Its own case: `make … 2>&1 | tail -3` **everywhere**, so `$?` was `tail`'s every single
time — the exact hazardous shape — and nothing broke, because no verdict ever rested on
`$?`. The verdict came from `self-host fixedpoint: verified — <sha>`, a line the build
itself prints. **A status can be overwritten by whatever ran last; a line the subject emits
cannot be printed by a subject that did not run.** And the property that does the real work:
**its absence is the tell.** There is no silent success to mistake for a silent failure.

Two conditions, or it degrades back into the same hole:

- **The subject must emit it, not a wrapper.** A harness printing its own "OK" after the
  step is the identical defect wearing a different hat — it is one more thing appended after
  the thing being measured.
- **Assert the line, do not merely display it.** `| tail` that *shows* the line and a grep
  that *requires* it are different checks; only the second fails when the line is absent.

Diagnostic question, corrected. **"Do you use pipelines?" is the wrong question** — frankwasm
used them universally and was fine. The right one is **"does any verdict rest on `$?` after
one?"** Pattern present, reliance absent, and only the reliance is the bug.

### 191a — a silent failure does not look neutral; it looks like the result you wanted

Three independent instances in one night, which makes it a property of the failure mode
rather than a coincidence:

| lane | silent failure | how it read |
| --- | --- | --- |
| frankA (186) | red run inside a timing harness | a **speedup** |
| frankB | aborted suite, 804 log lines and 141 artifacts unrun | "**one test fails**" |
| frankwasm | wasm build dies early | a **smaller module** — the hypothesis under test |
| coordinator | zero-init experiment segfaulted | **−83.9%** |

The bias has a direction and it is always toward the hypothesis. A run that stops early
produced less of everything — less time, less output, fewer failures, fewer bytes — and
*less* is what almost every experiment here is hoping to see. So the harness's own optimism
is not psychological, it is arithmetic: **the failure and the desired outcome are the same
measurement.** Which is why 191's positive assertion beats every negative one: "nothing went
wrong" is indistinguishable from "nothing ran", and only a line the subject emits separates
them.

---

## 192 — A DERIVED FIGURE AND ITS UNDERLYING ROWS ARE TWO MEASUREMENTS, AND THEY CAN DISAGREE

*(frankS, 2026-08-30, correcting its own "zero matches lost" evidence while the claim itself
survived.)*

frankS had reported a record fix as losing zero matches, *"computed as a set difference in
both directions, not from the totals"* — which is the strong form, and the coordinator
accepted it as such. It was right. The **file it was computed from** was not.

Root cause, and it generalises well past one harness: `sweep_rv.py` defaulted its ABI tag to
`call0`, which is `sweep.py`'s **xtensa** tag. Both write `xd/<tag>.<abi>.tsv`. Running both
legs under one run tag therefore produced a single file whose **header counts were xtensa and
whose rows were riscv32**. A set difference against it said 13 matches had regressed; nothing
had. It was diffing xtensa against riscv32.

**A file whose two halves come from different subjects is not corrupt in any way a reader can
see.** Every field is well-formed, the row count is plausible, and each half is internally
correct. Nothing short of comparing the halves against each other detects it.

frankS's own statement of the lesson, which is sharper than "check your tools":

> *My set-difference discipline was right and it is what makes the "zero lost" claim strong —
> but it reads a second file, and a second file is a second thing that can be wrong.*

That is the cost nobody prices. Upgrading from a total to a set difference **strengthens the
inference and adds a failure mode at the same time**, and the added failure mode is silent
where the weaker method's was not.

### 192a — the catch was ARITHMETIC, not suspicion, and that is why it worked

**13 lost and 6 gained cannot produce a +1 total.** The derived figure and the row set
disagreed, and only one of them could be right.

This is the part to copy. Vigilance is spent on the candidate you already doubt (the standing
finding in `coordinator-operating-rules`), so a check that depends on someone being sceptical
at the right moment protects the wrong thing. A check that is **one subtraction** does not:
it fires on the numbers, at zero cost, on every run, including the runs where everyone was
confident. **Whenever you have both a total and the rows behind it, subtract.** They were
computed by different code paths and their agreement is free evidence — while their
disagreement is the only signal that would ever have surfaced this.

Generalisation of the trigger, from frankS's second confusion the same session (a stale
reused binary path in its own loop read as three targets returning empty output): **a result
that is worse than possible is a harness bug until proven otherwise.** Implausibility is a
cheaper trigger than "does this look right", because it fires on arithmetic rather than on
judgement — and both of frankS's harness-vs-subject confusions that night were caught by the
result being *impossible*, not by it being *bad*.

Companion to 190b: there, re-deriving a constant tells you whether the check is alive; here,
subtracting a total from its rows tells you whether two live measurements agree. Both are
one command, both run without suspicion, and both were found by workers auditing their own
evidence rather than their own conclusions.

---

## 193 — A CAVEAT THAT ENDS IN A FULL STOP IS THE ONE TO CHECK

*(frankD, 2026-08-30, sweeping every limitation sentence in `devdocs/dev/*.md` — all passed,
and the reason they passed is the finding.)*

This index has said repeatedly that **a false limit is quieter than a false fix and survives
longer**: a wrong instruction gets re-tested by whoever follows it, while a wrong *caveat*
gets believed, reads as conscientious, and stops anyone re-checking. True, and useless as a
sweep — verifying a limitation costs a measurement per sentence, so nobody runs it.

frankD found the cheap proxy. Every limitation that survived its sweep **pairs the limit with
the instrument that gets past it, in the same breath**:

| the limit | the escape route, in the same sentence |
| --- | --- |
| *"`crtl_decl_probe` has no oracle"* | it is a **census**; `readelf -d` is the check |
| *"from outside there is no way to tell whether the ranges drifted"* | `PXXDBG=a.srcmap:*` — settled it in one run |
| *"no way to tell which you are holding from the report alone"* | record the `-O` level the way you record the sha |

**A bare limit is the dangerous shape; a limit with a named escape route defuses itself** —
the reader who wants past it is handed the way past instead of being told to stop. So the
sweepable question is not *"is this limitation true?"* (expensive, one measurement each) but
**"does this limitation say what to do instead?"** — visible at a glance, greppable, and it
selects exactly the population worth the expensive check.

> **A caveat that ends in a full stop is the one to check.**

Why the proxy is sound rather than merely convenient: an author who has actually *tried* to
get past a limit knows what the way past would be, and says so. An author who is reporting a
limit they inferred rather than hit has nothing to name — so the missing escape route is
evidence the limit was **reasoned, not measured**, which is the exact provenance that makes a
caveat wrong. The proxy is not a heuristic about writing style; it is a trace of whether the
claim came from an experiment.

Companion to 190b and 192a — the third one-command check found in a night, and like both of
those it was found by a worker auditing its **own evidence** rather than its own conclusions.
Table in `devdocs/dev/README.md` §4.

### 193a — an unfiled grant makes the board RE-OFFER work that is already done

The discharge of `grant-devdocs-dev-audit-to-frankd-time-boxed-report-only` is the mirror of
the rule that produced it. The grant was issued verbally, not filed; the sweep ran; the grant
was *then* filed, citing that sweep's own findings as its rationale — and the board, which
had never seen the first issue, offered the completed work as a fresh ticket. The coordinator
dispatched it. **Second instance the same night.**

> *A coordinator's memory of a verbal grant and the board's record of it are two instruments,
> and only one of them is queryable.* — frankD

Same structure as 192 one level up: two measurements of the same fact, silently diverged. And
the standing rule about unfiled grants was only half right. It said an unfiled authorisation
**reads as covered**, because a neighbouring ticket covers the same file — the risk being that
someone acts unpermitted. This is the other half: it also reads as **not yet done**, so the
board spends a dispatch re-offering it. **File the grant at the moment it is given**; a
coordinator's recall is not a record, and this seat's context is destroyed and rebuilt while
the work it tracks continues.

---

### 191b — an improving metric is not a passing test

*(frankA, 2026-08-30, increment 2 of `--rtl-libc`: written, measured, and reverted.)*

The choke-point conversion worked exactly as designed and produced the most attractive number
of the night:

| program | raw | increment 1 | increment 2 |
|---|---:|---:|---:|
| hello-world | 73 | 67 | **9** |
| file I/O + heap + string + exceptions | 195 | 105 | **9** |

**The second program segfaulted.** frankA's own note is the face:

> *"A syscall count of **9** was the most attractive number of the night while the binary was
> broken. I would have believed 9 if I had not also been diffing the output."*

191 says to assert on positive output the subject emits. This is *why* it is stronger, and it
sharpens the reason: the danger is not that a failure looks like nothing, it is that **a
failure looks like the number you were hoping for** (191a) — and a *metric* is precisely the
instrument that cannot tell them apart. 9 syscalls is what a working libc route and a dead
program both produce. What separated them was `heap sum 2997`, a positive output the program
emits and a segfault cannot forge.

So: **a metric is never the verdict.** Pair every count, timing or size with one positive
output the subject emits. The metric tells you how well it went; only the output tells you
that it went.

---

## 194 — THE LANDMINE IS NOT IN THE CODE THAT CRASHES, AND GROWING AN EMITTER ARMS IT

*(frankA, same session; filed as `bug-a-a-rel8-jump-patch-truncates-silently-when-its-span-grows`
[A p55], landed `d066764fa`.)*

`Code[p] := Byte(CodeLen - (p + 1))` — the rel8 patch idiom, ~30 sites across `symtab.inc`,
`ir_codegen.inc`, `exception_emit.inc`, `emit.inc`. `Byte()` truncates. **No range check, no
diagnostic.** Past 127 bytes of span, a forward jump becomes a **backward** one, landing in
the middle of an instruction.

Nothing is wrong with the code today: no current emitter spans 127 at those sites, so the
default build is correct and always has been. It is **armed by growing an unrelated emitter**
— an ordinary, safe-looking act — and when it fires, the binary crashes somewhere else
entirely with the responsible emitter nowhere on the stack. `--rtl-libc` tripped it first only
because growing `EmitSyscall` from 2 bytes to ~140 is the largest single emitter growth
anyone has attempted here.

**How it was found is the transferable part: a structural tell, not a hypothesis.** `rip`
faulted at `0x411115`, which is **inside** the 7-byte instruction at `0x41110f` — and a
mid-instruction `rip` cannot arise from linear execution, so it is not a clue, it is a
*proof* that control arrived by a bad jump. That converted an open-ended search into an
enumeration: scan the executable segment for any rel8 jump targeting that address. Exactly one
hit, `jns` at `0x41115e`, displacement **−75**; intended forward span **181**; `181 − 256 =
−75`. **Arithmetic, not a story** — the same closing move as 192a.

**Two wrong guesses preceded it and are in the ticket rather than tidied away**, each costing
a rebuild and each of the kind that sounds right: (1) the pushes clobber the 128-byte red zone
— added `sub/add rsp,128`, changed nothing; (2) the C call destroyed `rbp` — a breakpoint
showed **`rbp` was already nil on arrival**, so the new code never touched it. Recording the
refuted guesses is what makes the ticket cost the next reader two rebuilds less.

**The redesign is the right generalisation and did not wait for the bug to be fixed:** emit a
`call` to one shared out-of-line thunk. `EmitSyscall` emits ~5 bytes instead of ~140, so no
rel8 span moves and the landmine is not tripped — and the ~140 bytes exist once instead of at
43 sites. Smaller, faster, and it routes around a latent defect without depending on its fix.

**Who needs to know, beyond A:** Track O. O's entire campaign is *changing and growing
emitters*, which is the exact act that arms this. A peephole that adds four bytes in the wrong
place is indistinguishable, from the outside, from a miscompile.

---

## 195 — REPAIRING THE VISIBLE DEFECT RETIRES THE ONLY DETECTOR FOR THE INVISIBLE ONE

*(pxx-a5, 2026-08-30, on `tools/progress_stale_edge_devtest.py`. Measured, not supposed — the
control was run.)*

The devtest was red for a **real, provable** reason: `65a63f0d2` rewrote `check()`'s aperture
note from *"reads FRONTMATTER only"* to *"reads FRONTMATTER; STALE-PARK reads PROSE …"* and
left the devtest asserting the old literal. Exact string present at `65a63f0d2~1`, absent at
`65a63f0d2`. One-line repair.

**Underneath it, a second defect, invisible:** `_board()` set `pg.PROG` to a throwaway tree,
built the `Board`, and restored `PROG` in a `finally` **before `.check()` ran**. `Board()`
captures tickets at construction — so every assertion on `self.by_status` read the fixture,
while the `DUP-SLUG` / `NO-FRONTMATTER` / `NEAR-DUP` half of `check()`, which walks `PROG` on
disk at call time, read the **live repo**.

**Half the function under test saw the fixture and half saw master — invisible for exactly as
long as master happens to be clean.** (It carries six near-duplicates right now.)

**The two defects shared a single detector, and it belonged to the visible one only by
coincidence.** The leak was caught by a dumped `out` in an assertion message — an accident.
Repair the wording and the accident retires with it. pxx-a5 measured that rather than
supposing it: leak reinstated, repaired assertion in place, **file reports OK**.

> **A fix that makes a test pass can delete the only reason that test was ever going to fail
> for a different cause.** Nothing about the repair looks wrong. It looks like tidying.

And the sharpest detail: **the least deliberate line in the file was the load-bearing one.** A
debug dump nobody designed as a check was the entire detection surface for a fixture leak.

### 195a — the repair that is safe: assert the property directly and state-independently

The new ninth guard does not restore the accident; it makes the property explicit, and both
halves matter:

- a **synthetic near-dup pair in the fixture IS reported** — so the negative cannot be
  satisfied by a scan that reads nothing. That is *a control that has failed once*, which is
  the only kind that counts.
- on a clean fixture, **no finding names any file outside it** — which holds whether or not
  master carries near-duplicates, i.e. the assertion no longer depends on the state of a tree
  it does not own.

Sibling defect found in the same pass, and it is 190a wearing a name badge: the guard called
*"including on a clean board"* **had never once run against a clean board** — the fixture
rendered no `BOARD*.md`, so every run produced three `NO-BOARD` findings. **A guard whose name
asserts the coverage it lacks is worse than an absent one**, because the name is what stops
anyone writing the missing guard.

### 195b — a failure message can be true about a real thing and unrelated to the failure

The red's message named a `NEAR-DUP` between two **genuine** backlog tickets that had nothing
to do with the devtest — leaked in from the live repo. Extends 187a: a repro built from a
failure message inherits that message's error, and here the message was **not wrong**. It was
accurate, checkable, about real files, and pointed at work nobody needed to do. **A false lead
that checks out is more expensive than one that does not**, because verifying it confirms it.

---

## 196 — EACH HALF IS FASTER AND THE WHOLE IS 83× SLOWER

*(frank-optimize-b4, 2026-08-30, on `regression-test-threads-test-static-string-literals`,
auto-filed by T as a timeout.)*

```
full test, aarch64 -O0:   1.193s
full test, aarch64 -O3:  99.083s      <- 83x SLOWER at a HIGHER -O level
```

**Output is correct at both levels.** Nothing but a timeout could ever have fired — no wrong
value, no crash, no diagnostic. The only instrument that noticed was a clock with a deadline
on it, which is why this reached the board as a *tier* complaint rather than as a bug.

And the bisect refuses to localise:

| measured alone | −O0 | −O3 |
|---|---:|---:|
| the 200,000-iteration loop row | 1.111s | **0.295s** |
| the other seven rows | 0.039s | **0.019s** |
| all eight together | 1.193s | **99.083s** |

**Every part is faster; the whole is 83× slower.** So it is an *interaction*, and the standard
tool — remove things until it goes away — is structurally unable to find it, because removing
either side removes the interaction. A halving search assumes the defect is *in* a half.

This is the performance twin of 187: **a population that cannot contain the disagreement is
not weak evidence, it is zero evidence** — and here each individually-faster row reads as
*exonerating*, which is worse than uninformative. Two greens that jointly produce a red is a
shape the whole toolkit is blind to.

Recorded before the mechanism is known, deliberately, because the *measurement* is the durable
part and the story is not; b4 has said it will report the mechanism and not just the fix.

### 196a — b4 withdrew its own promotion recommendation on evidence from a different architecture

b4 had reported the case for promoting this pass to `-O2` as strong. It was — **on x86-64**,
where the same full test is 0.008s at `-O3`. The aarch64 measurement did not weaken that
evidence; it revealed the evidence had a **scope nobody had written down**.

> *"I said the case for promoting was strong. That was x86-64 evidence, and this is aarch64.
> Treat the promotion as withdrawn until this is understood."*

The failure mode this avoided is the expensive one: a recommendation whose supporting numbers
were all real, all correctly measured, and silently about a **subset** of the population it
was applied to. Compare the standing rule about surveys that do not name their own scope, and
190's `-O`-level scope note — three arrivals at one idea from three directions. **A
measurement carries its configuration or it carries nothing**: architecture, `-O` level,
build flags, host.

Note also which direction the correction ran. A worker retracting **its own** recommendation
on evidence it went and found is the strongest correction available in this system, and it is
the second time in one night (frankA killed its own defer-bodies recommendation with a
59/28/13 decomposition). Both were *cheaper* than the alternative, because a wrong promotion
lands in `-O2`, becomes the proven default, and is then measured by everyone as the baseline.

### 196b — the near miss it produced, and the checklist item that follows

Reading frankA's rel8 warning (194), b4 checked its own recent work and found it had come
close twice: `EmitStaticLitHandle` grows an x86-64 emit site from a 2-instruction setup plus a
call into a 10-byte `mov rax, imm64` plus a 4-byte `inc`, **at eight sites, several inside
branchy argument-marshalling code with `Code[p] := Byte(…)` patches around them.**

> *"It did not fire, but I did not check either — I checked the **semantics** of every site
> and never the **span**."*

That is the whole hazard in one sentence, and it is not carelessness: **span is not a property
anyone reviews, because it is not a property of the code being changed.** It is a property of
the *distance between two other things*, and it changes when you are not looking at either.
Checklist item for any emitter growth, now stated once so it is not re-derived: **when an
emitter grows, ask what rel8 patches span it** — and the tell if it has already fired is `rip`
(or `pc`) at a **mid-instruction address**, which cannot arise from linear execution.

---

## 197 — THE INSTRUMENT PRINTS ITS OWN SCOPE ONLY WHEN IT HAS NOTHING TO REPORT

*(pxx-a5, 2026-08-30, running 190b's sweep — and the first thing it found was its own file.)*

Method, and it is the reusable part: **run every devtest that touches a Makefile against a
scratch tree with an empty `Makefile` and an empty `test/`.** A guard that passes over nothing
is a guard that was never measuring anything. 19 candidates, 12 passed the empty tree, 10 of
those correct by construction (they name the Makefile only in prose, or build their own
`mkdtemp` fixture). **Two were real.**

### The one that matters

`tools/test_wiring_gate_devtest.py` — **pxx-a5's own file, written earlier the same session** —
**passed GREEN against a tree containing zero test files.** Its whole assertion is a negative,
and *a negative over an empty population is worth nothing* (187, arriving from the emptiness
side rather than the interning side).

**But the root cause was one level up, and it is the face.** `check_test_wiring.py` printed
its population count **only inside the all-clear branch**. So:

| state | what it printed |
|---|---|
| nothing wrong | `scanned N test subjects` — the count, i.e. the proof it looked |
| **one advisory live** | the advisory, and **no count at all** |

**The instrument disclosed its own scope exactly when its scope was not in question, and went
silent about it the moment there was a finding to weigh.** That is backwards in the precise way
that is hardest to notice: nobody audits the output of a clean run, and the run you *do* read
is the one that has quietly stopped telling you how much it looked at. A finding without a
denominator is unreadable, and this arranged for the denominator to be absent exactly when a
finding existed.

Sibling of 190a (an instrument that could not have failed) and of the standing rule that
**a survey will not name its own scope** — but sharper, because here the scope reporting was
*present and correct* and merely attached to the wrong branch. No line was wrong. The `if` was.

### 197a — a collapse detector is not a ratchet, and the difference is what makes it survive

The repair: move the count out of the branch; the devtest now parses `scanned N test subject`
and **fails below a floor of 250, against a live value of 2830.**

That gap is deliberate and pxx-a5 was explicit about why: **a tight bound there would fire on
every ordinary week of test-writing.** A guard that cries wolf earns the habit of being
scrolled past — and a scrolled-past guard is worse than an absent one, because its name still
claims the coverage. So the floor is set to catch **collapse**, not drift: it answers *"did the
scanner stop seeing the corpus?"*, which is the failure this bug actually was, and declines to
answer *"is the corpus the size I expect?"*, which nothing can answer without a maintainer.

**Name the question a bound is for.** A number chosen for feeling safe is the one that gets
disabled six weeks later.

### 197b — a label can describe a measurement the check is not making

Second real finding: `exit_observable_devtest.py`'s label read *"cross-target differential rows
are still ~536"* while **measuring 561**, behind a floor of **500** that could never have
noticed the drift. Three numbers, one check, no two of them agreeing — and every run green.

This is 192 (a derived figure and its rows are two measurements) applied to **prose**: the
label is a third measurement, asserted once at writing time and never re-derived, and it is the
one everybody reads. The floor is what fires; the label is what a human believes. **When they
disagree the label wins the argument and loses the truth.** Corrected the label; left the
escalated 531 stdout-only ratchet alone, which is right — that one is a live ratchet doing its
job and is not the same instrument.

---

## 198 — A SYSCALL NUMBER IS TWO FACTS: THE NUMBER AND THE SIGNATURE

*(frankS, 2026-08-30, landing the riscv32/xtensa `PXXSys*` arms — and walking into a trap it
had built itself.)*

When frankS filed the wrapper ticket it included a **measured** table of syscall numbers, so
nobody would re-derive them. Good practice, and the numbers were right. Beside them it wrote,
of rv32 `lseek`, that 62 *"is the `_llseek` split-offset question the existing riscv32 block
already documents — for source loads the plain form is what qemu-user tolerates"*, taken from
a comment in `platform_backend.pas`. It then implemented from its own table:

```
openat(AT_FDCWD,"test/hello.pas",O_RDONLY) = 3
llseek(3,0,2,NULL,UNKNOWN)                 = -1 errno=22 (Invalid argument)
read(3,0x2b2ad050,-22)                     = -1 errno=14 (Bad address)
```

**rv32 has no plain `lseek`.** 62 is `_llseek(fd, hi, lo, loff_t *result, whence)`; the 3-arg
form leaves the result pointer NULL, the size comes back −1, and `LoadFile` publishes an
**empty string with no error raised** — *the exact silent-wrong-value failure the ticket was
written to prevent, reached through the ticket's own guidance.*

> **A syscall number is two facts. My table was careful, correct, and covered one of them.**

And that is the mechanism: **because the numbers were measured, the table read as sufficient**,
so the *signature* — arriving from untested prose in a comment — inherited the credibility of
the measurement sitting next to it. A correct artefact is not a checked artefact. Compare
191b: an improving metric is not a passing test; here, a **right table is not a complete
answer**, and its rightness is what stopped anyone asking what else the question had in it.

The tell was one `strace` away the entire time. The fix was to mirror `PalBackendSeek`, which
has carried the correct split **in that same file** all along — the implementation was fixed
and the constant block's comment was not, and the stale one is what a reader meets first
because it sits beside `SYS_lseek = 62`. Filed as
`bug-b-platform-backend-rv32-comment-claims-plain-lseek-is-tolerated` [B p30]: **a comment
asserting a runtime behaviour is a claim, and that one was falsifiable in one `strace`.**

### 198a — `err[-1]`: the tool reported something ADJACENT to the truth

frankS's CFAIL sweep recorded `err[-1]`, the **last** line of compiler output. **A compiler
prints the cause first and token-context tails after.** So every CFAIL detail classified in
that sweep was the wrong line — and worse, the sweep **invented families that do not exist**
("6 × events") out of token fragments that happened to repeat.

> *The tool reported something adjacent to the truth, which is far more expensive than a tool
> that reports nothing.*

Third harness defect in two sessions, same family as the swapped baseline file (192) and the
stale binary path. A tool that reports nothing gets fixed the day it is noticed. A tool that
reports something plausible **gets built on**, and the structures built on it — here, a
partition and a set of invented failure families — look like findings.

### 198b — the conclusion was right and the evidence was wrong

frankS had recorded 6 scheduler/event programs as CoSwitch-blocked. Their **first** error is
actually `undefined variable (SYS_gettid)` — `scheduler.pas` defines `SYS_gettid`/
`SYS_exit_group` for four targets with **no terminal `{$else}`**, while its sibling
`palthread.pas` has one. frankS added the constants locally to find out, and all 6 then go
straight to `unsupported node in IR codegen: coswitch`. **So the conclusion held and the
evidence for it did not**: the constant gap is real drift, buys zero programs, and is masked
behind CoSwitch.

This is the shape the index has flagged before from the coordinator's side — *a right
destination reached by a false argument does not self-correct*, because the destination keeps
looking justified. The correct disposal is what frankS chose: a line in the CoSwitch ticket
(whoever takes it hits the constant gap immediately), not a ticket of its own.

---

## 199 — A SEARCH WHOSE EVERY PROBE REPAIRS THE THING IT IS PROBING

*(frank-optimize-b4, 2026-08-30, solving the 83× of face 196. Filed as
`bug-a-a-hot-write-to-a-data-page-that-shares-with-code-costs-1600x-under-qemu` [A p45].)*

**The quantity was an address.** `elfwriter.inc` emits one RWX `PT_LOAD` with data immediately
after code, so the boundary page holds both — and a static string literal's **refcount word
can land on the same 4 KiB page as translated code.** A qemu-style emulator invalidates its
translations when the guest writes to a page it translated code from, so a loop writing that
refcount re-translates the code beside it **every iteration**.

```
SLOW (aarch64 -O3):  rc word 0x420ea8 -> page 0x420000 ; highest proc 0x420710 -> 0x420000  SAME
FAST (+75 KB code):  rc word 0x433418 -> page 0x433000 ; highest proc 0x42bc50 -> 0x42b000  different
```

| binary | static blocks | rc on a code page | time |
| --- | --- | --- | ---: |
| x86-64 −O3, **native** | yes | yes | 0.009s |
| x86-64 −O3, under **qemu** | yes | **yes** | **14.661s** |
| x86-64 −O2 under qemu (rc on heap) | no | — | 0.435s |
| x86-64 −O3 **padded** under qemu | yes | **no** | **0.118s** |

Not an aarch64 defect: **x86-64 has it too, at 1600×, on the binary that runs in 0.009s
natively.** And the padded −O3 build is *faster than the −O2 build that has no static blocks
at all* — so the pass was never the problem; the address was.

**Why 196's bisect could not work, sharpened past "halving removes the interaction":**

> *Removing rows shrinks the code, which moves the data, which moves the literal off the page.
> The bisect was not a passive observer; the act of bisecting **was** the fix, applied
> silently, in both directions.*

Every subset was faster because **every subset relaid the binary.** That is a category worse
than an exonerating measurement: it is a **search whose every probe repairs the thing it is
probing**, so the search is guaranteed to terminate with "no row is responsible" no matter
where the fault lies. Reduction, delta-debugging and bisect all assume the probe does not
perturb the subject. Anything sensitive to **layout** — code size, alignment, address, cache
set, page boundary — breaks that assumption silently.

**The counter-move is the one b4 used: hold size constant.** The padded build keeps every row
and changes only the literal's page. That is a probe that varies one thing, where removing a
row varies two.

### 199a — the watcher auto-closing it was the cliff's SIGNATURE, not its absence

Mid-triage, T auto-closed the regression: `0f0a5619a413` passed after `5bb3e120d3f7` was red,
**with nothing fixed in between**. That reads as a flake and is the opposite — **any commit
that changes code size flips which page the literal lands on.** So a fresh NEW-RED stub for
this source is *the same finding with a new range*, not a second bug, and b4 wrote that into
the closed ticket so the next reader does not re-triage from scratch.

Generalisation: **for a layout-sensitive defect, spontaneous red↔green transitions across
unrelated commits are diagnostic**, not noise. The flakiness *is* the fingerprint.

### 199b — the second scope correction, and native was the configuration that could not show it

b4 had told the coordinator *"x86-64 is unaffected as far as I can measure"*. True, and the
scope was wrong in exactly 196a's way — it could only measure **natively**, and **native is
the one configuration in which this cannot appear**. Under emulation x86-64 is affected
*worse* than aarch64.

Same worker, same night, second time: a real, correctly-taken measurement silently describing
a subset of the population the claim was applied to. The `-O2` promotion stays withdrawn and
now for a better reason — promoting would put a mutable word beside code in **every** binary
at the proven default.

**And the honest tier fix, stated as such.** The loop count is now
`{$ifdef CPUX86_64} 200000 {$else} 2000`, aarch64 −O3 back to 1.07s. b4 did not hide the
cliff: the static refcount starts at 2^30, so **no reachable iteration count could ever prove
the reference is taken** — it was a smoke row all along. The proof that the test was not
weakened is that **all four arms still produce byte-identical output against one expectation**;
if the count were being asserted, they could not.

---

## 200 — THE REPORTING HALF DRIFTS FROM THE DECIDING HALF, AND NOTHING COUPLES THEM

*(pxx-a5, 2026-08-30, `8ab56be6e` — the second instance of 197's shape found within the hour,
in the fuzz rate limiter itself.)*

One mechanism, two halves, **two files with no import between them**:

- **deciding**: `twatch.open_actionable_count()` sets the backoff, and already discounts
  `NONACTIONABLE_CLASSES = {"fpc-self"}` — an external bug can never be resolved locally and
  would otherwise pin the fuzzer in permanent backoff.
- **reporting**: `pasmith_run.ledger_status()`, what a human reads, printed unconditionally:

```
22 finding(s), 7 open. Fuzzing is throttled while any are open
```

**Both halves of that sentence are false.** Every throttle-relevant entry in the published
ledger is class `fpc-self`, so the deciding half computes **0**; and the 7 counts rows that the
table *on the same page* labels `ticketed`. **The summary and the table disagreed about the
same rows, one screen apart.**

197 went silent about its denominator. This one **asserted a number that was governed
elsewhere** — the more dangerous of the two, because silence at least prompts a question.
Common family: *the reporting half of a mechanism drifting from the deciding half, with nothing
structural keeping them honest.* Two files, one behaviour, no import — the coupling existed
only in whoever wrote both.

### 200a — the polarity that MANUFACTURES work

191a says a silent failure looks like *the result you wanted*. This is the mirror and it is not
covered by that:

> **It was false in the direction that manufactures work.** A reader triages five FPC
> optimizer bugs to un-throttle a fuzzer **that is already at full speed** — and no pxx commit
> can retire any of them.

And the state actually worth knowing was the one it hid: *every `pxx-vs-fpc_*` signature fixed,
nothing throttling, full speed.* So the error cost twice — invented a queue of unfixable work,
and concealed a genuinely good result that would have redirected the effort.

Both polarities share one cause: **a report is a claim, and nobody re-derives a claim that
reads as routine.** The optimistic direction stops you looking; the pessimistic direction sends
you somewhere useless. Neither announces itself.

### 200b — refusing to collapse two questions that share one table

The fix left `ledger_open()` **deliberately unchanged**, and the reasoning is the transferable
part: it is *also* the recheck population, and `fpc-self_trace-length` reached `fixed` through
exactly that path.

> *"Can the fuzzer trip over it" and "does it hold the fuzzer back" are different questions
> over one table. The defect was answering the second with the first — and collapsing them the
> other way would have lost a real transition.*

The tempting fix (make `open` mean what the throttle means) would have been a **second**
instance of the same defect, in the opposite direction, and would have retired a path that had
already paid for itself. Compare 187b: the two-guard split was the same defect committed inside
its own fix. **When one table answers two questions, name both; do not pick a winner.**

### 200c — a guard that survives its own negative control needs its SCOPE written down

8 guards, `pasmith_ledger_throttle_devtest.py`, with the empty-tree discipline applied: emptying
`pasmith_run`'s copy of the constant turns **3 guards red**; restore is sha-identical at **0
red**. **Guard 8 stays green under that control** — it checks the report against the *computed*
number, which stays consistent when both drift **together**.

pxx-a5 did not delete it. It wrote into the docstring that **guard 1 is the correctness anchor
and 8 is only consistency**:

> **A guard that survives its own control needs its scope written down, not deleted.**

That is the correct third option, and it is the one nobody reaches for — the reflexes are
"strengthen it" or "drop it", and both destroy information. A consistency check is real and is
*not* a correctness check, and the failure is leaving a reader to assume which one it is.
Sibling of 190a (an instrument that could not have failed) with the opposite disposal: 190a's
check was dead and should go; this one is alive and merely narrow, so it gets a label.

Guard 1 itself is the right shape too — it asserts the two files' constants are **equal**, by
parsing `twatch` with `ast` rather than importing a daemon for one constant. That equality is
the **only** thing coupling the two halves, so it is the whole guard.

---

## 201 — A UNIFORMLY WRONG COMPILER REPRODUCES ITSELF PERFECTLY

*(frank-optimize-b4, 2026-08-30, catching the obvious version of its own page-align fix before
writing it — the first live worked example of 190's blind spot.)*

The obvious fix for the shared-page hazard (199) is `dataBase := AlignTo(dataBase, 4096)`. It
is wrong, and wrong in the quietest available way.

There is **one `PT_LOAD` with `p_offset = 0`**, so a virtual address *is* `LOAD_ADDR + a file
offset`: `dataBase := LOAD_ADDR + codeOffset + CodeLen`, with the data's file offset being
`codeOffset + CodeLen`. Aligning the **vaddr alone** desynchronises the two, and every emitted
data reference then reads **0..4095 bytes early**. Silent wrong values throughout every
emitted program.

> **And it would sail through a self-host fixedpoint, because the compiler would be wrong
> *consistently*.**

That is 190 stated as a principle and here demonstrated: the fixedpoint proves the compiler
reproduces **itself**, and a uniformly-wrong compiler reproduces itself perfectly — the binary
and its sources move together, convergence holds, and `converged after N round(s)` prints. A
gate whose oracle is the artefact under test cannot see a *uniform* defect at all. Only a
disjoint oracle can: an older binary, a second implementation, or reading the ELF header.

The correct change pads **`Code[]`** until `codeOffset + CodeLen` is itself a page multiple, so
vaddr and file offset stay congruent and `dataBase` lands on a page for free. Sufficient at all
three sites because `LOAD_ADDR = $400000` and `LOAD_ADDR32 = $08048000` are both page-aligned.

Corroboration worth noting for its **provenance**: frankA independently read the same layout
out of a binary for an unrelated reason — one RWX `PT_LOAD` at `0x400000`, file offset 0,
`0x00fedd` filesz / `0x01a4b4` memsz, data immediately after code, **VA == file offset**. Two
lanes, two binaries, two purposes, same header. That is what corroboration is supposed to look
like, as against two arms sharing an upstream.

### 201a — declining is not automatically the conservative choice

b4 had declined the better of its two fixes because it believed `elfwriter.inc` was held. It
was not, and b4's own reading of why it did not simply ask:

> *"Declining is not automatically the conservative choice when it silently downgrades the fix;
> it just moves the cost somewhere it does not get counted."*

The asymmetry is structural: **a wrong action leaves a trace and a declined action leaves
nothing.** A bad edit gets reverted, ticketed, and remembered. A fix quietly downgraded to its
weaker variant produces a commit that looks fine, and the better version simply never exists —
no artefact, no ticket, nothing to audit. So over-caution is **invisible by construction**,
which is exactly why it feels safe.

Companion to the manufactured-work polarity (200a). Both are errors that cost real work while
producing no evidence that anything went wrong.

### 201b — a negative stated from ONE idiom

Same hours, frankA sizing increment 3. It built its emitter list by grepping the byte-pair
idiom `EmitB($0F); EmitB($05)` and concluded four files. **The grep was blind to an entire
family**: kernel entries emitted as a **mnemonic string** through `EmitAsmX64([… 'syscall' …])`
— **17 of those in `ir_codegen.inc` alone**.

What caught it was not suspicion. frankA disassembled the actual binary instead of trusting the
list, and **site 1 turned out to be `ir_codegen.inc:928`, a line its own enumeration said did
not exist.** Standing rule, third instance in two days: *an existence claim survives one grep;
a non-existence claim does not.* And the specific form here — **a negative stated from one
idiom** — is the version to watch, because one idiom is what a grep *is*. Same shape as the
`+ '$' +` search that could not see a name built with `AppendChar`, and as `err[-1]` reading
the wrong line of compiler output.

The cheap defence is the one that worked: **enumerate from the artefact, not from the source.**
The binary contains every site by construction; a grep contains every site that matches one
spelling.

### 201c — a coordinator relaying a PLAN as a fact about the tree

Mine, twice in one night, and the second one caused work. I warned two lanes that
`EmitProgramEntryForTarget` was about to be contested, on the strength of frankA describing
increment 3 as *"the `_start` stub plus…"*. I located the stub correctly; the premise was a
lane's **plan**, which frankA then corrected (see 201b) — the seam is `x64_syscall` in
`x64enc.inc`, and none of the residual sites is the entry stub.

**A plan is a claim about the future by someone who has not measured it yet**, and it does not
acquire authority by passing through the coordinator. Worse, the warning I attached carried
three conditions — shorten your window, tiptoe around the arm boundary, land in a hurry — and
**a withdrawn constraint that nobody withdraws out loud keeps being obeyed**. Rushing is exactly
how a half-landing happens, which was the failure that lane had already refused twice that
night.

> **A stale warning costs more than no warning**, because it reads as current and nothing in it
> expires.

Same defect as the stale `platform_backend.pas` comment filed hours earlier (198). The rule
being enforced is the one you will not apply to yourself — so: **retract out loud, name the
premise that failed, and say which constraints are lifted.**

---

## 202 — A PROCESS-PATTERN SEARCH RUNS INSIDE A PROCESS WHOSE COMMAND LINE CONTAINS THE PATTERN

*(pxx-a5, 2026-08-30, killing its own reducer — and walking into the trap while doing the
thing a doc already warns about.)*

`pkill -f "reduce.py"` **matched its own shell's command line and killed the shell.** Exit 144.

CLAUDE.md already records one symptom of this: `until ! pgrep -f "make test"` never exits,
because the watcher's own command line matches the pattern. That entry documents **one command
and one symptom**, which is why it did not transfer. The general form is structural:

> **A `-f` pattern match is self-referential by construction** — the search runs inside a
> process whose command line contains the pattern you are searching for.

And the reason it keeps costing something is that **the failure mode differs by tool, and
neither presentation looks like the cause**:

| tool | what happens | what it reads as |
| --- | --- | --- |
| `pgrep -f X` in a wait loop | the loop never exits | a **hang** in the thing being waited on |
| `pkill -f X` | kills the asker | a **crashed tool**, or an unexplained exit 144 |

Neither says "your pattern matched you". Fix, in both cases: **bracket a character so the
literal pattern is not present in the matching process's own argv** — `[r]educe\.py`,
`[m]ake test`. pxx-a5 used exactly that to confirm the kill afterwards.

Worth noting *how* it was found: the shell died and the exit code was 144, i.e. the diagnosis
came from an odd exit status rather than from any message. It is the same family as 198a — **a
tool reporting something adjacent to the truth** — and this index's recurring lesson about
symptoms recorded without their mechanism: a doc that records *"`pgrep -f "make test"` never
exits"* protects the next person who runs that exact command, and nobody else. **Record the
mechanism, not the instance** — otherwise the entry is a landmine map with one mine on it.

### 202a — relaying a tool's confident claim is making the claim

Same message, and pxx-a5 volunteered it about itself rather than being told:

> *"I reported both DANGLING-SHA lines as findings for other lanes without checking them, on
> the strength of a confident message from a tool… Relaying a tool's confident claim is making
> the claim."*

The check's text said *"almost always a PRE-REBASE sha copied from a local reflog"* and named
an exact remedy, so it read as a finding rather than as an inference — and **three of those
tickets explained the true case in their own prose, one line from the citation.** Reading
either would have caught it.

This is the standing relay rule (*verify a peer's report before relaying it*) with the source
being **a tool rather than a peer**, and the tool is the harder case: a peer's claim carries
visible authorship and invites a check, while a tool's output reads as measurement. **The
confidence of a generated message is a property of its author's prose, not of its evidence.**

Note where the check landed, because it is the standing lesson about where verification flows:
pxx-a5 spent care on the *fuzz* findings — five oracles, two refuted hypotheses, a deferred
revalidation labelled NOT VALIDATED — and passed the tool's output along unread. The scrutiny
went to the thing it had doubts about.
