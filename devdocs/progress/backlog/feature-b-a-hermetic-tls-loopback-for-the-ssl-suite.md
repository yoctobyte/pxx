---
summary: "lib_synapse_ssl proves the dlopen'd libssl resolves real symbols, but not that a handshake completes — the handshake is verified only by a manual probe against `openssl s_server`. A TLS handshake needs both sides live at once and the suite is single-process with no fork, so automating it means a self-exec harness: the test re-runs its own binary as the server, cert from TSSLOpenSSL.CreateSelfSignedCert, port over the pipe."
track: B
prio: 30
type: feature
status: backlog
owner: unassigned
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
