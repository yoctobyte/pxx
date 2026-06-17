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
| Variant | ✓ | ✓ | ◐ | ◐ | aarch64 single/extended pending (`aarch64.inc:1956,2004`) |
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
| Interfaces | ◐ | ✗ | ✗ | ✗ | feature-interfaces; classes now unblock it |
| External (C-library) calls | ✓ | ✗ | ✗ | ✗ | `386:1994` `aarch64:1419` `arm32:1598` |
| External/dynamic symbols (ELF) | ✓ | ✗ | n/a | ✗ | `elfwriter.inc:622,628` |
| Method-pointer fixups (ELF) | ✓ | ✓ | ✓ | ✓ | done 2026-06-17 (writeELF32 + 64-bit writeELF) |
| `SetLength` on var-array param | ✓ | ✗ | ✗ | ✗ | `386:1705` `aarch64:1118` `arm32:1293` |
| Async I/O reactor (epoll/asyncnet/CoSleep) | ✓ | ✗ | ✗ | ✗ | per-arch syscalls (epoll_pwait, socketcall) |
| RTTI / streaming / LFM | ✓ | ◐ | ◐ | ◐ | needs ELF method fixups |
| GTK / LCL GUI | ✓ | ✗ | ✗ | ✗ | needs classes + external calls |

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
   - [ ] **RTTI on cross — 3 distinct bugs** (see ticket Log 2026-06-17):
     (1) frozen-string-through-pointer read (`c^.NamePtr^`) garbage on ALL cross
     targets incl. aarch64 — dominant, a codegen bug, fix first;
     (2) RTTI blob 8-byte stride vs 32-bit typinfo records (i386/arm32) — fix via
     `{$ifdef CPU32}` 4-byte padding in typinfo records (compiler/blob untouched);
     (3) sets (`set_lit`/`dynunique`) for test_rtti's published `set` property.
   - [ ] collections / dynarray-of-record (`setlen_dyn`, `dynunique`, `set_lit`)
   - [ ] interfaces (now unblocked by classes) — feature-interfaces
2. **ELF32 dynamic-link path** (i386/arm32):
   - [x] method-pointer fixups — done (writeELF32 apply loop)
   - [ ] external (dynamic) symbols — `elfwriter.inc:622,628`
3. **External calls in codegen** (C imports): i386 `1994`, aarch64 `1419`, arm32 `1598`.
4. **Aggregate-valued fn results**: i386 `1996`, aarch64 `1421`, arm32 `1600`.
5. **`SetLength` on var-array param**: i386 `1705`, aarch64 `1118`, arm32 `1293`.
6. **Async I/O reactor cross**: per-arch syscall numbers + reactor/asyncnet/CoSleep
   gating; run reactor/asyncecho/timer suites under QEMU.
7. **Variant edge types** (aarch64): single/extended — `1956`, `2004`.
8. **Interfaces** on all four (depends on classes) — feature-interfaces.

Items marked **—** (indirect-call param cap) are shared structural limits, not
cross gaps, and are out of scope for this arc.
