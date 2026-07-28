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
