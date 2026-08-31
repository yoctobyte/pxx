---
slug: bug-b-fpsend-to-a-closed-peer-kills-the-process-msg-nosignal-is-never-passed
track: B
prio: 60
type: bug
status: new
owner: ""
blocked-by: []
summary: "MEASURED, exit 141 (SIGPIPE): a write to a socket whose peer has closed KILLS a pxx program, through the RTL's own `fpSend` as well as through a raw write. `MSG_NOSIGNAL` appears exactly ONCE in the whole tree -- its own definition in sockets.pas:108 -- and is never passed; `PalIgnoreSignal` is called only from the FPC-compat `Signal(sig, SIG_IGN)` wrapper, never by networking code. platform.pas:132 states the opposite as fact: *\"Networking code ignores SIGPIPE so a closed peer yields an error, not death.\"* The comment describes the intended design and the code does not implement it, so this is a bug, not a comment fix. Any pxx server dies when a client disconnects."
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
