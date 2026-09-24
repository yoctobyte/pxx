---
slug: bug-b-the-scheduler-s-default-coroutine-stack-does-not-fit-an-esp32
track: B
tags: [S]
type: bug
prio: 35
status: done
owner: ""
created: 2026-09-24
found-by: frankH (running the windowed CoSwitch on an ESP32-S3)
blocked-by: []
summary: "FIXED 2026-09-24. Two causes, and the filed one was the smaller: on --platform=esp the scheduler's reactor table (64 slots x six MAX_CO-wide arrays, ~150 KB of bss) left almost no heap on an ESP32-S3 before any stack was allocated, AND the default coroutine stack was the hosted 192 KB. Now MAX_REACTORS = 1 on ESP (no capability lost: every raw syscall answers -ENOSYS there, so every FreeRTOS task already read tid -38 and attached to slot 0) and CO_STK = 32 KB, derived from measured high-water marks (httpdemo 18,064 B, deep-yield test 3,832 B on ESP-IDF). Hosted targets unchanged. Stated on Spawn's interface comment and in docs/library/async.md, including that a TLS handshake (~128 KB) needs SpawnSized. Guard: test-xtensa asserts an esp32s3 test_scheduler build has bss < 64 KB (172,560 B before, 24,384 B after)."
---

# The scheduler's default coroutine stack does not fit an ESP32

## Measured (2026-09-24, HEAD after the windowed CoSwitch)

**Setup.** test/test_scheduler.pas (three `Spawn` calls), built with only
`--target=esp32s3` and booted under S3 QEMU (-m 4M, no PSRAM).

**Result.** It prints nothing and aborts:

    pxx: out of memory (ESP-IDF heap exhausted)

The message is from builtinheap's ESP-IDF branch.

**Control.** The same three shapes pass on the real board with
`SpawnSized(..., 16384)`:
- the file is test/test_scheduler_yields_deep_in_a_call_chain.pas;
- it recurses 20 frames deep before each yield;
- it matches the x86-64 oracle.

So the context switch is fine. The default stack size is the problem.

## Not the ABI

The call0 build hits the same arithmetic. It only never ran on IDF, because
IDF could not call a call0 object before 2026-09-24.


## Resolution (2026-09-24, frankH)

**The measurement changed the diagnosis.** After CO_STK alone was cut to
32 KB, httpdemo still ran out of heap at the same SpawnSized GetMem. The
bss line said why: a trivial scheduler program had **172,560 B of bss**.
That is the reactor table, which on ESP can only ever use slot 0.

**High-water method.** A scratch copy of scheduler.pas (never committed):
- paints each stack with $5A5A5A5A at spawn;
- scans up from the canary when the coroutine finishes.

| program | where | used | given |
| --- | --- | --- | --- |
| test_scheduler_yields_deep_in_a_call_chain | ESP-IDF S3 QEMU | 3,832 B | 16 KB |
| test_scheduler_yields_deep_in_a_call_chain | qemu-xtensa windowed | 3,952 B | 16 KB |
| examples/net/httpdemo, larger coroutine | qemu-xtensa windowed | 18,064 B | 192 KB |
| examples/net/httpdemo, smaller coroutine | qemu-xtensa windowed | 6,320 B | 192 KB |

**Verified:**
- **Board:** unmodified test/test_scheduler.pas (three plain `Spawn`) on the
  ESP32-S3, built with `--target=esp32s3`, matches the x86-64 oracle, 7/7
  lines. Before the fix it aborted out-of-memory under S3 QEMU.
- **esp32c3:** builds, bss 24,384 B.
- **gate.sh quick:** GREEN.

**Not reached, and why:** httpdemo on ESP-IDF.
- Past the scheduler, it asserts in lwIP (`tcpip_send_msg_wait_sem`),
  because nothing called `esp_netif_init`. The net-c3 example makes that
  call itself, and httpdemo is a hosted example.
- With the call added in a scratch copy, it hangs silently after app_main.
  epoll is -ENOSYS on ESP, so the reactor degrades to polling, and a
  blocking lwIP socket call never yields.
- That is the ESP async-networking layer, not the stack size. Its figure
  above is therefore from qemu-xtensa (same code generator, same ABI).

## Log
- 2026-09-24 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit b2f5d2e52.
