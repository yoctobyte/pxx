---
slug: bug-b-fpsend-to-a-closed-peer-kills-the-process-msg-nosignal-is-never-passed
track: B
prio: 60
type: bug
status: done
owner: frankB
blocked-by: []
summary: "FIXED 2026-08-31 (frankB). Root cause was one level below the title: `PalBackendSend` called **write(2)**, which has no flags argument, so MSG_NOSIGNAL could not be passed even in principle -- and `PalBackendSendToIpv4/Ipv6` did have a flags slot and passed 0. Fixed in the PAL, the one chokepoint all nine send call sites share (sockets/net/asyncnet/dns/pxxcio): PalBackendSend now uses sendto(2) with a nil destination, and all three pass MSG_NOSIGNAL. Verified x86-64 and aarch64: closed-peer sends return -1/EPIPE(32) and the process survives, healthy TCP+UDP still transmit byte-correct. Regression test `test/lib_sock_closedpeer.pas` wired into lib-test -- it prints nothing and dies with SIGPIPE on the unpatched RTL. The PalWrite arm still dies and is LEFT that way deliberately: those sites are the C write(2) veneer and TFileStream, where SIGPIPE is correct pipeline behaviour. platform.pas's comment, which claimed the signal-disposition mechanism as fact, now describes the real one. Split out: [[bug-b-fprecv-and-fpsend-silently-discard-their-flags-argument]]."
---

# `fpSend` to a closed peer kills the process — `MSG_NOSIGNAL` is defined and never passed

- **Found:** 2026-08-31 by frankA (Track A), closing out item 5 of
  [[feature-signal-siginfo-ucontext]], whose re-entry condition was *"revisit
  with the net library"*. **That condition has fired** — `lib/rtl/net.pas`,
  `sockets.pas`, `http.pas`, `asyncnet.pas` and `netdb.pas` all exist — and
  nobody noticed, which is why this was still parked.
- **Track B's file-lane** (`lib/rtl`), so this is filed, not fixed.

## Measured

`socketpair(AF_UNIX, SOCK_STREAM)`, close one end, write to the other:

```
raw write(2):        exit 141   (128 + 13 = SIGPIPE)
RTL fpSend(s,...,0): exit 141
```

Neither reaches the line after the send. `EPIPE` (-32), the survivable answer, is
never observed because the process is already dead.

## The census

| | |
| --- | --- |
| `MSG_NOSIGNAL` in the tree | **1** occurrence — `sockets.pas:108`, its own `const` |
| `PalIgnoreSignal` callers | `signals.pas:95` only, inside `Signal(sig, SIG_IGN)` |
| networking code touching SIGPIPE | **none** |

So the mechanism exists twice over and is wired up neither time.

## The comment is the interesting part

`platform.pas:132` says, as a statement of fact in the PAL's own header:

> Networking code ignores SIGPIPE so a closed peer yields an error, not death.

Per CLAUDE.md, a comment that disagrees with the code means one of them is wrong
and you do not yet know which. Here the **code** is wrong: a net library whose
`send` kills the process when a client disconnects is a defect on its own terms,
and the comment is a correct description of what it should do. Do **not** fix
this by editing the comment.

## Suggested fix, and why it does NOT need the policy decision

Pass `MSG_NOSIGNAL` on the send paths (`fpSend`, `fpSendTo`, and whatever
`http`/`asyncnet` use underneath), so a closed peer returns `EPIPE`.

This is deliberately **not** a process-wide `PalIgnoreSignal(PAL_SIGPIPE)`, and
that distinction is the whole reason item 5 could stay parked for so long. The
base ticket left SIGPIPE **not** default-ignored on purpose, so that a write-loop
program still dies on a closed stdout — a real and wanted behaviour.
`MSG_NOSIGNAL` is per-call and socket-only, so it fixes networking **without
touching stdout**, and the policy fork dissolves rather than being decided.

A process-wide ignore would trade one silent wrong behaviour for another.

## Check while you are in there

`http.pas` / `asyncnet.pas` may write through a path other than `fpSend`. The
census above counts the CONSTANT, not the send sites — grep the callers before
declaring it fixed, and assert the survivable path by checking for `-32`/`EPIPE`
rather than by the program merely reaching the next line.

## Related

- [[feature-signal-siginfo-ucontext]] item 5 — this is what that item turned out to be
- [[a-comment-recording-a-bug-is-not-a-guard-against-it]]


---

## Resolution (frankB, 2026-08-31)

**The title names the symptom's mechanism, and the cause was one level down.**
`MSG_NOSIGNAL` was not merely "never passed" — at the `fpSend` path it *could
not* be passed, because `PalBackendSend` was:

    Result := __pxxrawsyscall(SYS_write, handle, Int64(buf), len, 0, 0, 0);

`write(2)` has no flags argument. The two `sendto` paths did have a flags slot
and were passing a literal `0`.

### Measured, before

`arms.pas` — one closed-peer connection, three write paths, one arm per run
(a SIGPIPE ends the process, so they cannot share one). All three died at the
**second** send; the first returns 64 because the bytes land in the socket
buffer before the peer's RST is processed:

    send   #1 -> 64  errno=0   EXIT: 141
    sendto #1 -> 64  errno=0   EXIT: 141
    write  #1 -> 64  errno=0   EXIT: 141

Note the `send` arm passed `MSG_NOSIGNAL` explicitly at the call site and it was
discarded — see the split-out ticket below.

### The fix, and why it is at the PAL

Nine call sites send on sockets (`sockets.pas`, `net.pas`, `asyncnet.pas`,
`dns_resolved`, `dns_async` x3, `dns_wire_blocking` x2, `pxxcio`). They share
exactly one chokepoint, so this is a `normalise-dont-special-case` fix at
`lib/rtl/platform/posix/platform_backend.pas` rather than nine edits:

- `PalBackendSend` → `sendto(2)` with a nil destination, flags `MSG_NOSIGNAL`.
- `PalBackendSendToIpv4` / `PalBackendSendToIpv6` → flags `0` → `MSG_NOSIGNAL`.
- i386 arms go through `SockCall6(SC_SENDTO, ...)`, which already existed.

Safe because **every** caller of `PalSend` is a socket by contract — verified by
enumerating all nine; none passes a plain file descriptor, so the new `ENOTSOCK`
surface is unreachable.

posix only. ESP's `lwip_send` has a flags slot but FreeRTOS delivers no signals,
so there is nothing to suppress; WASI's socket primitives are
`PAL_ERR_UNSUPPORTED`.

### Measured, after (x86-64 and aarch64 under qemu, both identical)

    send   #1 -> 64  errno=0 / #2..#4 -> -1 errno=32 (EPIPE)   SURVIVED, EXIT 0
    sendto #1 -> 64  errno=0 / #2..#4 -> -1 errno=32 (EPIPE)   SURVIVED, EXIT 0
    write  #1 -> 64  errno=0                                   EXIT: 141  (deliberate)

Positive control, needed because a syscall was *replaced* rather than tweaked —
healthy sockets must still carry data, checked by value not by exit code:
`tcp send/recv 64` byte-identical, `udp sendto/recvfrom 64` byte-identical,
`CONTROL OK`.

### The `write` arm is left dying, on purpose

The two `PalWrite`-to-a-possible-socket sites are `pxxcio.pas:153` (the C
`write(2)` veneer) and `classes.pas:669` (`TFileStream.Write`). Real `write(2)`
raises SIGPIPE, and a program in a shell pipeline *should* die when its reader
goes away. Suppressing SIGPIPE process-wide with `PalIgnoreSignal` would have
fixed all three arms in one line and been wrong for exactly this reason — it is
why the fix is a per-call flag and not a signal disposition.

### Cross-target check

`i386`, `riscv32`, `xtensa` and `wasm32` fail to build this RTL both before and
after, with identical pre-existing errors (i386 param passing, riscv32 atomics,
xtensa function results, wasm32 `SYS_openat`); the only delta is a wasm32 line
number moving 409→412, matching the three added lines. `aarch64` and `arm32`
build; aarch64 runs green. **No cross-target regression.**

### Regression test

`test/lib_sock_closedpeer.pas`, wired into `lib-test` after
`lib_platform_net_sockopt`. Expected output `send=ok / sendto=ok / live=ok /
survived`. Confirmed to discriminate: against the unpatched RTL it dies with
SIGPIPE having printed **nothing at all** — which is the point of the trailing
`survived` line, since the failure mode is a killed process rather than a wrong
value, so the assertion has to be a line that only a live process can print.

### Split out, not fixed here

[[bug-b-fprecv-and-fpsend-silently-discard-their-flags-argument]] — `fpSend`,
`fpRecv`, `fpSendTo` and `fpRecvFrom` all take a `flags` parameter and never read
it. Measured: two successive `fpRecv(..., MSG_PEEK)` calls should return the same
bytes; the first consumes them and the second **blocks forever** (timeout 124).
Fixing it means adding a flags parameter to the PAL across three backends, which
is a separate change with its own blast radius. That ticket notes the new
unconditional `MSG_NOSIGNAL` must be OR-ed in, not replaced, or this bug returns
for every caller passing 0.

## Log
- 2026-08-31 — resolved, commit PENDING-COMMIT.
