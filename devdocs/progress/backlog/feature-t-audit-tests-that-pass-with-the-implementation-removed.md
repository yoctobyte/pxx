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
