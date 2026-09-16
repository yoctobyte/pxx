---
slug: bug-c-quickjs-compiles-in-full-but-a-bytecode-function-finalizer-frees-a-minus-one-pointer
title: "quickjs compiles in full and then segfaults: js_bytecode_function_finalizer frees a -1 pointer on the simplest input"
track: C
prio: 60
type: bug
status: new
created: 2026-09-16
found: 2026-09-16
found-by: frankb-56, on clearing the last compile wall
owner: ""
blocked-by: []
summary: "quickjs-ng now COMPILES IN FULL under pxx (~85k lines, 3052 procs, 5.3MB binary) and segfaults at runtime on the simplest possible input -- `qjs 1` is enough, so this is the init/eval path and not any JS feature. Backtrace: JS_CallFree -> JS_FreeValue -> free_zero_refcount -> free_gc_object -> free_object -> js_bytecode_function_finalizer (quickjs.c:5503) -> js_free_rt (:1454) with ptr = 0xffffffffffffffff. js_free_rt guards only against NULL, so -1 reaches the allocator and the header read faults. BOTH OF THE FIXES THAT MADE IT COMPILE ARE EXONERATED, each by its own measurement rather than by argument. malloc_usable_size: a CONTROL returning 0 unconditionally -- which is quickjs's own portable-arm behaviour -- still segfaults identically (rc 139), so the accounting path is not producing the bad pointer. __builtin_frame_address: measured against gcc in quickjs's exact shape (a static inline feeding rt->stack_top, deltas taken at four recursion depths) and it is positive, monotonic and ~64 bytes per frame against gcc's ~48, so the stack-overflow check is not mis-firing. The -1 is therefore arriving from somewhere else, and the finalizer freeing a field that was never initialised is the shape to look at first. NOT DIAGNOSED FURTHER: which field, and whether this is a struct-initialisation, union-layout or fn-pointer-table codegen gap. The backtrace above frame 5 is unreliable (inlining interleaves js_free_value_rt/malloc_usable_size/js__malloc_usable_size out of order), so trust frames 5-13 and re-derive the rest."
---

# quickjs compiles in full, then frees a `-1` pointer

This is the wall behind the wall. Two tickets said quickjs was one item from a
verdict; clearing both got the file to **compile completely** and revealed a
runtime failure that no compile-time census could have predicted.

## Reproduce

    ./compiler/pascal26 -Ilib/crtl/include -Ilib/crtl/src -I<quickjs> \
        test/quickjs/runner.c /tmp/qjs        # builds clean, 3052 procs
    /tmp/qjs 1                                # SIGSEGV (139)

`1` is enough. So is `1+1`, `"a"+"b"`, and a bare function call — the engine
does not survive its own teardown of the simplest program, which puts this in
the init/eval path rather than in any JS feature.

## The backtrace, and which half of it to believe

    #5  js_free_rt (rt=0x7fffe7e00008, ptr=0xffffffffffffffff)   quickjs.c:1454
    #6  js_bytecode_function_finalizer (rt=..., val=...)         quickjs.c:5503
    #7  free_object (rt=..., p=0x7fffe7e18cc0)                   quickjs.c:5610
    #8  free_gc_object                                           quickjs.c:5630
    #9  free_zero_refcount                                       quickjs.c:5652
    #10 js_free_value_rt                                         quickjs.c:5700
    #11 JS_FreeValueRT                                           quickjs.c:5732
    #12 JS_FreeValue                                             quickjs.c:5739
    #13 JS_CallFree (ctx=..., func_obj=..., argc=0, argv=0x0)    quickjs.c:17408

**Frames 0–4 are garbage** — they show `js_free_value_rt` calling
`malloc_usable_size` calling `js__malloc_usable_size`, which is inside-out, and
`rt=0xffffffffffffffff` in a frame whose caller has a valid `rt`. Inlining has
interleaved them. Frames 5–13 are consistent and are the ones to work from.

`js_free_rt` guards only `if (!ptr) return;`, exactly as glibc callers do, so a
`-1` walks straight through into the allocator.

## Both compile fixes are exonerated, by measurement not by argument

| suspect | control | result |
| --- | --- | --- |
| `malloc_usable_size` (052eb5e6a) | return 0 unconditionally — quickjs's own portable arm | **still SIGSEGV, rc 139** |
| `__builtin_frame_address` | quickjs's exact shape: `static inline` feeding `rt->stack_top`, deltas at four depths, against gcc | positive, monotonic, ~64B/frame vs gcc's ~48B |

The first is the load-bearing one: if the accounting path were producing the bad
pointer, neutering it would change the outcome, and it does not.

## Where to start

`js_bytecode_function_finalizer` frees several fields of a `JSFunctionBytecode`.
A `-1` where a pointer belongs is the signature of a field **never written**
rather than one freed twice — a double free would be a valid-looking address.
So the first question is which field, and whether pxx zero-initialises that
struct the way the C the engine was written against does.

**Do not start by hardening `malloc_usable_size` against implausible pointers.**
glibc's faults on a garbage pointer too, and a plausibility check there would
convert this loud, locatable crash into a silently wrong accounting number —
trading the cheap failure for the expensive one.
