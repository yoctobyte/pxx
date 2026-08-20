---
track: A
prio: 50
type: bug
blocked-by: []
summary: "FindTypeAlias carried a leftover debug dump keyed on the literal name 'puint8': a lookup miss printed the entire alias table to STDOUT before the pointer-alias fallback resolved the name normally. Any C-interop Pascal source using an ordinary uint8-pointer name got a dozen lines of compiler internals mixed into its build output — and then compiled successfully, which is why nothing caught it."
status: done
owner: claude-acp
---

# `FindTypeAlias` prints a debug dump for `puint8`

- **Track A** (`compiler/symtab.inc`).
- Found 2026-08-20 while reading the type-name resolution path for
  [[feature-typeinfo-all-types]].

## Symptom

```pascal
program pu;
var x: puint8;
begin WriteLn('hi'); end.
```

```
FindTypeAlias failed to find puint8! AliasCount=12
  Alias 0: PVarRecInt64 (noff=84, nlen=12)
  Alias 1: PVarRecDouble (noff=101, nlen=13)
  ... nine more ...
ok: /tmp/.../pu  [code=55344B ...]
```

Thirteen lines of compiler internals on **stdout**, then a successful compile.

## Why it survived

Both halves of what makes a bug invisible were present:

1. **The compile SUCCEEDS.** A miss in `FindTypeAlias` is normal — `puint8`
   resolves through the pointer-alias path *after* that function returns -1. So
   the dump fires on a lookup whose failure means nothing, and the program
   builds and runs correctly. Nothing is wrong with the output binary.
2. **No test asserts on the compiler's own stdout.** Every test here checks what
   the compiled PROGRAM prints. A compiler that prints thirteen extra lines
   passes all of them.

`puint8` is not an obscure name to trip over, either — it is the natural
spelling for a `uint8*` in C-interop Pascal, which is exactly the code most
likely to hit it.

## Fix

Deleted the block, and the two locals (`s`, `j`) that existed only to build its
strings. Replaced with a comment saying why a miss here is normal, so the next
reader does not add diagnostics back for the same reason.

## Test

`test/test_puint8_no_compiler_spew.pas` — the assertion is on the **compiler's**
output, not the program's: no `FindTypeAlias`/`Alias 0:` line, and exactly one
line total (the `ok:` banner). That shape is worth reusing; it is the first test
in the suite that checks the compiler is QUIET, which is the property that was
missing rather than any property of the emitted code.

Bites: the pinned binary emits two matching lines.

## Gate

`make compiler/pascal26` (byte-identical fixedpoint) + `tools/gate.sh quick` GREEN.
