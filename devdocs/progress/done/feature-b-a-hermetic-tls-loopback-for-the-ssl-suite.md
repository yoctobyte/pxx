---
summary: "lib_synapse_ssl proves the dlopen'd libssl resolves real symbols, but not that a handshake completes — the handshake is verified only by a manual probe against `openssl s_server`. A TLS handshake needs both sides live at once and the suite is single-process with no fork, so automating it means a self-exec harness: the test re-runs its own binary as the server, cert from TSSLOpenSSL.CreateSelfSignedCert, port over the pipe."
track: B
prio: 30
type: feature
status: done
owner: frank-b
blocked-by: []
---

# A hermetic TLS loopback for the SSL suite

Split out of [[feature-real-dynlib-loader]] on 2026-08-29, where the handshake
(item (d)) was **measured working** but deliberately not added to the suite.

## What is and is not covered today

`test/lib_synapse_ssl.pas` asserts two real things — `uses ssl_openssl3`
compiles, and `InitSSLInterface` + `OpenSSLVersion` answer out of a real
`libssl`/`libcrypto` loaded at run time. That is the loader proven against a
third-party `.so` we do not control, which is what it was written for.

It does **not** assert that a handshake completes. That is checked only by a
manual probe (recorded in `feature-real-dynlib-loader`): `openssl s_server` on a
self-signed localhost cert, then `Connect` + `SSLDoConnect`, giving
`connect=0 ssl=0` — matching the FPC oracle byte for byte on the same source.

## Why it is not simply added

A handshake is a **conversation**: client and server must interleave, so both
sides have to be live simultaneously. The suite is single-process, and `lib/rtl`
exposes `PalExecve` / `ExecutePipeline` but no plain `fork`, so there is no way
to run "the rest of this Pascal program" concurrently. The existing plain-TCP
loopback in `lib_synapse.pas` works single-threaded only because `Connect`
completes into the listen backlog without the server having accepted yet — a TLS
handshake cannot borrow that trick.

Two shapes were considered and rejected for the gate as it stands:

- **Spawn `openssl s_server` via `ExecutePipeline`.** Adds an openssl-CLI
  dependency, a cert file, a port, and a readiness wait — i.e. a network-timing
  test inside Track B's gate. `lib-test` already loses runs to unexplained
  terminations; this would add a genuinely flaky one and its failures would look
  exactly like those.
- **Threads.** `blcksock` + `-dPXX_DYNLIB_LIBC` + `--threadsafe` together is an
  untested combination, and debugging it belongs in its own ticket rather than
  as a side effect of adding an assertion.

## The shape worth building

**Self-exec.** The test re-runs *its own binary* with an argument
(`ExecutePipeline(ParamStr(0), ['--tls-server'])`); the child binds an ephemeral
port, generates a cert in memory with `TSSLOpenSSL.CreateSelfSignedCert`, and
writes the port back over the pipe; the parent connects and does `SSLDoConnect`.
No external CLI, no cert file, no expiry to rot, no fixed port. The child is the
same binary, so it needs no extra Makefile wiring.

Guarded and skip-reported like the current SSL job (`external/synapse` +
`-dPXX_DYNLIB_LIBC` + a real libssl), so a box without them reports
`SKIPPED: tls-loopback` rather than a silent pass.

## Why it is worth doing at all

The crash it would guard against — a tail call through a function pointer
holding a stack address, inside `X509_verify_cert` — was a **compiler** bug
(`bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-cert`,
fixed `2ee660831`). Nothing in Track B's gate exercises a real handshake, so a
recurrence would surface as a segfault in whatever application hit it first
rather than in a suite. This is the only place we drive a third-party C library
through a full protocol conversation, which makes it worth more than its size.

## Resolution (frank-b, 2026-08-30) — built as specified, plus one arm

### The objection was re-priced first, and it is refuted as written

The ticket rejects the cheap shape because *"lib-test already loses runs to
unexplained terminations; this would add a genuinely flaky one and its failures
would look exactly like those."* Measured, in order:

1. **`8f0e1a589` could not have been one of those sources.** It only changes the
   reactor-exhaustion path, which requires all 64 slots occupied — a 65th
   thread — and if reached it prints a named fatal and exits **216**, loudly.
   The same precondition applies to `9bd3da8b2`. Neither can produce a silent
   termination. So the re-pricing premise I was handed is wrong, and the
   objection had to be tested directly instead.

2. **lib-test does not lose runs.** Four foreground runs: one red (a real bug,
   below), then **3/3 green at 391s / 402s / 407s**, on a box loaded at 12.93
   on 12 cores.

3. **The "unexplained terminations" are an observation artifact, and I
   reproduced it deliberately.** They are SIGTERM — and an agent harness kills a
   foreground command at **600s**. Two lib-test runs in one command is ~800s, so
   the second dies at exactly 10m with no error from `make`. lib-test at ~400s
   sits inside that ceiling with ~200s of headroom; nothing about lib-test is
   flaky.

**But the ticket's conclusion survives, with the mechanism inverted.** The worry
was that a flaky test's failures would *resemble* the existing noise. The real
risk is the reverse: a network test that **hangs** pushes lib-test past 600s and
*manufactures* the artifact. So "must never hang" became a hard design
constraint, and every wait in the new test is bounded — the child's accept, both
socket timeouts, and the parent's port read, which unblocks on the child's EOF
if the child dies.

### Built the self-exec design (the ticket's own recommendation)

`test/lib_synapse_tls_loopback.pas`, wired into `lib-test` beside
`lib_synapse_ssl` inside the existing `external/synapse` guard. The child is the
same binary re-run with `--tls-server`; it binds an ephemeral port and writes it
back over the pipe. No openssl CLI, no cert file, no fixed port, no expiry.

The cert comes from `ssl_openssl3` itself — `Prepare()` calls
`CreateSelfSignedCert` for a server socket with no cert configured. The method
is `protected`, so calling it directly does not compile; this is the supported
route to the same place.

### The arm the ticket did not ask for, and it is the one with teeth

**Two** handshakes, not one:

- `VerifyCert=False` → completes, and application data crosses it.
- `VerifyCert=True` → **rejected**, `certificate verify failed`.

Only the second proves `X509_verify_cert` actually *ran*. A permissive handshake
can complete without the verification path reaching a decision — and that
function is exactly where the compiler bug this exists to guard lived
(`bug-a-synapse-tls-handshake-jumps-into-the-stack-inside-x509-verify-cert`).
Without the rejecting arm this test could sit green while never entering the
code it protects, which is the failure mode this repo keeps producing.

### Verified

- **80/80 green** (40 serial + 40 as eight concurrent), ~1.2s per run, on a box
  loaded at 13.
- **Not vacuous**, two negative controls: with verification never enabled,
  `verify-rejects=FAIL ... handshake ACCEPTED an untrusted self-signed cert`,
  exit 1; with the server doing plain TCP, the run dies rather than passing.
- **All three recipe branches driven by `make` itself**, not by hand-substituting
  `$`: exit 77 → `SKIP` + `tls-loopback` recorded in `lib-test.skipped`, exit 0;
  a non-zero exit → diagnostic printed and the gate fails; success → `expect_same`.
- `make lib-test` green end to end at 407s with the job present and not skipped.

### Two side findings

**lib-test was RED on master** and had been since `9396b32c7` (22:16) — the PCL
migration onto stock GTK3 headers, which left `tools/lib_units_compile.py`
compiling eight GTK units with no include root. Fixed separately in `74161c581`;
that is why run 1 above was red.

**A TLS peer that closes early kills the process with SIGPIPE** (exit 141, no
output) — OpenSSL writes the ClientHello without `MSG_NOSIGNAL`, unlike
Synapse's own send path. Found via the negative control. **Not filed**: built
the same probe under FPC 3.2.2 and it exits 141 too, so this is Synapse+OpenSSL
behaviour and matches the oracle, not a pxx defect. Recorded here so the next
person does not re-derive it.

### Gate

`make lib-test` green (407s, this job included), built with `$(PXX_STABLE)`.
No compiler rebuild.

## Log
- 2026-08-30 — resolved, commit 2d4ce55bf.
