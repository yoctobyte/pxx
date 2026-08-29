---
summary: "`file of T` and untyped `file` are refused outright — only TextFile works. Blocks the classic Pascal record-file idiom (Assign/Rewrite/Write/Seek/FileSize/BlockRead)."
type: feature
prio: 70
track: P
blocked-by: [compat-pascal-four-type-sizes-disagree-with-fpc-and-every-value-agrees]
---

# `file of T` and untyped `file` are not supported

- **Type:** feature (Pascal frontend + RTL file layer). Track P; the RTL half
  (`Seek`/`FileSize`/`BlockRead`/`BlockWrite` over a typed handle) is Track B
  ground once the frontend accepts the type.
- **Status:** backlog. No existing ticket — searched the whole `devdocs/progress`
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
