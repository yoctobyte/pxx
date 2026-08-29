---
track: A
prio: 50
type: chore
status: backlog
blocked-by: []
owner: ""
summary: "Five defects in one day share one greppable shape: a construct has two or more arms, one arm carries a comment ASSERTING the invariant, and the sibling arm does not honour it. The comment is the signal and nothing reads it. Sweep rather than wait for the sixth discovery."
---

# A comment asserting an invariant is a claim about a SIBLING ARM, and nobody checks it

- **Type:** chore (audit) — **Track A** file-ownership by default; each finding
  is filed into whichever lane owns the arm.
- **Proposed:** 2026-08-29 by frankA, after hitting the shape three times in one
  day; generalised by the coordinator against two more from pxx-a5.

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
