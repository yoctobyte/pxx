---
slug: bug-c-quickjs-compiles-in-full-but-a-bytecode-function-finalizer-frees-a-minus-one-pointer
title: "quickjs compiles in full and then segfaults: js_bytecode_function_finalizer frees a -1 pointer on the simplest input"
track: C
prio: 60
type: bug
status: done
created: 2026-09-16
found: 2026-09-16
found-by: frankb-56, on clearing the last compile wall
owner: frankb-56
blocked-by: []
summary: "FIXED, AND IT WAS NOT A QUICKJS BUG NOR AN UNINITIALISED FIELD. A struct passed BY VALUE through a pointer declared from a FUNCTION-TYPE typedef (`typedef void F(args); F *p;`) got the wrong ABI. pxx registered a call signature for that spelling but never recorded WHICH record each struct parameter is (ProcParamRecId), so the SysV classifier had no RecSize and passed the struct as though it were a pointer -- while the CALLEE, compiled from the real declaration, read its registers per the true layout. quickjs stores class finalizers as `JSClassFinalizer *` (a function-TYPE typedef) and passes a 16-byte JSValue by value, so the finalizer received a stack address with tag 70 instead of the object and -1, then freed a -1 pointer. SCALARS WERE UNAFFECTED, which is why it survived: an int or a pointer needs no record identity, so every fixture using one certified the broken path. The equivalent fn-POINTER typedef spelling was always correct, so two spellings of the same C type disagreed. Fix mirrors the two lines the $cfnptr path already does at registration. quickjs-ng now RUNS: `qjs 1` exits 0, the curated smoke suite is byte-exact, and the js-sha256 library case is byte-exact against the RFC 4231 vectors. Regression test test/c_fntype_typedef_struct_abi.c wired into test-core, 7 rows across three SysV classes plus a scalar row; positive control MEASURED against the pinned pre-fix compiler, which fails 6 of 7 and exits 1, the one that passes being the scalar."
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

## Resolution (2026-09-16, frankb-56, Track C) — a wrong ABI, not a wrong field

The ticket guessed a field was never written. It was not: the field was read
from a struct pointer that had arrived as a **stack address**.

### Two plausible hypotheses, both killed by measurement

| hypothesis | how it died |
| --- | --- |
| struct/union LAYOUT differs from gcc | differential `offsetof` over the same unity TU — **every offset identical** |
| an optimiser dropped a store (the day's pattern) | crashes identically at `-O0/-O1/-O2/-O3` |

What worked was printing the value at both ends of the call, same instrumented
source, both compilers:

    pxx  [FREE_OBJ] p=0x7d90f8e18cc0   [FIN] p=0x7ffd204bf680   <- stack
    gcc  [FREE_OBJ] p=0x5f49ace30aa0   [FIN] p=0x5f49ace30aa0

`p` was correct going in; the 16-byte `JSValue` arrived corrupted, both halves
wrong (`tag=70`, not `-1`).

**Adding that instrumentation made the SEGFAULT vanish while leaving the wrong
values** — the garbage was benign in that build. Anyone bisecting on "does it
crash" would have concluded the probe fixed it.

### The boundary — the first two probes FAILED to reproduce, which is what found it

| shape | pxx |
| --- | --- |
| `typedef void (*P)(args); P p;` — pointer typedef | ok |
| `typedef void F(args); F *p;` — **function-type typedef** | **WRONG** |
| same, from an array-of-struct member (quickjs's shape) | **WRONG** |
| scalar args through the broken spelling | ok |
| 16-byte INTEGER+INTEGER / 16-byte SSE+SSE / 8-byte struct | **all WRONG** |

### Cause

`ParseCDeclType` yields a parameter's kind *and* its record identity; the
function-type-typedef registration loop kept only the kind. `tyRecord` says "a
record", not **which** record, so `ProcParamRecId` stayed `REC_NONE` and
`symtab.inc`'s `RecSize(ProcParamRecId[...])` had nothing to classify. The
`$cfnptr` path already did this, and its own comment says why: *"this is the
only place the indirect arm can learn that an argument is a register-classified
struct rather than a pointer."*

### Result

`qjs 1` exits 0; curated smoke byte-exact; **js-sha256 byte-exact against the
RFC 4231 vectors**. quickjs-ng runs real third-party JavaScript under pxx.

## Log
- 2026-09-16 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
