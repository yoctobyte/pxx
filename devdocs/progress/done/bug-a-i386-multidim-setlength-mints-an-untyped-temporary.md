---
track: A
prio: 45
type: bug
blocked-by: []
summary: "`SetLength(m, 3, 5)` on `array of array of Integer` does not BUILD for i386: the multidim desugar mints an AN_BINOP limit with no ASTTk, the AN_FOR lowering copies that 0 into the hidden limit temp, and i386 refuses a tyUnknown symbol. x86-64 absorbed it silently into its 8-byte slot."
status: done
owner: claude-A
---

# i386: multidim `SetLength` mints an untyped temporary

- **Track A** (`compiler/pasparser_stmt.inc` — `BuildMultiSetLen` /
  `BuildSetLenNest`).
- Found 2026-08-21 while cross-checking
  `bug-a-named-dynarray-alias-element-crashes-on-every-cross-target`.

## Repro

```pascal
program md;
var m: array of array of Integer;
begin
  SetLength(m, 3, 5);
  Writeln('ok ', Length(m), ' ', Length(m[2]));
end.
```

```
$ ./compiler/pascal26 --target=i386 md.pas md
pascal26:6: error: target i386: a compiler-minted temporary reached codegen
with an UNRESOLVED type (tyUnknown) — the type inference, not the backend, is
the gap
```

Pre-existing, not a regression: `stable_linux_amd64/default/pinned` fails the
same way. Native / arm32 / aarch64 / riscv32 all build and print `ok 3 5`.

## Root cause — a synthesiser that skipped the house convention

`SetLength(m, d0, d1)` desugars in `BuildMultiSetLen` into the outer call plus
`for i := 0 to d0-1 do SetLength(m[i], d1)`. That `d0-1` is a hand-built
`AN_BINOP`, and its `ASTTk` was never stamped.

**The IR lowering copies `ASTTk[node]` into the IR node verbatim** — it does not
infer a binop's type from its operands (`compiler/ir.inc`, the AN_BINOP tail:
`IRAppend(IR_BINOP, left, right, ASTIVal[node], 0, ASTTk[node])`). So the limit
lowered with `IRTk = 0`, and the AN_FOR lowering then did

```pascal
forLimTmp := AllocVar('', IntToTypeKind(IRTk[limitValNode]));
```

minting a **tyUnknown** symbol. x86-64's fat 8-byte slot swallows that; i386's
`IREmit386CheckScalarSym` correctly refuses it, and its message is exactly
right — the gap is in type inference, not in the backend.

Every other synthesiser in the file already stamps the type
(`BuildFlatNDIndex` / `BuildPartialNDRowIndex` in `pasparser_call.inc` set
`ASTTk := Ord(tyInteger)` on all five binops they mint). These two were the
omission — and, as usual, it was a **double case**: `BuildMultiSetLen` and
`BuildSetLenNest` carry the identical bug, and both had to be fixed.

## Fix

`ASTTk[limitN] := Ord(tyInteger)` in both. Verified `ok 3 5` on native, i386,
arm32, aarch64 and riscv32.

## Note for later

The AN_FOR lowering deliberately keeps *no* fallback for a tyUnknown limit. A
guard there would have silently papered over this and over the next omission of
the same shape; i386's refusal is the diagnostic that found it in one step.

## Log
- 2026-08-21 — resolved, commit ba398c9b1.
