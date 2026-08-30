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
