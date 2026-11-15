---
slug: bug-crtl-setenv-and-putenv-did-not-reach-an-execd-child
track: C
prio: 70
type: bug
status: done
created: 2026-11-15
found-by: pixx-cc, busybox udhcpc on Linux (its script ran without interface/ip/router, so DHCP never configured an address)
tags: [crtl, environment, exec, silent]
blocked-by: []
summary: "setenv/putenv/unsetenv/clearenv edited crtl's private 16K environment buffer, which getenv reads, but exec* passed `environ`, which still pointed at the startup envp: every write was lost at the exec (gcc: child A=putenv B=setenv; pxx: A= B=). stdlib.c's own comment said whoever added a spawn surface must pass this buffer; exec* was added and that was missed. Every write now ends in pxx_env_publish, which points `environ` at the buffer's live records, so exec* and a program walking `environ` both see them. An environment the load could not fit (over 16K) is passed on from the startup envp unchanged, so a write never shrinks it for the child. Not unified with the Pascal RTL's sysutils EnvVars (decide-env-write-side option 3). Test: c_envx (test/c_env_exec.c: execl, execvp, unsetenv of an inherited var, clearenv, a 20000-byte BIG; expected = gcc's output)."
---
