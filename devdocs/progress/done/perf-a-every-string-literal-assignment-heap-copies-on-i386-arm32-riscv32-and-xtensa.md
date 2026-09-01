---
slug: perf-a-every-string-literal-assignment-heap-copies-on-i386-arm32-riscv32-and-xtensa
track: A
prio: 55
type: perf
status: done
found: 2026-09-01
found-by: frankA
owner: frankA
blocked-by: []
summary: "`s := 'yy'` in a 2000-iteration loop allocates ZERO times on x86-64 and aarch64 and 1871 times -- one 32-byte heap copy per assignment -- on i386, arm32, riscv32 and xtensa. x86-64 has EmitStaticLitHandle (ir_codegen.inc:4114) and aarch64 has EmitStaticLitHandleA64; the other four backends have no such function at all, so every assignment of a string literal to a managed slot copies it onto the heap and then refcounts and frees it. Correctness is unaffected -- frees track allocs and nothing leaks -- but this is every string literal in every program on four of the six runnable targets, including the two ESP ones. Measured identical on 91c293722 and 317f9238a, so it is long-standing."
---

# Every string literal assignment heap-copies on four backends

## The measurement

```pascal
program LitOnly;
var i, k: Integer; s: AnsiString;
begin
  k := 0;
  for i := 1 to 2000 do begin s := 'yy'; k := k + Length(s); end;
  Writeln('k=', k);
end.
```

Built `-dPXX_ALLOC_CENSUS`, same source, same output everywhere:

| target | allocations |
| --- | --- |
| x86-64 | **zero** — no census line at all |
| aarch64 | **zero** — no census line at all |
| i386 | allocs=1871 frees=1869 live=2, `sizes 32:1871` |
| arm32 | allocs=1871 frees=1869 live=2 |
| riscv32 | allocs=1871 frees=1869 live=2 |
| xtensa | allocs=1871 frees=1869 live=2 |

Identical on **91c293722** and on **317f9238a**, so it is not a regression from
the dyn-array ownership fix this was found beside.

## The mechanism, and it is named

`EmitStaticLitHandle` (`ir_codegen.inc:4114`) hands back the address of a
saturated static literal block instead of allocating: no copy, no retain, no
free. aarch64 has its own `EmitStaticLitHandleA64`
(`ir_codegen_aarch64.inc:179`). `grep -l EmitStaticLitHandle compiler/*.inc`
returns exactly those two files — i386, arm32, riscv32, xtensa and wasm32 have
no such function, so they fall through to the ordinary allocate-and-copy path.

This is a mechanism two backends have and four do not, not a rule spelled
differently in six places. That makes it the good case: the x86-64 arm is small
and already factored, so the work is porting it, and the shape of the guard it
needs is settled — see `d782926ce`, "a static literal block is never written
again", which is the correctness condition the port must carry (a store into a
saturated literal must not write it, so the COW check has to fire before any
mutation).

## Renamed — follow this if you arrived from a commit message

Filed the same day as
`bug-a-array-of-ansistring-allocates-42-percent-more-on-i386-arm32-and-riscv32`
and replaced by it wholesale, because that slug was wrong twice over: the
mechanism is not about arrays, and the target list left out xtensa. Commits
`317f9238a` and `47dd31066` cite the old slug and cannot be rewritten; this is
the ticket they meant.

## How it was found, and what it is NOT

Found while sweeping `array of AnsiString` across targets for the dyn-array
ownership fix: i386/arm32/riscv32 did 5411 allocations against x86-64's 3799
for the same program. **The array was a red herring.** Reducing to the scalar
loop above shows the array contributes nothing to the divergence — the extra
allocations are the element literals, and they cost the same when assigned to a
plain variable. Anything phrased in terms of `array of AnsiString` is describing
the program the bug was noticed in, not the bug.

Not a leak: `frees` tracks `allocs`, `live` is flat, `assert_no_leak.sh` passes
on every target. The cost is one allocate/refcount/free round trip per literal
assignment.

## Why the priority is not low

Every string literal in every program, on four of the six runnable targets —
which is both ESP targets and both 32-bit ARM/RISC ones. `the-goal-cross-cross`
is languages × platforms, and this is a per-platform tax on the most common
managed operation there is. It is a `perf` ticket rather than a `bug` because
the programs are correct; it is not an `-O` ticket, because the levels must
both be correct and this is not a level, it is a missing mechanism.

## Verification this needs

The obvious trap is a port that stops allocating and also stops copying where a
copy was required. The positive control is a program that MUTATES a string that
came from a literal (`s := 'yy'; s[1] := 'z';`) and must still print `zy` while
a second variable holding the same literal still prints `yy`. Run it on the
backend under change BEFORE the port too — if it passes on the broken binary it
is not testing the COW path. `test/test_string_index_cow.pas` already exists
(added by `ad5559ff0`) and is the place to look first.

## Log
- 2026-09-01 — resolved, commit 0159ab983.
