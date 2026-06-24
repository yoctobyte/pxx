# Spurious "unterminated conditional directive" on synautil + jedi.inc

- **Type:** bug (lexer / conditional-directive nesting)
- **Status:** urgent (Track A)
- **Owner:** — (**Track A** — `compiler/**`)
- **Opened:** 2026-06-24
- **Found-by:** [[feature-synapse-compile-check]] — blocks the synautil/synaip/
  asn1util/synachar leaf set after the unixutil/Unix/BaseUnix shims landed.

## Symptom

Compiling Synapse's `synautil.pas` (valid FPC code) with `--mimic-fpc` fails at
the **lex phase** with no source location:

```
pascal26:2449: error: unterminated conditional directive ()
```

The conditional-directive stack PXX maintains while lexing reaches EOF still
open, even though the file's `{$ifdef}`/`{$ifndef}` and `{$endif}` are balanced
(47 openers / 47 closers by raw count, and it is real FPC-accepted source).

## Repro

```sh
PXX=./stable_linux_amd64/default/pinned
printf 'program p; uses synautil; begin end.' > external/synapse/.pxx_su.pas
$PXX --mimic-fpc -Fulib/rtl -Fuexternal/synapse external/synapse/.pxx_su.pas /tmp/o
# => pascal26:2449: error: unterminated conditional directive ()
```
(`lib/rtl` supplies the unixutil/unix/baseunix/dynlibs shims so the `uses` clause
resolves; the directive error is independent of them.)

## What is and isn't the trigger (narrowing done)

Three-way isolation points at an **interaction** between `jedi.inc`'s define set
and `synautil`'s conditional branches, not either alone:

- **`jedi.inc` alone** under `--mimic-fpc` → balances fine
  (`{$I jedi.inc}` + trivial program compiles).
- **`synautil` with the `{$I jedi.inc}` line removed** (defines supplied via
  `--mimic-fpc` only) → directive phase is fine; proceeds to the next real gap
  (`undefined variable (StrLCopy)`).
- **`synautil` *with* `jedi.inc`** → spurious "unterminated".

So a symbol `jedi.inc` defines activates a `synautil` conditional branch whose
directives PXX mis-pairs. It is **not** a single-define flip: re-adding any one
of `UNICODE/NEXTGEN/CIL/DELPHIX_SEATTLE_UP/VER100/COMPILER15_UP/MSWINDOWS/POSIX/
OS2/DELPHI/BCB/BDS2006_UP` to the no-jedi compile does **not** reproduce it — it
needs jedi's full define set.

Ruled out as the cause (each tested in isolation, all handled correctly):
- Labeled `{$ELSE FPC}` / `{$ENDIF OS2}` directives, even nested inside skipped
  branches.
- Inline `{$IFDEF X}...{$ENDIF}` embedded mid-expression
  (`synautil.pas:672/2191/2192`).

Likely area: the conditional-skip lexer mis-tracking nesting depth on some
directive **inside an inactive branch** that becomes reachable only under jedi's
defines (candidate: a `{$ifdef}` opener in a skipped region whose matching
`{$endif}` is on a labeled/peculiar line, or a directive form consumed without
incrementing/decrementing the stack while skipping). Bisecting by source
position from outside is confounded because the "unterminated" check is a global
lex-phase EOF check reported only after the `uses` clause parses — Track A can
instrument the conditional stack directly far faster.

## Done when

- `synautil.pas` (and the leaf set synaip/asn1util/synachar that pull it) gets
  past the conditional phase under `--mimic-fpc`, stopping only on genuine RTL
  gaps (`StrLCopy` etc.), not a directive error.
- A focused regression (reduced from synautil, or the synautil compile itself)
  lands under `make test`.
- Self-host fixedpoint byte-identical; `make stabilize` + `make pin` so Track B
  can re-probe ([[feature-synapse-compile-check]]).
