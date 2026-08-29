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
