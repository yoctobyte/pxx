---
track: B
prio: 25
type: feature
blocked-by: [decide-posix-master-vs-fpc-named-master-for-the-socket-facades]
summary: "BLOCKED on decide-posix-master-vs-fpc-named-master-for-the-socket-facades: the design says Posix.* is canonical and the FPC-named units wrap it, but the tree shipped the FPC-named units AS the implementation on PAL, and all three of the design's selectable backends already exist one layer down at the PAL. Building as designed would invert a working layer with 15 in-tree consumers plus Synapse, for zero current consumer. Not implementation work until the layering question is re-decided."
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

## 2026-08-28 — premise re-measured before picking it up: the FPC-named half is BUILT, and it is built the other way up

Offered as work while Track B's queue was thin. Read it for content first, and
the content is now partly wrong — filed by me on 2026-08-28 and already
inaccurate, because it was written from `feature-networking`'s design log rather
than from the tree.

**"The only piece of the networking programme decided in detail and never
built" is true of the `Posix.*` base and the selectable backend. It is false of
the FPC-named layer**, which exists, has consumers, and was grown from the
opposite direction:

| unit the design names | in tree | consumers |
| --- | --- | --- |
| `sockets` | **633 lines**, FPC-compatible IPv4 core | `lib/rtl/netdb.pas`, `test/lib_sockets.pas`, `test/lib_tls.pas`, `test/lib_https_mock.pas` |
| `baseunix` | 149 lines, `timeval` family + `fpgettimeofday` | **10 files** name it in a `uses` clause: `test/lib_unixshims.pas` and nine `examples/**` (all four mandelbrot, four parallel, raytracer_gui) |
| `unix` | 46 lines, minimal shim | Synapse's `synautil` |
| `unixutil` | 16 lines, minimal shim | Synapse's `synautil` |
| `unixtype` | **absent** | — |
| `Posix.*` | **absent** | — |

All four were grown demand-driven under `feature-synapse-compile-check`, and
`baseunix.pas` says so in its own header: *"NOT a port of FPC's BaseUnix — grow
it only as further units demand symbols."*

### That inverts the design's one settled question

The design's master decision was that **`Posix.*` is canonical and the
FPC-named units are thin wrappers over it, not siblings**. In tree the FPC-named
units ARE the implementation, sitting directly on the PAL, and the thing they
were supposed to wrap does not exist.

So building this as designed is not "low-priority work with no consumer". It is
a **refactor that inverts a working, consumer-bearing layer** so it can sit on a
base that nothing calls — with `sockets.pas`'s 633 lines and its four
consumers carrying the risk, and `baseunix`'s ten behind them. The value of
that inversion is real, but it arrives only when something needs
`Posix.SysSocket` spelled directly, and nothing does.

**Recommendation unchanged, reason upgraded:** do not build it. The old reason
was "no consumer". The new reason is that the tree has already answered the
design's central question the other way, by shipping, and the design has not
been re-argued against that answer. Whoever picks this up should start by
deciding whether "Posix is master" still holds now that the FPC-named units are
load-bearing — that is a `decide-` question, not an implementation task.

### One false positive worth naming

`test/dotted/posix.syssocket.pas` exists and is **not** a facade — it is an
11-line compiler fixture for dotted unit names (`AF_INET = 2`, `SockTag = 42`).
A grep for `Posix.` in this repo finds it and reads as prior art. It is not.

### Filing note

This ticket is the second instance of the shape in
[[chore-t-a-standing-collector-cannot-say-so-to-the-ranker]]: its own second
line says *"filed to preserve a design, not to schedule work"*, and it was
nonetheless offered as work. Unlike the crtl collector it is at p25 rather than
at the head of a queue, so it misleads less — but it would be a `standing:`
ticket under that proposal, and it is the case that shows the field is not
needed only for collectors.

## 2026-08-30 — dispatched again, re-measured again, and now BLOCKED on a `decide-`

Offered as work a second time (frankB, Track B), the queue being thin above p25.
The 2026-08-28 note's recommendation stands and is strengthened; what it lacked
was a mechanism to stop the ticket being re-offered, since a recommendation in
prose is invisible to the ranker. It now has one: `blocked-by:`
[[decide-posix-master-vs-fpc-named-master-for-the-socket-facades]]. **Do not
pick this up until that resolves** — the question is which way the layering goes,
and it is not Track B's to answer.

### The 2026-08-28 table re-verified against `d9b663137` — accurate, with two fixes

Line counts and absences confirmed exactly: `sockets` 633, `baseunix` 149,
`unix` 46, `unixutil` 16, `unixtype` and `Posix.*` absent. `sockets.pas` sits on
`platform` (PAL) directly — `uses platform, sysutils`, 17 PAL call sites — so
"the FPC-named units ARE the implementation" is measured, not inferred. Two
corrections, both cutting the same way:

- **`baseunix` has 11 in-tree consumers, not 10** — `test/manual/test_pylexer.pas`
  was missed. Plus Synapse: `synautil.pas:81`, `synaser.pas:139`, and the three
  `ssl_openssl*_lib.pas`.
- **`compiler/compiler.pas` is a FALSE POSITIVE.** It does say
  `uses SysUtils, Math, BaseUnix, …` at line 39 — inside `{$ifdef FPC}`, true
  only under real FPC, so it binds FPC's own BaseUnix during the seeded
  bootstrap and is not taken under PXX self-host. A grep reads it as "the
  compiler depends on this" and would wrongly put the self-host gate in an
  inversion's blast radius. Second instance of this ticket's own "false positive
  worth naming" section — the first was `test/dotted/posix.syssocket.pas`.

### The finding the earlier note did not have

**All three of the design's selectable backends already exist, one layer down at
the PAL.** `posix_syscall` → `lib/rtl/platform/posix/platform_backend.pas`;
`posix_libc` → that file's `-dPXX_DYNLIB_LIBC` path; `posix_lwip` →
`lib/rtl/platform/esp/platform_backend.pas`. The design's own vocabulary
(`PXX_POSIX_LIBC`, `posix_syscall`, `posix_lwip`) appears **nowhere in the tree**
outside this ticket, closed `feature-networking`, and `plan-networking.md` — it
was never spoken in code because the capability landed under PAL's names. So
building `Posix.*` as designed adds a *second* backend-selection mechanism over
a substrate that already selects backends, and a *fourth* face over PAL
(`sockets`, `net.pas`, `asyncnet.pas` are the three).

And the design's rationale for Posix-as-master was goal 2 of the programme:
compile Synapse via its **Delphi-`Posix.*` branch, explicitly not the FPC one**
(`plan-networking.md:16`, `:188-202`). Every Synapse job in `lib-test` compiles
with `--mimic-fpc` — the branch the plan said not to target. The goal that made
Posix master was dropped, and the route that shipped is the one it ruled out.
Details and the fork in the `decide-` ticket.

### Gate note for whoever eventually builds this

Nothing was built and nothing needs re-verifying: this session read the tree and
wrote tickets. No `lib-test` / `demos` run is claimed and none was needed.
