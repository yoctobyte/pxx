# C: preprocessor `defined(...)` expression leaks into sqlite token stream

- **Type:** bug (C frontend / preprocessor conditionals) — Track C
- **Status:** backlog
- **Owner:** unassigned
- **Found / Opened:** 2026-06-27, M5 sqlite bring-up
  ([[feature-c-desktop-lua-sqlite-path]]), after the CRTL `fsync`/`sysconf`
  header fix.

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

## Acceptance

- sqlite advances past the `pLockingStyle` / `posixIoMethods defined` wall.
- A focused preprocessor regression covers `#if X && defined(Y)` and
  `#if !defined(Y)` forms.
