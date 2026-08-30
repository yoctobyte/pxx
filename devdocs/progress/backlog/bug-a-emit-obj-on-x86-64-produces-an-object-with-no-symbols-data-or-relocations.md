---
track: A
prio: 40
type: bug
status: open
found: 2026-08-30
found-by: claude-T
---

# `--emit-obj` on x86-64 emits an object that exports nothing

Same source, same compiler, one flag apart. `test/test_emit_obj.pas`:

| target | sections | symbols |
| --- | --- | --- |
| riscv32 | `.text .rela.text` **`.data(0xb18) .rela.data .bss(0xa530)`** `.symtab(0xa60)` | **166**, incl. `app_main` FUNC GLOBAL |
| xtensa | `.text .rela.text` **`.data(0x840) .rela.data .bss(0xa530)`** `.symtab(0xab0)` | full |
| **x86-64 `--emit-obj`** | `.text` `.rela.text(size 0)` `.symtab(0x60)` | **4** |

The four x86-64 symbols are the null entry, a `.text` section symbol, and the
two UND imports. **There is no defined symbol at all** — no `app_main`, no
function. Nothing can link against this object because it exports nothing, and
it carries no data, no bss and zero relocations.

## It reports success, with figures the file does not contain

```
$ compiler/pascal26 -Fulib/rtl --emit-obj test/test_emit_obj.pas /tmp/teo.o
ok: /tmp/teo.o  [code=61709B  data=2864B  bss=42332B  procs=132]
```

`data=2864B bss=42332B procs=132` — and the object has no `.data`, no `.bss`,
and one defined symbol short of none. The summary line describes a compilation
that happened; the file describes what was written; nothing reconciles them.

## Why nothing caught it

`test-emit-obj` is a real, careful test — it asserts both directions of the
external-name aliasing bug, which is the kind of negative most tests skip. It
just never runs this path: every one of its assertions is against
`--target=riscv32` or `--target=xtensa`, and neither uses the `--emit-obj` flag.

> A test that exists, passes, and is unwired to this target — face 222,
> exactly. The feature is advertised generally in `--help` and in
> `docs/index.md` (*"also emit a relocatable object (`--emit-obj`, `.o`) for
> linking with other..."*), and is broken on the host architecture.

## Repro

```
compiler/pascal26 --target=riscv32          test/test_emit_obj.pas /tmp/rv.o
compiler/pascal26 -Fulib/rtl --emit-obj     test/test_emit_obj.pas /tmp/x64.o
readelf -SW /tmp/rv.o  | grep -c '\.data\|\.bss'     # 3 (.data .rela.data .bss)
readelf -SW /tmp/x64.o | grep -c '\.data\|\.bss'     # 0
readelf -sW /tmp/x64.o | grep -c 'FUNC'              # 0
```

Measured at `46316ba8b`, binary `1ff8acbe123b` (built at `5944ee686`).

## Scope note — I have NOT established what the right behaviour is

Two readings, and choosing between them is Track A's call, not mine:

1. The x86-64 relocatable writer is incomplete, and should emit `.data`,
   `.bss`, `.rela.*` and a real symbol table as riscv32/xtensa already do.
2. `--emit-obj` was only ever meant for the embedded targets, and the x86-64
   path should **refuse** rather than emit a silently unusable object.

Either is defensible. What is not defensible is the current state: an
advertised flag that reports success and writes an artifact that cannot be
used, on the default target. If (2), the fix is an error message and a docs
line, and it is cheap.

## Provenance

Found while investigating whether an external ELF-layout oracle
([[feature-t-a-second-oracle-dimension-section-alignment]]) had anything left to
check after Track A's `df98fea47` alignment invariant landed. It did not, for
alignment — but the objects it looked at on the way turned out to be empty.
T owns the tool, never the bug.
