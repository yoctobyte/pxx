---
summary: "i386/aarch64/arm32: any store through a pointer to a record that HAS a string[N] field is rejected"
type: bug
prio: 60
---

# Cross targets: a `string[N]` field poisons every pointer store to its record

- **Type:** bug (backend gap — loud, compile-time). **Track A** (codegen:
  `ir_codegen386.inc`, `ir_codegen_aarch64.inc`, `ir_codegen_arm32.inc`).
- **Status:** done
- **Opened:** 2026-07-14
- **Found by:** Track T — `tools/pasmith_run.py --cross` on the widened grammar
  ([[feature-pasmith-widen-grammar]]); every generated program with the record rung was
  rejected by all three cross targets. **T owns the tool, never the bug.**
- **Related:** [[bug-frozen-string-unsupported-riscv32-xtensa]] (b345) — same family:
  `string[N]` support outside the x86-64 backend.

## Repro

```pascal
program p4;
{$mode objfpc}
type
  PR = ^TR;
  TR = record a: longint; s: string[8]; end;   { the string[8] field is the trigger }
var r: TR; p: PR;
begin
  p := @r;
  r.s := '';
  p^.a := 1;              { storing the LONGINT field -- not the string }
  writeln(r.a);
end.
```

| target | result |
| --- | --- |
| x86-64 | compiles, prints `1` |
| i386 | `error: target i386: store through pointer of this type not yet supported` |
| aarch64 | `error: target aarch64: store through pointer of this type not yet supported` |
| arm32 | `error: target arm32: store through pointer of this type not yet supported` |

## What is and isn't broken

Removing the `string[8]` field makes it compile everywhere. So it is not the store's own
type that is unsupported — `p^.a` is a plain longint:

| record shape | store | i386 |
| --- | --- | --- |
| `record a: longint; end` | `p^.a := 1` | OK |
| `record a: longint; arr: array[0..3] of longint; end` | `p^.a := 1` | OK |
| `record a: longint; s: string[8]; end` | `p^.a := 1` | **rejected** |
| `record a: longint; s: string[8]; end` | `p^.s := 'abc'` | **rejected** |

The presence of the field is enough. The guard is at `ir_codegen386.inc:3278` (and the
two ARM equivalents): it rejects any store whose type kind is outside
`{ordinal, boolean, pointer, char, class, unknown}`, and a shortstring-bearing record
apparently reaches it with the record's own kind rather than the stored field's.

## Impact

Fuzzing the record rung against the cross-target oracle is impossible today — every
program is rejected before it runs, so the backend-divergence oracle sees nothing at all
for the entire class of linked/record-heavy programs. Beyond the fuzzer, it means no
32-bit or ARM program can hold a `string[N]` inside a record it reaches through a
pointer, which is an ordinary shape (a node in a list, a record on the heap).

## Acceptance

- The repro compiles and prints `1` on i386, aarch64 and arm32.
- `p^.s := 'abc'` (storing the shortstring itself through the pointer) works on all
  three.
- A cross-target regression test covers a heap record with a `string[N]` field.
- `tools/pasmith_run.py --cross --wide` then runs with `--shorts` on (it currently has
  to drop the shortstring rung for cross runs).

## Log
- 2026-07-14 — resolved, commit 7716bd2a.
