---
track: A
prio: 70
type: bug
---

# A C unit's code segfaults when the program also uses sysutils

Found while bringing up the vendored pdfgen backend
([[feature-lib-pxxpdf-reportlab-compat]]).

## Repro

```pascal
unit mid;
interface
uses pxxcio, sysutils, '<repo>/lib/vendor/pdfgen/pdfgen.c';
function midmake: Pointer;
implementation
function midmake: Pointer;
var w, h: Single;
begin
  w := 595.0; h := 842.0;
  midmake := pdf_create(w, h, nil);   { SIGSEGV inside pdf_create }
end;
end.
```

- `uses pxxcio, ...` alone: works, returns a document.
- `uses pxxcio, pylib, ...`: works.
- `uses pxxcio, sysutils, ...`: **segfaults inside pdf_create**.
- Compiling the same program with **`-dPXX_LIBC_HEAP`: works.**

## What is ruled out

The heap BRIDGE itself is fine with sysutils present: a C unit that
`calloc`s 4096 bytes, `memset`s it, `realloc`s to 8192, `memset`s again and
`free`s returns success, and Pascal-side `GetMem`/`FreeMem` and a direct
`__pxx_malloc` call both succeed immediately before the crashing call. So it is
not a plain "allocator missing" failure.

That `-dPXX_LIBC_HEAP` makes it pass points at the pxx allocator rather than at
pdfgen: some allocation pattern pdfgen uses (it grows a dstr with realloc and
keeps a linked object list) is mishandled when sysutils is also linked, or
sysutils and crtl disagree about who owns a block.

## Next step

`-dPXX_LIBC_HEAP` + valgrind on the failing shape — the technique that found
[[bug-nilpy-pydict-v-borrowed-reference]] — but note the libc-heap build does NOT
reproduce, so valgrind has to run against the pxx allocator with its own
poisoning, or the allocator needs instrumenting.

## Why it matters

Any Pascal library that wraps a C unit will use sysutils; the reportlab shim
does. Silent, and it fails deep inside third-party C where nothing looks wrong.

## Root cause (2026-07-28)

Not the allocator, and nothing to do with pdfgen's allocation pattern. It is
the b377 name-collision family ([[project_crtl_c_pascal_name_collision_macro]]):

pdfgen.c calls `time(NULL)`. cfront's `FindProc` spans the C and Pascal
namespaces case-insensitively, so `time` bound to **sysutils' Pascal
`function Time: TDateTime`** — no parameters, Double result, Pascal calling
convention. The call passed an argument the callee never declared and used its
result as a pointer; the crash was `mov eax, [rbp-8]` / `mov [rax], rcx`, a
pointer truncated to 32 bits, inside `Time`, not inside `pdf_create`.

That explains every observation in the ticket exactly:

- `uses pxxcio, ...` alone works — sysutils is not linked, so no `Time` exists
  and `time` stays the C one;
- `uses pxxcio, pylib, ...` works — same reason;
- `-dPXX_LIBC_HEAP` "fixes" it only because that build links libc's `time`,
  which wins before the Pascal routine is consulted.

The heap was a red herring throughout.

## Fix

The established cure for this family: `lib/crtl/src/time.c` defines
`__crtl_time`, and `lib/crtl/include/time.h` declares it with a FUNCTION-LIKE
macro `#define time(t) __crtl_time(t)`, so C callers reach the C
implementation while variables and struct fields named `time` are untouched —
exactly as `exp`/`Exp` and `log2`/`Log2` are handled in math.h.

The repro in this ticket now prints `ok`.

**A C source that calls `time()` without including `<time.h>` still binds the
Pascal routine silently.** That general hazard — any C call binding to a
Pascal proc of a different arity, with no diagnostic — is filed separately as
[[bug-cfront-silent-bind-to-pascal-proc-of-different-arity]].

## Log
- 2026-07-28 — resolved, commit HEAD.
