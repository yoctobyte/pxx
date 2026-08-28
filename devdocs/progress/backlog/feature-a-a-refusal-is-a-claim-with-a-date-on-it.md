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
