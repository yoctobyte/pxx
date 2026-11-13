---
track: C
tags: [c, x86-64, emit-obj, linker, miscompile, dropbear]
prio: 70
type: bug
blocked-by: []
summary: "An extern object declared while its struct type was still incomplete got a 0-byte .bss slot, so several of them shared one offset. The object writer names an import by its offset, so `&second` was relocated to the FIRST name at that offset, a silent pointer to the wrong object. Every name at that offset also counted as referenced, so unused declarations became UND symbols. A zero-size C global now gets one byte."
status: done
owner: claude
---

# Zero-size extern declarations shared one slot and one relocation

Found linking dropbear 2026.94 ([[feature-c-dropbear-builds-with-pxx]]). The
server's link asked for `clichansess`, which only the client defines and the
server never uses.

**Cause.** dropbear's `algo.h` declares three objects before their structs
are defined:

```c
extern const struct dropbear_cipher dropbear_nocipher;
extern const struct dropbear_cipher_mode dropbear_mode_none;
extern const struct dropbear_hash dropbear_nohash;
```

and `channel.h` declares `clichansess` the same way. An incomplete type sizes
to 0 in `symtab.inc`, so each declaration reserved 0 bytes and all of them got
the same `.bss` offset. The x86-64 object writer finds an import from a
relocation by offset (`ObjDataSymIndexForOff`, exact match, first wins), and
decides whether an import is used by offset (`ObjDataIsReferenced`). That
caused two failures:

1. **A miscompile.** `&dropbear_nohash` was relocated against
   `dropbear_nocipher`. Minimal form: declare `a`, `b` and `c` of incomplete
   types and take `&b`. The object's relocation names `a`.
2. **A link failure.** Taking the address of any one of them made all of them
   "referenced", so every one became an UND symbol, including `clichansess`
   in a program that never links the client code.

**Fix.** In `compiler/symtab.inc`, a C global of size 0 reserves one byte.
That gives each object its own address, which C requires anyway (6.5.9:
distinct objects compare unequal). Pascal layouts are not touched. The
object writer pays nothing extra: import slots are skipped or punched out at
write time.

**Test.** `test/c_incomplete_extern_distinct_a.c` + `_b.c`. Each is compiled
with `--emit-obj`, then the two are linked with `--link`.

- Row `cincext_und` checks with `nm` that the unused `client_only` is not
  emitted as an UND symbol.
- Row `cincext26` checks that each pointer reaches its own object and that
  the pointers are distinct. The expected output is gcc's.
