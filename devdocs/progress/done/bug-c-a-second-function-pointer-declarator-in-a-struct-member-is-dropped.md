---
summary: "C: `void (*f)(void *), (*g)(void *);` in a struct or union kept only f -- \"no member named 'g'\""
type: bug
prio: 40
---

# C: a second function-pointer declarator in a struct member is dropped

- **Type:** bug (C frontend). Reported 2026-11-27 by the rainyday session
  (Rainyday's kernel/dev/pci.c, split there as a workaround in 97258d0).
- **Status:** done

## Symptom

```c
struct s { int a; void (*f)(void *), (*g)(void *); };
int main(void) { struct s x; x.g = 0; return x.g != 0; }
```

gcc accepts it; pxx said `C: no member named 'g' in this struct/union`.

## Cause

In ParseCStructInto, ParseCDeclType consumes a `(*name)(params)` declarator
whole, and the function-pointer arm registers that one member and ends the
declaration (CEndCMember skips to the `;`). Every declarator after the first
was skipped. The comma loop of the plain-member path never ran for this
shape. A file-scope declaration of the same shape already worked: there,
CSplitDeclarators rewrites it into one declaration per declarator first
(bug-c-several-function-pointer-declarators-in-one-declaration).

## Fix

ParseCStructInto calls CSplitDeclarators(False) at the start of each typed
member. It splits only the shapes its own parser can't take: a `(*name)`
declarator anywhere, or a function-pointer typedef as the type. So
`int n, (*h)(int), *pn;` becomes three members, and plain `int a, b;` takes
the existing comma loop as before.

## Test

`test/c_struct_several_fnptr_declarators.c` (Makefile row c_sfpd) runs
against gcc at both widths. It covers two fn-pointers in one declaration, a
plain, a fn-pointer and a pointer declarator mixed, an array of fn-pointers
followed by another fn-pointer, and a union of two fn-pointers. It checks
each member's offsetof, the sizeof of the struct and the union, and calls
through every member.
