---
track: A
prio: 60
type: bug
blocked-by: []
summary: "In a `uses`-imported C header, struct bitfields lose their layout. A Pascal write to a bitfield member stores the value at bit 0 of its storage unit, unshifted and unmasked, overwriting neighbours, and a read returns the whole unit. The header's OWN static inline C code, compiled in the import context, has the same bug. Plain .c compiled by pxx (master and pin) and gcc are correct. Silent wrong ABI: ESP-IDF's RMT config (rmt_symbol_word_t duration0:15/level0:1/..., flags.queue_nonblocking at bit 1) would get garbage, i.e. wrong LED timings. Measured 2026-10-05, frank-user master 722eff275f, x86-64 and riscv32 alike."
status: done
owner: ""
---

# C import: bitfields ignore bit offset and width

- **Type:** bug (C header import, record layout of bitfields) — **Track A**, prio 60:
  silent wrong ABI on a feature that exists to get the ABI right.
- **Filed:** 2026-10-05 from `~/museum_landkaart`. Found by the bitfield checks added
  to async/test/abi_import_check.pas, with the deployed firmware's hand-packed RMT
  words as the oracle.

## Repro (x86-64; riscv32 under qemu-user prints the same)

```sh
cat > bfh.h <<'H'
typedef struct { unsigned int a : 1; unsigned int b : 1; unsigned int c : 4; unsigned int d : 10; } flags_t;
typedef union { struct { unsigned short d0 : 15; unsigned short l0 : 1; unsigned short d1 : 15; unsigned short l1 : 1; }; unsigned int val; } sym_t;
static inline unsigned int c_flags_word(void) { flags_t f = {0}; f.b = 1; f.c = 5; f.d = 700; return *(unsigned int *)&f; }
H
cat > p.pas <<'P'
program p;
uses bfh;
var f: flags_t; s: sym_t; w: PLongWord;
begin
  w := PLongWord(@f);
  FillChar(f, SizeOf(f), 0); f.b := 1;   writeln('b=1      word=', w^, '  want 2');
  FillChar(f, SizeOf(f), 0); f.c := 5;   writeln('c=5      word=', w^, '  want 20');
  FillChar(f, SizeOf(f), 0); f.d := 700; writeln('d=700    word=', w^, '  want 44800');
  FillChar(f, SizeOf(f), 0); f.b := 1; f.c := 5; f.d := 700; writeln('b,c,d    word=', w^, '  want 44822 (C says ', c_flags_word, ')');
  w^ := 44822; writeln('read back b=', f.b, ' c=', f.c, ' d=', f.d, '  want 1 5 700');
  FillChar(s, SizeOf(s), 0); s.d0 := 3; s.l0 := 1; s.d1 := 10;
  writeln('sym word=', s.val, '  want ', 3 or (1 shl 15) or (10 shl 16));
end.
P
pascal26 -I. p.pas p && ./p
```
Output:
```
b=1      word=1  want 2
c=5      word=5  want 20
d=700    word=700  want 44800
b,c,d    word=700  want 44822 (C says 700)
read back b=44822 c=44822 d=44822  want 1 5 700
sym word=655361  want 688131
```
The same header used from plain C (`c.c`: set b,c,d and s.d0/l0/d1, print the word
and `c_flags_word()`) prints 44822 / 44822 / 688131 and reads back 1 5 700 under
pxx master, the pin and gcc. So the C frontend's bitfield layout is right, and the
import path drops it, including for the header's own inline function.

## Real-world

ESP-IDF RMT (driver/rmt_tx.h, rmt_encoder.h, hal/rmt_types.h): `rmt_symbol_word_t`
(anonymous struct of 15/1/15/1-bit fields in a union with `val`), `flags` structs
of 1-bit fields (msb_first, queue_nonblocking, invert_out, with_dma...). With
`uses idf;`: `ec.bit0.duration0 := 3; ec.bit0.level0 := 1; ec.bit0.duration1 := 10`
gives word 1, want 688131. `tc.flags.queue_nonblocking := 1` gives 1, want 2.
`flags.msb_first` only works because it's bit 0.

## Expected

Imported bitfield members carry their bit offset and width. Pascal writes
read-modify-write the storage unit (shift + mask), reads extract (shift + mask,
sign-extend for signed types), exactly as the C frontend already does for .c
units. The header's inline functions compile with the same layout.

## Acceptance

The repro prints the "want" values. In ~/museum_landkaart/async,
`PXX_EXTRA=-dALIAS_WORKAROUND ./build.sh qemu-prog test/abi_import_check.pas` ends
`ABI checked=76 mismatches=0` (today 3 mismatches, all BITFIELD).
