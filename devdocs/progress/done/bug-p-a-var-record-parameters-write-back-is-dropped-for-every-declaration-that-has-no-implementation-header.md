---
slug: bug-p-a-var-record-parameters-write-back-is-dropped-for-every-declaration-that-has-no-implementation-header
track: P
type: bug
prio: 70
status: done
created: 2026-09-06
found-by: frankB
owner: frankB
blocked-by: []
title: "a `var` record parameter is silently passed a copy through an interface method, a `virtual; abstract` method, and a procedural type"
summary: "MEASURED 2026-09-06 at 0a7e1b347, compiler 2e5111165b05, against fpc 3.2.2 -Mobjfpc. `procedure Bump(var r: TBig)` called through an INTERFACE reference, a `virtual; abstract` method, or a PROCEDURAL TYPE writes to a private temp: the callee's assignment is discarded and the caller's record is unchanged. One file, six receivers, same signature -- pxx 301/401/1/1/501/1 where fpc gives 301/401/101/201/501/401. No crash, no diagnostic, a plausible value. CAUSE: ProcParamExplicitByRef (`declared var/out/const at the SOURCE level`, as opposed to promoted to by-ref because the >8-byte record ABI forces it) is written ONLY by pasparser_proc.inc; NONE of the four parameter parsers in pasparser_decl.inc wrote it, and symtab.inc zeroes it per proc, so it reads False rather than stale. A method is declared TWICE -- class or interface body plus implementation header -- and the header goes through ParseSubroutine, which overwrites the row; so the wrong row was written for every method in the language and repaired for everything that has a body. The three spellings with no implementation header are an interface method, `virtual; abstract`, and a procedural type. ir.inc's by-ref arm reads the False and takes the private-copy path meant for an ABI-promoted by-value parameter. SIZE IS IRRELEVANT despite the flag's name: a 4-byte record fails identically, because a `var` parameter is by-ref at any size. FIXED by writing ProcParamExplicitByRef -- and ProcParamIsConst, which two of the four also dropped -- at all four row-writes."
---

# a `var` record parameter's write-back is dropped where no implementation header repairs the row

```pascal
type TBig = record a, b, c: Int64; end;         { 24 bytes }
procedure Bump(var r: TBig);  { body: r.a := r.a + N }
```

One file, one signature, six receivers, `r.a` set to 1 before each call:

| receiver | pxx before | fpc 3.2.2 |
| --- | --- | --- |
| class method with a body | 301 | 301 |
| free routine | 401 | 401 |
| record method | 501 | 501 |
| **interface method** | **1** | 101 |
| **`virtual; abstract`** | **1** | 201 |
| **procedural type** | **1** | 401 |

## Cause

`ProcParamExplicitByRef` answers *"was this parameter declared `var`/`out`/`const`
in the SOURCE, or is it by-ref only because the >8-byte record ABI forces it?"*
`ir.inc`'s by-ref argument arm asks it: **False** means the callee gets a private
copy (correct for an ABI-promoted by-value parameter, and the fix for
`bug-byvalue-record-managed-field-aliases-caller`); **True** means pass the
caller's storage through.

It was written by `pasparser_proc.inc` only (`:1699`, `:2154`, `:2569`).
**None of the four parameter parsers in `pasparser_decl.inc` wrote it**, and
`symtab.inc:11892` zeroes it per proc — so it read False, not stale.

**Why the population is exactly three, and it is structural rather than a
sample:** a method is declared twice, and the implementation header goes through
`ParseSubroutine`, which overwrites the parameter row. Every routine with a body
was repaired. The three declarations with no implementation header are an
interface method, `virtual; abstract`, and a procedural type. Same mechanism as
[[bug-p-an-interface-dispatched-call-passing-a-named-dynamic-array-segfaults]],
one column over.

## The row that was written as a control and became a finding

A 4-byte record was added as a row that *could not fail* — no ABI promotion, so
surely the column is never consulted. **It failed the positive control**, 1 where
11 was wanted. A `var` parameter carries `IsRef` at **any** size, so `ir.inc`
reaches the same arm and reads the same False. The flag's name describes the
case it was invented for and not the set of cases that read it.

## ProcParamIsConst had to move with it

`symtab.inc`'s `ByRefArgNeedsLvalue` asks `ExplicitByRef and not IsConst`.
`ParseRecordMethodDecl` and `ParseProcTypeSignature` wrote **neither** column, so
writing `ExplicitByRef` alone would have turned a `const` record parameter — which
carries by-ref for exactly the ABI reason above — into one that refuses a
non-lvalue argument. Both columns land together; the fixture carries the
const-and-by-value rows that would have caught it.

## Fix

`ProcParamExplicitByRef` (and `ProcParamIsConst` at the two that lacked it) written
at all four row-writes in `pasparser_decl.inc`: `ParseRecordMethodDecl`,
`ParseProcTypeSignature`, the interface-method arm and the class-method arm of
`ParseTypeSection`.

Fixture `test/test_a_var_record_parameter_writes_back_through_every_receiver_that_has_no_implementation_header.pas`
(`VARRECWRITEBACK OK`, `test-core`, 11 rows): the three repaired receivers as
controls, the three broken ones, the small-record row, and the const/by-value
regression rows. Positive control measured — `VARRECWRITEBACK FAILED 4` with the
fix reverted and rebuilt. Byte-identical to fpc 3.2.2.

## Downstream

frankA is building by-value record parameter lifecycle and needs exactly this
column to tell a genuine `var`/`out` record parameter from an ABI-promoted one.
They said the parser-side route was unavailable because getting that
discriminator wrong *"finalizes the caller's live record through a `var`
parameter"* — the column was already wrong in that direction for these three
spellings. Told, with the measurement.

## Log
- 2026-09-06 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
