---
summary: "LANDED 2026-09-05. `file of T` and untyped `file` compile and run: one shared RTL record (FileRec, beside Text in `textfile`), the element WIDTH carried on the symbol (SymFileRecSize/SymFileElemTk, with the alias and parameter channels the string capacity already needed), Assign/Reset/Rewrite/Close/Erase/Rename/Seek/FilePos/FileSize/Truncate/Eof/BlockRead/BlockWrite, and Read/Write statement hooks that move one record per argument. 20 of 20 rows agree with fpc 3.2.2 -Mobjfpc on the same program, and ALL THREE files the test writes are BYTE-IDENTICAL to FPC's (12/72/32 bytes, positive control asserted). The three negative tests are re-pointed: test_file_type_fail.pas is RETIRED (its refusal is gone) and replaced by three that pin the refusals FPC also makes -- a reference-counted element type, writeln on a file, and a Read whose destination is not the element type. THE SETS NOTE IS WRITTEN AND ITS PREDICTED TRAP DOES NOT EXIST: we BLIT, so SizeOf(r) and the bytes a typed Write puts down are the same number and `BlockWrite(f, s, SizeOf(s))` is self-consistent. What is real is PORTABILITY -- measured, a `record s: set of 0..31; n: Integer` is 40 bytes here against FPC's 8, the mask's first four bytes IDENTICAL and `n` at offset 32 against FPC's 4 -- so such a file round-trips under pxx and is misread by FPC with no error. docs/library/file-io.md carries that."
type: feature
prio: 70
track: P
blocked-by: []   # both closed 2026-09-04 (compat-... in done/, p100 in done/); edge kept in the body's history
owner: frankB
---

# `file of T` and untyped `file` are not supported

> **BLITTING IS A CONSEQUENCE OF THE FORMAT CHOICE, NOT A LIMITATION — measured
> 2026-09-02 (`5f275966bf50` @ `bf92c45a7`), and this CORRECTS an earlier
> framing in this ticket's own history that said records could not blit.**
>
> **RE-MEASURED AT HEAD 2026-09-04 AND THE DIVERGENCE IS GONE.** The 09-02
> column below was correct when taken; the byte-prefix flip (`fd186a975`) and
> the `shortstring` arm that completed it (`6a890a405`) landed after it, and
> nothing updates a table. Both blockers are now in `done/`.
>
> ```
>                         pxx 09-02   pxx HEAD   FPC (-Mobjfpc)
> string[100]             108         101        101
> TRec = a:s[100]; b:s[200]
>   SizeOf                320         302        302
>   field b offset        112         101        101
> TGrid = [0..2] of [0..10] of string[100]
>   SizeOf               3564        3333       3333
>   inner / outer stride  108/1188    101/1111   101/1111
> ```
>
> **Six rows, six exact matches.** The padding this ticket is built around was
> the 8-byte length word needing alignment; a one-byte prefix is byte-aligned,
> so it is not that we stopped padding but that there is nothing left to pad.
>
> **What that changes for the feature:** a record or array of fixed strings now
> blits AND the result is FPC-readable. Those were two separate goals here and
> they have collapsed into one, so for this case there is no format choice left
> to state -- our layout IS FPC's. Sets are the only case where the choice
> survives.
>
> **Both compilers are fully contiguous.** FPC's record is exactly 101+201 with
> no padding; our grid is exactly 3*11*108 with clean strides. Nested arrays of
> fixed strings are the EASY case in both, not the hard one.
>
> **So `file of T` CAN blit — if it writes OUR layout.** The file is then
> self-consistent and simply not FPC-readable. Marshalling is required only by
> the decision to write FPC-compatible files, and that is true for sets as much
> as strings: writing our own 32-byte set is a blit too. **State the format
> choice first; the blit/marshal question is downstream of it and not
> independent.**
>
> ~~Two divergences that appear in RECORDS and not in arrays: **we pad and FPC
> does not**~~ — **RESOLVED 2026-09-04, see the re-measurement above.** This
> paragraph predicted that implementing
> [[feature-p-implement-the-real-tyshortstring-byte-prefix-layout]] would remove
> the padding as well as the width gap. It did, exactly, and that ticket is
> closed. The surviving half is the other one: **`string[1000]` cannot arise in
> FPC at all** (it exceeds the one-byte prefix, so it stays the wide kind here),
> so records holding one are ours-only by construction and blitting them is
> unambiguous — that remains true and is now a statement about `string[N]` for
> N > 255 specifically, not about fixed strings in general.
>
> **SETS: A CONSTRAINT AND A DOC OBLIGATION, settled by the owner 2026-09-02 —
> RE-MEASURED AT HEAD 2026-09-04 AND UNCHANGED, so this section stands as
> written while the string section above did not.** `set of 0..31` and
> `set of TE8` are both 32 bytes against FPC's 4, and in
> `record s: TSmall; n: Integer` our `n` sits at offset 32 against FPC's 4 —
> the field shift this section predicts, confirmed rather than assumed.
> Sets stay 32 bytes in memory. Measured: our mask is a byte-exact ZERO-EXTENSION
> of FPC's, so **a bare set writes with no conversion** — put down 4 bytes when
> the declared high bound is <= 31, else 32, read back and zero-extend, and the
> file is byte-identical to FPC's.
>
> **But a RECORD containing a small set cannot blit**: the set is 32 bytes in
> memory and 4 on disk, so every field after it shifts. That record must be
> marshalled field-by-field. The owner's instruction: *"advise against using
> records with sets for file-io or document it."* — so this ticket owes a
> **Track D doc note**, not just an implementation.
>
> And the trap to document beside it: `SizeOf(s)` answers **32** while the typed
> write puts 4 bytes down, so `BlockWrite(f, s, SizeOf(s))` writes 32 and
> desynchronises the file. The 32 is TRUE about our representation (the
> 2026-09-02 `SizeOf` rule) — the hazard is the gap, not the number.
>
> Background and the parked `smallset` mechanism that would remove all of this:
> [[decide-a-what-a-set-costs-bits-bytes-bounds-and-what-file-of-t-writes-to-disk]].

- **Type:** feature (Pascal frontend + RTL file layer). Track P; the RTL half
  (`Seek`/`FileSize`/`BlockRead`/`BlockWrite` over a typed handle) is Track B
  ground once the frontend accepts the type.
- **Status:** done
  tree for `file of` / "typed file" before filing.
- **Found:** 2026-08-16, Pascal oracle sweep vs `fpc -O- -Mobjfpc` (file I/O
  topic).

## What works and what does not

```
var ft: TextFile;          { ok }
var fi: file of Integer;   { error: file types are not supported (use TextFile for text I/O) }
var fr: file of TRec;      { same }
var fb: file of Byte;      { same }
var fu: file;              { same -- untyped files too }
```

**Text I/O itself is complete and matches FPC byte for byte** — the same sweep
ran `Assign`/`Rewrite`/`writeln(f,...)`/`Reset`/`ReadLn`/`Eof`/`Append`/`Close`
plus `FileExists`/`DeleteFile` and every line agreed. So this is one missing
type family, not a weak file layer.

The diagnostic is loud and names the alternative, which is why this is a
feature and not a bug: no program silently does the wrong thing.

## Why it is worth having

`file of TRec` is the classic Pascal persistence idiom — the shape a textbook,
a port of an older program, or an FPC corpus entry reaches for first. Its
absence pushes every such program onto `TFileStream` or raw `PAL` calls, which
is a rewrite rather than a port. It also blocks `Seek`/`FileSize`/`Truncate`
over records, which have no TextFile equivalent.

## Scope note — this needs the record layout question answered first

`file of TRec` writes `SizeOf(TRec)` bytes per element, so its on-disk format is
exactly the record layout. If the record holds a `string[N]`, pxx's layout is
not FPC's
([[compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees]]:
24 bytes where FPC says 11 — **re-measured 2026-08-29 against pinned v392 and
FPC 3.2.2, still exactly 24 vs 11.** The link here previously named
`compat-pascal-a-string-n-field-makes-a-record-a-different-size-than-fpc`,
which resolves to no ticket: it was folded into the four-type-sizes ticket and
the citation was left behind. A dead `[[link]]` reads exactly like a live one
and nothing checks — see
[[chore-t-a-wikilink-to-a-ticket-that-does-not-exist-is-never-detected]]), and a file written by one would not be readable by
the other. Land that first, or the feature ships with a silent incompatibility
baked into its file format — which is worse than not having it.

## Gate

An FPC-differential test writing and re-reading a `file of Integer` and a
`file of TRec` (Write/Read/Seek/FileSize/Truncate/Eof), diffed against
`fpc -O- -Mobjfpc`, plus a byte-for-byte comparison of the two written files;
`gate.sh quick`; self-host fixedpoint.

## Triage 2026-08-19 (Track D re-triage pass, pin v363)

**Genuine feature, still wanted, unchanged.** `var fi: file of Integer;` still
stops at `error: file types are not supported (use TextFile for text I/O)`, and
the untyped `file` form with it. Compat surface — FPC accepts the classic
record-file idiom — but the refusal is loud, so it stays a feature rather than
being promoted to a bug.

**Landmine confirmed, not merely suspected — and it is three recipes, not
one.** `Makefile:3989-3995` runs `test_default_textfile_fail.pas`
(`Default: file types are not allowed`), `test_file_type_fail.pas`
(`file types are not supported`) and `test_default_filefield_fail.pas`
(`record type contains a file field`), each under `!` with a grep on the
message.
Implementing typed files makes that program compile and reds `test-core` —
which `gate.sh quick` does not run, so it would surface only via Track T.
Re-point or retire that test in the same commit.


## The FPC-compiler corpus march reached this, 2026-08-27

`file of T` is now the **top blocker** for the FPC compiler-source march, not a
hypothetical. After seven fixes this session, `cutils.pas`, `globtype.pas`,
`constexp.pas` and `version.pas` all compile clean, and the next tier stops on
exactly two things:

| unit | stops on |
| --- | --- |
| `cclasses.pas`, `cfileutl.pas`, `cstreams.pas`, `comphook.pas`, `finput.pas` | `file types are not supported` — **this ticket** |
| `cmsgs.pas` | `TMessage = object` — [[feature-p-legacy-value-object-types]], which [[decide-old-style-object-types]] chose NOT to build |

Recorded as measurement, not as an argument to raise the priority.
`frontend-compat-philosophy.md` says *"a corpus is a measuring instrument, not a
dependency"*, and the same rule is what keeps `cmsgs.pas` from reopening the
`object` decision. The scope note above still stands: the `string[N]` record
layout question is the real gate, and it has NOT moved —
[[bug-p-index-0-of-a-frozen-string-is-not-the-length-byte]] fixed the length
byte's *observable* while leaving the *layout* at 8 bytes, precisely so it would
not pre-empt that decision.

## LANDED 2026-09-05 (frankB) — what was built, and the two places the ticket was wrong

### The design decision the ticket asked for, made and stated

`file of T` and `file` both resolve to **ONE** RTL record, `FileRec`, declared
beside `Text` in `lib/rtl/textfile.pas` and pulled in by the same token scan
(`file` joins `text`/`textfile`/`ioresult`/`flush`). What the element type
contributes is a **WIDTH**, not a layout — so a second record type per element
would buy nothing and cost every RTL routine an overload.

**The format choice, stated first as the ticket demanded: we write OUR layout.**
A typed `Write` blits `SizeOf(T)` bytes. For every element type that does not
contain a set that IS FPC's layout, measured byte for byte; for one that does,
it is not, and nothing marshals.

### Where the width lives, and why that was the whole problem

The record is shared, so the element width has no carrier in the type. It rides
on the SYMBOL — `SymFileRecSize` + `SymFileElemTk`, parallel arrays (never a
`TSymbol` field: project_tsymbol_field_landmine), stamped by `Alloc*` from a
`LastTypeFileRecSize`/`LastTypeFileElemTk` channel, with `AliasFileRecSize` for
`type TIntFile = file of Integer` and `ptypesFileRecSize` for a `var f:
TIntFile` parameter. Both extra channels exist for the reason `AliasStrCap` and
`ptypesStrCap` already document: a USE of the alias, and the parameter
allocation loop, are both far from where the type was parsed.

The compiler has to know the width at exactly **one** call — `Assign`, which
Pascal guarantees runs first — and it is injected there as an omitted trailing
argument named `__recsize`. Keyed on the PARAMETER name, not the routine's, so
the mechanism is declared in the RTL signature rather than in a compiler table
of routine names.

**THREE PLACES FILL AN OMITTED TRAILING ARGUMENT AND A STATEMENT-LEVEL
`Assign(f, name)` REACHES THE THIRD.** `FillDefaultArgs` and
`TryFillTrailingDefaults` (both `pasparser_call.inc`) serve arities the overload
matcher could not accept on its own; a call the matcher DID accept short comes
all the way down to `ir.inc`'s own fill loop with its defaults still unfilled.
Measured the expensive way: the override was written into the first two, the
program compiled and ran, every value was plausible, and `FileSize` answered 0 —
because `RecSize` was still the declared 128 and 20 div 128 is 0. A probe in
`DefaultArgValueNode` never fired at all, on any program, including the
compiler's own build. **Three mechanisms for one concept is the smell
root-cause-over-microfix names; until it is one, an override has to be in all
three or `Assign` works in some spellings and not others.**

### Measured against fpc 3.2.2 (`-O- -Mobjfpc`), same program, same run

`test/test_typed_file_of_t.pas`: **20 of 20 rows identical**, and the three
files it writes compared byte for byte:

```
test_typed_file_i.bin   IDENTICAL (12 bytes)
test_typed_file_r.bin   IDENTICAL (72 bytes)
test_typed_file_u.bin   IDENTICAL (32 bytes)
positive control (append one byte to ours) -> differs
```

The control is there because a `cmp` of two files a harness may never have
written passes on every row.

### The ticket's OWN prediction about sets was half right, and I measured which half

The ticket predicted a trap: *"`SizeOf(s)` answers 32 while the typed write puts
4 bytes down, so `BlockWrite(f, s, SizeOf(s))` writes 32 and desynchronises the
file."* **That trap does not exist in this implementation**, and it could not:
it presupposes a marshalling write, and we blit. `SizeOf(r)` and the bytes a
typed `Write(f, r)` puts down are the same number.

What IS real is portability, and it is worse than the trap because it is silent
on both sides. Measured, `record s: set of 0..31; n: Integer`:

```
                     FPC        PXX
SizeOf(set of 0..31) 4          32
SizeOf(TRec)         8          40
one record on disk   8 bytes    40 bytes
  the set's mask     22 00 00 80  22 00 00 80   <- IDENTICAL
  n = 12345          at offset 4  at offset 32
```

Both programs round-trip their own file correctly. Hand PXX's file to an FPC
build of the same program and it reads a plausible wrong `n`, with no error.
`docs/library/file-io.md` says exactly that, with this table, and gives the
workaround (store a `LongWord` and convert). The snippets there are FRAGMENTS
on purpose: `tools/docsnip.py` compiles complete programs against the PIN, and
the pin predates this feature, so a complete `file of T` program would be red in
front of a stranger for a reason that is not a defect.

### The negative tests: one RETIRED, three NEW

`test/test_file_type_fail.pas` asserted that `file` is refused. That refusal is
gone, so the test is deleted rather than reworded — a test whose name is its
premise cannot be re-pointed without lying. The three that replace it pin
refusals FPC also makes, each verified against fpc 3.2.2:

| new test | pxx | fpc 3.2.2 |
| --- | --- | --- |
| `test_file_element_type_fail` | `not allowed as a file element type` | `Typed files cannot contain reference-counted types` |
| `test_file_writeln_fail` | `writeln is not defined for a typed or untyped file` | `Can't use readln or writeln on typed file` |
| `test_file_read_size_mismatch_fail` | `the variable is 1 bytes and the file's element type is 4` | `Typecast has different size (1 -> 4) in assignment` |

`test_default_textfile_fail` and `test_default_filefield_fail` are UNCHANGED and
still red-on-compile: `Default()` refuses file types by name, and
`RecContainsTextRec` now asks about `FileRec` as well as `Text`, so a record
holding a `file of T` is refused the same way a record holding a `TextFile` was.

All of these live in `test-core`, which `gate.sh quick` does not run; they were
run explicitly with `PXX_ALLOW_FULL_SUITE=1`.

### `{$I+}` was HALF wired for a record file and now is not

`IRIoCheckedCallee` matches by NAME plus a `tyRecord` first parameter, so
`Reset`/`Rewrite`/`Close`/`CloseFile`/`Erase` on a `file of T` were already
checked the moment the type existed — and `Read`, `Write`, `Seek`, `Truncate`,
`BlockRead`, `BlockWrite` were not. Opening a record file raised on failure
while reading past its end returned silently: the worse half of the pair, and
invisible because the checked half looked like the feature working.

The six are added, gated on the first parameter's **record identity**
(`ProcParamRecId` = the `filerec` row) rather than on `tyRecord`, because
`Seek`, `Truncate`, `BlockRead` and `BlockWrite` are ordinary words and a user's
own `Seek(var s: TCursor)` would otherwise collect a `PXXIoCheck` it never asked
for. Measured: `{$I+}`, `Reset` on a path under a directory that does not exist,
then `Read` → `Unhandled exception: EInOutError: I/O error`, rc 217.

### One expected snapshot moved, and it is the guard working

`test/ast_slot_writes.expected` gains two lines — `AN_ASSIGN Left tmpIdent` and
`AN_ASSIGN Right destNode`, the write-side conversion temp's assignment. Both
slots hold real node indices, so this is a new SPELLING and not a new overload,
which is exactly the case `tools/ast_slot_overloads.py` is built to put in front
of a human rather than to reject. Reviewed, then `--update`; the tool's own
self-check (an injected payload write into `AN_SEQ`'s Right must be reported)
passes on the new snapshot, so the guard can still fail.

### What the negative tests actually assert

Each of the three greps its own MESSAGE, never the exit status. A negative test
that only requires a nonzero exit passes by failing for any reason at all —
including the reason you just removed — which is the same failure shape as a
probe that never fires: the instrument answers, and the answer is about
something else. `test-core` runs the grep for every negative test in the tier,
so a message drifting silently anywhere in that set is caught there rather than
here.

### Not done, and deliberately

- **The FPC compiler-source march is not re-measured.** The corpus
  (`cclasses.pas`, `cfileutl.pas`, `cstreams.pas`, `comphook.pas`,
  `finput.pas`) is not in this checkout, so the claim "this unblocks them"
  would be transcription. Whoever has the tree should re-run it; the refusal
  those units stopped on is gone.
- **`file of` a dynamic array / an open array element** is not supported;
  the element must be a fixed-size type. FPC refuses the reference-counted
  cases too, and the rest are unusual.
- **The Read/Write destination check is on the WIDTH, not the record's
  identity.** `Write(f, other)` where `other` is a different record of the same
  size is accepted; FPC catches it. The width is what the symbol carries, so
  catching identity would mean carrying the element's rec id too. Real gap,
  small blast radius (both records are the caller's own), and it is the same
  size-vs-identity question `FindProcOverloadRec` answers for overloads — the
  place to fix it is one channel wider, not a second check here.
- **`Default(TIntFile)`** — the alias spelling — is not refused. The `Default`
  guard is keyed on the type NAME, so `Default(FileRec)` and `Default(TextFile)`
  are caught and an alias to either is not. Pre-existing shape, one type wider.

## Log
- 2026-09-05 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
