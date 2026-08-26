---
track: P
prio: 40
type: bug
blocked-by: []
summary: "An error raised while compiling a unit pulled in by `uses` reports the correct LINE NUMBER for that unit but names an unrelated file in its `in:` line — every fgl.pp wall was reported as `in: stable_linux_amd64/default/builtin/builtinheap.pas`. Costs real time on corpus work, where the whole job is locating a wall in third-party source."
status: backlog
owner: —
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
