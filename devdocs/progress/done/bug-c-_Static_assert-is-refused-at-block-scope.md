---
summary: "RESOLVED 2026-09-16: the title named the LOUD half. A FALSE _Static_assert compiled SILENTLY at file, struct AND union scope — it parsed and skipped, so the struct stayed well-formed and nothing looked wrong; only block scope refused, and with the wrong message. That is a guard users write (the ABI layout check) that could not fail. One handler now serves all four scopes and evaluates through CEvalConstExpr. Ten scope/truth combinations checked against gcc, all agree."
type: bug
track: C
prio: 70
status: backlog
created: 2026-09-16
found-by: frankb-56
tags: [c-frontend, c11]
blocked-by: []
---

# `_Static_assert` is refused at block scope

## Measured 2026-09-16

```c
int main(void){ _Static_assert(sizeof(int)==4, "int is 4"); return 0; }
```

| compiler | result |
| --- | --- |
| gcc | compiles, rc=0 |
| pxx HEAD | `pascal26:2: error: call to undeclared function: _Static_assert` |
| pxx pin v410 | identical |

**Pre-existing, not a regression** — the two readings agree, which is why it is
filed rather than fixed in the commit that found it.

## Why

`_Static_assert` is in `CIsTopLevelSkipIdent`, so the **file-scope** walk skips
it (skipping, not evaluating — the assertion is not checked there either).
`ParseCStatementAST` has no arm for it, so at block scope it reaches expression
parsing and reads as a call to an undeclared function.

Found while probing the block-scope storage-class fix
([[bug-c-a-block-scope-static-is-silently-dropped-when-a-thread-storage-class-precedes-the-type]]),
whose narrow specifier set deliberately does NOT skip `_Static_assert` —
skipping it there would have turned this loud refusal into a silent no-op,
which is worse.

## Scope

C11 6.7.10 puts a static assertion wherever a declaration may appear, which
includes block scope. Real C uses it inside functions to pin layout assumptions
next to the code that depends on them.

**Refusing is the honest failure and is not urgent** — nothing compiles wrong
today, and the message names the construct. This is a gap, not a defect in
emitted code.

## Not just parsing

Note that the file-scope path **skips** the assertion rather than evaluating it,
so a false `_Static_assert` at file scope is currently accepted silently. Fixing
block scope by skipping there too would extend that silence rather than close
it. Whoever takes this should evaluate the constant expression in both places
and refuse on a false one — that is the point of the construct, and a skipped
assertion is a guard that cannot fail.

## RESOLVED 2026-09-16 (frankb-56) — and the block-scope refusal was the LEAST of it

**The ticket named the loud half and the silent half was three times larger.**
Filed as "refused at block scope", with a closing section noting that file scope
*skips* rather than evaluates. That section was right and the frontmatter was
ranked on the other half — prio 30, a parsing gap. Re-measured, the real defect
is that **a FALSE static assertion compiled silently at three of the four scopes
C11 allows one.**

| scope | gcc | pxx before | pxx after |
| --- | --- | --- | --- |
| file | error | **silent, ran** | error |
| struct body | error | **silent, ran** | error |
| union body | error | **silent, ran** | error |
| block | error | refused (wrong message) | error |

The three silent rows **parsed and skipped** rather than choking, so the
enclosing struct stayed well-formed and nothing looked wrong. That is why it
survived: the construct appeared to work.

**This is a guard OUR USERS wrote, in their code, believing it protects them**,
and the idiom it exists for is the ABI layout check —
`struct S { ...; _Static_assert(sizeof(struct S) == 32, ""); };` — which is
written in a struct body precisely so it sits next to the layout it is about.
Under pxx it stopped nothing.

### One handler, four sites

`CTryParseStaticAssert` returns False unless the current token actually starts
one, so each caller offers the door and falls through untouched. Wired at file
scope (before the skip arm), block scope (before the storage-class loop, since a
static assertion is a declaration and not one), and the struct member loop —
which unions share, so one door closed both.

**It evaluates through `CEvalConstExpr`**, the same evaluator every array bound
and case label already uses, so a construct constant enough for `int a[N]` is
constant enough here and no second constant-ness rule was invented to drift from
the first.

`_Static_assert` **stays in `CIsTopLevelSkipIdent`** so the backward specifier
scans (`CDeclSawStatic`/`Extern`/`ThreadLocal`) keep their stopping behaviour
unchanged; the new file-scope arm simply comes first.

`static_assert` is accepted as a spelling — C23 promotes it to a keyword and
`<assert.h>` has defined it as a macro since C11, so code arrives under both
names depending on whose header ran. The message is optional (C23 6.7.11) and
its absence is the standard's form, not a default invented here.

The diagnostic reports **the assertion's own line**, not wherever the parser
ended up: the operands can span lines and the reader needs the one they wrote.

### THE BUG THIS FIX INTRODUCED AND THE PROBE THAT HID IT

The file-scope arm was first written as a bare
`if not CTryParseStaticAssert then Next` inside an `else if` chain. **That is a
dangling else**: Pascal binds the following `else` to the INNER `if`, silently
re-parenting the whole remaining chain into that arm. It compiled, and a **TRUE**
assertion then **HUNG the top-level walk.**

**The false-assertion probe still passed**, because `Error()` escaped before the
damage could show. So the one row a reader runs first — the row the whole ticket
is about — said the feature worked, while the compiler hung on the *correct*
program. Found only because the test matrix ran the TRUE control immediately
after. `begin`/`end` there is load-bearing and is commented as such.

### Verified

`test/c_static_assert.c` (must compile and run, true assertions at all four
scopes, with `sizeof` and field reads asserting the **layout is unchanged** —
a struct whose assertion perturbed its layout would still compile) plus **four
Makefile refusal rows, one file per site**, each with the `!` precondition
branched on so an unexpected success fails the row rather than falling through
to a grep of an empty log.

    pxx     static assert: 4 scopes, layout intact   rc=0
    gcc     static assert: 4 scopes, layout intact   rc=0
    struct with an assertion in the body: 7 9 16 under both

Ten scope/truth combinations checked against gcc; all ten agree.

**Found by frankuser**, who measured the struct and union rows on origin and
reported them with the caveat that their tree did not carry this work — so the
rows described the shape of the hole and not a verdict on the fix. I ran the same
rows here before acting on them.

Gate: `make compiler/pascal26` converged after 1 round (7c0d39cb5e1b).
