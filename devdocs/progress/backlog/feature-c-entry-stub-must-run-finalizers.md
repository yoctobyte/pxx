---
track: C
prio: 40
type: feature
summary: "The C entry stub is `call main; exit_group(retval)`, so a plain `return` from main skips __pxx_run_finalizers entirely — which is why crtl cannot implement atexit without looking implemented and silently skipping handlers on the commonest exit path"
---

# The C entry stub must run the finalizers, or `atexit` cannot exist

- **Type:** feature — Track C (the C entry stub / `cparser.inc`), with a Track A
  half if the shell itself moves
- **Opened:** 2026-08-09
- **Filed by:** Track B, closing out
  [[feature-b-crtl-last-seven-unimplemented-declarations]]. `atexit` is the last
  declared-but-unimplemented crtl function, and it is the one that cannot be
  finished inside crtl. The ticket says to split it out; this is that split.

## Why crtl cannot do this alone

crtl owns `exit()`, so registering handlers and running them there is easy. It
does **not** own the other exit path: the C entry stub is `call main;
exit_group(retval)`, emitted by the compiler, and a plain `return` from `main`
bypasses crtl entirely.

So a crtl-only `atexit` would run handlers for `exit()` and **silently skip them
for `return`** — for the commonest exit path in C. That is strictly worse than
not having it, because a body-less declaration at least fails loudly at link
(`undefined symbol: atexit`), whereas a half-wired one looks implemented and
produces a plausible wrong result. Which is this project's worst failure class,
so it was deliberately not done.

## The mechanism already exists

`__pxx_run_finalizers` / `EmitFinalizerRunnerBody` (`symtab.inc:5616`,
`cparser.inc:8453`) is the shell every Pascal exit path calls. The C entry stub
does not call it. Wiring it in — so both `return` from `main` and `exit()` run
registered handlers, in LIFO order — is the whole change.

## Then, and only then

Track B adds the handler table in crtl against it, and
`tools/crtl_decl_probe.sh` reaches 0 unimplemented (it is at 1 as of 2026-08-09,
`poll` having landed).

## Gate

`atexit` handlers run in LIFO order for BOTH exit paths — a `return` from `main`
and an explicit `exit()` — matching gcc in `tools/gcc_diff_probe.sh`, plus the
existing C suites staying green (the stub is on every C program's path, so this
is not a narrow change).
