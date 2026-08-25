---
track: P
prio: 65
type: bug
blocked-by: []
status: backlog
owner: ""
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
