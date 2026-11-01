---
track: B
prio: 70
type: bug
---

# The builtin Copy builds its result a char at a time (30x slow on ESP32)

Reported 2026-11-01 by the remote_thermostat session, measured on a classic
ESP32 bridge board (xtensa, IDF 6.0.1). Parsing 33 mesh lines of ~470 chars
took 1032 ms with `Copy`, and 37 ms after the app swapped in its own
SetLength + Move. Mesh firmware-update throughput went from 0.5 KB/s to
7.2 KB/s, mostly because of that swap.

**Cause.** `__pxxStrCopy` in compiler/builtin/builtin.pas, which every program
without sysutils gets for `Copy`, looped `r := r + s[i]`. That is one append,
and so potentially one realloc, per char. `Delete` and `Insert` were built from
two such Copies plus a concat. sysutils' own Copy already used
SetLength + Move.

**Fix.** Copy is one `SetLength` plus one `__pxxMove`, and it re-reads
`Length(Result)` so a frozen (short) Result is still clamped to its capacity.
Delete and Insert each build the new string with one SetLength and up to three
Moves. The same commit fixes sysutils' Copy, which formed `index + count - 1`
before capping count: `Copy(s, i, MaxInt)` overflowed and returned `''`.

Measured on x86-64 under callgrind: 400 Copies of ~470 bytes went from 51.9M
instructions to 0.6M (about 87x). The algorithm is the same on every target.

**Test.** test/test_copy_delete_insert_are_one_move.pas (+ .expected) covers
every clamp edge, `Copy(...)[k]`, a string[5] result, a shared source left
untouched, and a 5000-byte string. Its output is identical to FPC 3.2.2. It
runs in test-core on x86-64 and riscv32, and also matched by hand on xtensa,
i386, aarch64 and arm32.

**Confirmed on hardware** 2026-11-01 by the thermostat session, ESP32 bridge
board, d1a3dc081d built through tools/pxx_latest.sh, with the app's workaround
removed. NextWord on 33 lines: 1032 ms (old builtin), 37 ms (workaround),
40 ms (new builtin). The whole S command went from 1354 ms to 215 ms, and a
32-frame round trip from 2.8 s to 0.69 s. No libgcc helpers.
