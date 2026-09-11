---
slug: feature-b-rtl-has-no-termio-unit-and-no-isatty
title: "`termio` has no `IsATTY`, and it is the FPC-compiler march's comptty wall"
track: B
prio: 40
type: feature
status: done
owner: frankH
found-by: frankH
created: 2026-09-11
tags: [rtl, unix, tty, fpc-corpus]
blocked-by: []
summary: "THE SLUG IS WRONG AND IS KEPT ONLY SO EXISTING CITATIONS RESOLVE: `lib/rtl/termio.pas` DOES exist -- 19 lines, three ioctl constants, added for synapse with its own comment saying `grow only as a consumer needs it`. What was missing is `IsATTY`. FPC's `comptty.pas:66` calls `termio.IsATTY(t)=1` inside `LinuxIsATTY`, so the march stopped with `undefined variable (IsATTY)`. TWO units reported it -- rgobj and aasmbase -- and they are ONE wall: both diagnostics are `comptty.pas:66` reached through a shared dependency, so it must not be ranked as two. fpc declares two overloads, `IsATTY(Handle: cint): cint` and `IsATTY(var f: text): cint` (rtl/unix/termiosh.inc:31-32) -- cint, NOT Boolean, because the call site that motivated this compares the result against 1."
---

# The wall

```
pascal26:66: error: undefined variable (IsATTY)
  in: /home/neo/src/fpc-trunk/compiler/comptty.pas
  near: begin LinuxIsATTY := termio . IsATTY >>> ( t )
```

Reached 2026-09-11 by [[feature-b-sysutils-has-no-executeprocess-and-no-texecuteflags]]
clearing `cfileutl.pas:136 unknown type: TExecuteFlags`.

## The slug and title were wrong, and how

Filed from a `grep -rn IsATTY lib/rtl/` that came back empty. That grep is
correct and the sentence written from it was not: it establishes that **the
FUNCTION** is absent and says nothing about **the UNIT**, which has existed
since the synapse work. The title asserted the wider of the two. This is the
quantifier failure CLAUDE.md names — the checked half lending its credibility
to the unchecked half — and it was caught one command later, by looking at the
file before editing it rather than after.

The slug stays because `70220c6f4`, the resolved ExecuteProcess ticket and
`umbrella-pxx-compiles-fpc-itself` all cite it; renaming would strand those for
no gain on a ticket that is being closed in the same breath.

## It is ONE wall, not two

rgobj and aasmbase both report it and both report `comptty.pas:66`. Same line,
same file, reached through a shared dependency.

## Resolved 2026-09-11 (frankH, Track B)

`lib/rtl/termio.pas` grows both of fpc's overloads, returning `Integer` to match
`cint`. Neither holds any knowledge of its own: both call `__pxx_isatty` in
`pxxcio.pas`, which IS the TCGETS ioctl. Reusing it rather than reimplementing
is the point — a second copy of "what makes something a terminal" is how the two
answers drift apart, and pxxcio's comment already carries the reasoning.

### Corpus

rgobj and aasmbase both move past `comptty.pas:66` and both now stop at
`comphook.pas:251 undefined variable (V_Status)` — the same line as each other
again. **That one is NOT an RTL gap**: `V_Status` is declared inside the corpus
at `globals.pas:149` as `$2000`.

**CORRECTED 2026-09-11, SAME EVENING.** This section first said V_Status was the
already-filed unit-cycle bug. **It is not.** That ticket
(bug-p-a-unit-cycle-closed-through-an-implementation-uses-cannot-see-the-other-interface)
is `status: done` — fixed by d52831ed7 + 6e8a821db, both ancestors of
origin/master — and its shape passes: a minimal A/B cycle prints fpc's 8192.
I matched a SLUG to a symptom without opening the ticket, and wrote the wrong
attribution into two commit messages (d57a1efaa, e1c789fd0) before checking.
The real defect is filed as
[[bug-p-a-units-interface-constants-are-invisible-to-a-second-units-implementation-uses]]
with four reductions that do NOT reproduce it recorded, since those are the
expensive part to rediscover.

### Verification

- **Oracle**: fpc 3.2.2 agrees on every value, through both a pipe and a pty —
  `ptmx=1 devnull=0 closed=0`, and the `Text` overload tracking its arm (`00`
  piped, `11` on a pty).
- **Positive control**: with `lib/rtl/termio.pas` stashed the fixture will not
  compile — `pascal26:46: error: undefined variable (IsATTY)`, rc=1.
- **The fixture opens its OWN descriptors and asserts nothing about stdout.**
  `IsATTY(Output)` is 0 under any capturing harness, and 0 is equally what a
  stub, a failed ioctl and a bad fd return — a row that cannot fail. A pty
  master answers 1 however the test was invoked, so the suite gets a row whose
  expected value is not the failure value.
- **`/dev/null` is the row that earns its place**: a character device that is
  not a terminal. An `fstat`+`S_ISCHR` implementation — the obvious wrong one,
  named in pxxcio's own comment — answers 1 there and would pass every other
  row in the file.

## Log
- 2026-09-11 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit d57a1efaa.
