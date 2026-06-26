# PXX Language Feature Matrix

This matrix tracks proposed dialect additions, standard extensions, and compiler enhancements discussed for the Pascal and Python frontends of PXX, evaluating their complexity, compliance, and priority.

| Feature | Standardization | Implementation Complexity | Priority / Use Case | Status | Description |
|---|---|---|---|---|---|
| **PChar $\rightarrow$ String Coercion** | **Standard** (FPC/Delphi compatible) | **Low-Medium** | **Critical** / Unblocks clean C-header use | ✅ Delivered | Auto-generate copying loops when assigning or casting `PChar` to a Pascal `string`/`AnsiString`. |
| **Auto-Typed Variables (`var a: auto`)** | **Dialect** (Modern Object Pascal has inline `var`) | **Low** | **High** / Ergonomics for wrapperless C imports | ✅ Delivered | Deferred type-inference. The variable is declared as `auto` and statically locks into the type of its first RHS assignment. |
| **`default` Assignment** | **Dialect** | **Low-Medium** | **High** / Reset variables without spelling type-specific zero values | ✅ Delivered | `x := default` resets explicitly typed variables to their default state: zero, `nil`, empty string, or zeroed managed storage. |
| **Nested Subroutines** | **Standard** (Wirth Pascal core) | **High** | **Medium** / Structural modularity | ⬜ Deferred | Functions declared inside functions. Requires lexical scoping (passing a stack frame static-link pointer to inner scopes). |
| **Out-Param Return-Lifting** | **Dialect** | **None** (Shared with Python) | **Done** | ✅ Delivered | Trailing `T**` C out-parameters are lifted to the call's return value (e.g., `db := sqlite3_open(path)`). |
| **Dynamic `any` Type** | **Dialect** (Variant concept) | **Very High** | **Low** / Scripting helper | ⬜ Excluded | Dynamic types with runtime tagging and dispatch. Discarded to keep compiler bootstrap lightweight. |
| **Procedural types** (`procedure(...)` / `function(...): R`) | **Standard** (Wirth/Delphi) | **Medium** | **High** / Callbacks, dispatch tables, the coroutine spawn ABI | ✅ Delivered (all 4 targets) | Proc-typed var/param/global/local, `@Proc`/`nil` assign, `v(args)` indirect call (statement + expression). |
| **Method pointers** (`of object`) | **Standard** (Delphi) | **Medium** | **Medium** / Event handlers | ✅ Delivered (**x86-64 only** — needs cross classes) | 16-byte Code/Data value; `m := @obj.Method`; calling injects `Self`. |
| **Generators** (`; generator;` + `yield` + `for x in g`) | **Dialect** (Python-shaped) | **High** | **High** / Lazy sequences, iterators | ✅ Delivered (all 4 targets) | Two lowerings: stackless (all targets, state machine) + stackful (x86-64, coroutine). |
| **Coroutines + cooperative scheduler** (`Spawn`/`CoYield`/`RunUntilDone`) | **Dialect** (library) | **High** | **High** / Concurrency without threads | ✅ Delivered (all 4 targets) | Stackful fibers over the `CoSwitch` primitive; one thread, per-stack exception chain. `lib/rtl/scheduler.pas`. |
| **Async I/O** (epoll reactor, `asyncnet` sockets, `CoSleep` timers) | **Dialect** (library) | **High** | **High** / Concurrent servers on one thread | ✅ Delivered (**x86-64 only** — per-arch syscall numbers pending) | `WaitReadable`/`WaitWritable` park a coroutine on epoll; blocking concentrated into one `epoll_wait`. |
| **Channels** (`ChanSend`/`ChanRecv`) | **Dialect** (library) | **Low** | **Medium** / Coroutine messaging | ✅ Delivered (all 4 targets) | Bounded ring; send blocks when full, recv when empty (pure cooperative). `lib/rtl/channel.pas`. |

---

### Technical Q&A: `PChar(s)` vs `@s[1]`

* **The Question:** Is `PChar(s)` the same as `@s[1]`, and is there a difference regarding `nil` safety?
* **The Answer:** Yes, there is a critical difference in **nil-safety**:
  1. **Empty String Representation:** In PXX (as in Free Pascal), empty managed `AnsiString` variables are represented by a `nil` pointer (0) to save allocation overhead.
  2. **`@s[1]` (Dangerous):** Accessing `s[1]` on an empty string tries to reference the first character. Because the string is `nil`, this attempts a dereference of address `0` (or `0 + 8` for length offset), causing an immediate **Segmentation Fault**.
  3. **`PChar(s)` (Safe):** If `s` is `nil` (empty), `PChar(s)` evaluates safely to `nil` (0). Since C library calls (like SQLite) frequently accept `nil` to denote optional or empty string arguments, `PChar(s)` behaves correctly and safely.

---

### Architectural Advice on `PChar` (Cast vs. Normal Function)

While it is tempting to implement `PChar` as a regular library function, it **must remain a compiler-recognized typecast/builtin** for lifetime and memory correctness:
* **The Dangling Pointer Risk:** If `PChar(s)` were a normal function, passing the string `s` by-value would make a temporary local copy of the string in the function's stack frame. Returning a pointer to this copy would immediately create a **dangling pointer** once the function returns.
* **Inline Strings:** For legacy inline/frozen strings, the compiler must offset the variable's frame address by `+8` to skip the length prefix. A normal function cannot inspect the caller's frame layouts dynamically. 
* **Conclusion:** Keeping `PChar` as an AST-level cast (e.g., `AN_PTR_CAST` with a sentinel in `ir.inc`) is correct because it reinterprets the original variable's pointer/address directly without copying.

---

### Delivered SQLite Demos

The test suite now demonstrates both Pascal C-interop styles:
1. **Static typing:** explicit typenames parsed from the imported header.
2. **Auto-typed locals:** deferred static type inference locks C handle locals on first assignment.

---

## Per-target codegen parity matrix (Intel + ARM)

Authoritative parity audit for ticket
`feature-cross-target-feature-parity`. Scope is the four hosted Linux targets:
Intel (**x86-64**, **i386**) and ARM (**aarch64**, **arm32**). Xtensa / RISC-V
(ESP32) are deferred and intentionally omitted.

Legend: **✓** works (byte-identical self-host where applicable) · **✗** hard
`Error('… not yet supported')` in the backend or ELF writer · **◐** partial /
edge cases pending · **—** structural limit shared by *all* targets (not a cross
gap).

Each ✗ is a checklist item below the table. Seeded by grepping
`ir_codegen.inc` / `ir_codegen386.inc` / `ir_codegen_aarch64.inc` /
`ir_codegen_arm32.inc` / `elfwriter.inc` for `not yet supported` /
`not supported` (2026-06-17).

| Feature | x86-64 | i386 | aarch64 | arm32 | Notes / blocker site |
|---|:--:|:--:|:--:|:--:|---|
| Integer arith (8/16/32) | ✓ | ✓ | ✓ | ✓ | |
| Int64 / UInt64 arith | ✓ | ✓ | ✓ | ✓ | i386 r-pair, arm32 r0:r1, aarch64 native |
| Float (single/double) | ✓ | ✓ | ✓ | ✓ | feature-cross-float-variant |
| Variant | ✓ | ✓ | ✓ | ✓ | single/extended box as VT_DOUBLE all 4 (test_cross_variant_single) |
| Managed AnsiString (COW) | ✓ | ✓ | ✓ | ✓ | feature-cross-managed-string-cow |
| Records (by-val / copy / fields) | ✓ | ✓ | ✓ | ✓ | feature-cross-managed-aggregates |
| Dynamic arrays | ✓ | ✓ | ✓ | ✓ | |
| Open-array params + `Length` | ✓ | ✓ | ✓ | ✓ | feature-open-array-length-gap |
| `array of const` (TVarRec) | ✓ | ✓ | ✓ | ✓ | |
| Multidim fixed arrays | ✓ | ✓ | ✓ | ✓ | |
| Short-circuit `and`/`or` | ✓ | ✓ | ✓ | ✓ | lowered in shared IR |
| Exceptions (try/except/finally) | ✓ | ✓ | ✓ | ✓ | feature-cross-exceptions |
| Generators / coroutines / async **surface** | ✓ | ✓ | ✓ | ✓ | stackful + stackless |
| Channels | ✓ | ✓ | ✓ | ✓ | |
| Procedural types / indirect call | ✓ | ✓ | ✓ | ✓ | param-count cap is shared (—) below |
| Indirect call > N params | — | — | — | — | x86-64 >6, aarch64 >8, arm32 >4: structural, all targets |
| **Class instantiation (VMT + ctor)** | ✓ | ✓ | ✓ | ✓ | done 2026-06-17; byte-identical |
| Class fields / methods / virtual dispatch | ✓ | ✓ | ✓ | ✓ | incl. inheritance + properties |
| `__rttireg` / `__resources` ops | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 |
| Class-reference field/var store (`tyClass`) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 |
| Method pointers (`of object`) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (TARGET_PTR_SIZE TMethod.Data) |
| Aggregate-valued fn results (records/sets) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (hidden-dest ABI; ecx/x8/r12) |
| Frozen inline-string store-through-ptr | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (typinfo SetStrProp) |
| Metaclass value (`cref := TFoo`, IR_CLASSREF) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 |
| Metaclass / RTTI streaming (field+name reads) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (CPU32 blob padding + frozen-string fixes) |
| Frozen `string` copy / `Length` on cross | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (was managed-only); future: ShortString-255 sizing |
| Sets (`set of`, literal, `in`, `+`/`-`/`*`, `=`/`<>`/`<=`/`>=`) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (32-byte bitset; unblocks `for..in (set)`) |
| Collections / dynarray-of-record depth | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (`setlen_dyn` / `dynunique` ported; field/nested targets via portable `PXXDynSetLen`/`PXXDynArrayUnique`) |
| Interfaces (CORBA) | ✓ | ✓ | ✓ | ✓ | done 2026-06-19 (decl/implement/call, fat pointer, is/as/Supports, implicit coercion, identity, nil, inheritance; 32-bit fat-ptr param ABI forced by-ref). ARC deferred → feature-interface-refcounting |
| External (C-library) calls | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (i386 cdecl / aarch64 AAPCS x0-x7+v0-v7 / arm32 armel r0-r3; GOT-slot call). Full ABI: float/single/double + Int64/UInt64 args & returns; i386 16-aligned; validated vs libc/libm (test_extern_c_float) |
| External/dynamic symbols (ELF) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (ELF32 PrepareDynamicData32 i386/arm32; 64-bit writeELF interp+GLOB_DAT per-arch for aarch64) |
| Method-pointer fixups (ELF) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (writeELF32 + 64-bit writeELF) |
| `SetLength` on var-array param | ✗ | ✗ | ✗ | ✗ | broken on ALL targets (incl. x86-64): param ABI passes the open-array data ptr, but `SetLength` needs `&caller_slot` to publish back → no-op/segfault. Cross-cutting ABI gap, not a cross port → feature-setlength-var-array-param-abi |
| Async I/O reactor (epoll/asyncnet/CoSleep) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (per-arch SYS_*; aarch64/arm32 epoll_pwait; i386 socketcall; epoll_event pad on aarch64/arm32) |
| RTTI typinfo reads (props/ordinals/strings/sets/events) | ✓ | ✓ | ✓ | ✓ | done 2026-06-19; `test_rtti` wired into all 3 cross suites |
| Component streaming + LFM loading | ✓ | ◐ | ◐ | ◐ | typinfo reads done cross; streaming layer (`GetMethodProp` + `-101`/`-103` specials) not yet ported → feature-cross-streaming-lfm |
| GTK / PCL GUI | ✓ | ◐ | ◐ | ◐ | classes + external calls now done on cross; untested on i386/aarch64/arm32, likely needs extern-ABI breadth (float C args) — feature-cross-extern-abi-breadth. NB: uses our own stub units, not real LCL |

Notes on aarch64 ELF: the 64-bit ELF writer (`writeELF` path) already applies
`MethodFixups` and external symbols, so aarch64 is **not** blocked at the
writer — only at codegen (instantiation/external). The `writeELF32` blocks are
i386/arm32-only.

### Checklist (each ✗ → close-out item)

Dominant blocker first; items sharing a fix are grouped.

1. **Classes on cross** (the gating item) — **core DONE 2026-06-17**:
   - [x] i386 / aarch64 / arm32: class instantiation (VMT init + ctor call)
   - [x] class field / method access + virtual dispatch (incl. inheritance, properties)
   - [x] `__rttireg` / `__resources` ops on all three
   - [x] class-reference field/var stores (`tyClass`) on all three
   - [x] method pointers (`of object`) on all four (TARGET_PTR_SIZE TMethod.Data)
   - [x] aggregate-valued fn results (records/sets) on all four (hidden-dest ABI)
   - [x] frozen inline-string store-through-ptr on all three cross targets
   - [x] `IR_CLASSREF` metaclass value (`cref := TFoo`) on all three
   - [x] **RTTI typinfo reads on cross** — all 3 bugs from the original arc are
     closed: (1) frozen-string-through-pointer read, (2) CPU32 blob stride, (3)
     sets. `test_rtti` (props/ordinals/strings/published-set/event-thunk) wired
     into all 3 cross suites 2026-06-19, output-equal to x86-64.
   - [ ] **component streaming + LFM on cross** — `test_streaming`/`_enumset`/
     `test_lfm` still fail at `GetMethodProp` (`-101`/`-103` + typed-ptr-index
     specials not on cross) → feature-cross-streaming-lfm.
   - [x] collections / dynarray-of-record (`setlen_dyn`, `dynunique`, `set_lit`)
   - [x] interfaces (CORBA) on all four — done 2026-06-19 (feature-interfaces);
     all 5 interface tests wired into the cross suites 2026-06-19
2. **ELF32 dynamic-link path** (i386/arm32):
   - [x] method-pointer fixups — done (writeELF32 apply loop)
   - [ ] external (dynamic) symbols — `elfwriter.inc:622,628`
3. **External calls in codegen** (C imports): i386 `1994`, aarch64 `1419`, arm32 `1598`.
4. **Aggregate-valued fn results**: i386 `1996`, aarch64 `1421`, arm32 `1600`.
5. **`SetLength` on var-array param**: broken on ALL targets (incl. x86-64) —
   cross-cutting param-ABI gap, spun out to feature-setlength-var-array-param-abi.
   The cross backends keep the explicit `not yet supported` guard.
6. **Async I/O reactor cross**: per-arch syscall numbers + reactor/asyncnet/CoSleep
   gating; run reactor/asyncecho/timer suites under QEMU.
7. **Variant edge types**: single/extended — DONE all 4 (box as VT_DOUBLE).
8. **Interfaces (CORBA)** on all four — DONE 2026-06-19 (feature-interfaces).
   ARC (`IInterface`/refcount) deferred → feature-interface-refcounting.

Items marked **—** (indirect-call param cap) are shared structural limits, not
cross gaps, and are out of scope for this arc.
