---
prio: 55
track: A
type: bug
status: backlog
found: 2026-08-30
found-by: pxx-b
---

# `--emit-obj` ignores `external name 'sym'` and emits the Pascal identifier as the undefined symbol

## What happens

```pascal
program alias_esp;
function PalSysRead(fd: Integer; buf: Pointer; n: Integer): Integer; cdecl; external name 'read';
function PalSysWrite(fd: Integer; buf: Pointer; n: Integer): Integer; cdecl; external name 'write';
function PalSysOpen(path: PChar; flags: Integer; mode: Integer): Integer; cdecl; external name 'open';
var n: Integer;
begin
  n := PalSysOpen(PChar('/x'), 0, 0);
  n := PalSysRead(n, nil, 0);
  n := PalSysWrite(n, nil, 0);
end.
```

```
$ pxx --target=riscv32 --platform=esp --no-signals --emit-obj alias_esp.pas alias_esp.o
ok: alias_esp.o  [code=339708B ...]
$ readelf -sW alias_esp.o | awk '$7=="UND"{print $8}'
calloc
free
PalSysOpen        <-- should be `open`
PalSysRead        <-- should be `read`
PalSysWrite       <-- should be `write`
```

The object asks the linker for **`PalSysRead`**, a name that exists in no C
library. `name 'read'` was parsed and discarded.

## Why it is a bug and not a missing feature

The feature exists and its semantics are already documented in
`compiler/pasparser_proc.inc` (~1283):

> `name 'sym'` sets the LINK symbol, NOT the Pascal routine identifier — the
> routine stays callable by its declared name (e.g. `c_dlopen ... name 'dlopen'`).

And it is honoured on the **dynamic-import** path. The same source built as a
host executable emits a dynamic import named `write` — it fails at run time with
`undefined symbol: write`, which is the loader not finding libc's symbol, i.e.
the alias was applied. So one back end honours the clause and the other silently
drops it.

## Scope: not ESP-specific

Same three UND symbols under every `--emit-obj` combination tried:

| build | UND emitted |
| --- | --- |
| `--emit-obj` (x86-64) | `PalSysOpen` / `PalSysRead` / `PalSysWrite` |
| `--target=riscv32 --emit-obj` | same |
| `--target=riscv32 --platform=esp --emit-obj` | same |

So it is the relocatable-object writer, not a target or platform quirk.

## Failure mode — silent, and it surfaces far away

Compilation succeeds with no diagnostic. The breakage appears later, in a
foreign build system, as an undefined reference to an identifier that appears
nowhere in any C source — for ESP that is an ESP-IDF CMake link error naming a
Pascal symbol, which reads as "the Pascal object is broken" rather than "a
directive was ignored". Per CLAUDE.md's table this is the *silent wrong
behaviour* row: source that compiles and then behaves wrongly is a bug in the
owning lane, not a compat or feature item.

## Why it matters beyond the one directive

`read` and `write` are Pascal keyword tokens (`lexer.inc:352` -> `tkRead`,
`:369` -> `tkwrite`), so a routine cannot simply be *named* `read`. `external
name 'read'` is the language's answer to exactly that, and on `--emit-obj` there
is currently no answer at all: a C symbol whose name collides with a Pascal
keyword is unreachable from a relocatable object.

That blocks [[feature-pal-esp-posix-fd-semantics]], whose whole design is moving
the ESP PAL onto direct POSIX `open`/`read`/`write`/`close`. That ticket's body
guesses the fix is "imported C declarations under safe Pascal names or a
compiler-supported external symbol alias" — the alias exists; it is just not
applied here.

**The workaround is deliberately not being taken.** Renaming the C side, or
routing the PAL around the collision, is the compiler-appeasement pattern
CLAUDE.md forbids: it would hide this and look like progress.

## Fix direction (Track A's call)

Wherever the object writer materialises an undefined symbol for an external
routine, use the recorded link symbol (`extSym`) when set, falling back to the
routine identifier — the same precedence the dynamic path already applies. The
parser already captures it; the question is only whether the object writer reads
it.

## Suggested regression

`--emit-obj` a program with `external name 'sym'` and assert with `readelf -sW`
that the UND symbol is `sym` and not the Pascal identifier. Cheap, no linker
needed, and it fails today.

Note the test must assert the symbol NAME. "It compiles" passes right now.
