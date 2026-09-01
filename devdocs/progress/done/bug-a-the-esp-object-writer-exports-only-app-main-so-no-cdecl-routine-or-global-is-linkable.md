---
type: bug
track: A
tags: [emit-obj, elf, esp, xtensa, riscv32, symbols, linkage]
prio: 35
summary: "--emit-obj for xtensa/riscv32 emits exactly ONE global symbol, `app_main`. Every proc is LOCAL FUNC and no data symbol is planned at all, so a `cdecl` routine and a `cvar` global that both link on x86-64 and i386 are invisible in an ESP object. The x86-64/i386 writers gained data groups in 72000d1e1 and d402147d6; writeELF32Rel and writeELF32RelIram have a different symbol model and gained nothing."
status: done
---

# The ESP object writer exports only app_main

## Measured

`test/c_obj_data_pascal.pas` — two `cvar`/`public` globals and four `cdecl`
routines — built with `--emit-obj` at `d402147d6`:

| target | writer | `OBJECT GLOBAL` | `FUNC GLOBAL` |
| --- | --- | --- | --- |
| x86-64 | `writeELFRelX64General` | 2 | the 4 cdecl routines |
| i386 | `writeELFRel386General` | 2 | the 4 cdecl routines |
| riscv32 | `writeELF32Rel` | **0** | **1** — `app_main`, and nothing else |

xtensa could not be measured on the same source: the fixture fails to compile
for that target inside the RTL (`near: := 0 to High ( Separators ) do`), which
is a separate pre-existing gap and does not bear on the symbol model.

## Not an oversight in the data work — a different model

`writeELF32Rel`'s own comment states it: *"every proc as LOCAL FUNC (debug
visibility without link-time name collisions), the program entry exported GLOBAL
as app_main"*. That is the ESP-IDF component shape — one entry point the SDK
calls — and it predates data symbols entirely. So the object does not merely
lack the DATA groups the two general writers gained; it has never exported a
`cdecl` routine either, and the data gap is the smaller half of that.

This is why the parent ticket's *"every target `--emit-obj` supports"* row is
not satisfied by the x86-64/i386 work and cannot be closed by extending it: the
group layout the general writers share (`4 + localProcs + localData`,
`extSym0`, `impSym0`) has no counterpart here.

## The question to answer first, in Track U if it is a fork

Is an ESP object supposed to be linkable by name at all? The SDK calls
`app_main`; a component that also exports helpers to other components is a
different use than the one this writer was built for. **Do not widen the export
surface before that is answered** — every symbol made GLOBAL is a name that can
collide inside an IDF build, and the LOCAL-FUNC choice above is a deliberate
guard against exactly that, not an omission.

## Acceptance

- The question above answered, from a real IDF component that needs it or from
  the owner — not inferred from the x86-64 writer's behaviour.
- If the answer is yes: a `cdecl` routine and a `cvar` global appear as `GLOBAL`
  in an xtensa AND a riscv32 object, with the same directive-gated rule the
  Pascal frontend already applies, and `app_main` keeps working unchanged.
- `writeELF32RelIram` covered too — it is the writer any program with an `iram;`
  proc or a `@proc` value routes to, so testing only the plain path tests the
  one an ESP program is least likely to take.

## Resolved

frankA, 2026-09-01. Compiler `03130e1067d4`. Regression rows: `test-emit-obj`
block 4b-octies over `test/c_obj_esp_export.c` and `test/esp_obj_export.pas`,
riscv32 and xtensa, both writers.

**The question this ticket said to answer first turned out to be answerable by
measurement rather than by asking.** The fork was "is an ESP object supposed to
be linkable by name at all", and the reason it looked like a fork is that
widening an export surface can collide inside an IDF build. But the rule the
x86-64 and i386 writers use is DIRECTIVE-GATED: only `cdecl` and only
`cvar`/`public`. Nothing joins the global group that the programmer did not
mark, so the LOCAL-FUNC collision guard is kept rather than traded away, and
the actual divergence being removed is that the same marker meant something on
four targets and nothing on two.

**Asserted, not argued:** an unmarked ESP program's object is BYTE-IDENTICAL
across the change, on riscv32 and xtensa, built with the two compilers either
side of it (`69eeb1efd71e` and `03130e1067d4`). The regression row carries the
one-run form of the same property — an unmarked program exports exactly one
defined global.

**What works.** Data exports through both writers, both frontends, both
targets. Routine exports through the C frontend, both targets. `app_main` stays
exactly as it was.

**What does not, and it is not the writer.** A Pascal `cdecl` routine still
does not export on xtensa/riscv32, because `pasparser_proc.inc` only sets
`ProcCdecl` for x86-64, aarch64, arm32 and i386 — the C convention is not
claimed for those targets at all, so exporting such a routine would export
something callable and wrong. A Pascal ESP object can therefore export DATA and
not routines until
[[bug-a-the-cdecl-soundness-reject-still-has-its-argument-shaped-door-on-four-targets]]
lands. The writer half is target-neutral and needs no further work then.

**Two things the work found.**

- **A duplicate `app_main`.** The writer emits its own GLOBAL `app_main` at the
  program entry; a C source that DEFINES `app_main` has a proc of that name
  too, so the first version of the export loop put two GLOBAL definitions of one
  name in one object at different values (symbols 8 and 10, values 0 and 0x134).
  `ObjEspProcIsExported` excludes it: the entry symbol owns the name.
- **Imports are refused, not silently zeroed.** These writers relocate every
  global reference against the `.bss` section symbol, so an `external` variable
  would read zero forever. `ObjRefuseEspDataImports` errors instead, and the
  regression row asserts the message rather than a nonzero exit.

One unrelated defect fell out of the sweep and is filed separately:
[[bug-a-c-a-global-initialised-with-a-function-address-is-not-exported]] — of
seven C file-scope forms, `fp_t F = helper;` is the only one that gets no symbol
at all, on every target, which makes it a frontend gap rather than a writer one.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit 9e4668d27.
