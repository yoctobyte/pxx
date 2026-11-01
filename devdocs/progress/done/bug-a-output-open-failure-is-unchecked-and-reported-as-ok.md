---
track: A
prio: 50
type: bug
blocked-by: []
summary: "When the output executable cannot be opened for writing (measured: ETXTBSY because the previous build is still running), pxx writes the whole image to the negative 'fd' (-26) one byte at a time, every write failing EBADF, then prints `ok: <file> [code=...]` and exits 0. The old binary stays on disk and is reported as freshly built. Measured 2026-09-30 with pinned v398 via strace."
status: done
owner: ""
---

# Output open failure is unchecked, and reported as success

- **Type:** bug (ELF/output writer) — **Track A**.
- **Filed:** 2026-09-30 from `~/museum_landkaart` (an ESP32-C3 app with a host
  build that serves HTTP). Rebuilt the host binary while it was running,
  and got `ok` + exit 0. The web page served afterwards was the old one.

## Repro

```sh
pxx prog.pas prog && (./prog &)      # any long-running program
pxx prog.pas prog; echo "exit=$?"     # -> ok: prog [...]   exit=0
strace -e trace=write pxx prog.pas prog 2>&1 | grep -m3 EBADF
# write(-26, "\177", 1) = -1 EBADF
# write(-26, "E", 1)    = -1 EBADF
# write(-26, "L", 1)    = -1 EBADF
```

`-26` is `-ETXTBSY`: the open's error return is used as the descriptor.

## Why it matters

"A clean exit is not evidence about the binary" is already a house rule
for `compiler/pascal26`; this is the same trap for every user program, and the
compiler itself is what's printing the lie. The open result is not checked; it
should fail with a diagnostic and a nonzero exit. (A successful build of the same
program makes 68 `write` calls, so the byte-at-a-time writes are a
failure-path fallback, not the normal writer.)

A reasonable fix also sidesteps ETXTBSY entirely: write `<out>.tmp`, then
`rename` over `<out>` (a rename replaces a running executable fine).

## Acceptance

Building over a running binary either succeeds (new inode via rename) or fails
with a message and a nonzero exit, never `ok` with the old file in place.

## Resolution (2026-11-01)

By the time this was picked up, the exit code was already honest: the
short-write check (a5d4348b22) turned the `ok` into exit 1. But the message
blamed the disk ("df -h, df -i, ulimit -f"), and a build over a running
program still could not succeed.

Fix: every artefact writer opens through OutOpen (compiler/util.inc). On
ETXTBSY it unlinks the old file and opens again, as ld does: the running
process keeps its inode and the new build gets a new one. This uses a raw
unlinkat per host architecture in the self-hosted build and fpUnlink under
FPC. The `.map` writer, the wasm/asm text writers, the disassembler output and
the ELF linker output use it too, which covers the 14 sites that opened with
577 directly.

Measured: building over a running program gives exit 0, `ok:`, a new inode,
and the old process still running. Pin control: rc=1. fpc-check (FPC-built
compiler byte-identical) passes.

Test: test/test_building_over_a_running_program_replaces_it.pas, a test-core
row that starts the program, rebuilds it, and expects `rc=0` plus the new
output.
