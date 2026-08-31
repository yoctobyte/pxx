---
summary: "nilpy: os.system / subprocess-shaped process spawning over the RTL's libc-free execve"
type: feature
track: N
prio: 60
---

# nilpy: spawn a process (open a file in the desktop's viewer)

- **Type:** feature (Nil-Python frontend, stdlib surface) — **Track N**
- **Status:** backlog
- **Opened:** 2026-07-26 — needed by songformatter's Preview PDF action
  ([[feature-demo-songformatter-pxx-target]]).

## The RTL side already exists

`ExecutePipeline` in `lib/rtl/sysutils.pas` spawns libc-free via raw
`sys_vfork`/`sys_execve`/`sys_pipe2`/`sys_wait4` (ticket
`feature-sys-process-spawning`, done — host green). So this is only a nilpy
binding, NOT a Track A runtime gap.

## Surface

Minimum for the consumer: `os.system(cmd)` and `subprocess.Popen([...])` with
`subprocess.DEVNULL` for stdout/stderr — songformatter hands a PDF to
`xdg-open`/`open`/`os.startfile` and does not read the child's output. `os.startfile`
is Windows-only in CPython and can wait for the PE port.

## Interim

songformatter can carry a stub that writes the PDF and reports the path instead of
launching a viewer, so the app compiles before this lands; the on-canvas preview
does not depend on it.

## Gate

`make test-nilpy` green with a `.npy` case spawning a child and observing its
effect, + `--tier quick` + self-host byte-identical.
