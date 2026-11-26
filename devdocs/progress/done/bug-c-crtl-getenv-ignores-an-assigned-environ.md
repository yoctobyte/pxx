---
slug: bug-c-crtl-getenv-ignores-an-assigned-environ
track: C
type: bug
status: done
owner: claude-dupwt
created: 2026-11-26
found-by: GNU make 4.4.1's own suite (features/errors, features/targetvars, misc/general4) on the pxx build, Nodisx
summary: "crtl's getenv read a private copy taken at the first call (from /proc/self/environ), so a program that ASSIGNS environ was not seen: GNU make sets `environ = envp` in the child and calls execvp, which reads PATH through getenv, so a makefile's `PATH := .` was ignored and the parent's PATH searched. glibc's getenv reads environ. Now the copy follows environ: the first load uses environ when it is set (/proc only before the runtime fills it), and any later call whose environ differs from the one the copy agreed with (the load, or setenv's publish) reloads from it. Test row c_wrerrenv26."
---

Fixed in lib/crtl/src/stdlib.c (`pxx_env_seen`, `pxx_env_from_environ`).
Edge kept: a setenv made in a file-scope initializer, before the runtime
fills environ, is lost when the runtime then assigns environ. It was
already lost to exec* in that case.
