---
summary: "C: `l + 1` over `struct line l[4]` was refused as a struct operand (regression in e17b4497b4)"
type: bug
prio: 70
---

# C: pointer arithmetic on a struct array is refused as a struct operand

- **Type:** bug (C frontend, a regression in e17b4497b4 "struct operands to
  scalar operators refused"). Found 2026-11-28 rebasing the git recipe's
  fixes onto it: test c_const_comma_assign_and_vla_sizeof, git's MOVE_ARRAY
  over a struct array.
- **Status:** done

## Symptom

```c
struct line l[4]; struct line *p = l + 1;   /* also (l + 1)->len, sizeof(*(l + 1)) */
```

pxx: `C: a binary operator needs a scalar operand, not a struct or union`.
gcc accepts it: the array decays to a pointer.

## Cause

CRefuseRecordOperand refuses any operand whose node kind is tyRecord. An
array's node (AN_IDENT, or an AN_FIELD array member) carries its ELEMENT
kind, so an array of structs looked like a struct value.

## Fix

8ef917f5d8 (bug-c-an-array-of-structs-member-is-refused-as-a-struct-operand)
lets an operand through when CNodeDecaysToPointer(e) holds. That helper
declines an array of unknown size (ArrLen -1: `struct kv a[] = {...}`, an
extern `T x[]`) and a dynamic field, so `q = a + 1` over `struct kv a[]`
(test_c_member_access_through_a_comma_ternary_or_assignment) and cpyext's
`tp_slots = g_type_type_slots` (test_cpyext_hello) stayed refused. After it,
CRefuseRecordOperand now also lets through any AN_IDENT whose symbol IsArray,
and any AN_FIELD that RecFieldIsArray. Struct values stay refused
(c_structop26).

Test c_struct_array_pointer_arith (row c_sapa26), against gcc on x86-64 and
i386. It covers locals, a global, a struct's array field, `->` and `*` on
the sum, pointer differences, sizeof, memmove over `l + 1`, and comparisons.
