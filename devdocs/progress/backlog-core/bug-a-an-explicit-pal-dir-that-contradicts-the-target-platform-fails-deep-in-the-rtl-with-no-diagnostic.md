---
slug: bug-a-an-explicit-pal-dir-that-contradicts-the-target-platform-fails-deep-in-the-rtl-with-no-diagnostic
title: "A -Fu naming the wrong platform PAL dir for the target dies on `undefined variable (SYS_getgid)` twenty lines inside the RTL"
track: A
prio: 30
type: bug
status: backlog
blocked-by: []
owner: ""
created: 2026-09-05
found-by: frankD
summary: "`--target=wasm32 -Fulib/rtl/platform/posix` compiles the POSIX platform_backend for a WASI target and dies on `undefined variable (SYS_getgid)` -- a diagnostic naming neither the target nor the search path, twenty lines inside an RTL file the user did not write. The override itself is CORRECT and documented (AddDefaultPasUnitDirs appends the target's PAL after any user -Fu, deliberately, so an explicit -Fu wins); what is missing is any warning that the explicit PAL dir contradicts TargetPlatform, which the compiler already knows. Reachable by copying a working Makefile row: a dozen-plus rows hardcode -Fulib/rtl/platform/posix, correct natively and wrong for every cross target. Cost real triage twice in one evening -- reported as a Text-on-wasm32 backend bug, then retracted as a stale binary, and it was neither."
---

# The three-line reproduction

Measured 2026-09-05 at `4ef367091`, compiler binary `25113fd3` (`converged`),
host x86-64.

```
$ cat textio.pas
program textio;
var f: Text;
begin Assign(f, 'x.txt'); Rewrite(f); WriteLn(f, 'hi'); Close(f); end.
```

| invocation | result |
| --- | --- |
| `pascal26 --target=wasm32 textio.pas o.wasm` | **ok** — `path_open fd_close fd_read fd_write` imported |
| `pascal26 --target=wasm32 -Fulib/rtl -Fulib/rtl/platform/posix …` | **`undefined variable (SYS_getgid)`** |
| `pascal26 --target=wasm32 -Fulib/rtl -Fulib/rtl/platform/wasi …` | **ok** |

The error, in full:

```
  in: lib/rtl/platform/posix/platform_backend.pas
  near: := Integer ( __pxxrawsyscall ( SYS_getgid >>> , 0 ,
pascal26: too many errors, stopping
```

`SYS_getgid` is declared in six per-architecture `const` blocks in that file
(`platform_backend.pas:179, 209, 237, 265, 325, 362`) and wasm32 has none,
correctly — it is not a syscall platform. `lib/rtl/platform/wasi/` is a complete
separate backend and is what the target wants.

# Why this is a bug and what it is NOT

**The override is not the bug and must not be removed.** `AddDefaultPasUnitDirs`
(`compiler/compiler.pas`, ~line 320) says so itself:

> The PAL search roots the default RTL needs (platform_backend lives under
> `lib/rtl/platform/<pal>/`), **appended AFTER any user `-Fu` so an explicit
> override still wins.**

That is a deliberate, useful property. Someone cross-building against a
hand-rolled PAL needs it.

**The bug is that a contradiction the compiler can see produces no diagnostic.**
`TargetPlatform` is already computed (`PLATFORM_WASI` for wasm32, a few lines
above the quoted comment). The compiler therefore knows, before it opens a single
unit, that it was handed a `-Fu` ending in `platform/posix` while building for a
WASI target — and says nothing, failing later inside a file the user never wrote,
on an identifier that means nothing to them.

# The reachability is the reason this is worth fixing rather than documenting

A dozen-plus Makefile rows in this repo hardcode
`-Fulib/rtl -Fulib/rtl/platform/posix` (e.g. `Makefile:5819, 5922, 5940, 5946,
6298, 6308, 6320`). Every one is correct — they are native rows. **Copying one
and adding `--target=<anything>` is the single most likely way anyone writes a
new cross row**, and it produces this.

It cost real triage on 2026-09-05: it was reported as "ordinary Pascal file I/O
does not compile for wasm32", investigated as a possible arm of a wasm32 backend
defect, then retracted as a stale binary — and it was **neither**. Ordinary
`Text` I/O compiles for wasm32 and imports the full WASI set; so do
`Reset`, `file of Integer`, `uses sysutils` and `Erase`. Only the contradicting
`-Fu` fails, on any binary, fresh or stale.

# Suggested shape

A warning, not an error — the override stays legal:

```
warning: -Fu names lib/rtl/platform/posix but the target platform is wasi;
         the PAL for this target is lib/rtl/platform/wasi
```

Emit it when an explicit `-Fu` path's final component matches a *known* PAL
directory name (`posix`, `wasi`, `esp` — `ls lib/rtl/platform/`) other than the
one `TargetPlatform` names. Keying on the known set rather than on any mismatch
keeps a hand-rolled PAL at an unrelated path silent, which is the case the
override exists for.

# Guard

A row asserting the warning fires for the contradicting pair and does **not**
fire for either agreeing pair, plus one asserting the contradicting build still
*compiles* when the PAL genuinely does supply the symbols — otherwise the warning
quietly becomes an error and takes the documented override with it.

Note the shape of a test here: the failing invocation must use two different
platforms whose backends genuinely differ. A row pairing a platform with itself
passes because the right answer and the wrong answer are the same.
