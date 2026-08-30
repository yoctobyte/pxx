---
track: A
prio: 30
type: bug
status: backlog
found: 2026-08-30
found-by: frankD
blocked-by: []
summary: "--proc-map computes every address as LOAD_ADDR + CODE_OFFSET + BodyAddr, using the STATIC code offset unconditionally. A dynamic build (-dPXX_LIBC_HEAP, --shared) sits at DYNAMIC_CODE_OFFSET, so every PROC line is 0x70 low -- a constant shift over all routines. Measured on the pinned binary. It does not fail; tools/vgsym.py resolves the shifted address to the PRECEDING routine, so the symbolized stack is wrong rather than absent. compiler.pas's own comment already states the limitation; nothing enforces it."
---

# `--proc-map` emits static addresses for a dynamic build

- **Type:** bug (silently wrong tool output)
- **Track:** A — `compiler/compiler.pas`, the `--proc-map` emit site
- **Found:** 2026-08-30 by frankD, auditing `devdocs/dev/valgrind.md`

## The defect

`compiler.pas` (grep `DumpProcMap`) emits one line per routine as

```pascal
writeln(StdErr, 'PROC ', IntToHexStr(LOAD_ADDR + CODE_OFFSET + Procs[i].BodyAddr, 8), ' ', Procs[i].Name);
```

`CODE_OFFSET` is the **static** layout constant. `defs.inc` also defines
`DYNAMIC_CODE_OFFSET` (grep both names; they differ by 0x70), and the ELF writer
uses the dynamic one whenever the binary declares an external — which is what
`-dPXX_LIBC_HEAP` and `--shared` do.

The code comment at the emit site already says *"x86-64 static layout only … a
dynamic build shifts by the dynamic header delta."* So this is a **known**
limitation with nothing enforcing it: no warning, no suppression, no adjustment.

## Measurement (pinned binary, one program compiled twice)

```
program p;
procedure Foo; begin Writeln(1); end;
begin Foo; end.
```

| build | `<out>.map` (the ELF writer's own map) | `--proc-map` on stderr |
| --- | --- | --- |
| default (static) | `0x40efb0 Foo` | `0040efb0 Foo` — agree |
| `-dPXX_LIBC_HEAP` (dynamic) | `0x40eb61 Foo` | `0040eaf1 Foo` — **0x70 low** |

`readelf -l` confirms the second binary carries `PT_INTERP` and
`DT_NEEDED libc.so.6`. 0x70 is exactly the difference between the two offset
constants, so the error is uniform, not noise.

## Why it matters more than a 0x70 rounding error

**It does not fail; it lies.** `tools/vgsym.py` resolves an address with
`bisect_right(addrs, a) - 1` under a 0x20000 tolerance, so a shifted address
still matches *a* routine — the one **before** the correct one, whenever the
0x70 shift crosses a boundary. Most emitted routines are shorter than 0x70. The
consumer therefore gets a confidently symbolized, wrong stack.

The profile where this bites is the one profile that exists for debugging:
`-dPXX_LIBC_HEAP` is the valgrind heap profile. Every leak hunt run per
`devdocs/dev/valgrind.md`'s old instructions was symbolizing through a uniformly
shifted table.

## Fix

One line: select `DYNAMIC_CODE_OFFSET` when the build is dynamic, the same way
the ELF writer already does. If that selection is not reachable at the emit
point, the honest fallback is to refuse — print nothing and say why — rather
than emit a table that is wrong by a constant.

A second, cheaper option worth weighing: **delete the flag.** `<out>.map` is
written by default (`EmitMapFile := True`, `--no-map` suppresses), carries the
correct dynamic address, and `vgsym.py` already parses its format. `--proc-map`
duplicates it, to stderr, less correctly. If the profiler workflow that
motivated it can read `<out>.map`, the flag has no remaining job. That is a
Track U-ish call rather than a fix; stated here so whoever takes this does not
have to rediscover the overlap.

## Doc arm — already done, do not redo

`devdocs/dev/valgrind.md` told readers to pass `--proc-map` and claimed that
flag is what writes `<out>.map`. Corrected 2026-08-30 by frankD: the quick start
now drops the flag, and a section records the measurement above. Note the
pipeline in that doc was always right — it fed `vgsym.py` the `.map` file, not
the stderr — which is exactly why the wrong prose survived. **The instructions
were wrong in a way the printed command did not reproduce.**

## Not verified here

Whether the doc's two caveats about emitted blobs symbolizing as `_start+...`
survive once you symbolize through `<out>.map`. They are consistent with a
uniform 0x70 under-shift (the blobs start at 0x400120 in a dynamic build), but
valgrind is not installed on this box, so that is a hypothesis from the
compiler's output, not a run. Whoever fixes this can settle it in one command.

## Gate
Track A: `make compiler/pascal26` + compile one program dynamic and static, diff
the `--proc-map` stderr against `<out>.map` — they must agree in both modes.
