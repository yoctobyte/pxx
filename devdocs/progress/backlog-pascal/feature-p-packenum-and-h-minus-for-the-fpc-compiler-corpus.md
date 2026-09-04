---
slug: feature-p-packenum-and-h-minus-for-the-fpc-compiler-corpus
track: P
prio: 45
type: feature
blocked-by: []
status: backlog
owner: unassigned
created: 2026-09-04
summary: "{$PACKENUM 1} and {$H-} are accepted and not implemented, and both are in the first nine lines of FPC 3.2.2's fpcdefs.inc — so every unit of the FPC compiler corpus is compiled with 4-byte enums and a longstring default where the source asked for 1-byte enums and shortstrings. Silent until 2026-09-04; the unknown-directive warning is what surfaced them."
---

# The FPC compiler corpus asks for two layouts we do not give it

Found 2026-09-04 by frankS, the first thing the new class-1 directive warning
said out loud (`bug-p-an-unknown-compiler-directive-is-silently-ignored`).
`--mimic-fpc-compiler --target=arm32` now gets past `{$i fpcdefs.inc}` — that
was `feature-p-packrecords-c-directive` — and immediately reports:

```
$ pascal26 --target=arm32 --mimic-fpc-compiler fd.pas
pascal26:3: warning: compiler directive {$H-} is recognised but not implemented …
pascal26:9: warning: compiler directive {$PACKENUM} is recognised but not implemented …
```

`/usr/share/fpcsrc/3.2.2/compiler/fpcdefs.inc`, lines 1-9:

```pascal
{$mode objfpc}
{$asmmode default}
{$H-}
{$goto on}
{$inline on}
{$interfaces corba}

{ This reduces the memory requirements a lot }
{$PACKENUM 1}
```

`fpcdefs.inc` is included by essentially every unit of that compiler, so this is
not one file's opinion — it is the corpus-wide setting, and its own comment says
why it is there.

## Why this is worth ranking above a directive nicety

**`{$PACKENUM 1}` is a record-layout change, not a size preference.** An enum
field inside a record moves every field after it. Any pxx-compiled FPC unit that
exchanges a record with a differently-compiled one — including the shadow-RTL
boundary that `goal-compile-fpc-compiler` depends on — disagrees about where the
fields are, self-consistently, which is the failure shape that
`bug-a-pascal-nilpy-rust-and-zig-over-align-an-8-byte-member-on-i386` took a
mixed link to see.

`{$H-}` is the string default for the whole corpus; ignoring it means every bare
`string` in FPC's sources is a long string where the source said shortstring.
Whether that is a problem for pxx specifically needs measuring — pxx's string
model is not FPC's — and that measurement is half this ticket.

## Not obviously one job

They are filed together because they arrive together and from one include, not
because the fix is shared. Split if the enum half turns out to be the only real
one. Measure before scoping, the way
[[feature-p-packrecords-c-directive]] did: `{$PACKRECORDS C}` turned out to be a
no-op against our existing rule, and this pair may not be.

## Gate

A record with an enum field laid out under `{$PACKENUM 1}` matching the gcc/FPC
oracle for the same declaration, on x86-64 AND a 32-bit target — the pattern in
`test-packrecords-c-gcc-oracle`, whose positive control (a second row whose
answer must DIFFER) is the part to copy. Do not assert only that the directive
is accepted: accepted-and-ignored is the state this ticket reports.

## Related

- [[bug-p-an-unknown-compiler-directive-is-silently-ignored]] — surfaced it; the
  class-1 list is where these two names live.
- [[feature-p-packrecords-c-directive]] — the wall before this one.
- [[goal-compile-fpc-compiler]] / [[feature-mimic-fpc-compiler-define-profile]]
