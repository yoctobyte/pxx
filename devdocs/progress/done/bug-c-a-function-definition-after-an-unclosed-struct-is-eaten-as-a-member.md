---
slug: bug-c-a-function-definition-after-an-unclosed-struct-is-eaten-as-a-member
track: C
prio: 35
type: bug
blocked-by: []
summary: "`struct S { int a;` followed by a function definition is not detected as unterminated: the function's closing brace closes the STRUCT, the function is swallowed as a member, and the program fails with `main function not found`. gcc errors at the `{` that opens the body."
status: done
owner: frankC
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

## Fixed — and it was worse than this ticket said. frankC, 2026-08-30

**I filed this at p35 on one measurement and it was worth more.** The ticket
recorded the case that *errors* (`main function not found`). Measured properly
before fixing, the same defect has a **silent** shape:

```c
struct S { int a;          /* brace never closed */
void f(void) { }
};
int main(void) { return 0; }
```

**Compiled clean on `pinned`.** `f` was consumed as a struct member and
**vanished** — the definition did not exist in the output — and a program that
never calls it builds and runs with the function simply absent. Call it and the
only diagnostic is `call to undeclared function: f` **at the call site**,
pointing away from the missing brace by however many lines the header is.

That is the silent-wrong-behaviour shape, not a message-quality one: real C
source, one missing brace, compiles to a different program. Worth 50, not 35 —
and the reason I under-priced it is worth more than the number: **I filed it from
the one shape I had in front of me**, which happened to be the loud one. A defect
priced from its noisiest instance is priced from the instance least likely to
hurt anyone.

### The fix, and where it deliberately stops

`CEndCMember` replaces the bare `Eat(tkSemicolon)` at all three member
terminators in `ParseCStructInto`. A member declaration ends at `;`; if it does
not, and what follows is a **body**, it is a function definition and a brace is
missing above.

Two spellings reach it, and the second is the common one:

- `int b { } ;` — the cursor is on the brace. Refuse.
- `void f(void) { }` — the cursor is on the **parameter list**. Skip the balanced
  parens and look at what follows; refuse only if it is a brace.

**A paren alone is not enough to refuse**, and that is the whole design of the
narrowness: the member parser's leniency past a missing semicolon is what carries
the odd system header, so `void f(void);` after a missing semicolon still just
continues, exactly as before. The genuine function-pointer member never reaches
here at all — `ParseCDeclType` consumes that declarator whole and its own arm
calls `CEndCMember` with the cursor already past it.

| | `pinned` 53800fbeb0b6 | now | gcc |
| --- | --- | --- | --- |
| `void f(void) { }` after an unclosed struct | **compiles clean, `f` gone** | `2: a struct member cannot have a body` | `2:14: expected ... before '{' token` |
| `int f(void) { ... }` | compiles clean | same, line 2 | same |
| `int f() { ... }` | compiles clean | same, line 2 | same |
| `int b { } ;` | compiles clean | same, line 2 | same |
| `int main(void) { ... }` after one | `1313: main function not found` | same, line 2 | same |

Same line gcc names, in every row.

### The test that matters is the second one

`cmember_body` asserts the refusal. **`cmember_lenient` asserts the leniency the
refusal must not widen into** — a real `int (*fp)(void)` member, comma
declarators, and a member with a genuinely missing semicolon before the closing
brace — and it must compile *and run*. It passes on `pinned` too, which is the
point: it is a guard against my own fix, not evidence for it.

### Gate

Self-host converged, 1 round, `bd77594de5cd`. forwardlint clean of C-lane
failures. 12 C corpus programs compile; a four-system-header program still
imports and runs. Both new `test-core` rows validated in both directions.

### Comment-nesting, the fourth and fifth time tonight

`{ }` comments nest, so a brace in the prose ends the comment early — and
switching to `(* *)` does not escape it: **`(*` nests too**, and the phrase
"RET (\*name)(params)" killed a build the same way. Both are now spelled out in
words. The general rule, which the playbook should carry: **a Pascal comment
cannot contain its own delimiters in either style, so quoting code in one is a
hazard in a repo whose comments quote C constantly.**

## Log
- 2026-08-30 — resolved, commit e1ce94434.
