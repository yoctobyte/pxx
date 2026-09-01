---
type: bug
track: A
tags: [emit-obj, elf, esp, xtensa, riscv32, symbols, linkage]
prio: 35
summary: "--emit-obj for xtensa/riscv32 emits exactly ONE global symbol, `app_main`. Every proc is LOCAL FUNC and no data symbol is planned at all, so a `cdecl` routine and a `cvar` global that both link on x86-64 and i386 are invisible in an ESP object. The x86-64/i386 writers gained data groups in 72000d1e1 and d402147d6; writeELF32Rel and writeELF32RelIram have a different symbol model and gained nothing."
status: open
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
