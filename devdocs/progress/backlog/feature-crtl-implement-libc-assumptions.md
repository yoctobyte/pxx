---
prio: 45  # auto
---

# crtl: implement the libc assumptions real-world C leans on

- **Type:** feature (libraries) — Track B (`lib/crtl`).
- **Status:** backlog, ongoing collector — 2026-07-06.
- **Premise (user, 2026-07-06):** gcc has its own libc; we have our own
  (`lib/crtl`, libc-free). Real C leans on a *waspnest of libc assumptions* —
  headers, macros, feature-test knobs, struct layouts, function contracts. Bring
  our crtl up to those assumptions incrementally, driven by what real projects
  actually touch. Don't chase completeness for its own sake — implement what the
  corpus (zlib → tcc → …) demands, one landed piece at a time.

## Why a standing ticket
Each real-world bring-up ([[feature-c-corpus-zlib]], tcc next) surfaces a fresh
batch of "libc assumed X" gaps. Rather than a ticket per tiny gap, collect them
here; split a dedicated ticket out only when a gap is large or blocks a whole
project. Distinguish: a **compiler/parser** gap is Track C (own ticket); a
**library surface** gap (missing header symbol, wrong macro, absent function) is
this ticket / Track B.

## Known / expected assumption classes (fill in as found)
- Header symbols declared-but-unimplemented (functions real code calls).
- Feature-test macros & config (`STDC`, `_LARGEFILE64_SOURCE`, `Z_HAVE_UNISTD_H`
  style probes) that gate which code path a project compiles.
- Struct layouts C code reaches into (stat, FILE internals, off_t width).
- `<limits.h>` / `<stdint.h>` / `<inttypes.h>` completeness (widths, INT*_MAX,
  format-length macros).
- errno values + names; `<ctype.h>` locale assumptions; math edge functions.
- (zlib specifically will want: correct `<unistd.h>`/`<fcntl.h>` for gzio file
  I/O, `off_t`/`lseek`, and whatever the gzgetc fast-path macro assumes.)

## How to work it
Bring up a real project → when it fails on a *library* symbol/assumption (not a
parser bug), add the concrete gap here with the project + call site, implement
the smallest crtl piece that satisfies it, land green (`make lib-test`), tick it
off. Keep gcc's libc as the oracle for behaviour.

## Gate
Per-item: the crtl addition compiles + the consuming project advances; `make
lib-test` stays green. Ongoing ticket — never "done", pruned as the corpus grows.
