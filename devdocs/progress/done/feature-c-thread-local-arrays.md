---
track: C
tags: [C, tls, threads]
prio: 30
type: feature
status: done
owner: unassigned
found: 2026-11-14
summary: "A file-scope C `__thread` ARRAY or STRUCT (and arrays of structs, multi-dimensional, static or not, initialised or not) now gets one copy per thread on x86-64, i386, aarch64 and arm32, and initialisers reach every new thread. They used to warn and fall back to one shared copy (TLSREFUSE_ARRAY / TLSREFUSE_TYPE). Pascal threadvar arrays/records are still refused."
---

# C: `__thread` arrays and structs

## Mechanism

A scalar thread-local is handled by ThreadVarRewriteRange: its AN_IDENT is
rewritten in place to `AN_DEREF(AN_TLSBASE + off)`. That rewrite is wrong for
an array. C reaches an array through its symbol on many paths: argument decay,
pointer-arithmetic strides, row decay, pointer-to-array shapes. After the
rewrite, `strcpy(buf, ...)` passed the first char as the pointer and crashed.

So a C array or struct keeps its AN_IDENT, and its address is redirected where
every one of those paths ends up, `IRAppend`:

- `IR_LEA` / `IR_SLOTADDR` of such a symbol become
  `IR_TLSBASE + SymTlsOffset`;
- `IR_LOAD_SYM` / `IR_STORE_SYM` (a small struct moved whole: `return tp;`,
  `c = tp`) become `IR_LOAD_MEM` / `IR_STORE_MEM` through that address;
- `IR_DYNDATA` reaching such a symbol is an internal error.

`CTlsReachedByAddress` (pasparser_decl.inc) is the one predicate.
ThreadVarRewriteRange skips these symbols, and the two init passes below key
on the same predicate.

## Initialisers

The scalar copy into the init image (`(slot 13)^[off] := sym`) does not fit
an array: element targets have too many shapes. An initialiser store into a
thread-local array or struct is compiled a second time with `TlsArrToImage`
set. While it is set, IRAppend points the address at the init image
(`[TLSBASE + 8*TLS_SLOT_INIT_IMAGE] + off - TLS_USER_FIRST_OFF`). The second
pass happens at both places C global initialisers are emitted:
CompilePendingGlobalInits (one entry per element) and CInitEmitAssign (the
aggregate walker; multi-dimensional and struct initialisers go this way).
CTryBakeGlobalInit now refuses thread-locals, because a baked .data image
would be storage nobody reads.

## Layout

A struct is placed at 16-byte alignment in the user area, because
CRecAlign is in a later include. Large arrays hit the existing area-full
error, which names `-dPXX_TLS_USER_4K/8K/16K` (default 3072 bytes).

## Tests

`test/c_thread_local_arrays.c` covers int/char/short[2][3]/long long arrays,
structs, a struct with nested arrays, an array of structs, `static`, `&a[i]`
differences, `sizeof`, pointer arithmetic, row decay and struct return. Rows
c_tlarr26, c_tlarr_i386, c_tlarr_a64 and c_tlarr_arm32 compare against
gcc's output. Row ctls_two_reasons now expects 0 warnings; the
array-plus-struct program it compiles no longer degrades.

## Not done

- Function-scope `static __thread` (TLSREFUSE_FUNCSCOPE):
  feature-c-a-function-scope-thread-local-gets-real-per-thread-storage.
- Pascal `threadvar` arrays and records are still refused.
