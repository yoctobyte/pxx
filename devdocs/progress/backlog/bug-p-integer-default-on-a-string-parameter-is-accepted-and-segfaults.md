---
track: P
prio: 60
type: bug
summary: "`procedure R(s: AnsiString = 1)` compiles clean and SEGFAULTS on the omitted argument — the bare ordinal is handed to the callee as a string. FPC rejects the declaration outright. A silent-acceptance corruption bug, same family as the ctor-variant one: no diagnostic, and the crash is wherever the string is first touched"
---

# An integer default on a string parameter compiles, then segfaults

- **Type:** bug (Pascal frontend — parameter default declarations; memory corruption)
- **Opened:** 2026-08-10
- **Found by:** Track A+C+P+N, checking whether string defaults *arrive*
  correctly while resolving
  [[bug-p-float-literal-default-in-a-parameter-list-fails-to-parse]]. The
  neighbouring correct shapes all passed; this one is what the sweep turned up.

## Repro

```pascal
program n;
procedure R(s: AnsiString = 1); begin writeln('[', s, ']'); end;
begin R(); end.
```

```
ok: n  [code=47507B ...]        { compiles clean, no warning }
[Segmentation fault (core dumped)
```

Note the partial output: `[` is written, then the fault — the crash is at the
point the string is first *touched*, not at the call, which is the same
"lands far from the cause" shape as
[[bug-p-constructor-with-a-defaulted-variant-param-corrupts-memory]].

## What narrows it

| shape | result |
| --- | --- |
| `s: AnsiString = 'a'` | ok — value arrives as `'a'` |
| `s: string = 'frozen'` | ok |
| `s: AnsiString = 1` | **compiles, then segfaults** |
| `d: Double = 2` (integer default, float param) | ok — the ordinal is converted |

So the type mismatch is *tolerated* for a numeric parameter (correctly, by
conversion) and is silently wrong for a string one, where the ordinal reaches
the callee as a pointer.

## Cause (mechanism identified, fix not chosen)

`ParseParamDefaultValue` (`compiler/parser.inc`) picks the default's shape from
the **literal's** token kind, never from the **parameter's** declared type: an
integer literal takes the ordinal arm regardless of what it is defaulting. The
call site then rebuilds it with `DefaultArgValueNode`, whose ordinal arm emits
an `AN_INT_LIT` tagged with `Procs[mpi].Params[k].TypeKind` — i.e. tagged
`tyAnsiString`. Nothing converts, so `1` is passed where a string pointer is
expected.

Note `DefaultArgValueNode` *already* carries a special case of exactly this
shape for `tyVariant` (it retags the ordinal `tyInteger` so the value gets
boxed). That is the second instance of "the literal's kind and the parameter's
kind disagree" — which argues the fix belongs at the declaration, as a
compatibility CHECK, rather than as a third retag downstream.

## Recommended fix

**Reject it at the declaration**, as FPC does: after
`ParseParamDefaultValue` returns, verify the default's shape against the
parameter's `TypeKind` and `Error` on a mismatch that cannot be converted
(ordinal → string/class/pointer). That closes the whole family at one site
instead of one arm at a time, and turns a segfault into a compile error.

Check the corpora before landing: `lib/**` may contain a `= 0` on a string
parameter that has always "worked" because the argument was never omitted, and
a new error would break the build. If so, warn under the default dialect and
error under `--strict-fpc` (see `meta-dialect-extensions-and-fpc-strict`).

## Gate

The repro becoming a compile error; `test/test_default_params_methods.pas`
extended (it is the home for this concept); `tools/gate.sh quick`. If a
`{%FAIL}`-style conformance case is the right home for the diagnostic, prefer
that over a runtime test.
