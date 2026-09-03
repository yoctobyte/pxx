---
track: U
prio: 45
type: decide
status: backlog
created: 2026-09-03
found-by: frankA
owner: ""
blocked-by: []
summary: "OPEN FORK, and everything about the frozen string model's sizing hangs on it. A plain frozen `string` (`-uPXX_MANAGED_STRING`) is ALLOCATED at three different sizes -- 8388616 bytes for a global, 264 for a local, 264 for a record field -- and CLAMPED at 255 in every one of them, by assignment as well as by concat, measured. So 8388352 bytes of every global plain string are unreachable by construction, and a dynamic array of them strides 8 MB per element and SEGFAULTS at 1000 elements on i386/aarch64/arm32/riscv32 while x86-64 refuses the shape outright -- ALL OF IT REPRODUCED ON PIN v401, none of it new. Two readings and they lead opposite ways: (A) the ALLOCATION is intent -- STRING_CAP is named, commented `{ 8 MB }` and used at four sites, LOCAL_STR_CAP's comment says `max string length for local/stack variables`, so capacity is meant to be storage-class-dependent and the flat DEFAULT_STR_CAP clamp is the defect; or (B) the CLAMP is intent, 255 is the type's capacity, and every allocation above 264 is dead space. Not decidable from the code: both are internally consistent and each has a constant written as though it were the answer. Blocks feature-a-dynamic-array-of-frozen-strings, whose element stride IS this number."
---

# What is a plain frozen `string`'s capacity — 255, or 8 MB?

Under `-uPXX_MANAGED_STRING` a bare `string` is the frozen inline `tyString`.
Nothing in the tree says how big one is, and three parts of the compiler answer
differently.

## Measured, 2026-09-03 (frankA), HEAD and pin v401 identical

**Allocation** — adjacent-address deltas, with a control program to confirm the
bss accounting:

| where | bytes reserved |
| --- | ---: |
| global `var g: string` | **8,388,616** (`STRING_CAP + 8`) |
| local `var l: string` | 264 |
| record field `a: string` | 264 |

Three globals of type `string` take bss from 38,732 to **25,204,580** — exactly
`3 x 8,388,616` more — against a control program with no strings. In default
mode the same three are 8 bytes each, because `string` is `tyAnsiString` there.

**Reachable capacity** — 255, everywhere, by every path:

| store | global | local |
| --- | --- | --- |
| 9000 x `s := s + 'y'` (concat) | 255 | 255 |
| direct 300-char literal assignment | 255 | 255 |

Neighbours intact in every case, so the clamp is doing its job safely. **It is
not a concat-only clamp** — that was worth checking, because if it were, a
global could really hold 8 MB and only the concat path would be wrong. It is
not: a straight assignment truncates identically.

So **8,388,352 bytes of every global plain frozen `string` cannot be reached.**

## The consequence that is not merely wasteful

`array of string` in the frozen model strides `STRING_CAP + 8` per element,
because the element size is taken from the ARRAY VARIABLE's storage class — a
category error for a dynamic array, whose elements live on the heap and are
neither global nor stack-local.

| target | `SetLength(a, 3)` | `SetLength(a, 1000)` |
| --- | --- | --- |
| x86-64 | refused: *"dynamic array of record/string not yet supported"* | refused |
| i386, aarch64, arm32, riscv32 | works, values match FPC 3.2.2 | **SIGSEGV** |
| wasm32 | compiles, traps at runtime | — |

Measured stride on all four accepting targets: `8388616`. So the small case
works only because the elements are enormously over-spaced, and **x86-64's
refusal is currently the only honest behaviour of the six.** All of this
reproduces byte-for-byte on **pin v401**, so none of it is recent.

## The fork

**(A) The allocation is the intent; the clamp is the defect.**
`STRING_CAP = 8388608 { 8 MB }` is a named constant used at four sites
(`ast_syminfer.inc:151`, `symtab.inc` 4809 / 5292 / 7671), each choosing it by
storage class, and `LOCAL_STR_CAP = 256`'s own comment reads *"max string length
for local/stack variables"*. That is what a deliberate storage-class-dependent
capacity looks like. Under this reading the clamp should ask the symbol, a
global plain `string` really can hold 8 MB, and the frozen self-host
(`bootstrap-frozen`, `stabilize-frozen`) plausibly needs it for source text.

**(B) The clamp is the intent; 255 is the capacity.** Every clamp in the tree
uses `DEFAULT_STR_CAP`, the measured behaviour is 255 in all three storage
classes and both store paths, and 264 = 255 + prefix is what a local and a field
already get. Under this reading every allocation above 264 is dead space and the
dyn-array stride is simply wrong.

**Neither is derivable from the code**, which is why this is a decision and not
a bug: both readings are internally consistent, and each has a constant written
as though it were already the answer. The tie-breaker is intent about the frozen
model, which is the owner's.

## What it unblocks, and what it invalidates

- [[feature-a-dynamic-array-of-frozen-strings]] cannot be implemented without
  it: the ticket says "no path knows its stride", and the truth is that the
  stride IS known and is 8 MB. Choosing between 264 and 8 MB is the whole job.
- Under (A), `bug-a-a-plain-frozen-string-records-capacity-zero...` recorded the
  WRONG number: `b84e73e53` writes `DEFAULT_STR_CAP` at both allocators, and
  under (A) a global should record `STRING_CAP` and a local `LOCAL_STR_CAP`.
  It is behaviourally neutral today because the clamp already used 255, so
  nothing is broken either way — but it is one arm of this fork written into a
  writer, and it says so in its own body.
- Under (B), four backends should stop accepting a shape they cannot size, or
  start sizing it at 264; x86-64 needs no change at all beyond lifting a
  refusal that was right.

## Recommendation

**(B), 255**, unless the owner wants big frozen strings. It matches every
observable the compiler has today, it makes `array of string` cost 264 bytes an
element instead of 8 MB, and (A) requires making the clamp storage-class-aware
in eleven substitution sites plus every backend's clamp helper — for a
capability nothing currently asks for. But (A) is the reading the CONSTANTS
support, so this is exactly the fork not to guess at.
