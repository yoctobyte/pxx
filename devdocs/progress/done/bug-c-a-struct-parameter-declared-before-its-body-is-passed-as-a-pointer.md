---
slug: bug-c-a-struct-parameter-declared-before-its-body-is-passed-as-a-pointer
track: C
prio: 85
type: bug
status: done
owner: pxx2
created: 2026-11-26
closed: 2026-11-26
found-by: pxx2 (Nodisx zstd recipe: every multithreaded compression failed with "Parameter is out of bound")
tags: [cfront, abi, structs, silent-miscompile]
summary: "A prototype that names a struct type by value before the struct's body (`typedef struct S S; size_t f(S s);`, body later) was compiled as a by-REFERENCE parameter: ABICRecordParamByValue refuses an unsized record, and nothing revisited the decision when the body arrived. Every call then passed a pointer where the callee, compiled with the full type, read the bytes, and every argument after it was shifted. zstd's ZSTDMT_initCStream_internal (216-byte ZSTD_CCtx_params) and ZSTDMT_createCCtx_advanced (24-byte ZSTD_customMem) are declared this way, so all multithreaded zstd compression failed. The prototype fixup now notes such parameters and ParseCStructInto settles them when the body is laid out. Test c_spbb26 against gcc."
---

# A struct parameter declared before its body is passed as a pointer

```c
typedef struct big_s Big;                 /* zstd.h */
size_t init(void *m, ..., Big p, unsigned long long pl);   /* zstdmt_compress.h */
struct big_s { ... };                     /* zstd_compress_internal.h */
init(m, ..., params, size);
```

The call site copied `params` to a temporary and pushed its ADDRESS (8
bytes, popped as 0x10 with the last argument). The callee, compiled in
zstdmt_compress.c where the struct was complete, read 216 bytes from
`[rbp+0x10]`. It saw nbWorkers=0, a garbage pledgedSrcSize and a garbage
windowLog, and ZSTD_checkCParams refused. Single-threaded zstd was fine,
because a small known input takes the nbWorkers=0 path in the caller and
never makes the call.

Any size was affected: a 16-byte two-register struct came out garbage
too. A function defined in the same file after the call, which is the
test's shape, broke the same way.

The fix: in the prototype fixup (the CALLER's half of the by-value decision),
a struct parameter whose body has not been seen goes on a pending list.
At the end of ParseCStructInto, the list entries for that record get
`IsRef := not ABICRecordParamByValue(rec)`.

Not covered: a function-pointer signature that names an incomplete struct
by value (the three fpSig sites) still decides once. No case of that has
been seen yet.
