---
slug: bug-a-an-indexed-shortstring-sysopen-path-segfaults-on-x86-64
track: A
prio: 55
type: bug
status: open
blocked-by: []
created: 2026-09-05
found-by: frankS (closing bug-a-riscv32-and-xtensa-accept-a-shortstring-sysopen-path-and-open-nothing)
summary: "`SysOpen(arr[0], 0)` where `arr: array[0..1] of ShortString` SEGFAULTS on x86-64 and answers FALSE for an existing file on riscv32 and xtensa. The parser admits the shape because its guard checks `Syms[idx].TypeKind` and never `Syms[idx].IsArray`, so an array-of-frozen-string symbol passes `TypeIsFrozenString`; every backend then re-derives the address from the SYMBOL and gets the array base rather than the element. A crash on the DEFAULT target, reachable from ordinary source, and pre-existing — not introduced by the riscv32/xtensa fix that found it."
---

# An indexed ShortString SysOpen path segfaults on x86-64

## Why prio 55 and not lower

Set at filing, not re-ranked later. **The default target segfaults on source the
parser accepted.** The subject is a string kind and the reflex is to rank that
as a string ticket; CLAUDE.md ranks the MECHANISM, never the datatype, and the
mechanism here is a crash on x86-64 -- the one target the dev loop, `gate.sh
quick` and the pin all run on. It is also NOT in the class that is structurally
invisible on 64-bit hosts: this one is visible on the default target and has
simply never been pointed at.

## Measured

2026-09-05, compiler `0d8884ee2e9a` at `95c84cadf`. Same file as
`test/test_sysopen_shortstring_path.pas` creates, opened through `arr[0]`
instead of a plain variable:

```pascal
var arr: array[0..1] of ShortString;
begin
  arr[0] := dir + '/pxx_sysopen_shortstring_path.tmp';
  fd := SysOpen(arr[0], 0); writeln('arr  ', fd > 2);
end.
```

| target | result |
| --- | --- |
| x86-64 | **Segmentation fault (core dumped)**, exit 139 |
| riscv32 | compiles, prints `arr  FALSE` (local qemu RUN) |
| xtensa | compiles, prints `arr  FALSE` (local qemu RUN) |

The equivalent program with a plain `sp: ShortString` prints `TRUE` on all
three — that row is now wired in `test-core` and green, so this is the indexing,
not the ShortString.

## Why the parser lets it through

`compiler/pasparser_expr.inc:1952` guards the path argument with

```pascal
if (idx < 0) or ((not TypeIsFrozenString(Syms[idx].TypeKind)) and
                 (Syms[idx].TypeKind <> tyAnsiString)) then Error('SysOpen: not a string var');
```

`FindSym` returns the ARRAY symbol, whose `TypeKind` is the element's, so
`TypeIsFrozenString` is true and `IsArray` is never consulted. The guard was
written to separate string kinds and it does that correctly; it was never asked
whether the symbol was scalar.

## The actual root cause is one level deeper, and it is shared

`ParseLValueAST` already builds a correct element lvalue and hands it over as
`valNode`. **Every backend then throws that away and re-derives the address from
the symbol index** — x86-64 via `EmitTerminateString(symIdx)` +
`EmitLeaStrDataRdi(symIdx)` (`ir_codegen.inc:11274`), riscv32 and xtensa via
`SysPathFrozenSym`, which returns -1 here precisely because it refuses
`IsArray` and so falls back to generic evaluation.

So there are two honest fixes and they are not the same size:

1. **Reject `IsArray` in the parser guard** — one line, turns a segfault into a
   diagnostic on all seven targets at once, and costs a shape nobody can be
   relying on today because it crashes. This is the cheap correct answer.
2. **Use the lvalue the parser already computed** instead of the symbol, in
   every backend. This is the shape the IR wants (`ir-as-substrate.md`) and it
   makes indexed paths WORK rather than be refused, but it is five backend arms
   and a decision about what "terminate this string" means when the destination
   is computed.

**Do not do (1) and call the ticket closed if (2) is what anyone wants** — a
refusal is a fine answer only if nobody needs indexed paths. Nothing in the tree
uses one today (that is why this has never been seen), which argues for (1) now
and (2) only on demand.

## Scope note

`SysPathFrozenSym`'s `not Syms[v].IsArray` check is deliberate and correct: it
declines the case it cannot lower rather than lowering it wrongly. Removing that
check would turn riscv32/xtensa's wrong answer into a wrong answer at a
different address, not into a fix.
