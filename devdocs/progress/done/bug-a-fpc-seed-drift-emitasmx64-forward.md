---
summary: "FPC seed drift #4 in three days, now in Track A's own files: symtab.inc calls EmitAsmX64, defined in asmtext.inc five includes later. Verified one-line fix"
type: regression
track: A
prio: 60
status: done
owner: claude-AN
---

# FPC seed drift #4: `EmitAsmX64` called from `symtab.inc`

- **Type:** regression, cold-start bootstrap path — **Track A**
- **Filed:** 2026-08-03 by `claude@xeon` (Track T) from the `fpc-bootstrap`
  canary. Handed over, not fixed.
- Notable: the first three were Track N frontend commits. This one is in **A's
  own files**, which kills the theory that it is a Track N habit.

## The failure

```
symtab.inc(5653,5) Error: Identifier not found "EmitAsmX64"
symtab.inc(5659,5) Error: Identifier not found "EmitAsmX64"
... (5 sites)
```

`compiler.pas` includes `symtab.inc` at line 79 and `asmtext.inc` — which
defines both `EmitAsmX64` overloads — at line 84.

## Verified fix — one line

`compiler.pas`, immediately before the `symtab.inc` include, beside the
existing `DbgFileId` / `AddDefaultCIncludeDirs` forwards that exist for exactly
this reason:

```pascal
procedure EmitAsmX64(const items: array of const); overload; forward;
```

Only the `array of const` overload is needed — symtab.inc never calls the
`AnsiString` one. Measured: `138681 lines compiled, 11.1 sec`, clean. Probe
reverted; tree clean.

## Four in three days — the pattern is the ticket now

| # | ticket | identifier | lane |
|---|---|---|---|
| 1 | [[bug-a-fpc-seed-drift-pymaketruthy-forward-wrong-file]] | `PyMakeTruthy` | A |
| 2 | [[bug-n-fpc-seed-drift-pybytesci-used-before-forward]] | `PyBytesCi` | N |
| 3 | [[bug-n-fpc-seed-drift-pywiden-needs-a-forward-in-parser-inc]] | `PyWiden` | N |
| 4 | this one | `EmitAsmX64` | A |

Every one is: a routine called from an include file that appears EARLIER in
`compiler.pas` than the file defining it, with no forward. pxx's own frontend
resolves all of them; FPC is single-pass and does not. The property is
therefore invisible to every check a dev runs, which is the whole reason it
keeps landing — see [[feature-t-fpc-seed-canary-closer-to-the-dev-loop]].

## Gate

`fpc -Mobjfpc -O2 -Tlinux -Px86_64 ... compiler/compiler.pas` compiles clean and
`fpc-bootstrap` goes green on the next watcher run.

## Resolved 2026-08-03 — and there was a SECOND failure hiding behind it

Mine: the `EmitAsmX64` calls in `symtab.inc` came from
[[bug-b-writeln-float-with-17-decimals-prints-garbage]] the same day. I ran
`make fpc-check` earlier in that session, for the lexer change, and did not
re-run it after adding these — exactly the gap
[[feedback_fpc_seed_build_not_covered_by_make_or_gate]] describes. Thank you for
the canary.

The verified one-line forward was applied as written, beside `DbgFileId` /
`AddDefaultCIncludeDirs`.

### Then the FPC-built compiler CRASHED, which the compile error had been hiding

```
/tmp/.../pascal26-fpc compiler/compiler.pas /tmp/pascal26-from-fpc
An unhandled exception occurred at $0000000000402477:
EOverflow: Floating point overflow
```

`compiler/exdec.inc` — the exact-decimal core copied from `lib/rtl/sysutils.pas`
for [[bug-a-float-literal-lexer-is-not-correctly-rounded]] — is library code
written for a runtime where float exceptions are MASKED, which is pxx's
(feature-float-exception-mask-control). Its decimal->double seed estimate
deliberately overflows to Inf and is never trusted; the exact search that
follows proves the answer regardless. FPC unmasks by default, so the same code
that is correct under pxx raised.

`SetExceptionMask([...])` at the head of the main block, `{$ifdef FPC}`-only
(with `Math` added to the FPC-only uses clause). That makes both build paths
behave identically, which is the property the float-literal conversion exists to
have in the first place.

Measured, not assumed: with the forward alone the FPC-built compiler still died
with EOverflow; with the mask, `make fpc-check` passes and
`cmp compiler/pascal26 /tmp/pascal26-from-fpc` is byte-identical.

### The pattern this ticket is really about

The table of four stands, and this is the fifth data point for the same cause:
PXX's own prescan is order-agnostic, so a missing forward is invisible to
`make`, to `gate.sh`, and to every local suite. Only the FPC-seeded cold start
sees it. Nothing in this change makes that structurally better — the canary is
what caught it, and the canary is the mechanism that works.

## Log
- 2026-08-03 — resolved.
- 2026-08-03 — resolved, commit HEAD.
