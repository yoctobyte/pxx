---
title: "C23: an enum with a fixed underlying type (`enum E : T`)"
status: done
owner: claude-dupwt
prio: 70
area: cfront
---

C23 6.7.2.2 lets an enum name its underlying type: `enum E : uint8_t { ... }`.
The enum then has T's size, alignment and signedness, at its definition and at
every later `enum E`. cfront mapped every enum to int and stopped at the colon.

FreeBSD's sys/types.h uses it whenever `__GNUC__ >= 13`
(`__enum_uint8_decl(vtype) { VNON, ... }`, used as `__enum_uint8(vtype)
v_type;`), and drm-kmod's DRM core reaches it through sys/vnode.h. It was the
first error in 1813 of the 2100 GPU-driver compiles in the first pxx census
(feature-nodisx-linux-gpu-drivers-built-by-pxx).

Fix (compiler/cparser.inc): a tag table (CEnumFixedTag/CEnumFixedTk in
defs.inc). After `enum [tag]`, a `:` followed by a type (an integer keyword
or a typedef name) is read as the fixed type and recorded for the tag. The
type-specifier, the bare `enum E : T { };` declaration and `typedef enum E : T
{...} N;` all use it, and a later bare `enum E` finds it. `enum bf : 3` (an
unnamed bitfield) still parses as a bitfield, because a number is not a type.
The resolved kind bypasses the short/long arithmetic that would otherwise
widen a 16-bit base back to int.

Test row c_c23enum26 (test/c_c23_enum_fixed_underlying_type.c): sizes, a
struct's offsets, signedness, 8-bit wraparound and the bitfield case. Its
expected output is gcc's.
