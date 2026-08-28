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
   articulated it. **A written-down rule does not catch its own violation.**

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
