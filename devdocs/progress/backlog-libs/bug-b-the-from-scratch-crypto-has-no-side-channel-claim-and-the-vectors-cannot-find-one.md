---
track: B
prio: 40
type: bug
blocked-by: []
summary: "The from-scratch crypto stack (aesgcm, ecdsa_p256, rsa, sha256/512, x509, tls13_* — 3,114 lines over 13 units) is validated against published SPEC TEST VECTORS by 11 test units, and makes NO claim about side channels: across the whole stack the only mention was rsa.pas's `{ constant-time-ish compare }`, which was a length-independent compare and not constant time. THE VECTORS CANNOT FIND THIS BY CONSTRUCTION — a timing leak produces CORRECT VALUES, so every vector passes while the property is absent, which is CLAUDE.md's match-the-assertion-class-to-the-defect-class rule with a cryptographic consequence instead of a missing free. NOT AN ALARM, and prio 40 for a measured reason: tls.pas names the OpenSSL backend 'the safe default' and tls13_native does NOT self-register (a caller opts in via Tls13NativeRegister), so this code is reachable only deliberately and nothing ships it by default. The defect is that the ASSUMPTION was nowhere — a later seat could promote the native stack to default on the strength of a green vector suite and would be reading a correctness result as a security one. Headers in aesgcm.pas and ecdsa_p256.pas now state what is and is not asserted; this ticket owns the residual question."
---

# The from-scratch crypto has no side-channel claim, and the vectors cannot find one

## What is actually asserted

11 test units against published spec vectors: `lib_aesgcm`, `lib_ecdsa_p256`,
`lib_rsa`, `lib_rsa_pss`, `lib_sha256`, `lib_sha512`, `lib_x509`,
`lib_tls13_hs`, `lib_tls13_keys`, `lib_tls13_record`, `devtest_tls13_handshake`.

That is a genuine oracle and it is the whole reason implementing a documented
algorithm from a public spec has been cheap here — see
[[mimic-the-one-percent-and-the-esp32-origin]] for the owner's framing of the
paradox: *"implementing from scratch using a public spec is trivial for an
agentic tool... and leads to way less headaches than trying to compile existing
python code."*

## The blind spot, and it is structural rather than an oversight

**A timing side channel produces correct values.** So it is invisible to every
assertion in that suite, however many vectors are added — the same structural
blindness as the open-array leak that printed `OPENARRAYFRESH OK` while 1504 of
3000 arrays leaked, and as a chained-store bug that printed identical values in
the wrong ORDER. The instrument cannot observe the quantity.

Which means: **a green vector suite is a correctness result and must never be
read as a security one.** Nothing here is evidence either way about constant-time
behaviour, because nothing measured it.

## Why this is prio 40 and not urgent

- `tls.pas` names the OpenSSL backend **"the safe default"**.
- `tls13_native.pas` **deliberately does not self-register** — its own comment
  says so, and a caller must call `Tls13NativeRegister`.

So the native stack is reachable only on purpose, and no default path terminates
TLS with it. The shipped risk today is low; the *recorded* risk was zero, which
is the actual defect.

## What would change the priority

1. Anyone promoting the native stack to the default.
2. Anyone using these units to terminate TLS for a third party rather than as a
   client for ourselves.
3. A target where OpenSSL is unavailable — **the ESP32 case, which is the
   project's origin** — because there "opt in deliberately" and "the only option"
   become the same thing. That is the one where this ticket's prio should rise
   before the work starts, not after.

## Scope of a fix, so nobody over-builds it

Making the whole stack constant-time is a large and specialist job and is **not**
what this ticket asks for. It asks, in order:

1. The claim is written down. **Done** — headers in `aesgcm.pas` and
   `ecdsa_p256.pas`, and `rsa.pas`'s `constant-time-ish` is now honest about
   being a length-independent compare.
2. Decide whether we WANT the native stack to be side-channel resistant, or
   whether it is explicitly a "works where OpenSSL cannot reach" stack with the
   limitation documented. **That is a Track U intent question, not an
   engineering one**, and it is cheap to answer: *do we intend this TLS to
   protect against an attacker who can time it, or only against one who can read
   the wire?*
3. Only if the answer is the former does any constant-time work get ranked.

Until 2 is answered, implementing blinding or a constant-time ladder would be
work nobody asked for against a threat model nobody has stated.
