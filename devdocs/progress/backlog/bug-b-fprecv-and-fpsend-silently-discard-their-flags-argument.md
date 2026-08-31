---
slug: bug-b-fprecv-and-fpsend-silently-discard-their-flags-argument
title: "fpRecv/fpSend/fpSendTo/fpRecvFrom accept a flags argument and discard it — MSG_PEEK hangs the caller"
track: B
prio: 55
type: bug
blocked-by: []
status: new
created: 2026-08-31
owner: frankB
summary: "MEASURED: sockets.pas's fpSend/fpRecv/fpSendTo/fpRecvFrom take a `flags: cint` parameter and never read it -- the four bodies call PalSend/PalRecv/PalSendToIpv4/PalRecvFromIpv4, none of which has a flags parameter at all. So MSG_PEEK is silently dropped: two successive fpRecv(..., MSG_PEEK) calls should both return the same bytes, but the first CONSUMES them and the second BLOCKS FOREVER (repro hangs, timeout exit 124; the first returns 8 with the right bytes, so the wrong answer is a hang, not a bad value). MSG_OOB is dropped the same way. This is NOT the SIGPIPE bug: MSG_NOSIGNAL is now set unconditionally inside the PAL send primitives, so closed-peer death is fixed independently of this. The fix is a real signature change -- a flags parameter through platform.pas and the posix/esp/wasi backends -- which is why it is filed rather than folded into the SIGPIPE fix."
---

# What was measured

`lib/rtl/sockets.pas` — all four bodies take `flags` and ignore it:

    function fpSend(s: cint; msg: Pointer; len: cint; flags: cint): ssize_t;
    begin Result := SockRetSize(PalSend(s, msg, len)); end;      { flags unread }

Same shape at `fpRecv`, `fpSendTo`, `fpRecvFrom`. `MSG_OOB`/`MSG_PEEK`/
`MSG_NOSIGNAL` are declared at `sockets.pas:108` and no call site can make any of
them take effect.

## Repro — the failure is a HANG

Send 8 bytes, then peek twice on the receiving socket:

    n1 := fpRecv(cli, @r1[0], 8, MSG_PEEK);   { -> 8, bytes correct }
    n2 := fpRecv(cli, @r2[0], 8, MSG_PEEK);   { blocks forever }

`peek1 returned -> 8  first byte 100`, then nothing; `timeout 20` kills it (124).
The first peek consumed the data, so the second waits for bytes that will never
come. A caller doing the standard "peek at the header, then read the whole
message" gets a deadlock, not a wrong value.

## Why it is not fixable at the sockets.pas layer

`PalSend(handle, buf, len)` / `PalRecv` / `PalSendToIpv4` / `PalRecvFromIpv4`
have no flags slot in their signatures. Threading one through means touching
`lib/rtl/platform.pas` plus all three backends
(`platform/{posix,esp,wasi}/platform_backend.pas`) and every caller — coordination
and memory, hence a ticket.

Note the posix send primitives now pass `MSG_NOSIGNAL` unconditionally
(`bug-b-fpsend-to-a-closed-peer-kills-the-process-msg-nosignal-is-never-passed`).
A flags parameter must OR that in rather than replace it, or the SIGPIPE bug
returns for every caller that passes 0 — which is most of them.

## FPC parity

FPC's `Sockets` passes flags straight to the syscall. This is a genuine parity
gap in a unit whose header claims the FPC surface, not a deliberate divergence.
