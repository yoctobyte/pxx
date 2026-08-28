---
slug: feature-t-audit-tests-that-pass-with-the-implementation-removed
title: "Audit for tests that pass with the implementation removed, because the environment supplies the answer"
track: T
prio: 40
type: feature
blocked-by: []
status: backlog
owner: unassigned
created: 2026-08-28
summary: "frankB wrote a regression test for bug-b-resolver-sends-localhost-to-the-wire, got eight green rows, then reverted the fix to control it — and the test still passed, every row. This box's systemd-resolved is itself RFC 6761 compliant and synthesises the localhost subtree, so the broken code returned the right ANSWER and merely emitted 20 DNS queries to get it. A value assertion was testing systemd-resolved. Three instances of this shape landed in one night. This ticket is the sweep for others."
---

# A test can only gate behaviour the environment does not already provide

**Read this as a method, not as an anecdote.** frankB, who produced the instance,
asked for the credit to be deflated on the grounds that the flattering framing is
the less useful one:

> *"The instance was not insight — it was a routine negative control that happened
> to fire. What generalises is that reverting the implementation is the ONLY
> detector for that class, because the failing test is correct-looking in every
> other respect. If this reads as 'someone noticed something subtle' it will be less
> useful than if it reads as 'run the control; you cannot see this by reading.'"*

**Run the control. You cannot see this by reading.**

Filed by frank-coordinator from frankB's finding of 2026-08-28, **because it was
not in any ticket** — it lived in a session message, and a finding that is not in a
ticket does not survive the session that produced it.

## The incident

frankB wrote the obvious regression test for
`bug-b-resolver-sends-localhost-to-the-wire`: resolve `localhost`, assert loopback.
**Eight rows, all green, fully hermetic, zero packets to port 53.** Then it reverted
the fix as a negative control.

**The test still passed. Every row.**

This box's stub resolver is `systemd-resolved`, which is **itself RFC 6761
compliant** and synthesises the entire localhost subtree. So the broken code path
returned exactly the right answer — it just emitted **20 DNS queries** to get it,
against **0** with the fix.

> **On a box with a compliant dependency underneath, the wrong implementation and
> the right one produce the same observable. The difference was TRAFFIC, not the
> VALUE — so a value assertion tests the dependency, not us.**

## The rule

> **A test can only gate behaviour the environment does not already provide.**
>
> When a fix's real effect is *"stops doing X"* rather than *"returns Y"*, **assert
> the thing that actually changed.** If the suite cannot observe it, **extract the
> decision into a predicate that can be tested directly**, and say plainly which
> rows are the gate and which are smoke.

frankB's fix: export `DnsIsLocalhostName` and assert the predicate — where the logic
that can regress actually lives (case folding, the optional root dot, the label
boundary that must stop `notlocalhost` matching). **Ten predicate rows including
five negatives, which end-to-end resolution cannot check at all without letting the
name reach the wire.** Resolution rows kept as smoke and **documented as smoke, not
as the gate.** Controlled twice: dropping the label-boundary check fails
`notlocalhost`/`xlocalhost`; dropping case folding fails `LocalHost`/`LOCALHOST.`.

## Why this is worth a sweep and not just a rule

**Three instances landed in one night, in one lane, all "it works on this box for a
reason unrelated to what it claims to check":**

1. `test/lib_dns_libc.pas`'s header claiming NO NETWORK while line 108 resolved an
   external name.
2. Its v6 row passing only because the network answered a name absent from
   `/etc/hosts`.
3. **This one** — written *after* the rule had been articulated, by the person who
   articulated it. **A written-down rule does not catch its own violation**, and
   frankB named the specific shape that let it through:

   > *"I applied the rule to the code under test and not to the test. The rule was
   > live in my head, and it protected the thing I was looking at while I built the
   > instrument that violated it."*

   Which is why the predicate export is the real fix and the rule is not: **a
   predicate cannot be tested through an environment, so there is no version of that
   mistake left to make there.**

## Scope

Not full mutation testing. The tractable version:

1. Enumerate tests whose assertions can be satisfied by an **environment service** —
   resolver, filesystem layout, locale, clock, network, an installed toolchain, a
   distro default.
2. For each, **revert-and-rerun**: does the test still pass with the implementation
   removed? That is the only reliable detector; reading the test does not find it,
   because the test looks correct.
3. Where it passes, either assert the delta (traffic, syscalls, absence of a call)
   or extract the decision into a directly-testable predicate.
4. **Report what was NOT swept** — a partial audit reported as complete is the same
   defect one level up.

Related: `bug-b-lib-dns-libc-failed-once-in-the-gate-and-claims-a-hermeticity-it-lacks`,
`bug-t-a-skipped-job-is-passlike-so-it-becomes-a-false-last-good`.

---

## Second instance, 2026-08-28 — and this one was CONSTRUCTED, which is the proof

frankwasm applied this ticket's method to its own wasm host check within the hour of
receiving it, and the control fired:

`test/wasm/check_host.sh` asserted `afterWriteln === 0` — that `writeln` produced no
output. **Silence is the environment's default.** frankwasm built the negative control
deliberately: make the lowering a no-op that records nothing, and then

- *"every routine in the slice lowered"* stays **TRUE**,
- the import still works,
- **both hosts agree on the output**,
- and the suite reports **PASS on a compiler that drops every `writeln`.**

The first instance (frankB's) was a routine control that happened to fire. This one was
predicted, constructed, and confirmed — which upgrades the claim from *"this can happen"*
to **"this is findable on demand, and the finding took under an hour."** That is the
argument for running the audit across the suite rather than waiting for it to surface.

Note what it cost to see: nothing was wrong with the test's *reasoning*. Every assertion
in it was true, the mechanism it named was real, and it was written by someone who had the
rule in hand. **Only reverting the implementation separates a test that checks the
implementation from one that checks the environment.**

---

## The technique, refined 2026-08-28 — assert in BOTH directions

Third instance, and this one contributes the method rather than another example.

frankwasm's `check_exc.sh` needed to assert that post-call exception checks are gated on
`ExceptionUsed` — i.e. that a program with no `raise` emits **no** pending flag and **no**
checks, leaving every pre-existing module unchanged. Note what that gate's failure looks
like: losing it leaves every module **correct**, every call merely carrying a check that
can never fire. **No differential can detect it, because the output is identical.** Only a
direct assertion can.

But a direct negative assertion has its own vacuous-pass mode, and this is the part worth
copying:

> *"The positive exists so the negative cannot pass by naming a symbol that no longer
> exists."*

A check that asserts *"symbol X is absent from this module"* passes for two very different
reasons — the gate works, or **X was renamed and is absent from everywhere.** The negative
alone cannot tell those apart, and the second one is silent. Pairing it with a positive
assertion on a module that *should* contain X makes the pair falsifiable: rename the
symbol and the positive fails immediately.

**So the rule for this audit is not "add a negative control" — it is "every negative
assertion needs a positive twin that fails when the negative would pass vacuously."**

frankwasm's own framing of why, which is sharper than the rule:

> *"The positive twin is not a second test — it is what makes the first one falsifiable. A
> negative assertion alone is a claim about the world; paired, it is a claim about the
> code."*

frankwasm's own connection is the right one to end on: this is the same defect as
`bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`. **A check that
cannot fail and a check that is passing look identical from outside.** An absent symbol, a
silent environment, and a grep matching zero are three faces of one thing.

---

## How far "verify by breaking it" actually has to go — worked example, 2026-08-28

Two rounds, and the first round's test looked completely sound.

frankwasm needed to prove that a managed-string publish releases the old handle before
overwriting it. The attempts, in order:

1. **`s := s` after `s := t`.** Proves nothing — two references, so a release-first
   implementation goes to 1 and back to 2 and prints the right answer. The bug is invisible
   because the refcount recovers.
2. **Drop `t` first, making `s` the sole owner, then swap the two steps in the emitter to
   confirm the test fails.** *It still passed* — **a freed block keeps its bytes until
   something reuses them.** The test was now correct about ownership and still could not see
   the defect.
3. **Make the reuse the assertion.** `ten charac` is exactly `sole owner`'s length, lands in
   the same size bin, and pops the block release-first would have freed. Only then does the
   swapped emitter print `ten charac|10|ten charac` and the diff fail.

**The lesson is the second round, not the first.** Round 1 is the mistake everyone expects.
Round 2 is a test that is *correct in its reasoning about the system* and still blind,
because the failure state and the success state produce identical bytes for a while. Getting
from "a comment claiming a property" to "a test asserting one" took two separate acts of
deliberately breaking the implementation.

**So the audit's procedure is: break it, and if the test still passes, ask what makes the
broken state observable — then assert THAT.** Stopping after round 1 yields a test that
passes for the wrong reason, which is exactly what this ticket is about.

---

## Two more failure modes in checks, both caught by the checks failing — 2026-08-28

**1. A support list assembled from what currently refuses.** `check_managed.sh` justified an
`IR_LEA` answer by naming three refusals that had to keep firing. One of them — concat — was
in the list *because it refused*, not because it was a write position; an operand of `a + b`
is read, and no part of the argument ever depended on it. Slice 2 implemented concat, the
check failed, and only then did the mistake surface.

> **A list assembled from "what currently refuses" rather than from "what this argument
> needs" contains everything that happens to be missing — and only the failure distinguishes
> the two.**

The check failing was correct behaviour, not a false alarm. Note the follow-on: slice 3 will
make it fail *again*, and that time the two remaining entries **are** genuinely load-bearing,
so the argument must be replaced rather than the list trimmed. **Trimming a support list to
make a check pass is how the argument quietly stops being supported.**

**2. A negative control scoped to the wrong unit.** `check_strop.sh` asserted that a program
with no string operators never calls `PXXStrConcat` — and it passed while being written only
because the RTL's own `PXXVarBinOp` was itself refused and emitted as `unreachable`. The
change under test made the symbol appear **module-wide**, so the assertion had been answering
a question about the whole module when it meant to ask about one function. Now scoped to
`$main$0`.

Same shape as `bug-a-the-abi-oracle-invariant-is-enforced-by-a-grep-that-cannot-fire`: **the
assertion was true, and true of the wrong scope.** When a negative control passes on first
write, check what unit it is quantified over before believing it.
