---
slug: bug-c-a-function-definition-after-an-unclosed-struct-is-eaten-as-a-member
track: C
prio: 35
type: bug
blocked-by: []
summary: "`struct S { int a;` followed by a function definition is not detected as unterminated: the function's closing brace closes the STRUCT, the function is swallowed as a member, and the program fails with `main function not found`. gcc errors at the `{` that opens the body."
status: backlog
---

# A function definition after an unclosed struct is eaten as a member

```c
struct S { int a;
int main(void) { return 0; }
```

```
pxx:  pascal26:2: error: main function not found
gcc:  error: expected ':', ',', ';', '}' or '__attribute__' before '{' token
```

Split from `bug-c-an-unterminated-declaration-still-parses-the-appended-pascal-rtl`,
which fixed the *truly* unbalanced case (`struct S { int a;` with nothing after
it now says `unterminated C construct` on line 1). This one is a different
defect and the fix there cannot reach it: **nothing is unterminated.** The member
list is closed, by `main`'s brace, and every token in between is a plausible
member declarator until the `{`.

## What to fix

A struct/union member declarator followed by `{` is not a member. The member
parser should refuse there, naming the line of the `{`, the way gcc does — the
information is local and does not need the enclosing construct's state.

The same shape presumably applies to a `union` and to a nested struct; check
before assuming, and check whether an `enum` body has an equivalent (an
enumerator followed by `{`).

## Gate

The example errors at line 2 naming the unexpected `{`, not at line 2 with
`main function not found`. `cunterm_struct` / `cunterm_enum` / `cnomain` stay
green. Self-host byte-identical.
