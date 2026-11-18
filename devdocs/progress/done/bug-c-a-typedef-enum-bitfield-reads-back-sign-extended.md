---
track: C
tags: [cfront, bitfields, enums, pathb, lvgl]
prio: 85
type: bug
blocked-by: []
summary: "A bitfield whose type is a TYPEDEF'd enum (`side_t side : 2`) was signed, so 2 read back as -2. gcc makes an enum bitfield unsigned when no enumerator is negative, and pxx already did for `enum X f : n`, but not through a typedef name. LVGL's line masks keep their side that way: every triangle (chart area fills, gauges) drew nothing in the pxx-built widgets demo."
status: done
owner: pxx2
---

# A typedef'd enum bitfield read back sign-extended

## Symptom

The pxx-built LVGL 9.2.2 widgets demo on /dev/fb0 drew the Analytics
charts without their gradient area fills and the gauges without their
arcs. Off-screen, `lv_draw_triangle` produced no pixels at all, even for
a plain solid triangle.

## Cause

`lv_draw_sw_mask_apply` returned TRANSP for the triangle's bottom edge.
That edge is a horizontal line mask with
`cfg.side = LV_DRAW_SW_MASK_LINE_SIDE_TOP` (2), stored in
`lv_draw_sw_mask_line_side_t side : 2`. pxx read the 2-bit field as signed
and got -2, so `side == ..._TOP` was false and the mask said "transparent".

C leaves an enum bitfield's signedness implementation-defined. gcc
zero-extends when no enumerator is negative. cparser already stored
`enum X f : n` fields as unsigned (CTypeBaseIsEnum, c-testsuite 00218),
but a typedef name resolved to plain int and lost the "enum" mark.

## Fix

- `CTypedefIsUEnum[]`: set for `typedef enum {..} T;` when
  ParseCEnumBody saw no negative enumerator (`CEnumBodyHasNeg`), and
  carried through `typedef T Alias;`.
- ParseCDeclType's typedef path sets CTypeBaseIsEnum from it, so the
  existing bitfield rule applies.
- An enum with a negative enumerator stays signed, as in gcc.

## Test

test/c_typedef_enum_bitfield.c, rows c_tdenumbf26 and c_tdenumbf26_i386
(gcc-compared). The rows cover a typedef'd enum, one with a negative
enumerator, a tagged typedef enum, an alias, a plain `enum` field, an
8-bit field and a switch on the field.
