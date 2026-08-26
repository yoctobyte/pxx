---
track: P
prio: 40
type: bug
blocked-by: []
summary: "An error raised while compiling a unit pulled in by `uses` reports the correct LINE NUMBER for that unit but names an unrelated file in its `in:` line — every fgl.pp wall was reported as `in: stable_linux_amd64/default/builtin/builtinheap.pas`. Costs real time on corpus work, where the whole job is locating a wall in third-party source."
status: done
owner: opus5-frank1
---

# A diagnostic in a `uses`d unit names the wrong source file

- **Type:** bug (Pascal frontend — diagnostic provenance)
- **Track:** P
- **Found:** 2026-08-25, on every wall of the fgl corpus rung
  ([[feature-pascal-corpus-fgl]]).

## Measured (pxx `stable_linux_amd64/default/pinned`, VERSION 374)

```
$ pxx --mimic-fpc -Fulibrary_candidates/fpc-rtl/rtl/objpas test/fgl/list_str.pas out
pascal26:892: error: String(): operand must be Char or string
  in: stable_linux_amd64/default/builtin/builtinheap.pas
  near: Items  FPosition    >>>  end
```

Line 892 is correct — it is `rtl/objpas/fgl.pp:892`, and the `near:` context is
that line's text. The `in:` line names `builtinheap.pas`, which has nothing to do
with it. Reproduced identically on four unrelated errors in fgl.pp (lines 892,
1061, 1189, 1602); each named `builtinheap.pas`.

Guess at the mechanism, unverified — do not record this as the root cause without
measuring it: the `in:` line looks like it reports the *last* source file the
compiler opened (or the current builtin/RTL unit) rather than the file owning the
reported line. `PXXDBG` / a probe on the diagnostic emitter, not reasoning, should
settle it (`devdocs/dev/debugging-playbook.md`).

## Why it matters

On a corpus rung the entire job is "find which line of 60k lines of third-party
source we cannot compile". A file name that is confidently wrong sends you to the
wrong file first every time. The line number being right makes it worse, not
better — it reads as precise.

## Gate
`make compiler/pascal26` (self-host fixedpoint) + `tools/gate.sh quick`.

## Links
Found under [[feature-pascal-corpus-fgl]] · umbrella
[[feature-pascal-corpus-expansion]]

## Outcome — 2026-08-27

Measured with the `PXXDBG=a.srcmap` hook a previous pass left here for exactly
this question — *"there is no way to tell from the outside whether the RANGES
are wrong or the token INDEX is: this prints both."* It is the **index**, and
the ticket's own guess (*"reports the last source file the compiler opened"*)
was close but not it.

### Measured

The ticket's repro is gone (fgl is 7/7 now), so the wall was re-created: an
undefined name injected at `fgl.pp:892`, the line the ticket names.

```
$ PXXDBG='a.srcmap:*' pascal26 --mimic-fpc -Fu<fglcopy> -Fu<objpas> test/fgl/list_str.pas out
pascal26:892: error: undefined variable (bogus_name_here)
PXXDBG a.srcmap tok=430 srcline=892 lexing=FALSE tokcount=83436 -> test/fgl/list_str.pas
PXXDBG a.srcmap   [0] start=0      ... test/fgl/list_str.pas
PXXDBG a.srcmap   [3] start=29722  ... <fglcopy>/fgl.pp
```

The table is **correct** — fgl.pp owns tokens 29722..40777. The diagnostic asked
about token **430**, and `Tokens[430].Line` is 892. A token carrying fgl.pp's
line number is sitting at an index the table assigns to `list_str.pas`.

### Root cause: line and file came from two different places

A **generic specialization splice** copies the template body out of the template
pool and pastes it into the using file's token stream
(`SpecializeStream`, `pasparser_generic.inc`). The pasted tokens keep their
`.Line`, because the line **rides on the token**. They do not keep their file,
because the file **rides on the token's INDEX** — and the index is now the
destination's. So the two halves of "where" disagree by construction, and the
line being right is what made it read as precise.

`AdjustSrcRanges` — the earlier fix under
[[bug-a-a-diagnostic-in-a-used-unit-names-the-wrong-source-file]] — handles the
other half of the same edit correctly: it slides the boundaries **around** a
splice. It cannot supply the pasted region's own provenance, because the range
table is positional and a paste's provenance is not its neighbours'.

Which wrong file gets named is incidental to the layout. Today token 430 lands
in the MAIN file's range, so `in:` is suppressed entirely and the diagnostic
silently claims the error is in the file the user typed — measured against
`stable_linux_amd64/default/pinned`, which prints no `in:` line at all for the
new test. At VERSION 374 the same index landed in `builtinheap.pas`'s range,
which is the form the ticket recorded.

### The fix

The splice now says where its tokens came from, so line and file have one
source:

- `TemplateSrcKey[]` (`defs.inc`) — the `KeyStrs` id of the file each generic
  template was CAPTURED from, recorded at capture because that is the only
  moment the answer exists: by splice time the body is in the template pool and
  its origin index is gone.
- `TemplateSrcKeyOfTok` — pool index → template → source key. Linear over
  `TemplateCount` (≤ 128).
- `PasSpliceTokFile(startTok, count, srcKeyId)` (`dbg_filetable.inc`) — plants
  the pasted region's file and a second entry restoring whatever covered the
  splice point. A no-op when the paste lands in its own file.
- `PasInsertSrcRangeAt` — an ORDERED insert, because `PasSrcOfTok` scans
  backwards and assumes the table is sorted by start; a plain append in the
  middle would be invisible to every lookup below it. An entry already starting
  at the same index is replaced rather than stacked, the rule `PasMarkTokFile`
  already uses, so a repeated splice at one point cannot grow the table.

### Result

```
pascal26:892: error: undefined variable (bogus_name_here)
  in: <fglcopy>/fgl.pp
```

Right line, right file, from inside a specialized generic body.

Not touched, deliberately: the other `InsertTokens` callers paste **synthesized**
tokens (alias declarations, deferred specialization headers), which have no
origin file — the destination is the correct answer for them and they are left
alone. Only a paste that MOVES tokens between files needs provenance.

### Measured

`test/test_diag_in_specialized_body_names_the_template_file_fail.pas` +
`test/units/ugenericbad.pas` (wired into `test-core`): a generic whose template
body contains an undefined name, specialized from another file. Asserts rc=1,
the line (21, in the template), `in: test/units/ugenericbad.pas`, and that no
binary is produced. The pinned compiler prints no `in:` line for it at all.

### Gate

`make compiler/pascal26` byte-identical (a0f06312611d) · `tools/gate.sh quick`
GREEN · pascal-conformance 346/0/170/34 · c-conformance 220/0 · fgl 7/7.

## Log
- 2026-08-27 — resolved, commit PENDING-COMMIT.
