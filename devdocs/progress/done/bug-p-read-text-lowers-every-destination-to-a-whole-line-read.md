---
track: P
prio: 65
type: bug
blocked-by: []
status: done
owner: frank1-P-read
summary: "`ParseTextReadRest` lowers BOTH the numeric and the string destination of `read[ln](f, ...)` to `TextReadLn`, which eats a whole line and its terminator. So `readln(t, n, m)` on '42 3' gives 0 0, `read(f, s)` is indistinguishable from `readln(f, s)`, and `read(f,s); readln(f)` skips every other line. The RTL half landed (TextReadNumTok / TextReadStrTo, cursor-preserving, FPC-measured); this is the frontend half, and the whole lowering is already proven against FPC."
---

# `read(Text, ...)` lowers every destination to a whole-line read

The frontend half of
`bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line`. Track B landed
the RTL primitives and **proved the replacement lowering against FPC 3.2.2 by
hand-writing the emitted sequence** — 17 shapes, zero divergences — so this is a
mechanical edit to one function with the answer already known.

`ParseTextReadRest` is in `compiler/pasparser_stmt.inc` (~line 2940), which is
Track P's carved-out file. No shared internals are involved: no new AST node, no
IR op, no symtab field, no backend. Two RTL procs get called that were not called
before.

## The symptom

FPC 3.2.2 vs pxx at `9170a6193`, measured, every failing row a **silent** wrong
value:

| file | statement | FPC | pxx |
| --- | --- | --- | --- |
| `42 3` | `readln(t, n, m)` | 42 3 | **0 0** |
| `42 3` | `read(t,n); read(t,m)` | 42 3 | **0 0** |
| `42  ` | `readln(t, n)` | 42 | **0** |
| `1 2`/`3 4`/`5 6` | `readln(t,n,m)` loop | works | **all zero** |
| `42 abc` | `read(t,n); readln(t,s)` | `42[ abc]` | **`0[]`** |
| `L1`/`L2` | `read(f,s)` twice | `L1`, `` | `L1`, **`L2`** |
| `L1`/`L2` | `read(f,s); readln(f); read(f,s)` | `L1`,`L2` | `L1`, **``** |

Reading a table of numbers — the commonest reason to open a text file at all —
returns zeros with no error, no exception and no diagnostic.

## Root cause

Both the numeric and the string arm call `TextReadLn`, which by definition
consumes the line AND its terminator:

```pascal
{ numeric arm }
TextReadLn(f, tmp);        { the WHOLE line }
Val(tmp, dest, code);      { '42 3' and '42  ' both fail; code is discarded }

{ string arm }
callNode := GenMakeCall6(procRead, ...)   { procRead = TextReadLn }
```

`Val` wants the string to be the number and nothing else, so a second token or a
trailing blank makes it fail, and the discarded failure leaves the destination at
whatever it held — 0 for a fresh variable. The string arm has the same shortcut
with a different face: `read` and `readln` lower identically, so `read(f, s)`
swallows the terminator FPC leaves parked.

The two are one defect. Each was a fix for something worse (the numeric dest slot
used to be handed to `TextReadLn` as an AnsiString and got corrupted), not a
design.

## The RTL half — DONE, and it is on `dev`

`lib/rtl/textfile.pas` now exports two cursor-preserving readers, built on a
shared `TFNextByte` / `TFPushBack` over the one-byte lookahead `Eof` already
fills. Both are measured against FPC 3.2.2 **including the cursor** — the oracle
drained the rest of the file character by character after each read — and covered
by `test/lib_textreadnumtok.pas` in `make lib-test`:

- `TextReadNumTok(var f: Text; var s: AnsiString)` — skip whitespace *including
  line breaks*, take the whitespace-delimited token, push the delimiter back.
- `TextReadStrTo(var f: Text; var s: AnsiString)` — up to but NOT over the
  terminator; at an eoln returns `''` without advancing.
- `TextReadLn` keeps its meaning (line + terminator) and stays `readln`'s skip.

## The frontend half — what to change

In `ParseTextReadRest`:

1. **Numeric arm:** `procRead` → `FindProc('TextReadNumTok')` for the hidden-tmp
   read. Everything after it (the `ValFloat`/`ValQWord`/`Val` dispatch, the
   `Int64` temp for a narrow ordinal) is unchanged and correct.
2. **String arm:** call `TextReadStrTo` instead of `TextReadLn`.
3. **The trailing skip stops being a special case.** Today it fires only when the
   last destination was the char arm, because "the string and numeric arms
   already consume the terminator (TextReadLn eats it)". Once all three arms are
   cursor-preserving that is false for all of them alike, so `isLn` emits the
   `TextReadLn(f, junk)` skip after **every** destination kind — and
   `trLastWasChar` is deleted outright. That collapse is the tell that this is a
   root-cause fix and not three microfixes
   (`devdocs/dev/normalise-dont-special-case.md`). `readln(f)` with no
   destinations keeps working: it is now just the blanket skip.

`readln`'s string arm is `TextReadStrTo` + skip, not `TextReadLn` — measured
equal to FPC on CRLF input too (`TextReadStrTo` stops at the CR, the skip's
`TextReadLn` steps over CR+LF).

## Proof the design is right

Written out by hand, exactly as the fixed parser would emit it, and diffed
against FPC's real `read`/`readln` on the same files. 17/17 identical:

```
readln-two-one-line  readln-trailing-sp  read-two-then-str    readln-then-readln
readln-three         readln-cross-line   readln-str-twice     readln-str-crlf
read-str-twice       read-str-readln-str readln-char-twice    read-char-twice
readln-bare-then-str read-num-eoln       read-num-eoln2       readln-table
readln-real
```

Note `read-num-eoln` / `read-num-eoln2`: after `read(t, n)` on `'42 3'` FPC says
`Eoln` is FALSE and on `'42'#10'x'` it says TRUE. Those two rows are the ones a
value-only test cannot see, and they are what the whole change is about.

## Known divergence, deliberate

FPC scans a numeric token to the next **whitespace**, not to the first character
a number cannot use: `'42,3'` is a *runtime error 106* there, not the `42` a
stop-at-any-non-digit reader would give. Ours takes the same token, `Val` fails,
and the destination stays 0 — a divergence in the ERROR path only. By the
project's "we seek language compliance, not error-handling compliance" rule that
silent 0 stays until I/O checking covers it; every VALID numeric input agrees.

## Gate

Track P: `make compiler/pascal26` (the self-host fixedpoint) + the repro above.
`test/test_read_text_char.pas` and `test/lib_textreadchar.pas` are the existing
char-arm regressions and must stay green — the char arm itself does not change.
Worth adding a `test/` case for the numeric table read once the lowering lands,
since `test/lib_textreadnumtok.pas` covers only the primitives.

## 2026-08-25 — landed (Track P, `frank1-P-read`)

The edit is exactly what the B write-up predicted, in `ParseTextReadRest`
(`compiler/pasparser_stmt.inc`): the numeric arm's hidden-tmp read is
`TextReadNumTok` instead of `TextReadLn`, the string arm is `TextReadStrTo`,
and `procRead` (`TextReadLn`) is now used for one thing only — `readln`'s
end-of-line skip.

**`trLastWasChar` is gone, not adjusted.** The variable, its three assignments
and the `isLn and (trLastWasChar or (headSeq = -1))` guard were all deleted; the
skip is a bare `if isLn then`. Nothing was added to replace it, so the change is
a net removal of a case — the collapse the ticket predicted actually happened,
and the three arms now have the same shape. `readln(f)` with no destinations
still works: it is the skip on its own, which is what `headSeq = -1` used to
special-case.

### Verified against FPC 3.2.2, cursor included

The oracle is the B worker's method, re-run here rather than trusted: read a
value, then drain the rest of the file one character at a time with control
bytes rendered `<LF>` / `<CR>` / `<SP>`, so the cursor is *visible*. 31 probe
programs compiled by both `fpc -Mobjfpc` and the built compiler, stdout diffed:

* **new compiler: 0 divergences over 31 probes.**
* **pinned (pre-fix) compiler: 14 divergences over the same first 24** — so the
  probe has teeth; it is not agreeing because it is blind.

Both `Eoln`-after-a-numeric-read rows are in there (`'42 3'` → FALSE, `'42'#10'x'`
→ TRUE) and both were wrong before. So were the eight `rest=[...]` cursor rows.
Also probed, because `lib/rtl/configparser.pas` and `lib/rtl/pathlib.pas` drive
`while not Eof(f) do readln(f, s)`: an Eof loop over a file with and without a
trailing newline, an empty file, CRLF input, readln past EOF, and a
whitespace-only line — all identical to FPC, which is the equivalence
`TextReadStrTo` + skip must have with the old single `TextReadLn` for `readln`.

The B worker's two corrections both held: `'42,3'` scans to whitespace (FPC's
runtime error 106, our silent 0 — the stated error-path divergence), and
`'42  '` leaves **two** blanks, asserted as such.

### Regression test

`test/test_read_text_value_cursor.pas`, wired into `make test`'s core sweep next
to the existing char test. 55 assertions over 22 shapes, **every one asserting
value AND cursor**, and every expectation is FPC's own output for that same
program — the file compiles under `fpc -Mobjfpc` unchanged and prints
`total ok 55 / 55` there too. Against the pre-fix pinned compiler it prints
`total ok 25 / 55` (30 failures), which is the measure of what the fix bought.

`test/test_read_text_char.pas` stays green at 25/25 — the char arm did not
change, it only stopped being the special case.

### Gate

`make compiler/pascal26` converged (self-host fixedpoint, byte-identical);
`tools/gate.sh quick` GREEN (self-host 172s + `testmgr --tier quick` + FPC seed
canary). No pin needed for this — nothing here changes the stable binary's
contract; a pin would only be to hand Track B a compiler that already emits the
new lowering.

### Unblocks

`bug-b-read-of-a-number-from-a-text-file-reads-the-whole-line` (Track B, prio 88)
is now resolvable — its entire symptom table is covered by the probe run above.
Left for its own lane to close.

### Filed en route

None in the compiler. One RTL gap noticed while writing the test and *not*
chased: `lib/rtl/sysutils.pas` exports `FloatToStrF(value: Double; precision:
Integer)`, not FPC's `FloatToStrF(value, format, precision, digits)`, so the
FPC-shaped call is a compile error. Track B/F territory, unrelated to this
ticket, and the test uses `Round(d * 100)` instead.

## Log
- 2026-08-25 — resolved, commit e6064f14b.
