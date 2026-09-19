---
slug: feature-c-a-function-scope-thread-local-gets-real-per-thread-storage
track: C
prio: 40
type: feature
status: backlog
created: 2026-09-19
found-by: frankS
tags: [tls, threads, c-frontend]
blocked-by: [feature-a-the-threadvar-area-is-3072-bytes-of-bss-in-every-program-that-has-no-threadvar]
summary: "`static __thread int t;` inside a function body now WARNS that it gets one shared copy (TLSREFUSE_FUNCSCOPE, 2026-09-19) — this ticket is the other half: giving it real per-thread storage, as file-scope scalars get on x86-64. IT IS BLOCKED ON THE AREA SIZING AND THAT IS THE WHOLE REASON IT IS NOT DONE ALREADY: the thread-local user area is sized by EmitTlsMainInstall BEFORE anything is lexed, so a NEW CLASS OF CONSUMER meets a size chosen without knowledge of it, and since 402d61e0d a full area is a hard Error rather than a warning. Wiring function scope in today would therefore make a program with several block-scope thread-locals STOP COMPILING where it compiles now (silently wrong under threads) — an acceptance regression in the direction 402d61e0d's author deliberately chose for FILE-scope declarations, where the programmer wrote `__thread` and can read the flag in the diagnostic; a block-scope static in a vendored dependency is not that case. The conjunction that produced eight red rows on 2026-09-19 (a zero-sized NilPy area, errno becoming __thread, area-full becoming an Error) is the same mechanism firing, so the sizing is known-moving rather than merely suspected. ir_codegen.inc's own comment names the prerequisite in its own words: \"a cleverer scan is not the improvement here; moving the decision is, and that is a different change with its own measurement\". The warning is landed and correct meanwhile; nothing here is urgent and nothing is silent."
---

# Function-scope `__thread` deserves real storage, once the area can see it

## Where this starts from

The warning half is landed:
`bug-c-thread-local-storage-still-shares-one-copy-off-x86-64-and-a-warning-is-all-that-stands-there`
gained a sixth reason, `TLSREFUSE_FUNCSCOPE`, because a thread-local declared
inside a function body was the **only member of the degraded family that said
nothing at all** — it never reached `TryAssignThreadVarStorage`, so it was not
refused for a reason, it was never asked.

That fix deliberately **does not reach the allocator**, changes no storage, and
consumes no area slots. This ticket is the part it declined.

## Why it is blocked rather than merely unstarted

`EmitTlsMainInstall` bakes the area size **before anything is lexed**. So any
new class of consumer meets a size chosen without knowledge of it, and
`402d61e0d` made a full area a hard `Error`.

Wiring function scope in today means: a translation unit with several
`static __thread` declarations in bodies — which **compiles today** and is
silently wrong under threads — **stops compiling**. That is a refusal of a
working build to protect it from a race, which is precisely the trade the
file-scope path declined for the four reasons that are our own limits.

**This is not a theoretical interaction.** On 2026-09-19 three individually
correct changes conjoined — a NilPy program's area fixed at zero (`6a87b7f89`),
every C unit declaring a thread-local through `errno.h` (`c5ae069c5`), and
area-full becoming an `Error` (`402d61e0d`) — and every mixed NilPy+C build
refused. Eight red rows, none of the three in the bisect range. The sizing is
**known to be moving**, not suspected of it.

## The prerequisite, in the code's own words

`compiler/ir_codegen.inc` already states it:

> *a cleverer scan is not the improvement here; moving the decision is, and that
> is a different change with its own measurement*

So the blocker is the area-sizing decision moving to where it can see the
declarations, or the cap ceasing to be a compile-time constant. That is Track A
and larger than this ticket; wired as `blocked-by` so this ranks honestly
instead of sitting behind a sentence in somebody's message.

## Acceptance

**Assert the RELATION, not a per-target constant**: two threads must never see
each other's value for the same function-scope thread-local, and their addresses
for it must differ. That carries no expected width, passes on every target that
implements it, and fails on every target that shares one copy — so it needs no
per-target table to maintain and cannot pass by matching a default.

**Positive control:** the fixture must also assert that a block-scope static
**without** `__thread` still shares one copy across threads, or a change that
made every block-scope static thread-local would pass it.

**And carry the non-change row from the warning fixture** —
`test/c_func_scope_thread_local_warns.c` asserts `static __thread` still counts
`1 2 3` single-threaded, matching gcc. Real storage must not break that.
