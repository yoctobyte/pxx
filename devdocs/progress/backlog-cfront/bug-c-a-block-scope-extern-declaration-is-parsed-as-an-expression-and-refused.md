---
slug: bug-c-a-block-scope-extern-declaration-is-parsed-as-an-expression-and-refused
track: C
prio: 60
type: bug
status: backlog
created: 2026-09-19
found-by: frankS
tags: [c-frontend, storage-class]
blocked-by: []
summary: "`extern` INSIDE A FUNCTION BODY is not handled at all and the declaration is parsed as an EXPRESSION, so legal C is refused with a diagnostic that names the wrong thing: `error: undeclared identifier 'extern' used as value`. Measured 2026-09-19 at HEAD, three shapes, gcc accepting every one of them: `extern int g;` in a body (gcc prints 7, we refuse), `extern int puts(const char *);` in a body (gcc prints hi, we refuse — and a block-scope extern FUNCTION declaration is ordinary real-world C, not an exotic), and `extern __thread int g;` (gcc prints 7, we refuse). This is NOT the thread-local seam even though it was found there: plain `extern int g;` with no thread storage class anywhere fails identically, so the cause is the block-scope storage-class loop in ParseCStatementAST never accepting `extern` as a declaration opener. THE CODE ALREADY PREDICTED THIS AND SAID SO: the comment above that loop states extern `is legal at block scope and is not handled today, and adding it is a behaviour change this fix has no measurement for`. The measurement now exists and it is worse than not-handled — it is legal C refused, pointing at the wrong token. Secondary: on the `extern __thread` shape the parser recovers past the error and then emits the function-scope thread-local warning too, which tells the programmer C requires `static` or `extern` when they wrote `extern`; fixing this removes that spurious second diagnostic."
---

# A block-scope `extern` is read as an expression

## Measured — HEAD, x86-64, 2026-09-19, gcc as the oracle

| source (inside a function body) | gcc | pxx |
| --- | --- | --- |
| `extern int g;` | prints `7` | `error: undeclared identifier 'extern' used as value` |
| `extern int puts(const char *);` | prints `hi` | same error |
| `extern __thread int g;` | prints `7` | same error, **plus** a spurious thread-local warning |

All three are legal C. The block-scope `extern` function declaration in row two
is not an exotic — it is a common way to name one symbol without pulling in a
header.

## Cause

`ParseCStatementAST`'s block-scope storage-class loop accepts
`register|auto|static|__thread|_Thread_local` and **not `extern`**. So `extern`
is never consumed as the start of a declaration; the statement parser falls
through to expression parsing and reports the identifier it could not resolve.
The diagnostic is honest about what the parser was doing and names the wrong
thing entirely as far as the programmer is concerned.

**The code already called this.** The comment above that loop says `extern`

> *is legal at block scope and is not handled today, and adding it is a
> behaviour change this fix has no measurement for*

That was the right call at the time — it was written for a fix about `static`
being dropped, and it declined to widen. **The measurement now exists**, and it
shows the status quo is not "not handled" but "legal C refused, pointing at the
wrong token".

## Not the thread-local seam

Found while working
`bug-c-a-bare-thread-in-a-function-body-is-accepted-and-returns-a-garbage-value`,
and it is worth saying plainly that it is **a different bug**: the plain
`extern int g;` row has no thread storage class anywhere and fails identically.
Anyone fixing this should not scope it to thread-locals.

## Secondary, and it disappears with the fix

On the `extern __thread` shape the parser recovers past the error, reaches
`__thread`, and emits the function-scope thread-local warning — whose text says
C requires such a declaration to be `static` or `extern`, to a programmer who
wrote `extern`. A misleading diagnostic produced by error recovery. It is not
worth special-casing; handling `extern` removes it.

## Positive control

A fixture must assert the plain `extern int g;` row **and** a row with no
`extern` anywhere that still compiles, or a change that accepted every unknown
identifier as a declaration opener would pass it. Assert the VALUE (`7`, `hi`),
not merely that the compile succeeded — an `extern` that parses but binds to the
wrong symbol compiles cleanly and returns the wrong number.
