# C: preprocessor `defined(...)` expression leaks into sqlite token stream

- **Type:** bug (C frontend / preprocessor conditionals) — Track C
- **Status:** done
- **Owner:** Track CA
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the CRTL `fsync`/`sysconf`
  header fix.
- **Closed:** 2026-06-27

## Symptom

After `fsync` and `sysconf(_SC_PAGESIZE)` resolve from `unistd.h`, sqlite
advances to:

```text
Expected: ), but got:  (Kind: 1, Line: 32926)
  near:   pLockingStyle   posixIoMethods >>>   defined
pascal26:32926: error: unexpected token ()
```

Repro command:

```sh
./compiler/pascal26 -Ilibrary_candidates/sqlite library_candidates/sqlite/sqlite3.c /tmp/sqlite3
```

The reported source line is inaccurate after preprocessing. The nearby unix VFS
locking-style region contains preprocessor conditionals such as:

```c
#if SQLITE_ENABLE_LOCKING_STYLE && defined(__APPLE__)
```

The token context suggests a `defined` operator from a preprocessor expression
is not being folded/skipped and is leaking into normal C parsing near
`pLockingStyle` / `posixIoMethods`.

## Likely Shape

Teach the C preprocessor conditional evaluator to handle `defined NAME` and
`defined(NAME)` inside `#if` / `#elif` expressions, including boolean
combinations with `&&`, `||`, and `!`, so disabled platform-specific sqlite
blocks are skipped before the C parser sees their tokens.

## Cause

`defined(...)` evaluation already existed. The real failure was the physical-line
joiner in `CPProcessText`: when it saw a normal C line with unbalanced
parentheses, it kept appending following physical lines, even if the next line
was a preprocessor directive. sqlite's valid shape:

```c
if( pLockingStyle == &posixIoMethods
#if defined(__APPLE__) && SQLITE_ENABLE_LOCKING_STYLE
  || pLockingStyle == &nfsIoMethods
#endif
){
```

was rewritten into one invalid C line containing `#if defined(...)`.

## Fix

Stop continuation joining when the next physical line starts with `#`. Emit the
current C line, process that directive immediately, and let normal conditional
state decide whether following lines are emitted.

## Regression

Added `test/cpreproc_defined_directive_join_b100.c`, wired into
`make test-core`. It covers both the sqlite-style directive inside a continued
expression and `X && defined(Y)` / `!defined(Y)` conditional forms.

## Acceptance

- sqlite advances past the `pLockingStyle` / `posixIoMethods defined` wall.
- b100 covers `#if X && defined(Y)` and `#if !defined(Y)` forms.
