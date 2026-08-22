---
track: P
prio: 70
type: bug
blocked-by: []
status: done
owner: claude-A
commit: PENDING-COMMIT
summary: "`SizeOf(System.LongWord)` failed with `undefined variable (LongWord)`. The name-vs-expression token scan added by feature-p-sizeof-of-an-expression accepted a builtin type name for the FIRST token of the operand but tested tkIdent alone for the rest of the run, so a qualified name whose tail is a reserved TYPE token was routed to the expression path — where it is not a value. Resolves regression-test-core-test-fpc-compat-batch."
---

# SizeOf of a qualified builtin type name

Filed by the Track T watcher as `regression-test-core-test-fpc-compat-batch`
(`pascal26:132: error: undefined variable (LongWord)`, bad `1021bbdece65`, last
good `9cebdbb1f02c`). Re-verified at HEAD before acting; still red. Introduced
by `0b77e2bea` (SizeOf takes an expression), which is inside that range.

## Repro

```pascal
var bb: LongWord;
begin
  bb := 200;
  Writeln(Ord(System.LongWord(bb) = LongWord(bb)));  { ok }
  Writeln(SizeOf(System.LongWord));                  { undefined variable (LongWord) }
  Writeln(SizeOf(System.Pointer));                   { same }
end.
```

`SizeOf(LongWord)` and the `System.LongWord(bb)` CAST both worked; only
`SizeOf` of the qualified TYPE name failed.

## Root cause

`SizeOf` picks the name path or the expression path by scanning the operand's
tokens to the closing `)`: anything at bracket-depth 0 that is not `tkIdent` or
`tkDot` means an expression. The scan's ENTRY test already knew a type name need
not be an identifier —

```pascal
else if (Tokens[szScan].Kind = tkIdent) or
        (BuiltinTypeNameTk(GetTokenStr(szScan)) <> tyUnknown) then
```

— but the loop body did not, so the first token of `System.LongWord` was
accepted and the third rejected. Down the expression path, `System.LongWord` is
not a value, and the error names the tail as an undefined variable.

## The fix

The loop body asks `BuiltinTypeNameTk` too, so a qualified type name is
`ident (. name)*` where a name may be an identifier OR a reserved type token —
the same rule the entry test already applied to the first token.

## Verified against fpc

`test/test_sizeof_of_an_expression.pas` gains `qual-longword`, `qual-pointer`
and `qual-int64` (29 -> 32 assertions), and `test/test_fpc_compat_batch.pas` is
green again at 14/14.

## Gate

`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick` GREEN.
