---
track: B
prio: 25
type: feature
blocked-by: []
summary: "The Posix.* / FPC-named (BaseUnix, Sockets, UnixType) socket compat facades over the PAL substrate, with a selectable syscall-or-libc backend. Fully designed inside feature-networking and never built; split out when that umbrella closed so the design survives its container."
status: backlog
owner: unassigned
---

# `Posix.*` and FPC-named socket compat facades

- **Track B** (`lib/rtl`). Split out of [[feature-networking]] on 2026-08-28,
  when that umbrella was closed as delivered.
- **Filed to preserve a design, not to schedule work.** This is the only piece of
  the networking programme that was decided in detail and never built. Every
  other residue of that umbrella has its own ticket and all of them are `done`.
  Closing the umbrella without this would have deleted the design.

## Why the priority is low

Nothing is blocked on it. The Synapse milestone that motivated the compat path
is already achieved by a different route — `lib_synapse` in `lib-test` compiles
real Synapse under `--mimic-fpc` and runs b64/md5/sha1/crc32 plus TCP ping/pong.
These facades buy the ability to compile Delphi-flavoured source that spells
`Posix.SysSocket` directly, which is a real capability with no current consumer.

CLAUDE.md's ruling applies: we do not chase reference parity for its own sake,
and a compat item is ranked by how much real code needs the form. Today: none in
tree.

## The design, carried forward verbatim in substance

From `feature-networking`'s log (2026-06-19, refined the same day) and
`devdocs/developer/plan-networking.md`:

- **`Posix.*` is the canonical base; the FPC-named units wrap it.** That master
  question was explicitly settled — Posix is master, `BaseUnix`/`Sockets`/
  `UnixType` are thin wrappers over it, not siblings.
- **The base API has a SELECTABLE backend**, one interface, two bodies:
  `posix_syscall` (default, libc-free, the substantial implementation) and
  `posix_libc` (opt-in via `PXX_POSIX_LIBC`, trivial externs).
- **Cost is ~1.3x, not 2x**, because the types and structs live in one shared
  include — `NetinetIn` is pure data — and only the function bodies differ.
- **A third backend `posix_lwip`** lets the same surface reach ESP, since lwIP's
  BSD-socket API is Posix-shaped. The ESP story becomes "backend differs" rather
  than "API absent", with documented gaps.
- **These are BLOCKING compat surfaces and they do not merge with the async
  transport.** `plan-networking.md:117`: "they coexist with the async transport,
  they do not merge." The portable cross-target surface stays `TNetSocket`;
  `asyncnet.pas` stays the coroutine face over the same PAL primitives.

## What already exists to build on

The PAL socket substrate is complete for this: IPv4/IPv6 TCP and UDP, `PalPoll`
readiness, `-errno` returns with `PAL_NET_EWOULDBLOCK`/`ECONNREFUSED`/
`ECONNRESET`, and introspection (`PalGetSockError`, `PalGetSockNameIpv4`,
peer-reporting `PalAcceptIpv4`). `net.pas` and `asyncnet.pas` are the two faces
over it today. Nothing new is needed below these facades.

The two compiler blockers this path once had — [[feature-dotted-unit-names]] and
[[feature-conditional-declared-directive]] — are both **done**, so `Posix.*` unit
names and `{$IF DECLARED(Qualified.Symbol)}` are no longer obstacles.

## Gate

Track B's: build with `$(PXX_STABLE)`, never rebuild the compiler; `make
lib-test` / `make demos`. A facade is only worth landing with a consumer, so the
gate should include compiling something real against it rather than a smoke unit
that only proves the names resolve.
