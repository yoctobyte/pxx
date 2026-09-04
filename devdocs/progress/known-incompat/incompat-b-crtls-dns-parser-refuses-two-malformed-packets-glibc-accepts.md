---
summary: "KNOWN-INCOMPAT, chosen (2026-09-04). crtl's resolver refuses two malformed DNS inputs that glibc accepts, both measured against glibc on this box: (1) ns_name_unpack() refuses a compression pointer that points FORWARD -- glibc follows it and returned 2 where crtl returns -1; (2) res_nsend() discards a datagram whose QR bit is clear -- glibc accepts it, and a probe that sends a decoy with the right id and QR=0 followed by the real reply gets 6.6.6.6 under glibc and 10.1.2.3 under crtl. Both crtl answers are the RFC-conforming ones (RFC 1035 4.1.4: a pointer names a PRIOR occurrence; RFC 1035 4.1.1: QR distinguishes a query from a response) and both are strictly safer, since each glibc behaviour lets bytes an attacker chose reach a caller. No conforming server emits either shape, so no correct program is refused. Chosen, not tolerated: matching glibc here would mean deliberately accepting input the protocol says is invalid."
type: compat
track: B
prio: 5
status: known-incompat
created: 2026-09-04
found-by: franks-ab
owner: ""
---

# crtl's DNS parser refuses two malformed packets that glibc accepts

Both were found by `test/c_crtl_resolv.c` and `test/c_crtl_res_send.c`, whose
oracle is glibc on this box. Neither is a pxx bug and neither is a glibc bug in
the sense that matters — glibc's choices are defensible as leniency toward
real-world servers. We chose the other side, and this file is the record of
choosing rather than of tolerating.

## 1. A forward compression pointer

    forward-ptr(STRICTER) initparse=-1 uncompress=2     <- glibc
    forward-ptr(STRICTER) initparse=-1 uncompress=-1    <- crtl

The probe puts a pointer at offset 12 aimed at offset 20, which is *ahead* of
it. glibc follows it, finds the root label there, and reports 2 bytes consumed.
`lib/crtl/src/arpa/nameser.c` refuses any target that is not strictly before
the pointer.

**RFC 1035 §4.1.4 says a pointer names "a prior occurrence of the same name".**
A forward pointer is therefore not something a conforming server emits, and
following one builds a name out of bytes the parser has not validated yet —
the packet is walked out of order, so a length byte can be reached before the
bound that would have rejected it.

**The strict rule is also what makes termination cheap.** "Strictly backwards"
terminates on its own; the jump counter beside it is a second, independent
bound rather than the only one. glibc, having no ordering rule, has to rely on
its counter alone.

Note the two rows agree on `initparse=-1` — the message as a whole is refused
either way. The divergence is only visible through the direct
`ns_name_uncompress()` call, which is why the test makes that call separately
rather than trusting the message-level verdict.

## 2. A reply with the QR bit clear

    notresp.example.com rc=ok h_errno=0 addr=6.6.6.6    <- glibc
    notresp.example.com rc=ok h_errno=0 addr=10.1.2.3   <- crtl

`test/c_crtl_res_send.c` runs a DNS server on 127.0.0.1 that, for this name,
sends a decoy carrying `6.6.6.6` with the **right query id** and **QR clear**,
then the real reply carrying `10.1.2.3`. glibc accepts the first datagram on
the id alone; `res_nsend()` in `lib/crtl/src/resolv.c` skips it and keeps
waiting, so it gets the real answer.

**RFC 1035 §4.1.1: QR is 0 for a query and 1 for a response.** A datagram with
QR clear is not an answer to anything. Accepting it means a caller's address
comes from a packet that never claimed to be a reply.

**The decoy's address differs from the real one on purpose.** If both carried
`10.1.2.3` the row would pass whichever packet was accepted — the
expected-value-collides-with-the-failure-value trap. The two addresses are what
make the row able to fail.

## Why this is `known-incompat/` and not a bug in either direction

- The measurement is **true and reproducible**: both rows come from a
  differential run against glibc, with the packets constructed in the test.
- **No correct program is refused.** Both shapes are ones a conforming server
  never produces, so the only inputs affected are malformed or hostile.
- **Ours is the safer answer in both cases**, and safety is the whole job of a
  parser whose entire input is chosen by someone else.

## What would reopen it

Real source — not a probe — that is correct against glibc and wrong against
crtl *because* of one of these two rules. That means a real nameserver
observed emitting a forward compression pointer, or a real deployment where
answers legitimately arrive with QR clear. Neither has been seen; if one is,
the fix is a documented leniency flag, not silently matching glibc.
