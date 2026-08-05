---
track: A
prio: 60
type: bug
summary: "i386 only: a scalar `string` local is never released at scope exit — `procedure R; var s: string; begin SetLength(s, 40) end;` called in a loop leaks ~150 MB per 60k calls. Every other target is flat"
---

# i386: a scalar managed-string local leaks at scope exit

- **Type:** bug — Track A (i386 epilogue / managed-local cleanup)
- **Status:** backlog
- **Opened:** 2026-08-05
- **Found by:** Track A, while fixing
  `bug-a-local-static-array-of-string-never-released-at-scope-exit` — i386 was
  the one target whose leak did not go flat, and the residue turned out to be a
  different and much larger bug. **Pre-existing**: `pinned` leaks identically.

## Repro — 9 lines

```pascal
program i386leak;
procedure R;
var s: string;
begin
  SetLength(s, 40);
end;
var k: Integer;
begin
  for k := 1 to 60000 do R;
  writeln('done');
end.
```

max RSS after 60 000 calls:

| target | |
| --- | --- |
| x86-64 | 264 KB |
| arm32 | 5 604 KB (5 524 KB baseline — flat) |
| aarch64 | 6 424 KB (6 360 KB baseline — flat) |
| **i386** | **153 176 KB** |

~2.5 KB leaked per call, linear. The same shape leaks through any spelling that
allocates a fresh string — `s := 'val' + Chr(i)` leaks identically — so it is the
scope-exit release that is missing, not `SetLength` specifically.

## Why it stayed hidden

It needs a **local** in a routine called repeatedly. A string built in the main
program body, or one that outlives the loop, shows nothing. And i386 is not the
default build, so nobody watching RSS would see it.

It also MASKS other leak work on i386: any measurement of a managed-local leak
on that target is swamped by this one, which is exactly what happened above.
Fix this before trusting any i386 RSS number.

## Where to look

`EmitProcEpilog` in `compiler/symtab.inc`, the `TargetArch = TARGET_I386` branch.
Its cleanup loop has the arms (COM interface, AnsiString, variant, record) and
they look right by inspection — the AnsiString arm does
`mov eax, [ebp+off]; push eax; call PXXStrDecRef; add esp, 4`. So the likely
fault is not the arm but whether the loop RUNS: check
`ProcHasManagedLocalCleanup`'s result actually gates the i386 path the same way
it gates the others, and that the epilogue is not taking an early return before
reaching it. Measure with `-dPXX_HEAP_DEBUG` rather than by reading.
