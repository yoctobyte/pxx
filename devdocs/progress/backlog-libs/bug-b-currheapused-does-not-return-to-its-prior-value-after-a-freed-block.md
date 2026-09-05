---
slug: bug-b-currheapused-does-not-return-to-its-prior-value-after-a-freed-block
title: "`GetFPCHeapStatus.CurrHeapUsed` grows across a block whose allocations were all freed — and FPC's does too, by less"
track: B
prio: 20
type: bug
status: backlog
owner: ""
created: 2026-09-06
found-by: frankB
blocked-by: []
summary: "MEASURED AND NOT DIAGNOSED — this is the residual of an exculpation, filed so it has an owner rather than a claim. A program doing 100 IntToStr/concat iterations and NOTHING else reports `Lost: 208 bytes` through the FPC testsuite's own `DoMem` helper under pxx, and `Lost: 64 bytes` under fpc 3.2.2. So CurrHeapUsed is a high-water reading in BOTH compilers and neither returns to zero, which is the fact that exculpates exception handling in texception3 (all 119 sub-tests pass; only the final DoMem assertion fails). The open question is whether pxx's number SHOULD return, and it is not answered here. Also unmeasured: pxx reports `Size: 262144 Kb` where fpc reports `352 Kb` — a 745x difference on the first line, which is the arena, and which nothing has said is wrong."
---

# The measurement

```pascal
program dm;
uses erroru, sysutils;
var mem: SizeUInt; i: Integer; s: string;
begin
  mem := 0;
  DoMem(mem);
  for i := 1 to 100 do begin s := IntToStr(i); s := s + 'x'; end;
  writeln('control lost = ', DoMem(mem));
end.
```

```
pxx: [HEAP] Size: 262144 Kb,  Used: 240 bytes,  Lost: 208 bytes    -> 208
fpc: [HEAP] Size: 352 Kb,     Used: 1344 bytes, Lost: 64 bytes     ->  64
```

`erroru.pp` is FPC's own testsuite helper; `DoMem` is
`GetFPCHeapStatus.CurrHeapUsed` before and after.

# Why it is filed rather than fixed, and what it exculpates

`texception3.pp` was skipped for "RTL `ExitCode` variable missing; try/finally
with exit/break/continue". Both clauses are stale. Re-measured, the row compiles,
runs, and **passes all 119 exception sub-tests**; its only failure is the last
statement:

```pascal
if DoMem(mem)<>0 then
  begin
    writeln('exception generates memory holes');
    do_error(99999);
  end;
```

`exception generates memory holes` is the message that comes out, and it is
**not** what is wrong — the control above shows the same non-zero answer for a
program containing no exception at all, under both compilers. The pxx allocation
census agrees: a 1000-iteration raise/handle loop gives `allocs=1871 frees=1868
live=3`.

**That is the whole reason this ticket exists.** The reading "exception handling
leaks 3408 bytes" is coherent, comes from FPC's own testsuite, and is false — and
I had already written it into `pxx.skip` before running the control. A message
printed by a test is a claim about the test's own model, not a measurement.

# The residual, which is what someone owns here

Neither compiler returns CurrHeapUsed to its starting value, so a test asserting
`DoMem = 0` is asserting something about an allocator rather than about the code
under it. **Whether pxx's 208 is defensible is not established.** Two sub-questions:

1. Should `CurrHeapUsed` fall when a block is freed? pxx bump-allocates from one
   arena; if the number is a high-water mark by construction, say so in the
   function's own contract, because the name promises otherwise.
2. `Size: 262144 Kb` against fpc's `352 Kb` is the arena reservation. Nobody has
   said that is wrong, and nobody has said it is right either.

Low prio: no compiling program's ANSWERS depend on it — only a program that
introspects the allocator, and this repo does not chase parity on those
(CLAUDE.md, "compatible with FPC means the value, not the intermediate's type").
It is filed because "not exception handling" is half a finding.
