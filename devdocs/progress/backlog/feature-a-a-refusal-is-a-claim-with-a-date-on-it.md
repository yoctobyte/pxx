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
