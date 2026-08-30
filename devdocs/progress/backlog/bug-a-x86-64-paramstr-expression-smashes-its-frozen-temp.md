---
slug: bug-a-x86-64-paramstr-expression-smashes-its-frozen-temp
track: A
prio: 70
status: backlog
---

# `ParamStr(i)` as an EXPRESSION smashes the stack when the argument is longer than 256 bytes (x86-64)

Found from the wasm lane while building the argv oracle: the NATIVE build is
what diverged, not the new backend.

## Repro

```pascal
program b2;
var i: Integer;
begin
  WriteLn('count=', ParamCount);
  for i := 1 to ParamCount do
    WriteLn('expr[', i, ']=[', ParamStr(i), ']');
  WriteLn('done');
end.
```

```
$ long=$(printf 'x%.0s' $(seq 1 300))
$ ./b2 alpha "$long"
count=2
expr[1]=[alpha]
expr[2]=[xxxx...300 of them...]
expr[3]=[]
expr[4]=[]
...            <- runs forever; 1.1M lines before it was killed
```

`ParamCount` is 2 and the loop prints `expr[3]`, `expr[4]`, … — the counter and
its bound are no longer what the program set them to.

Threshold, measured by bisection: **258 bytes is fine, 260 is not.**

## Cause — measured, not inferred

`ParamStr(i)` in expression position desugars to `ArgStr(i, <hidden temp>)`
with a **frozen** temp, `AllocVar('', tyString)`
(`compiler/pasparser_expr.inc:1846`, and the same in `pyparser.inc:43029`). A
frozen local is `LOCAL_STR_CAP + 8` = **264 bytes** (`defs.inc:56`).

The x86-64 fill is `EmitArgvToString` (`compiler/symtab.inc:6048`), and its
copy is **unbounded**:

```
  EmitB($80); EmitB($3C); EmitB($0E); EmitB($00);   { cmp byte [rsi+rcx], 0 }
  EmitB($74); EmitB($05);                           { je +5 }
  EmitB($48); EmitB($FF); EmitB($C1);               { inc rcx }
  EmitB($EB); EmitB($F5);                           { jmp -11 }
  EmitB($48); EmitB($89); EmitB($C8);               { mov rax, rcx }
  EmitStoreStrLen(dstIdx);
  EmitLeaStrDataRdi(dstIdx);
  EmitB($F3); EmitB($A4);                           { rep movsb }
```

`rcx` is the full `strlen(argv[i])` with no clamp, so `rep movsb` writes
`8 + strlen` bytes into a 264-byte slot. Anything past that is the adjacent
frame slot — in the repro, the loop's own control state. It also writes a
length word larger than the capacity, so `Length()` reports 300 for a buffer
that holds 256.

The index bounds check right above it is correct and unsigned; it is only the
LENGTH that is unchecked.

## Scope

- **x86-64 only.** `EmitArgvToString` emits x86-64 bytes directly.
  riscv32 routes the same construct through `PXXCStrToFrozen`
  (`ir_codegen_riscv32.inc:2553`), which clamps at 255 (`builtinheap.pas`), so
  it truncates instead of overflowing. aarch64 / arm32 / i386 / xtensa show no
  call to either and want checking as part of this ticket.
- **The MANAGED destination is fine.** `ArgStr(i, s)` with `s: string` goes
  through `EmitArgvToStringManaged`, which sizes the allocation from the
  length. Verified: 300-char argument, correct output, no corruption.
- **Not just a synthetic input.** Any argument over 256 bytes does it, and a
  long absolute path or a quoted list of flags reaches that in ordinary use.

## Suggested fix

Clamp `rcx` to `LOCAL_STR_CAP` before the `rep movsb`, the way
`PXXCStrToFrozen` clamps at 255 — the destination's capacity is known at emit
time from `dstIdx`, so this is a `cmp`/`cmova` in `EmitArgvToString`, not a
signature change. Truncating matches what riscv32 already does; silently
overwriting the neighbouring slot matches nothing.

Worth deciding at the same time whether the two paths should share one
routine, since they currently disagree about the clamp AND about the limit
(256 vs 255) — `normalise-dont-special-case`.

## Test

`test/wasm/check_argv.sh` covers the same three shapes on wasm32 and passes;
it deliberately keeps its diffed slice under the threshold and carries a
comment pointing here, so restoring the long argument to that slice is the
regression test once this is fixed.
