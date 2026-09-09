---
slug: feature-p-threadvar-is-not-supported-at-any-scope
title: "`threadvar` is not supported at any scope"
track: P
prio: 40
type: feature
blocked-by: []
status: open
owner: ""
created: 2026-09-06
summary: "`threadvar t: LongInt;` at program or unit level is refused with `expected 'begin' before 'threadvar'`. FPC supports it, and it is the language's only spelling for thread-local storage -- so a program that wants per-thread state has no way to ask for it. Measured 2026-09-06 by probe while dispositioning tclass17 and terecs21, two `%FAIL` rows about `threadvar` INSIDE A CLASS whose refusals were being satisfied by this gap rather than by their own subject."
---

# The measurement

```pascal
program p; {$mode objfpc}
threadvar t: LongInt;
begin t := 1; WriteLn(t); end.
```

```
pascal26: error: expected 'begin' before 'threadvar'
```

# What it costs

`threadvar` is the only source-level spelling of thread-local storage in the
dialect. Anything wanting per-thread state — an error code, a current-context
pointer, a per-thread allocator cache — has to reach for a different mechanism
or not have one. Ranked as a feature rather than a bug because nothing miscompiles;
the declaration is simply not accepted.

Two corpus rows (`tclass17`, `terecs21`) assert that `threadvar` is invalid
INSIDE A CLASS. They pass today, and not for that reason — pxx never gets far
enough to have an opinion about the class. Closing this gap turns them into real
assertions, and they should be re-measured then rather than assumed.

`task-t-twelve-syntax-shaped-fail-rows-may-be-refused-by-a-parse-gap-rather-than-their-own-subject`

## PROSE EDGES BY DESIGN

## The same concept fails the OPPOSITE way in the C frontend

`bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared`
is this gap one frontend over, and the pair is worth holding together because
the failure modes are inverted: **Pascal refuses loudly and C accepts and
shares the storage silently.** Neither frontend has thread-local storage; only
one of them says so. A program that wants per-thread state gets a diagnostic in
Pascal and a race in C.

Not wired as `blocked-by` in either direction — neither gates the other, and
they will most likely be fixed by one shared TLS mechanism rather than by each
other.

## What it blocks in the corpus, measured 2026-09-06 at compiler 0d77c1e48ea4

`tclass16.pp` and `terecs20.pp` (the `%SKIPTARGET=$nothread` pair, `class
threadvar` in a class and in a record) are gated on THREE things, not the two
their skip rows named:

1. this ticket — plain `threadvar` at any scope,
2. `class threadvar` inside a class/record body, which is the rung above it,
3. the **RTLEvent family** — `PRTLEvent`, `RTLEventCreate`, `RTLeventSetEvent`,
   `RTLeventWaitFor`, `RTLEventDestroy` — absent from `lib/rtl` entirely.

Rung 3 is NOT the general threading surface, which is largely present and
tested: `BeginThread`, `WaitForThreadTerminate`, `TThreadID`, `EndThread` and a
native `TThread` all exist (`lib/rtl/palthreadobj.pas`, `lib/rtl/cthreads.pas`,
`test/lib_fpc_thread_surface.pas`). A first probe of these two rows reported the
whole threading RTL missing and that was the probe's fault — it omitted the
`uses` clause, so `unknown type: TThreadID` was about the program and not about
the RTL. Filed as `feature-b-the-rtlevent-family-is-absent-from-the-threading-rtl`.


## What a taker should know before starting (2026-09-09, frankS)

Not an edge, deliberately — I have not established that this is blocked, and
saying so in prose without the frontmatter edge is how a ticket lies to its
reader. What I did establish is that **the mechanism this feature needs already
partly exists**, which the ticket does not say:

- `thread_emit.inc:142` installs a per-thread block via `arch_prctl(ARCH_SET_GS)`
  — *"GS, not fs: fs belongs to libc, and a pxx program may link one"* — and a
  pxx-native thread gets a DISTINCT non-zero GS base (measured 2026-09-06 by
  frankC on a pxx `BeginThread`: main `42D110`, child `7BDB21FF7A80`).
  `TLS_SLOT_*` / `TLS_BLOCK_SIZE = 1152` has three free map slots plus a 64-slot
  tail, which `ir_codegen.inc:78` records as UNUSED rather than absent.
- So a pure-pxx `threadvar` may be implementable on what is already there,
  without touching ELF TLS at all.

**And the thing that may or may not make it a fork:**
[[decide-pxx-thread-local-storage-is-gs-relative-and-the-x86-64-psabi-is-fs-relative]]
is open. It is about INTEROP — TLS relocations in gcc-built objects are
fs-relative and ours is gs-relative — so it may leave a pxx-only `threadvar`
entirely alone. **That is the question to settle first**, and it is one
measurement, not a design discussion: does anything in the intended
implementation emit or consume an ELF TLS relocation? If no, this ticket is
unblocked and the decide ticket is about a different program. If yes, wire the
edge.

The sibling in C is [[bug-c-__thread-is-accepted-and-silently-ignored-so-thread-local-storage-is-shared]],
and the two frontends fail in OPPOSITE directions on the same missing feature —
Pascal refuses loudly, C accepts and shares one `.bss` object. Whoever builds
the mechanism should close both; the honest failure and the silent one have the
same cause.
