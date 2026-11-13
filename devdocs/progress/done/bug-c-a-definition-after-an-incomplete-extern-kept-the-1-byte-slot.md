---
track: C
tags: [c, x86-64, globals, miscompile, dropbear]
prio: 80
type: bug
blocked-by: []
summary: "A file-scope struct definition that followed an `extern` declaration made while the struct was incomplete reused the declaration's slot without resizing it. A const definition lost its initialiser (read back as zeros), and a non-const one overran its neighbours. dropbear's `dropbear_nocipher = {NULL, 16, 8}` read blocksize 0, and both the server and dbclient died on their first packet with \"division by zero\". The slot now grows to the complete type."
status: done
owner: claude
---

# A definition after an incomplete extern kept the 1-byte slot

Found running the pxx-built dropbear 2026.94
([[feature-c-dropbear-builds-with-pxx]]). Every connection to the server, and
every dbclient login, ended in `Runtime error 200 (division by zero)` inside
`encrypt_packet`, at `padlen = blocksize - len % blocksize`.

**Cause.** `algo.h` declares `extern const struct dropbear_cipher
dropbear_nocipher;` before `struct dropbear_cipher` is defined. The
declaration reserved a slot of the incomplete size: 0 bytes before
[[bug-c-zero-size-extern-declarations-shared-one-slot-and-one-relocation]],
1 byte after it. `common-algo.c`'s definition
`const struct dropbear_cipher dropbear_nocipher = {NULL, 16, 8};` found the
existing row and reused it. Arrays have a grow step for exactly this
(`CGrowGlobalArray`); records had none.

- **const definition:** the object was 1 byte of `.bss` with no initialiser,
  so `blocksize` read 0.
- **non-const definition:** the 16-byte initialiser was written into a 1-byte
  slot. It read back right only because nothing else used the bytes it
  overran.

**Fix.** `CGrowGlobalRecord` in `compiler/cparser.inc`, the record twin of
`CGrowGlobalArray`. When a definition reaches an existing global row whose
reservation is smaller than the now-complete struct, it allocates a slot of
the full size (honouring `aligned(N)`) and moves the row there. Offsets are
read from the row when code is generated, so a function that took the
address before the definition also gets the new slot.

**Test.** `test/c_definition_after_incomplete_extern.c` (row `cdefinc26`,
expected output from gcc). It covers:

- a const definition and a non-const one;
- a 56-byte struct;
- an address taken before the definition;
- guard globals on both sides, so an overrun shows;
- `sizeof` of each object.
