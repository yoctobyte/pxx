---
title: File I/O
order: 54
---

# File I/O — text files and record files

PXX has the two classic Pascal file surfaces, both in the `textfile` unit, both
pulled in automatically when your source mentions them:

| you write | you get | positions are counted in |
| --- | --- | --- |
| `var t: Text;` / `TextFile` | a text file — `WriteLn`, `ReadLn`, `Eof`, `Eoln` | lines and characters |
| `var f: file of T;` | a record file — `Write`, `Read`, `Seek`, `FileSize` | **records** |
| `var f: file;` | an untyped file — `BlockRead`, `BlockWrite` | blocks (128 bytes by default) |

`Seek`, `FilePos`, `FileSize` and `Truncate` count in **records, never bytes**.
`FileSize` of a five-element `file of Integer` is 5, and `FilePos` after one
`Read` is 1. That is the whole point of the typed surface, and it is the one
thing to keep in mind when porting code that used raw handles.

```pascal
{ fragment — the declarations and the shape of the idiom }
type
  TEntry = record
    id: Integer;
    score: Double;
  end;
  TEntryFile = file of TEntry;

{ Assign, Rewrite (create) or Reset (open existing), then Write/Read/Seek,
  then Close:

    Assign(f, 'entries.dat');
    Rewrite(f);
    Write(f, e);
    Close(f);

    Reset(f);
    Seek(f, 2);        { the THIRD record, not byte 2 }
    Read(f, e);
    Close(f); }
```

`Reset` opens a typed file for **reading and writing**, so the read-modify-write
idiom — `Reset`, `Seek`, `Read`, `Seek`, `Write` — works without reopening, as
it does in FPC.

## What must not go in a record file

**Reference-counted element types are refused at compile time.** `file of
AnsiString`, `file of` a record holding a dynamic array, an interface or a class
reference — what would land on disk is a pointer, so the file is meaningless the
moment the program exits. FPC refuses the same shapes.

## Records containing SETS are not portable to FPC

**This is the one place where a `file of T` written by PXX cannot be read by
FPC, and it is silent — both programs run, both round-trip their own files.**

A set is **32 bytes in memory in PXX and 4 bytes in FPC.** Writing a record
blits it, so every field after a set sits at a different offset in the two
compilers' files. Measured, `fpc 3.2.2 -Mobjfpc` against PXX, same program:

```
type
  TSmall = set of 0..31;
  TRec = record s: TSmall; n: Integer; end;

                     FPC        PXX
SizeOf(TSmall)       4          32
SizeOf(TRec)         8          40
file of TRec, one record written:
  bytes on disk      8          40
  the set's mask     22 00 00 80    22 00 00 80   <- IDENTICAL, and then
  `n` (12345)        at offset 4    at offset 32
```

The mask itself agrees — PXX's is a byte-exact zero-extension of FPC's — so the
divergence is entirely the **width**, and therefore entirely the **offsets of
everything after it**.

**What this means in practice:**

- A PXX program writing and reading its own `file of TRec` is correct. The
  round-trip works; nothing is lost.
- The same file handed to an FPC build of the same program is misread, with no
  error. It will read a plausible wrong `n`.
- **So: do not put a set in a record you intend to exchange with FPC.** Store
  the set as an explicit `LongWord` (or an array of them) in the record and
  convert on the way in and out, and the file becomes portable.

There is **no `BlockWrite` size trap here**: `SizeOf(r)` and the number of bytes
a typed `Write(f, r)` puts down are the same number (40 above), so
`BlockWrite(f, r, SizeOf(r))` is self-consistent. It is portability that is
lost, not consistency.

Strings are **not** in this category any more. A `string[N]` field is laid out
byte-for-byte as FPC lays it out, and a record or array of them blits and is
FPC-readable.

## Text files

The text surface is complete and matches FPC byte for byte —
`Assign`/`Reset`/`Rewrite`/`Append`/`WriteLn`/`ReadLn`/`Eof`/`Eoln`/`SeekEof`/
`Close`, plus `SetTextBuf`, `Flush`, `Erase`, `Rename` and `IOResult`. Use it
for anything line-oriented; the record surface above is for fixed-size binary
records and random access.
