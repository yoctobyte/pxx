---
slug: bug-c-a-block-scope-extern-declaration-is-parsed-as-an-expression-and-refused
track: C
prio: 60
type: bug
status: done
created: 2026-09-19
found-by: frankS
tags: [c-frontend, storage-class]
blocked-by: []
summary: "FIXED 2026-09-19. `extern` INSIDE A FUNCTION BODY was not a declaration opener: the block-scope storage-class loop in ParseCStatementAST did not accept it, so the statement parser fell through to expression parsing and legal C was refused with `undeclared identifier \'extern\' used as value` — a diagnostic naming the wrong token. Fixed by accepting `extern` in that loop AND DISCARDING the declaration, which is the whole of the fix: it declares external linkage and defines nothing, so allocating no storage is what makes the name resolve outward to the file-scope symbol. THE ONE-LINE VERSION IS A TRAP AND IT WAS MEASURED, NOT REASONED ABOUT: adding `extern` to the loop set alone hands the declaration to ParseCLocalDeclAST, which allocates a stack slot, so the name SHADOWS the symbol it was written to reach — `int g = 7;` at file scope with `extern int g;` in the body printed -80651752 against gcc\'s 7, trading a loud refusal for a silent wrong value. That variant was built and run against the fixture: it passes a compiles-now row and fires three of the five. Four shapes now match gcc exactly (`extern int g;`, multiple declarators, a block-scope extern FUNCTION declaration, `extern __thread int g;`), and the spurious second diagnostic is gone — error recovery used to reach `__thread` after refusing `extern` and tell a programmer who wrote `extern` that C requires `static` or `extern`. WHAT IS NOT FIXED, ASSERTED SO IT CANNOT DEGRADE SILENTLY: the name is not REGISTERED, because pass 1 does not descend into function bodies, so a symbol declared `extern` in a body and nowhere else in the TU still reports `undeclared identifier <name>` at its first use — pointing at the NAME rather than at `extern`, which is honest and still not C. A Makefile row pins that so it cannot become a silent fold-to-zero. The three shapes real code writes are the ones that now work."
owner: frankS
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

## Population — measured, and the number is NOT the argument

Counted 2026-09-19, and both instruments were wrong in a way worth recording:

- **`grep` for an indented `extern` OVER-COUNTS.** It matches file-scope
  declarations indented inside a preprocessor block, which is most of what it
  finds: sqlite `shell.c:220` (`extern int isatty(int);` inside a `#else`) and
  `sqlite3.c:15039` (`extern const int sqlite3one;` inside `#ifdef
  SQLITE_AMALGAMATION`/`#else`) are both **file-scope**. Raw counts of 2 / 3 / 19
  for busybox / zlib / sqlite are therefore upper bounds, not the population.
- **Using the COMPILER as the instrument did not run.** Compiling
  `sqlite3.c` to count this error answered **0** — and the compile had died at
  **line 52** on `stray token at top level: '__BEGIN_DECLS'`
  (`bug-c-sqlite-with-threadsafe-stops-at-a-stray-BEGIN_DECLS`). A zero from a
  compile that never reached the construct. Caught by asserting the
  precondition; quoted without it, it would have read as evidence of absence.

What survives: **busybox has exactly two genuine block-scope instances**
(`shell/ash.c:14787` inside `#ifdef GPROF`, `libbb/appletlib.c:1043` inside
`#if 0`) and **both are preprocessed out of every build we make**. So busybox's
GREEN at 394 applets says nothing whatever about this construct — the lines
never reach the parser. That is not reassurance, it is an instrument that is
silent rather than passing.

**The frequency is not why this should be fixed, and the ticket should not be
read as claiming it is.** The fix is strictly ADDITIVE — it accepts legal C we
currently reject — so unlike a refusal it carries no risk of breaking a working
program and needs no population to justify it. Frequency bears only on the
prio, and on the evidence here it is thin: `p60` was set on the strength of
"legal C, refused, with a diagnostic that names the wrong token", which stands
on its own. Anyone re-ranking should use that argument, not a corpus count.

## Positive control

A fixture must assert the plain `extern int g;` row **and** a row with no
`extern` anywhere that still compiles, or a change that accepted every unknown
identifier as a declaration opener would pass it. Assert the VALUE (`7`, `hi`),
not merely that the compile succeeded — an `extern` that parses but binds to the
wrong symbol compiles cleanly and returns the wrong number.

## Resolution — 2026-09-19

**Accept `extern` in the block-scope storage-class loop, then DISCARD the
declaration.** Both halves are the fix and the second is the one that matters.

`extern T n;` declares external linkage and **defines nothing** (C 6.7.1,
6.2.2). The right amount of storage to allocate is therefore none, and the
right binding for the name is whatever the file scope already has — so
discarding the declaration produces both at once: no local exists, and every
later reference in the body resolves outward to the symbol the programmer wrote
`extern` to reach. The skip is depth-aware over parens, brackets and braces so a
declarator carrying its own semicolons cannot cut it short.

### The obvious fix is a trap, and this was measured before it was believed

Adding `extern` to the loop set **and stopping there** lets the declaration fall
into the ordinary local-declaration arm, which allocates a stack slot. The name
then shadows the file-scope object:

| | gcc | pxx, naive fix |
| --- | --- | --- |
| `int g = 7;` + `extern int g;` in a body | `7` | **-80651752** |

That is **strictly worse than the bug it fixes** — a loud refusal replaced by a
silent wrong value, which is the class this tree spends the most time on. The
variant was built and run against the committed fixture rather than argued
about: it **passes** a "compiles now" row and **fires three of the five** rows.

### Why the fixture writes through the name instead of reading it

On that naive build, row 1 read **0**, not garbage. A shadowing local is
uninitialised, so a read-only assertion is a coin flip and can certify the
broken compiler. Every row therefore **writes through the extern name and reads
back through a function with no `extern` in it** — a write that the second route
cannot see is the thing a local physically cannot fake.

### Measured against gcc, same sources, 2026-09-19

| source (inside a function body) | gcc | pxx before | pxx now |
| --- | --- | --- | --- |
| `extern int g;` | `7` | refused | `7` |
| `extern int a, b;` | binds both | refused | binds both |
| `extern int add2(int,int);`, callee defined below `main` | `5` | refused | `5` |
| `extern __thread int g;` | `7` | refused **+ spurious warning** | `7`, silent |

### One divergence, chosen

gcc **rejects** `__thread extern int g;` (`'__thread' before 'extern'`) while
accepting `extern __thread int g;` — its `__thread` extension constrains an
order C11's `_Thread_local` does not. Reading `extern` inside the loop means we
take the discard arm for both arrangements, so **we accept the spelling gcc
refuses**. A declaration nobody writes on purpose, no wrong value anywhere;
recorded in the code beside the flag so the next reader knows it was measured
and chosen rather than missed. *The first version of that comment asserted the
order was free — gcc refuted it within the hour, and the comment was corrected
before it landed.*

### What is NOT fixed, and it has a row of its own

The name is **not registered**. Pass 1 does not descend into function bodies, so
a symbol declared `extern` in a body and **nowhere else in the TU** stays
unknown and its first use reports `undeclared identifier <name>`. That points at
the name instead of at `extern`, which is the honest diagnostic and still not C
semantics. Registering it is a two-pass change and not this one. A Makefile row
asserts that failure mode so it cannot quietly become a fold-to-zero.

### Rows added (`test-core`)

`test/c_block_scope_extern_binds_the_file_scope_symbol.c` (5 rows, asserts
binding — matches gcc byte for byte), plus three controls: an unknown identifier
in statement position must **still** be refused (a change making any leading
identifier a declaration opener passes everything else and destroys the
diagnostic for every typo in the language); the extern-only name must report at
the NAME; and `extern __thread` must compile, return 7, and **not** warn.

## Log
- 2026-09-19 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
