---
slug: bug-c-an-empty-brace-initializer-leaves-a-local-array-uninitialised
track: C
prio: 55
type: bug
status: done
created: 2026-11-21
found-by: claude-pxx (toybox readelf -S, 2 rows)
tags: [cfront, init, silent, stack]
blocked-by: []
summary: "DONE 2026-11-21: `char a[16] = EMPTY;` (an empty brace pair, GNU and C23) left a local ARRAY uninitialised -- the zero-fill ran only when the list had elements. A struct was fine. toybox readelf -S printed a stray 0x01 from its flags buffer. Test c_ebla26."
---

# An empty brace initializer leaves a local array uninitialised

## Found

toybox `readelf -S` failed 2 suite rows. Every column matched a gcc build
of toybox except the flags column of section 0, where pxx printed a byte
0x01. The buffer is `char sh_flags[16] = {}, *p = sh_flags;`, and with no
flags nothing is written to it.

Reduced: after the stack is dirtied, `char a[16] = {}` and `int b[4] = {}`
read back the garbage under pxx and zeros under gcc. A struct initialised
the same way was zeroed.

## Cause

ParseCLocalDeclAST zeroes a local array before the element stores (C99
6.7.8p21) only `if (nArrElems > 0) or (CStrInitCount > 0) or
(recArrInitCount > 0)`. An empty list has no elements, so all three were 0.

## Fix

A `hadBraceInit` flag (an `=` followed by an open brace) joins the
condition.

## Test

test/c_empty_brace_local_array.c (row c_ebla26). It covers char, int,
2-D long, pointer, double and struct-element arrays plus a plain struct,
on a dirtied stack, twice. Expected output is gcc's. The pinned compiler
prints garbage for it.
