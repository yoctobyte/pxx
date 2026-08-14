---
track: B
prio: 45
type: bug
summary: "lib_platform_esp calls every Pal* entry point with fd 0 — literally stdin — so its output changes with how the run was launched, and PalSocketClose(0) closes stdin mid-test; with stdin closed its own PalSocket() is handed fd 0 and half the results change meaning. lib_sockets binds a fixed port 28744, so two concurrent runs collide. Both diagnosed with repros by Track T; the harness half is already fixed."
status: done
owner: track-b-bughunt
---

# `lib_platform_esp` uses fd 0 as a socket, and `lib_sockets` binds a fixed port

- **Type:** bug (test sources) — **Track B** (`test/lib_*.pas`).
  Diagnosed by Track T on 2026-08-14 while resolving
  [[bug-t-three-network-tests-flake-and-cost-real-debugging-time]].
  **T owns the tool, never the bug** — the harness half is fixed, these are yours.
- These were read as *flaky network tests* for weeks. Neither is about the
  network, and one is not about timing either.

## 1. `test/lib_platform_esp.pas` — every call passes fd 0, which is stdin

```pascal
writeln('bind=',      PalBindIpv4(0, PAL_NET_IP_LOOPBACK, 48691));
writeln('recv=',      Integer(PalRecv(0, nil, 0)));
writeln('sockclose=', PalSocketClose(0));        { <- closes STDIN }
writeln('poll=',      PalPoll(0, PAL_POLL_IN, 0));
```

There is no socket here. `0` is whatever file descriptor 0 happens to be, so
the test measures the launch environment. Measured, same binary, four stdin
kinds:

| stdin | `seek` | `flush` | `socket` | `bind` | `connect` |
|---|---|---|---|---|---|
| `/dev/null` | 0 | −22 | 3 | −88 | −88 |
| pipe | **−29** | −22 | 3 | −88 | −88 |
| regular file | 0 | **0** | 3 | −88 | −88 |
| **closed** | **−9** | **−9** | **0** | **0** | **−115** |

The last row is the sharpest: with fd 0 closed, the test's own `PalSocket()`
returns the lowest free descriptor — **0** — so every later `Pal*(0, …)` call
operates on a real socket instead of stdin, and the line stops meaning what it
says. `sockclose=0` then reports success at closing a socket the test created
by accident.

**What the test is presumably for** is asserting the ESP PAL's *unsupported*
surface — that these entry points refuse rather than answer wrongly. That
intent is fine; passing fd 0 is not the way to express it. Use an fd the test
owns (a real `PalSocket()` result), or a deliberately invalid one (`-1`), so the
answer is about the PAL rather than about the shell.

## 2. `test/lib_sockets.pas` — fixed port

```pascal
const PORT = 28744;
...
a.sin_port := htons(PORT);
```

Two concurrent runs collide, which is exactly what happened when a gate and a
cross-sweep overlapped. `test/lib_net_v6only.pas` already shows the fix in this
same tree — it binds port 0 and reads back what it got:

```pascal
if (rc < 0) or (bound.Port <= 0) then ...
client := NetTcpConnectTimeout(NetLoopback(bound.Port), 2000);
```

## 3. `lib_net_v6only` — no defect found

Included for completeness because the original ticket named it. **20 consecutive
runs with an unchanged binary produced one identical output.** It already binds
port 0, so the fixed-port hypothesis does not apply. Its one observed flake
(`gate.sh lib` RED, GREEN on re-run) remains **unexplained** — most likely
collateral from whatever else was contending at the time, possibly the
`lib_sockets` port above. Do not "fix" it speculatively; if it recurs, capture
the failing output, because nothing here reproduces it.

## What Track T already did

`tools/testmgr.py` now launches every job with `stdin=subprocess.DEVNULL`
(`Manager.launch`), so under testmgr fd 0 is deterministic regardless of how the
run was started. That removes the *variance*, and it is worth having on its own
merits — but it does not fix these tests: a plain `make lib-test` from a
terminal still hands `lib_platform_esp` a tty, and the test still closes its own
stdin. Covered by `tools/devtest_job_stdin.py`.

## Gate

Each of the two, run 10x with an unchanged compiler, gives one verdict — and
for `lib_platform_esp`, one identical *output* under `/dev/null`, a pipe, a
regular file and a closed fd 0. That last one is the real check; port
independence is the easy half.

## Log
- 2026-08-14 — resolved, commit 2e508c822.

## Resolved 2026-08-14 (Track B)

### 1. `lib_platform_esp` — `BADFD = -1` everywhere

Every `Pal*` fd argument now passes the named constant `BADFD = -1` instead of
`0`, so the answer is about the PAL rather than about how the run was launched,
and nothing can close the test's own stdin. The one call that may legitimately
succeed, `PalSocket`, now closes what it opened and reports `socket=ok` rather
than the descriptor NUMBER — which is likewise an environment fact (it is
whatever happened to be free).

**Measured, the ticket's own gate.** One binary, four stdin kinds
(`/dev/null`, a pipe, a regular file, fd 0 closed):

| build | before | after |
| --- | --- | --- |
| `--platform=esp` (the gated one) | identical | identical |
| `-Fulib/rtl` (posix PAL — what `lib_cross_sweep.sh` builds) | **four different outputs** | **one identical output** |

The esp build's output is byte-for-byte what it was, so none of the three
recorded expectations (Makefile, `tools/library_suite.sh`) needed touching —
`PalSocket` returns `-38` there, so the new branch still prints `socket=-38`.

### 2. `lib_sockets` — port 0 + `fpGetSockName`

`PORT` is now `0` and the client aims at the port the kernel actually handed
out, read back with `fpGetSockName` — the same shape `test/lib_net_v6only.pas`
already used. That adds one assertion line (`sockname=ok`), so the Makefile
expectation gained it; `fpGetSockName` had no other coverage.

**Measured:** 10 sequential runs → one identical output; **8 concurrent runs →
one identical output**, which is the case that used to collide.

`tools/optdiff.skip` dropped its `lib_sockets*` entry — its stated reason
("fixed port, TIME_WAIT flakes across back-to-back runs") is exactly what this
fixes, and a stale skip hides real optimizer divergence.

### 3. `lib_net_v6only` — untouched, as the ticket asked

No speculative fix. It already binds port 0.

### Still environment-shaped, deliberately left

The posix build of `lib_platform_esp` still uses fixed `/tmp/no-host-fallback*`
paths for `PalOpen`/`PalMkdir`/`PalRmdir`, so two concurrent posix builds could
in principle race on them. Not fixed here: the gated build is the esp one, where
those calls never reach the filesystem, and `platform.pas` exposes no pid to
build a unique name from. Noted rather than silently left.

### Cross note

`tools/lib_cross_sweep.sh`'s known-benign entry for `lib_platform_esp`
`sendto=-9` vs `-14` **still stands** — re-measured under `qemu-aarch64-static`
after the change and the divergence is unchanged. It is the nil buffer, not the
descriptor: x86-64 reports EBADF first, aarch64-under-qemu reports EFAULT. The
comment's "fd 0" was corrected to "fd -1".

**Gate:** `make lib-test` green against stable v300 (sockets + platform among
the 80 named jobs).
