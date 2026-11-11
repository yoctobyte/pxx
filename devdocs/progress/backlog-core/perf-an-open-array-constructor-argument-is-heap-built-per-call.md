---
track: A
prio: 30
type: perf
blocked-by: []
summary: "`P(['mov rax, %', v])`, an array constructor passed to an open-array parameter, is built per call as a heap DYNAMIC array: SetLength-style growth, PXXAlloc with eight caller-saved pushes, a zero fill, then PXXDynArrayRelease after the call. FPC builds it on the stack. Measured 2026-11-11 while profiling the compiler: on lib_charset.pas, PXXDynArrayRelease alone grew by 71 M instructions (+2.8% of the whole compile) when ~30 k raw EmitB sequences became EmitAsmX64([...]) calls. Hits every Format(...) and array-of-const call in user programs too."
status: open
owner: unassigned
---

# An open-array constructor argument is heap-built per call

## What happens

For

```pascal
procedure P(const items: array of const);
...
P(['mov rax, %', v]);
```

x86-64 at -O2 emits a dynamic-array build at the call site. It checks
capacity, calls `PXXAlloc` (with eight caller-saved pushes around it),
zero-fills, stores the header and elements, passes the array, and after the
call releases it with `PXXDynArrayRelease`. The release was added by
`done/bug-a-an-array-constructor-in-argument-position-leaks-its-dynamic-array.md`,
which fixed the leak but kept the heap build.

An open-array parameter only needs a pointer and a high bound. A constructor
whose length is known at compile time can live in the caller's frame, and FPC
puts it there. Elements that hold managed values (an AnsiString VARIABLE in an
array of const) still need their references handled. Literals and ordinals
need none.

## How it was found

The compiler was profiled with callgrind on `test/lib_charset.pas` while raw
`EmitB` codegen was converted to `EmitAsmX64([...])` (raw-asm batch 21,
2026-11-11). The compiler binary has no symbols; the `.map` written beside the
binary symbolizes the callgrind addresses.

| compiler | instructions |
|---|---|
| batch 20 | 2.494 G |
| batch 21 | 2.707 G (+8.5%) |
| batch 21 + whole-call encode memo | 2.554 G (+2.4%) |

The remaining +2.4% is almost entirely this ticket: `PXXDynArrayRelease`
+71 M and the call-site build inside `IREmitNode` +18 M. The two numbers are
identical with and without the memo, because they scale with call sites
executed, not with encoding work.

## Correction (later the same day): most of the cost was the exit sweep

The 71 M was not the per-call build. Each constructor site keeps a hidden
dyn-array temp for the whole routine, and on EVERY exit the routine released
EVERY such temp, whether or not that path had touched it. That was a full
lock + PXXDynArrayRelease call per site, even for a nil slot. IREmitNode has
hundreds of `EmitAsmX64([...])` sites, and it made 18.8 M of the 19.2 M
release calls in one lib_charset compile. Converting more sites grew the bill
per IREmitNode INVOCATION, not per executed emit.

Fixed in symtab.inc (EmitManagedLocalCleanup, SXR_DYNARR arm): a nil slot now
skips the lock and the call (`test rax, rax / jz`). The compiler's own
instructions on lib_charset went from 2.676 G to 2.294 G, 8% below the pre-
conversion batch-2 compiler, with output byte-identical. This applies to every
program with a dynamic-array local, not just the compiler.

What remains for this ticket is the smaller per-call cost: a 1-element
`P(['x', v])` loop still spends ~540 instructions a call (PXXAlloc ~166,
release ~146, PXXFree ~66). A frame buffer for literal-length `array of const`
constructors would remove that. The elements are borrowed (see the leak
ticket's table), so the ownership question it raised does not apply to
AN_VARREC_ARRAY.

## Acceptance

- A literal-length array constructor passed to an open-array parameter
  allocates nothing on the heap. Check with `PXXDBG` heap counters or a
  callgrind count of `PXXAlloc` over a 1 M-call loop.
- `Format` and the existing array-of-const tests stay green.
- The leak regression test from the done ticket stays green.
- The compiler's own self-compile drops by roughly the +2.4% above.
