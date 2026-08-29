---
track: A
prio: 50
type: chore
status: working
blocked-by: []
owner: frankD
summary: "Five defects in one day share one greppable shape: a construct has two or more arms, one arm carries a comment ASSERTING the invariant, and the sibling arm does not honour it. The comment is the signal and nothing reads it. Sweep rather than wait for the sixth discovery."
---

# A comment asserting an invariant is a claim about a SIBLING ARM, and nobody checks it

- **Type:** chore (audit) — **Track A** file-ownership by default; each finding
  is filed into whichever lane owns the arm.
- **Proposed:** 2026-08-29 by frankA, after hitting the shape three times in one
  day; generalised by the coordinator against two more from pxx-a5.


## PASS 1 RESULT: the population has THREE shapes, and proximity does not predict catchability

frankD, 2026-08-29 (`e7385984b`). Population made concrete: **53 hits across 21
files** under `compiler/` and `lib/` for this ticket's own phrase list — small
enough to finish. Pass 1 took the **8 whose claim spans more than one arm**, on
the reasoning that a single-arm assertion has no sibling to betray.

**The distance column was added to test one hypothesis and refuted it.** The
hypothesis (frankA's, and a good one) was: if every instance is close — same file,
same routine, two paragraphs — the problem is *reading what you already have
open*, and the remedy is a review habit rather than tooling.

What came back:

| shape | example | distance | remedy |
| --- | --- | --- | --- |
| **close sibling** | rows 1-7 | same file / same routine | the review habit |
| **self-false** | row 8 (frank-rust) | **eleven lines** | **nothing readable** — only a failing output caught it |
| **distant reference** | frankD's two findings | different files / subsystems | a periodic sweep |

**Proximity does not predict catchability, and the closest instance is the least
reachable by reading.** Row 8's comment is false about its *own* arm and is *more
persuasive than the code beside it* — no sibling to visit, and re-reading would
not have helped. Meanwhile frankD's two are cross-file, where the person reading
the violating code sees nothing wrong **because the claim lives elsewhere**.

So the three columns want **a habit, an oracle, and a sweep**, and only the first
is free. That is a materially different conclusion from the one this ticket was
filed with, and it argues harder against a checker: a checker addresses search,
and search is the failure mode in exactly one of the three columns.

**frankD's own caveat, recorded rather than buried:** pass 1 *deliberately
selected multi-arm claims*, which selects for distance — so its half of the
evidence is biased toward its own conclusion. The single-site "must never" /
"always" assertions are unswept and would likely restore the close-shape
majority. **A survey that names what it selected for is worth several that do
not.**

### Findings filed (neither a live bug)

- **`bug-a-the-ir-frame-op-doc-asserts-a-frame-layout-riscv32-does-not-use`** —
  `defs.inc:816` documents `IR_FRAME`'s saved-fp chain as `[fp]`/`[fp+PtrSize]`,
  universal, no exception. riscv32 is `+8`/`+12`, and `ir.inc:4977` says assuming
  otherwise *"would have silently walked into the locals"*. The lowering asks the
  accessors and is correct; **the IR-op reference a backend implementer reads is a
  false universal** — which is the reader most exposed to it.
- **`bug-a-promocore-is-not-the-only-place-that-knows-the-promo-slot-layout`** —
  `ir.inc:9399` says both promo store paths go through `promocore.pas`, *"the only
  place that knows the layout"*; x86-64's hand-emitted variant-release blob
  encodes `[rax+8]` at three sites in `ir_codegen.inc`. Offsets agree, nothing is
  broken. **~200 lines from the comment that records what instance #4 cost.**

### Verified HOLDING — recorded so nobody re-checks

pypal's syscall table; pylib's three UTF-8 offset helpers; **`ManagedElemKind`'s
nine doors** — the best-maintained instance found, whose own comment *is* the
record of this defect and where every door now asks it; the `InternKey` /
`dbg_filetable` twin; and instance #4's site, re-checked and still fixed.

### Remaining

45 of 53 first-tier hits; **prior #1 (backend/inline twins) is the highest-yield
seam left** — pxx-a5's `builtinheap` census is that shape, and so are both of
frankD's findings plus instance #4. Then prior #2 (frontend lowering arms), then
row 7, which needs a different grep (prescriptions read against their own bodies).

Parked in `unfinished/` with a coverage log so continuation is cheap. **No Track A
file lock was held at any point** — read-only, findings filed as tickets, no
source edited — so the `unfinished/`-is-critical-for-A rule does not bite: it
exists because a half-applied compiler change can break the self-host gate, and
this applies none.

## The shape

A construct is reachable through two or more arms. One arm gets fixed, and the
fix leaves behind **a comment stating the property the fix established**. The
sibling arm does not honour that property. **The comment is now the best
available signal that a sibling is broken — and nothing reads comments.**

Five instances, one day, five different subsystems:

| # | construct | fixed arm | broken sibling | how it presented |
| --- | --- | --- | --- | --- |
| 1 | a `def` returning a receiver expression | field read (`return q.n`) | **method call** (`return c.call()`) | field printed right, method **segfaulted** |
| 2 | `for` bound evaluation order | `ir.inc` `AN_FOR` | `SLLowerFor` (stackless generator) | stackful **passed** and hid it |
| 3 | `range()` stop re-evaluation | 3-arg **runtime** step | 3-arg **literal** step | **hung forever** |
| 4 | string COW / meta word | `PXXStrUnique` (5 targets) | x86-64's inline `AnsiStrUniqueAddr` | silent stale ASCII flag |
| 5 | ordered string compare | x86-64 inline | `PXXStrCmp3` (4 targets) | `'zzz' < 'aaa'` by **allocation order** |
| 6 | `SomeName(expr)` named-type cast | 4 of 5 `ParseFactorCore` dispatch sites | `FindTypeAlias` arm | alias cast **did not narrow** — silent wrong value |
| 7 | a TICKET's own prose | the paragraph listing `vm.push(...)` attribute use | the prescription two paragraphs below it | prescribed edit would have **swapped** one failing set for another |
| 8 | the Delphi generics rewrite's fixed-point exit | `DesugarImportedDelphiGenericUses` (new) | `ParseGenericTemplateNamed`'s loop | round read **idle** while work remained — an emitted `type` keyword silently vanished |

**Instance 6 is the loudest and was found the same day, by pxx-a5 (`6cc4afc17`).**
It is worth stating separately because it removes the last charitable reading of
this shape. There are **five** dispatch sites in `ParseFactorCore` deciding what
`SomeName(expr)` casts to; four build an identical node and differ only in which
names they recognise (the type KEYWORD token at `:1478`, `Integer` at `:1571`,
`OrdinalNameToTk` at `:4074`, `BuiltinScalarTypeKind` at `:6725`,
`FindTypeAlias` at `:6434`). It was the **fourth** round of fixing one construct.
And `:1564`'s comment, written during the *previous* round, says:

> *"the fix for the other spellings deliberately left this one alone — which is
> precisely how the second path stays broken."*

That comment does not merely imply a broken sibling whose invariant went
unchecked. **It names the surviving broken arm outright, in advance, and it
still took another round.** So the population is not just findable in principle
— in at least one case it was already found, written down, and left. The gap
this audit closes is not detection, it is follow-through.

**Instance 8 is the first where the comment is not about a sibling arm at all —
it asserts an invariant about the SAME arm, and is simply false.** Both copies of
the fixed-point loop in `pasparser_generic.inc` exited on `until TokCount =
dgenBefore`, carrying:

> *"A round that rewrites nothing inserts no alias declaration, so an unchanged
> TokCount is exactly 'nothing left to collapse'."*

It is not exact. The same round also REMOVES each `<Args>` group it rewrote, so
one argument tuple used twice removes 8 tokens and inserts 8, and the loop reads
"idle" on a round that did work. **Distance between the comment and the
violation: eleven lines, same procedure, same screen.** That number is the point
— this was not a sibling in another file that a reader could not have been
expected to visit. Reading the comment could not refute it; the comment is
*more* persuasive than the code, which is what made it survive. Only a wrong
output did: the `type` keyword the desugar emits went missing on exactly the
cancelling input, and the search for why arrived here.

The remedy that distance implies is **not** tooling and not more careful reading.
It is that an invariant stated in prose next to the code it governs is worth
nothing until something fails when it is violated — the same reason a claim in a
ticket has to be diffed against an oracle before it is written down. Fixed in
`bug-p-a-delphi-mode-generic-from-a-used-unit-cannot-be-specialized`; the sibling
loop was corrected in the same commit, where its only effect is one extra round
in the case that was silently reading "idle".

**In every one, the fixed arm's comment names the property the unfixed arm
lacks.** Instance 3's runtime-step arm says outright: *"the previous lowering
re-ran the stop expression on every iteration"* — and the literal-step arm was
doing exactly that. Instance 4's `PXXStrUnique` calls itself *"the single choke
point for byte mutation, which is what makes the cache sound."*

### Row 7 is the same defect wearing a document instead of a comment

Added on frankA's argument, which is better than the framing I first gave it. I
had relayed this to pxx-a5 as advice about writing tickets — *"store X rather
than Y" is a stronger claim than "X is missing", and the second is usually all
the evidence supports.* True, and **unactionable**: nobody knows in the moment
which of their claims is the over-strong one.

What makes it a row rather than advice is the tell. `bug-n-the-only-callers-of-
evalpystmts-encode-a-contract-that-changed` prescribed storing the bound methods
*"rather than a `vm` receiver"*. Following that literally would have broken the
suite, because those scripts also reach `vm` by attribute — `vm.push(123)`,
`vm.pop()`, `vm.pic.append("x")`, `vm.memory`, `vm.words` — and only the implicit
host-call *receiver* rule was removed by `ff439149e`. The prescription would have
traded one set of failing rows for a different set.

**The evidence to catch that was already in the ticket, two paragraphs above the
prescription, unread by whoever wrote the last line.** That is not a lesson about
ticket-writing. It is this audit's defect exactly — a document states the
invariant, and the next author does not read it — with a `.md` file in the role
the comment plays in rows 1-6.

So the population this audit sweeps is wider than source comments: **any artefact
that states a property near the code or prescription that must honour it.** The
sweep should read ticket prescriptions against their own bodies wherever a ticket
prescribes an edit rather than describing a symptom.

## Why it keeps winning

- **The fix lands on the arm that needed it for a SECOND reason.** In #3 the
  runtime-step arm needed a temp because its ternary reads the stop *twice*; the
  literal arm reads it *once*, and once **per iteration** is the whole bug. The
  safer-looking arm got fixed and the common one did not.
- **The surviving arm's failure is usually worse.** Segfault, hang, silent wrong
  value — versus the loud case that got attention first.
- **The sibling's green is real.** #2's stackful generator genuinely passed. A
  pass from the wrong configuration is the quiet direction: nothing is red, so
  nothing is triaged.

## The work

**This is a grep, not an analysis.** Comments asserting an invariant are a small,
findable population — *"the single choke point"*, *"every X must"*, *"this is
what makes ... sound/safe/correct"*, *"the previous lowering"*, *"always"*,
*"never"*. For each: name the arms the claim covers, and check each arm honours
it.

Two useful priors from the instances above:
1. **Backend/inline twins** — pxx-a5's `builtinheap` census found 30 routines
   called by a cross backend and never by x86-64, 9 naming an inline twin in
   their own comment. That census has a form; reuse it.
2. **Frontend lowering arms** — literal vs runtime operand, 2-arg vs 3-arg,
   stackful vs stackless, field vs method. #1, #2 and #3 are all this.

**Findings are filed into the owning lane, not fixed here** — IR/codegen → A,
dialect/frontend → P/N, RTL → B. The audit produces tickets.

## Explicitly NOT the claim

That comments are bad, or should be removed. **The comments are correct and are
the only reason these were findable at all.** The defect is that a claim about
several arms is written where only one arm can see it, and no tooling reads it.
A checker is probably not the answer either — natural-language invariants do not
mechanise cleanly, and a checker that cries wolf gets scrolled past. A **one-time
sweep producing a ticket per real finding** is the honest scope.

---

## 2026-08-29 — sweep pass 1 (frankD). Population defined, 8 claims checked, 2 findings.

Taken as a **read-only** audit: findings filed into owning lanes, **no source
edited**, so it held no Track A file lock at any point and could not collide with
frankA. Everything below measured against pinned v393.

### The population, made concrete

The ticket says *"this is a grep, not an analysis"* and names the phrases. Run
over `compiler/**` and `lib/**` (`.inc`, `.pas`, `.c`):

```
grep -rniE "single choke point|the only place|must (always|never)|\
is what makes .* (sound|safe|correct)|every [a-z_]+ must"
```

**53 hits in 21 files.** That is the whole first-tier population and it is small
enough to finish. This pass examined 8 of the strongest — the ones whose claim
covers more than one arm, since a single-arm assertion has no sibling to betray.

### Findings — 2, both filed, neither a live bug

- [[bug-a-the-ir-frame-op-doc-asserts-a-frame-layout-riscv32-does-not-use]] —
  `defs.inc:816` documents `IR_FRAME` as *"[fp] = the caller's fp, [fp + PtrSize]
  = the return address"*, universal, with no exception. riscv32 puts them at
  **+8/+12**, and `ir.inc:4977` says assuming otherwise *"would have silently
  walked into the locals"*. The lowering is correct (it asks the accessors); the
  **IR-op reference a backend implementer reads** is not.
- [[bug-a-promocore-is-not-the-only-place-that-knows-the-promo-slot-layout]] —
  `ir.inc:9399` says both promo store paths *"go through promocore.pas, the only
  place that knows the layout"*. x86-64's hand-emitted variant-release blob reads
  the payload as a literal `[rax+8]` at three sites in `ir_codegen.inc`. Offsets
  agree, so nothing is broken — but **this is instance #4 again, same file, same
  arm**: a "single choke point" claim whose exception is x86-64's hand-emitted
  path, ~200 lines from the `PXXStrUnique` comment that records the last time
  that cost two months.

### Claims checked and HOLDING — 4, worth recording so nobody re-checks them

- `pypal.pas:93` *"the per-arch syscall table — the only place numbers appear"* —
  holds. `pylib.pas` has one `__pxxrawsyscall` mention and it is a comment; the
  32 scattered sites its header describes are genuinely gone. (203 hits repo-wide
  are other subsystems making their own syscalls, outside the claim's scope.)
- `pylib.pas:2938` *"these three helpers are the ONLY place the two coordinate
  systems meet"* — holds. `pystr_slice_step`, 7,000 lines away and a plausible
  straggler, goes through `PyStrCharLen`/`PyStrByteOfChar` like the rest. The
  UTF-8 arithmetic in `TPyBytes.decode` is sequence *validation*, not offset
  conversion — a different concern, not a violation.
- `symtab.inc:2711` `ManagedElemKind`, *"the only place that answer is written
  down"* — holds, and it is the best-maintained instance found. Its own comment
  is the record of this exact defect (*"one absent case reachable through nine
  doors"*), and every door now asks it; `ir.inc:4689` even names a would-be
  twelfth.
- `dbg_filetable.inc:114` *"InternKey, not InternStr: these paths must never
  reach the emitted string pool"* — holds. The comment names its twin
  (`CMarkTokModule`) outright, and the twin uses `InternKey` **and** carries the
  reason with a measured byte-count. A model for what the audit wants.

Instance #4's own site (`ir_codegen.inc:2416`) re-checked: **fixed**, and its
comment now documents the divergence properly.

### The distance column — and pass 1 CONTRADICTS the hypothesis

frankA asked for how far apart the statement and the violation sit, on the
hypothesis that every instance is close (same file, same routine, two
paragraphs) — which would make the remedy a reading habit rather than tooling.

**Both findings in this pass are cross-FILE, and neither could have been caught
by reading the violating code:**

| finding | statement | violation | distance |
| --- | --- | --- | --- |
| IR_FRAME layout | `defs.inc:816` | `ir_codegen_riscv32` prologue | different files, different subsystems |
| promocore layout | `ir.inc:9399` | `ir_codegen.inc:2662/2728/3389` | different files |

Note the direction, because it matters for the remedy: in both, the person
reading the *violating* site sees nothing wrong — the claim lives elsewhere. In
frankA's seven, the fixed arm's comment sat beside the code someone was already
editing. So the population appears to have **two sub-shapes**:

1. **close** — the comment is in the diff you are already reading, and the
   remedy really is a review habit ("grep the sibling before closing");
2. **distant** — the invariant is asserted in a *reference* artefact (an IR-op
   doc, a unit header) about arms living in other files, where no reading habit
   at the violation site can help, because the assertion is not there to read.

Sub-shape 2 is not reachable by review discipline and is the one that argues for
the sweep being periodic rather than one-time. On this evidence the "always
close" hypothesis is **false as stated** — but note the sampling bias, and it
cuts the right way: pass 1 deliberately picked claims *covering multiple arms*,
which selects for distance. A pass over the `must never` / `always` single-site
assertions would likely restore the close-shape majority. Worth finishing before
anyone concludes anything.

### What is left

- **45 of 53** first-tier hits unexamined (the ones this pass judged single-arm
  on their phrasing — that judgement is itself unverified and cheap to redo).
- **Prior #1, backend/inline twins** — largely unswept. pxx-a5's `builtinheap`
  census (30 routines called by a cross backend and never by x86-64, 9 naming an
  inline twin in their own comment) is the highest-yield remaining seam, and both
  of this pass's findings plus instance #4 are that shape.
- **Prior #2, frontend lowering arms** — unswept.
- **Row 7, ticket prose** — unswept. Needs a different grep (prescriptions
  read against their own bodies), not the phrase list above.

Parked in `unfinished/`, not abandoned. **The Track-A-in-unfinished rule does not
bite here**: that rule exists because a half-applied *compiler change* can break
the self-host gate, and this audit has applied none — it edits no code by
construction.

### Addendum — instance 8 landed concurrently, and it makes THREE shapes not two

frankA's instance 8 (eleven lines, same procedure, same screen, and the comment
false about its **own** arm rather than a sibling's) arrived while pass 1 was
running. Folding it in, the distance column now separates three shapes, and they
imply three different remedies:

| shape | distance | what would have caught it |
| --- | --- | --- |
| **close sibling** — frankA's 1-7 | same file, often same routine | a review habit: grep the sibling before closing |
| **self-false** — instance 8 | eleven lines, same screen | *nothing* readable. The comment is more persuasive than the code. Only a failing output caught it |
| **distant reference** — pass 1's two | different files, different subsystems | a periodic sweep; no reader at the violation site can see the claim |

So the "always close" hypothesis is right about *distance* for the majority and
wrong about what follows from it. Instance 8 is the closest of all nine and the
least reachable by reading — which means **proximity does not predict
catchability**, and "read what you already have open" is not the remedy even
where the comment is on the same screen. The three columns want three things: a
habit, an oracle, and a sweep. Only the first is free.

---

## 2026-08-29 — sweep pass 2 (frankD): the `builtinheap` seam. **One LIVE bug.**

Prior #1, worked from [[audit-a-builtinheap-invariants-x86-64-inlines-past]]
rather than rebuilt — claude-N's census was reproduced first (45 reached by
x86-64, **30** called by a cross backend and never by x86-64: identical numbers,
so the seam is measured, not assumed) and then read for invariant claims, which
is what that census explicitly left to a reader.

Two findings, and unlike pass 1 **one of them is a real wrong-answer defect**:

### 1. `bug-a-xtensa-has-no-ordered-string-compare-and-sorts-by-heap-handle` — LIVE

`'zzz' < 'aaa'` on xtensa compares the two heap **handles** as signed ints and
answers by allocation order. That is verbatim the defect `PXXStrCmp3` exists to
fix. The helper's own header says:

> *"**the four cross backends** had NO ordered-string arm at all"*

**There are five.** The fix went to i386/aarch64/arm32/riscv32; xtensa was never
visited. The word "four" is the entire finding — it reads as a complete
enumeration, so nobody counted the arms. This is the audit's thesis in its purest
observed form: *a comment asserting an invariant is a claim about a sibling arm,
and the count in the sentence is itself an unchecked claim.*

Evidence is measured, and the limits are stated in the ticket: hosted xtensa
**hangs on hello-world**, so I could not produce the wrong output and did not
claim to. What stands instead is the guard read directly, the `FindProc` grep,
and a size delta that cannot be innocent — the ordered compare is **52 bytes
SMALLER** than the equality compare on xtensa, and **4 bytes larger** on riscv32.
Note the second-order point: the target with no working oracle is the target that
kept the bug. Pass 1 concluded one shape wants an oracle; here the *absence* of
one is the proximate cause.

### 2. `bug-a-threadsafe-is-x86-64-only-is-asserted-in-five-places-and-has-been-false-since-july` — a NEW shape

`--threadsafe` has accepted **x86-64/i386/aarch64/arm32** since `07fee0844`
(2026-07-06). Five comments in four files still say x86-64-only. The code is
correct at every site; nothing misbehaves.

The reason it is worth a ticket is that it is **not this audit's shape at all**,
and it is the first sub-shape that argues for something cheap and mechanical.
There is one concept, one correct implementation, and **a scope that widened
once** — silently invalidating every sentence in the tree that stated the old
scope. No sibling arm exists to grep for.

Distance runs the entire range within this single finding, which is why it is
the most informative item in either pass:

| site | asserts | refuted by | distance |
| --- | --- | --- | --- |
| `ir.inc:12730-12733` | "x86-64 only" | `ir.inc:12734` — the condition it introduces, testing all four | **ONE LINE** |
| `builtinheap.pas:2039` | `PXXStrIncRef` "NON-atomic" | its own `{$ifdef PXX_TS_SOFTLOCK}` atomic arm, 8 lines below | **8 lines** |
| `defs.inc:809` | `IR_IO_LOCK` "x86-64 + ThreadSafeMode only" | real lock calls in three cross backends | **cross-file** |
| `ir_codegen386.inc:4099`, `:4242` | "i386 runs single-threaded" | `compiler.pas:1586` | **cross-file** |

`git blame` on the first: **the comment is 2026-07-02 and the condition directly
below it is 2026-07-06.** The commit that widened the scope edited the line under
the sentence asserting the opposite and did not touch it. 54 days.

### Claims checked and HOLDING (pass 2)

- **`PXXStrCmp3`'s claim about its x86-64 twin** — *"x86-64's inline sequence
  uses `repe cmpsb` + the unsigned setcc family"*. Holds: `ir_codegen.inc:3876`
  is `repe cmpsb`, and `EmitSetcc(opTk, False)` four lines later selects
  `setb`/`setbe`/`seta`/`setae` (`ir_codegen.inc:3531-3534`). A cross-file claim
  about a sibling arm that is simply **correct** — worth recording precisely
  because the audit otherwise only ever writes down the failures.
- **`EmitAcquireHeapLock386` (`ir_codegen386.inc:106-111`)** — states that i386's
  lock lives in the Pascal helpers so the codegen-side acquire is a deliberate
  no-op. Correct, and it is the sentence the two wrong ones 4000 lines below it
  in the same file should have copied.

### Distance, updated across both passes

| shape | instances | distance | remedy |
| --- | --- | --- | --- |
| close sibling | frankA 1-7 | same file / routine | a review habit |
| self-false | instance 8; `ir.inc:12732`; `builtinheap.pas:2039` | 1-11 lines | an oracle — nothing readable helps |
| distant reference | frankD pass 1 ×2; `defs.inc:809`; `ir_codegen386.inc` ×2 | cross-file | a periodic sweep |
| **miscounted enumeration** | **xtensa/`PXXStrCmp3`** | the claim IS the count | **count the arms mechanically** |
| **stale scope after a widening** | `--threadsafe` ×5 | 1 line to cross-file | **grep the old scope string when you widen a gate** |

The two new rows are the useful ones, because both have a cheap mechanical
remedy and neither is reachable by careful reading. "Four cross backends" is
falsified by `ls compiler/ir_codegen_*.inc`. "x86-64-only" is falsified by
`grep -rn "x86-64.only" compiler/` in under a second. **Pass 1 said the shapes
want a habit, an oracle and a sweep, only the first free; pass 2 finds two shapes
whose remedy is a one-line grep — and they are the two that produced the live
bug and the oldest lie respectively.**

### Still left

45 of 53 first-tier phrase hits; the remaining unaudited `builtinheap` twins
(`PXXStrEq`, `PXXVarClear`, the console-read family — the float→text family is
**Track F** by charter and stays out); prior #2 (frontend lowering arms); row 7
(needs its own grep). And one **new** cheap sweep this pass suggests: every
comment containing a target enumeration ("the four cross backends", "x86-64 and
i386", "i386/ARM32/AArch64") checked against the actual backend list — that is
where both of pass 2's findings live.
