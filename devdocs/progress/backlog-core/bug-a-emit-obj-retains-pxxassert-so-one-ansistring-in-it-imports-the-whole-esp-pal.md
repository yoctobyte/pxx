---
track: A
prio: 65
type: bug
status: backlog
found: 2026-09-05
found-by: frankZ
owner: ""
blocked-by: []
summary: "Every `--emit-obj` xtensa object now imports 18 `lwip_*` symbols plus `vTaskDelay` and `esp_timer_get_time`, for a routine the program never calls, and the xtensa link in test-emit-obj fails. TWO facts, neither sufficient alone: `--emit-obj` retains the whole builtin unit (test_emit_obj carries 114 PalBackend symbols, test_esp_hello carries 0, and NEITHER contains an Assert), and `f0a1a8be9` gave `__pxxAssert` an AnsiString local + concatenation whose string path reaches the PAL's file I/O — which on ESP shares a translation unit with the socket backend. riscv32 is clean only because the POSIX backend defines those calls in-object. Bisected to the commit and narrowed to the hunk; ordinary ESP programs are byte-identical, so this is NOT the esp32 bare-image size regression."
---

# `--emit-obj` retains `__pxxAssert`, so one AnsiString in it imports the whole ESP PAL

## What breaks

`test-emit-obj#src:test/test_emit_obj.pas@3` — the xtensa link step. The recipe
links the emitted object against newlib and a three-symbol C shim
(`ext_notify`, `ext_aliased_link`, `main`), deliberately with **no ESP-IDF**:
its own comment says these checks "need NO qemu and NO ESP-IDF". The object now
imports symbols only ESP-IDF provides, so `ld` fails with 25 undefined
references.

## Measured

Reproduces at master (`cd2d0f3ca`, `compiler/pascal26 = 0a20bae79296`,
`converged after 2 round(s)`):

| object | UND symbols | PalBackend syms |
| --- | --- | --- |
| riscv32 | **2** — exactly `ext_notify` + `ext_aliased_link` | 114 |
| xtensa | **35** — adds 18 `lwip_*`, `vTaskDelay`, `esp_timer_get_time`, `rmdir` | 114 |

**riscv32 is not clean because it imports less — it carries the same 114 PAL
symbols.** It selects the POSIX backend, which *defines* those calls in-object
(syscalls), where the ESP backend *imports* them from lwIP/FreeRTOS. The failure
therefore looks target-specific and is backend-specific.

## Bisected

Archive spans 2026-07-07 → 09-05, 1906 reports. This job is red in **7, all on
09-05**; the recipe is unchanged across the window (0 diff lines naming
`test_emit_obj`), so the `@3` key is stable and its earlier absence means "not
red" rather than "different key" — worth checking, because
[[bug-t-the-job-map-cannot-be-asked-whether-a-given-source-was-exercised]] fakes
exactly this shape.

Endpoints measured, not inferred (`git bisect` never tests its own):

    b8e3b3010   riscv32_link=ok  xtensa_link=ok    xt_lwip_und=0
    5b5fdb0b3   riscv32_link=ok  xtensa_link=fail  xt_lwip_und=18

**The xtensa link RAN and PASSED at the good endpoint**, which rules out the
tempting reading that this is coverage arriving because `make` used to abort at
the riscv32 link — the recipe's own comment says it once did, and that is not
what happened here.

Bisect over 158 commits, 7 probes, no skips, monotonic:

    674bc0a1e 18 · 502f273d1 18 · d8afd1979 18 · f0a1a8be9 18  <- first bad
    49194d2ab  0 · 7701b8d40  0 · a5b77e3b4  0

Confirmed at the commit's own boundary: `f0a1a8be9~1` link **ok** / `lwip=0`,
`f0a1a8be9` link **fail** / `lwip=18`.

## Narrowed inside the commit

Run *at* `f0a1a8be9` so no later change confounds it. Reverting `builtin.pas`
alone does not build — the parser injects a third argument — so the splits go
the other way:

| control | lwip_und |
| --- | --- |
| baseline | 18 |
| **A** — `pasparser_stmt.inc` reverted (position composition at `Assert` sites) | **18** |
| **B** — `__pxxAssert` BODY reverted, 3-arg signature kept | **0** |

So it is the body, not the position machinery: the new `var text: AnsiString`
plus `text := text + pos`. An earlier control that swapped only the
`writeln(text, '.')` line came back 18 and looked exonerating — it left the
concatenation in place and could not have isolated anything. **A control that
leaves half the suspect standing cannot clear it.**

## Why this is nobody's gate failure, and why `f0a1a8be9` should not be reverted

That commit is **right**: it made six assertion rows byte-identical to fpc 3.2.2,
having measured FPC rather than trusting the ticket's sketch, and it gated
properly — `converged`, `quick` GREEN, changed test-core rows run standalone,
plus NilPy and C probes against the signature change.

Nothing available to it could have shown this. The self-host fixedpoint never
targets ESP; `gate.sh quick` never links xtensa; on x86-64 every one of those
symbols resolves from libc without comment. **This is only observable where
there is no OS to resolve them**, which is the same structural blind spot as
`bug-a-set-membership-32-bit-backends-truncate-the-set-constant` and the
method-pointer width class: the dev loop, quick and the pin all run on the one
host that cannot see it.

Reverting would trade FPC parity for a link. Reshaping `__pxxAssert` to dodge
the string path is a compiler-appeasement workaround and is out.

## The actual defect is the pairing

Two facts, each harmless alone:

1. **`--emit-obj` retains the whole builtin unit.** `test_emit_obj` carries 114
   `PalBackend` symbols; `test_esp_hello` carries **0**; **neither program
   contains an `Assert`.** So object output keeps `__pxxAssert` where a normal
   build drops it.
2. **`__pxxAssert` acquired a PAL-reaching dependency.** Its string path reaches
   the PAL's file I/O, and on ESP that is the same translation unit as the
   sockets — so file I/O drags `lwip_socket`.

Fixing either breaks the pairing. Candidates, none of them mine to choose:

- **(A)** `--emit-obj` drops builtins nothing references — the general fix, and
  it shrinks every object.
- **(S/B)** split the ESP `platform_backend` so file I/O does not drag the
  socket surface — narrower, and useful independently.

## Two measurements for [[feature-a-every-emit-obj-object-links-its-own-full-copy-of-crtl-so-n-objects-cost-n-runtimes]]

That ticket (A p55, HELD by frankA — **not claimed here**) owns option (A), its
step (3). Two facts from this object refine its model rather than repeat it, and
both were measured on a PASCAL object where frankA's were measured on a C one:

- **`__pxxAssert` and `PalBackendSocket` are `LOCAL`, not weak exports.** frankA
  measured that DCE's residual is *"PINNED BY BEING EXPORTED, not unpruned — a C
  object exports 286 crtl entry points WEAK, `--dce` drops 269 LOCAL bodies and
  exactly ZERO weak ones."* **That explanation does not cover this case.** These
  are exactly the local bodies that measurement says get dropped, and they are
  retained anyway. So the Pascal `--emit-obj` path has a second retention
  mechanism, or DCE is not reaching it.
- **`--dce` changes nothing here.** With and without: `code=336324B` byte for
  byte, `lwip_und=18`, `pal=114`, `__pxxAssert` still present.
- **Every symbol carries `SIZE 0`.** frankA already flagged this for the two
  init/fini thunks; it is general here, and it means `--gc-sections` has no
  extents to work with even once per-function sections exist. Their own
  measurement — the flag drops 168 bytes of 624888 — is consistent with that.

Not investigated further: that ticket is held, and this one exists to say the
retention now has a RED attached to it, not to take its work.

## Explicitly NOT the size regression

I tested this hoping to collapse two tier reds into one cause. It does not:

    f0a1a8be9~1  test_esp_hello  objbytes=112896  code=106908B  pal=0  lwip=0
    f0a1a8be9    test_esp_hello  objbytes=112896  code=106908B  pal=0  lwip=0

**Byte-identical.** Ordinary ESP programs are untouched, so this is not a cause
of [[bug-a-the-esp32-bare-image-doubled-in-code-and-grew-half-again-in-bss]] and
must not be cited as one.

## Box

plexus, kernel 7.0.0-30-generic, xtensa-esp-elf 15.2.0 (esp-15.2.0_20251204),
against `compiler/pascal26 = 0a20bae79296` at `cd2d0f3ca`. Every link above is a
real `xtensa-esp32s3-elf-gcc` invocation, not qemu. ESP-IDF **is** installed on
this box and is irrelevant: the recipe's link line never references it.
