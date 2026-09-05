---
slug: bug-p-an-unqualified-call-to-a-user-routine-named-read-or-write-is-eaten-by-the-intrinsic
title: "An UNQUALIFIED call to a user routine named Read/Write is eaten by the I/O intrinsic — the declaration side was fixed and the call side never was"
track: P
prio: 60
type: bug
status: backlog
found: 2026-09-05
found-by: frankB
owner: ""
blocked-by: []
summary: "`read`/`write`/`readln`/`writeln` are LEXER KEYWORDS (tkRead, tkwrite, ...), so they are not identifiers anywhere an identifier is expected. pasparser_name.inc already re-admits them in MEMBER-NAME and METHOD-NAME position -- its own comment says `so e.g. TStream.Read / TStream.Write can be declared` -- so declaring the method works and QUALIFIED calls (`Self.Read(b,c)`, `s.Read(b,c)`) work. An UNQUALIFIED call does not: inside TStream.ReadBuffer, `if Read(Buffer,Count) < Count` is refused with `expected expression`, in statement position as well as expression position. Separately, a global (non-method) routine cannot be NAMED Read at all -- `function Read(var B; C: Longint): Longint;` is refused at the declaration with `expected name`, so the method-name predicate was never extended to routine names. Measured 2026-09-05 against compiler 62fa62403452: this is the TOP BLOCKER for four of the five units of the FPC compiler-source march, all reaching it through cstreams.pas:227."
---

# The measurement — the FPC compiler-source march, re-run 2026-09-05

Re-run by frankB after `feature-pascal-typed-and-untyped-files` landed, against
compiler `62fa62403452` (self-host fixedpoint verified) at master `2316f7058`.
Corpus is FPC 3.2.2's own compiler sources, `/usr/share/fpcsrc/3.2.2/compiler`,
which IS installed on this box even though `library_candidates/` has no copy —
the previous note on the typed-files ticket said it was unavailable in the
checkout, which was true of the checkout and wrong about the box.

**Invocation matters and the earlier march was missing a define.** pxx has no
standalone-unit output, so each unit is reached through a three-line driver
program that `uses` it, and FPC's own build passes `-dx86_64` — without it
`globtype.pas` stops at `unknown type: PInt`, because `PInt` is declared inside
`{$ifdef cpu64bitaddr}` and `fpcdefs.inc` derives that from `x86_64`. That is a
CORPUS SETUP defect, not a pxx one, and it masked everything behind it:

```
pxx -Mobjfpc -dx86_64 -Fu$C -Fi$C -Fu$C/x86_64 -Fi$C/x86_64 drv_<unit>.pas
```

| unit | before (2026-08-27) | now |
| --- | --- | --- |
| `cutils`, `globtype`, `constexp`, `version` | OK | OK |
| `cclasses` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `cstreams` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `comphook` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `finput` | `file types are not supported` | **`cstreams.pas:227 expected expression`** |
| `cfileutl` | `file types are not supported` | `conditional directive: comparison requires integer operands` |
| `cmsgs` | `TMessage = object` (predicted) | `unknown type: TSystemCodePage` |

**Claim only what was checked: these units no longer stop THERE. None of them
BUILDS.** The typed-file refusal is gone from every row that had it, which is
what the typed-files ticket predicted and is all it predicted.

Two side-findings worth carrying: `cmsgs` does NOT stop where the old table
said it would — it never reaches `TMessage = object`, so the row that was used
to keep [[decide-old-style-object-types]] closed was measured through a define
gap. And `cfileutl`'s conditional-directive refusal is a separate defect that
has never had a ticket.

# The defect

`cstreams.pas:227`, in `TCStream.ReadBuffer`, and the sibling at `:236`:

```pascal
procedure TCStream.ReadBuffer(var Buffer; Count: Longint);
  begin
     CStreamError:=0;
     if Read(Buffer,Count)<Count then     { <-- refused }
       CStreamError:=102;
  end;
```

`Read` is `TCStream.Read`, declared in the same class. This is not an obscure
spelling — it is the shape of `TStream.ReadBuffer` in FPC's and Delphi's own
RTL, and `TStream.Read`/`Write` is one of the most-used method pairs in the
Pascal world.

## The boundary, varied rather than assumed

22-line repro, and five neighbours run against `62fa62403452`:

| # | shape | verdict |
| --- | --- | --- |
| 1 | unqualified `Read(B,C)` in EXPRESSION position, inside a method | **`expected expression`** |
| 2 | `Self.Read(B,C)`, same place | accepted |
| 3 | `s.Read(B,C)` from outside the class | accepted |
| 4 | unqualified `n := Read(B,C)` in STATEMENT position, inside a method | **`expected expression`** |
| 5 | unqualified `Write(B,C)` in expression position | **`expected expression`** |
| 6 | global `function Read(var B; C: Longint): Longint;` | **`expected name`, at the DECLARATION** |

So it is **QUALIFICATION**, not position: rows 2 and 3 go through the member
path, which `IsMemberNameTok` already admits these tokens to. Rows 1, 4 and 5
reach the primary parser, where `tkRead` is not an identifier and the intrinsic
arm is the only thing that wants it.

**Row 6 is a SECOND, EARLIER defect and should not be folded into the first.**
`IsMethodNameKind` admits `tkRead` in method-name position, so the class member
declares fine — but a global routine name does not use that predicate, so
`function Read(...)` cannot be declared at unit or program level at all. FPC
accepts it; `read` is not a reserved word in FPC, which is the premise
`pasparser_name.inc` is already written around.

# Where it lives

`compiler/paslexer.inc:122,152` makes the tokens. `compiler/pasparser_name.inc`
holds the two predicates that already re-admit them, and its comment states the
principle: *"Read/Write/Readln/Writeln are intrinsics resolved by context at the
call site, not true reserved words — FPC lets a user declaration shadow them."*
**Context at the call site is exactly what is missing** — the statement dispatch
at `pasparser_stmt.inc:5346` has one narrow instance of it already (a function
assigning its own result by a name that lexes as an intrinsic), which is the
precedent for the general rule and shows the shape of the check.

# Gate

The repro above, both directions: the six rows, with 2/3 still accepted so the
fix cannot be a blanket "never treat it as an intrinsic". Plus a POSITIVE
CONTROL that the intrinsic still wins where nothing shadows it — an ordinary
`Read(f, x)` and `Write(f, x)` on a Text and on a typed file, which is what
`test_typed_file_of_t.pas` already asserts, so that test is the control and
must stay green. Then re-run the march and record which row moves.
