---
prio: 55
track: A
type: bug
status: done
found: 2026-08-30
found-by: pxx-b
owner: frankA
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

---

## RESOLVED 2026-08-30 (frankA)

### The divergence, and it was FIVE copies of one decision, not two

The ticket frames this as one back end honouring the clause and another
discarding it. The measurement is narrower and worse: `elfwriter.inc` made the
same "alias, else Pascal name" decision in **five** places, hand-rolled each
time. Two were right and three were wrong.

| site | writer | before |
| --- | --- | --- |
| `PrepareDynamicData` ×2 | executable dynamic imports | correct — tested `ProcExtName` |
| `writeELF32RelIram` | xtensa/riscv32 `--emit-obj` (iram) | wrong |
| `writeELF32Rel` | 32-bit `--emit-obj` | wrong |
| `writeELFRelX64` | x86-64 `--emit-obj` | wrong |
| `writeELFSharedX64` | **`--shared` (.so)** | wrong — *not in the ticket* |

Each wrong writer was wrong **twice**, because sizing the string table and
writing it are separate loops: `Length(Procs[ExternalProc[i]].Name)` when
sizing, `writeStrZ(..., Procs[ExternalProc[i]].Name)` when writing. Ten call
sites over five decisions.

### `--shared` was affected too, and the ticket did not know

Found by grepping for the sibling rather than by trusting the scope line. It is
invisible to `readelf`: the `.so` this writer emits carries no section header
table, so `readelf --dyn-syms` prints *"Dynamic symbol information is not
available"* and a symbol-level check sees nothing at all. The bytes are still in
`.dynstr`, so the demonstration is `strings`:

```
alias_old.so:  PalSysOpen 1  PalSysRead 1  PalSysWrite 1   bare 'open' 1
alias_new.so:  PalSysOpen 0  PalSysRead 0  PalSysWrite 0   bare 'open' 2
```

An instrument that cannot see a defect is not evidence the defect is absent.

### The fix — one function, not six patches

`ExternalLinkName(extIdx)` at `elfwriter.inc:126` is now the only place the
decision exists; all ten sites call it. This is
`normalise-dont-special-case.md` applied literally: the bug WAS the second
path, and sizing/writing can no longer drift apart because they ask the same
function.

Deliberately NOT changed: the `Error(...)` at `:1870` still names
`Procs[ExternalProc[0]].Name`. It is a diagnostic pointing the user at a
declaration they wrote, so the Pascal identifier is the useful name there.

### Verification

`make compiler/pascal26` — `converged after 2 round(s)`, fixedpoint verified.

The ticket's exact repro, all three `--emit-obj` writers:

| build | UND before | UND after |
| --- | --- | --- |
| x86-64 | `PalSysOpen/Read/Write` | `open` `read` `write` |
| riscv32 `--platform=esp` | `PalSysOpen/Read/Write` | `open` `read` `write` |
| xtensa `--platform=esp` | `PalSysOpen/Read/Write` | `open` `read` `write` |

`calloc`/`free` correctly still resolve to their Pascal names — they carry no
alias, so the fallback arm is exercised too. `readelf` reports no string-table
corruption, which is the check that the sizing and writing halves agree.

### The regression asserts the NAME, in both directions

frankB's acceptance criterion, taken literally. `test/test_emit_obj.pas` gains
`ext_alias_decl` declared `external name 'ext_aliased_link'`, and
`test-emit-obj` asserts on riscv32 and xtensa:

```
readelf -sW ... | grep -q 'UND ext_aliased_link'      # the alias is there
! readelf -sW ... | grep -q 'ext_alias_decl'          # the Pascal name is NOT
```

The negative is the half that catches the bug. Confirmed as a control, not
assumed — run against the pinned pre-fix binary and the fixed one:

```
BASELINE (pinned)  riscv32  alias=0 pascal_name=1 -> FAIL
BASELINE (pinned)  xtensa   alias=0 pascal_name=1 -> FAIL
FIXED (HEAD)       riscv32  alias=1 pascal_name=0 -> pass
FIXED (HEAD)       xtensa   alias=1 pascal_name=0 -> pass
```

The baseline **compiled cleanly** in both rows. That is the whole reason this
survived: every existing check of the path is satisfied by an object that is
wrong.

## Log
- 2026-08-30 — resolved, commit 1a7658326.
