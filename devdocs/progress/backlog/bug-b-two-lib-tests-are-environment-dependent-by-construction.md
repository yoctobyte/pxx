---
track: B
prio: 45
type: bug
summary: "lib_platform_esp calls every Pal* entry point with fd 0 — literally stdin — so its output changes with how the run was launched, and PalSocketClose(0) closes stdin mid-test; with stdin closed its own PalSocket() is handed fd 0 and half the results change meaning. lib_sockets binds a fixed port 28744, so two concurrent runs collide. Both diagnosed with repros by Track T; the harness half is already fixed."
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
