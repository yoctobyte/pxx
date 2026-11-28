---
slug: bug-c-a-struct-redefinition-in-one-scope-is-silently-ignored
track: C
prio: 35
type: bug
status: backlog
created: 2026-11-28
found-by: the Nodisx git recipe (bug-crtl-unistd-h-declares-getopts-struct-option)
---

# C: a struct redefinition in one scope is silently ignored

```c
struct option { int a; };
struct option { void *value; };
int main(void) { struct option o; o.value = 0; return 0; }
```

gcc: `redefinition of 'struct option'`. pxx keeps the first body and says
`no member named 'value'` at the use, far from the cause. With identical
member names and different types, it would compile and lay out the wrong
struct with no diagnostic.

## Why the duplicate is skipped today

There are two guards, ParseCStructInto's and the bare `struct T {...};` path
in the declaration parser. Both skip a body for a record that already has
fields. That is needed for two reasons:
- The C driver reads the token stream more than once (signatures, bodies, the
  crtl-prototype rerun), so a struct's own definition is seen again. Laying it
  out again appended its fields and hung the compiler
  (bug-a-compiler-hang-on-valid-c-programs).
- A host header that pxx falls back to can redefine a struct crtl defines
  (`struct in_addr`), and those builds work today.

## What a fix needs

The fix must tell the same definition seen again from a different one.
- Option one: record where the first body starts (file and line, or a
  hash of its tokens) and refuse only a different body.
- Option two: decide the host-header case separately. It is either
  refused like gcc, or kept, if crtl and the host layout agree.

Measure against the Nodisx recipes and Rainyday before landing: a refusal
there is a regression even where gcc refuses too.
