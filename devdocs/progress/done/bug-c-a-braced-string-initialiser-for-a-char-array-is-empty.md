---
track: C
tags: [cfront, initialisers, strings, pathb, tinyx]
prio: 85
type: bug
blocked-by: []
summary: "`char a[] = { \"abc\" }`, a braced string initialiser (C11 6.7.9p14), was sized 1 and left empty; a sized `char a[8] = { \"xyz\" }` was empty too. TinyX's colour-name table is written that way, so the pxx-built X server knew no colour names and st exited with \"could not allocate color 'black'\"."
status: done
owner: pxx2
---

# A braced string initialiser for a char array was empty

cparser.inc CRewriteBracedCharStrInit runs before pass 1, next to the K&R
rewrite. It drops the braces around `"..." "..." [,]` when both of these hold:

- the declarator is `NAME[...]`, with exactly one bracket group and no `*`;
- the specifiers back to the start of the declaration are char,
  signed/unsigned, qualifiers or storage classes.

Every initialiser path already handles the unbraced spelling. Arrays of
pointers, 2-D arrays and structs keep their braces.

Test: test/c_braced_char_string_init.c (row c_brstrinit26) against gcc on
x86-64 and i386. It covers static, local, sized, unsigned and signed arrays,
embedded `\0`s, and the forms that must keep their braces.
