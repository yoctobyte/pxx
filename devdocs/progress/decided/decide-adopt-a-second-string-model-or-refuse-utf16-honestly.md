---
slug: decide-adopt-a-second-string-model-or-refuse-utf16-honestly
title: "UnicodeString/WideChar: adopt a second string model, or refuse UTF-16 honestly and document it?"
track: U
prio: 62
type: decide
status-note: "DECIDED 2026-08-30 by the owner: adopt a real fixed-width UTF-16 kind. Windows is explicitly NOT a consideration. The coordinator's stride objection was wrong and is retracted in the resolution."
blocked-by: []
status: decided
owner: ""
created: 2026-08-30
found-by: frank-coordinator, escalating feature-unicodestring-model rather than dispatching it
summary: "feature-unicodestring-model [A p62] says in its own body that this is a MODEL DECISION, not a function to write -- and its title offers the alternative outright: a real UTF-16 model, or an honest refusal. pxx has one string model (bytes, CP_UTF8 passthrough) and the RTL is already candid about it at the declaration: UTF8Decode/UTF8Encode are the identity, WideChar casts to a 2-byte ordinal. Adopting UTF-16 is a second model in a compiler whose whole design pushes generality DOWN into one substrate. Refusing means fcl-json's \\uXXXX surrogate path stays uncompilable. Neither is derivable from the code or from a sensible default, so it is Track U."
---


> ### CORRECTION TO THIS RESOLUTION, 2026-08-30 (frankwasm, measured while building it)
>
> **My "worked precedent" argument was wrong on the facts, and the conclusion is
> right for a better reason.** I wrote that `PXX_KIND_TEXTSTR` proved the tag
> mechanism works. Measured: `PXX_KIND_BYTESTR` and `PXX_KIND_TEXTSTR` are
> defined and documented but **never stamped and never read** — every write to the
> kind field in `builtinheap.pas` is `PXX_KIND_LEGACY`. The kind word was dead
> weight. **`WIDESTR` is the first kind ever actually stamped.**
>
> NilPy's character semantics are real — `len("héllo")` is 5 and `t[0]` is 日,
> CPython-exact — but they were achieved by **static typing plus the ASCII flag**,
> not by the kind tag. So the precedent holds for *semantics*, not for the
> mechanism I cited.
>
> **And the "does the two-kind design extend to three?" question I raised
> dissolves.** There is no third semantics. BYTESTR's rule is *Length counts
> storage elements, index yields one element*; WIDESTR is that same rule at element
> width 2. **TEXTSTR is the odd one out — the only kind that decodes.** The axis is
> `elements vs characters`, not `bytes / chars / code units`, and UTF-16 joins the
> side that already exists.
>
> That is also the real reason the stride retraction holds, independently of the
> `elemSize` argument: **the header length was already a BYTE count**, so refcount,
> free, block copy, in-place append and every backend's retain/release blob are
> byte-shaped and work unchanged. Nothing needed a second arm — not because the
> kind machinery existed, but because the byte-counted header made width
> irrelevant to everything except indexing.
>
> **`Length` and `s[i]`, settled against fpc as oracle** (with `{$codepage utf8}` —
> without it fpc widens the raw source bytes, reports 6, and appears to agree with
> pxx, which is an artifact):
>
> | | fpc wide | fpc uni | fpc ansi | pxx today |
> | --- | --- | --- | --- | --- |
> | `Length('héllo')` | 5 | 5 | 6 | 6 |
> | `Ord(w[2])` | 233 (é) | | | 195 (`$C3`) |
>
> So `Length(s)` = UTF-16 **code units** = header bytes >> 1, and `s[i]` yields a
> **WideChar**. fpc-exact.

> ## RESOLUTION, 2026-08-30 — **adopt it. A fixed-width UTF-16 kind, and it is the EASY case.**
>
> Owner: *"(a) we don't care for windows, and (b) I'm not seeing how widestring is
> hard in any way — yes, `Length()` would depend on the actual string type.
> WideChar is already easier than UTF-8. I don't think it's a big issue."*
>
> **Both points land, and my stride objection above is RETRACTED.** I argued that
> 2-byte storage would need a second arm in six backends because stride 1 is baked
> in. Measured, that is wrong: the generic array-index lowering already multiplies
> by `elemSize` — `(IRIVal[indexNode] - lo) * elemSize` in `ir_codegen.inc`, with
> `elemSize` 2/4/8 handled throughout every backend. The `tyAnsiString`/`elemSize = 1`
> test I cited is a **fast path**, not the only path. A 2-byte element rides
> machinery that already exists for `array of Word`.
>
> **And the owner's real point is the decisive one: fixed-width is EASIER than what
> already shipped.** `PXX_KIND_TEXTSTR` — NilPy `str`, variable-width UTF-8 with
> public positions counting CHARACTERS — needs `PXX_FLAG_ASCII`/`ASCII_KNOWN` to
> cache a scan so `len` and indexing stay O(1) in the common case, and falls back to
> scanning when a byte is >= $80. That is the hard case and it is DONE. Fixed-width
> UTF-16 needs none of it: index is `data + i*2` unconditionally, and `Length` is
> the header's byte count shifted right by one. **The expensive string kind was
> already built; this one is strictly cheaper.**
>
> **The Track M argument is struck entirely** — the owner does not care about
> Windows, so the "convert at every `*W` boundary" cost that was doing the work in
> my previous recommendation is not a cost anyone is paying. With it gone, real
> 2-byte storage also wins on the merits it always had: it is FPC's actual layout,
> so `PWideChar` interop is natural rather than a conversion.
>
> ### What the work actually is
>
> - a `PXX_KIND_WIDESTR` alongside BYTESTR/TEXTSTR; header `length` stays a BYTE
>   count, so `Length()` lowers to a shift and every existing memcpy/compare/concat
>   path keeps working unchanged;
> - a `tyWideString` / `tyUnicodeString` static kind so assignment and overload
>   rules work — and specifically so `WideChar(u1) + WideChar(u2)` builds a string
>   instead of adding two ordinals, which is the actual `jsonscanner` wall;
> - literal encoding for a wide literal;
> - conversion helpers at the boundaries, which the owner named up front;
> - `Write`/`Writeln` and file I/O converting on output.
>
> None of that is a second substrate. Track B/library work plus a type kind, as the
> owner said.
>
> ### Sequencing note for whoever schedules it
>
> It touches `defs.inc`, `symtab.inc` and `ir.inc`, which is the same file set as
> `feature-a-typeref-migrate-consumers` — currently held by frankwasm. Queue it
> behind that rather than interleaving.

> ## OWNER INPUT, 2026-08-30 — the groundwork exists, and it narrows the fork to ONE question
>
> Owner: *"we did do some preparation. We added an extra tagging header to each
> string — so all (dynamic) strings can use the same ansistring work. But we are
> free to tag and implement as needed. This also applies to widechar, and all
> unicode variants. If all is well, we can just tag the type, and the rest should
> more or less be library/Track B work. So implementing new string types is
> (almost) free, give or take some conversion helpers."*
>
> **Verified, and substantially right.** `compiler/builtin/builtinheap.pas` carries
> `[kind:8][refcount:8][length:8][data...]` with a META word of
> `BlockKind(8) | Flags(8) | KindData0(8) | KindData1(8)`, bits 32-63 reserved.
> Kinds are defined and LIVE: `PXX_KIND_BYTESTR = 1` (*Length counts BYTES,
> FPC-exact*) and `PXX_KIND_TEXTSTR = 2` (*NilPy str — public positions count
> CHARACTERS*). And there is a **worked precedent**: `feature-nilpy-text-string-kind`
> is in `done/` — NilPy `str` already counts characters over the shared byte
> substrate, with an ASCII flag keeping the common case O(1). A second string
> SEMANTICS has already been added through this header and it worked.
>
> **So the allocation/refcount/lifetime/copy-on-write half — the expensive half —
> is genuinely already paid.**
>
> ### The one thing the tag does not decide: STORAGE WIDTH
>
> `TEXTSTR` differs from `BYTESTR` in how positions are INTERPRETED. The data is
> still bytes, stride 1, UTF-8. That is not the axis UTF-16 needs. So the fork
> collapses to:
>
> | | cost |
> | --- | --- |
> | **UTF-8 internally, UTF-16 only at the boundary** | genuinely near-free, exactly as the owner describes: a kind + conversion helpers, reusing TEXTSTR's machinery. Unblocks `jsonscanner`'s `\uXXXX` surrogate path, which is a byte-OUTPUT problem wearing a UTF-16 hat |
> | **Real 2-byte storage elements (FPC's layout)** | NOT free. Stride 1 is baked into indexing, iteration, comparison and concat in codegen — the backends special-case `tyAnsiString` at `elemSize = 1` (literally, `ir_codegen_xtensa.inc:1677`). Six backends, each needing a second arm: the sibling-arm rule that bit three times on 2026-08-30 alone |
>
> ### What decides it is not JSON — it is Track M
>
> The cheap branch stops being cheap the moment something needs a **real UTF-16
> buffer handed to an external API**: `PWideChar` interop, and specifically the
> Windows `*W` entry points. Track M (MSWindows) is a live campaign. If pxx is
> going to call Windows wide APIs, a UTF-8-internal `UnicodeString` means
> converting at every boundary crossing — which is correct, and is what Go and
> Rust do, but it is a deliberate choice rather than an oversight to discover
> later.
>
> **Revised recommendation: UTF-8 internally + a `UTF16` kind for boundary
> buffers, decided explicitly now rather than discovered by the Windows lane.**
> Also worth settling in the same breath: what `Length(s)` returns and what `s[i]`
> yields for the new kind. BYTESTR/TEXTSTR is a two-way split (bytes vs
> characters); UTF-16 wants a third answer (code units), and the existing design
> should be checked for whether it extends to three cleanly before anything is
> built on it.

# Why this is being escalated rather than worked

`feature-unicodestring-model` is ranked p62 and reads like implementation work. It
is not. Its own body says *"Why this is a model decision, not a function"*, and its
title already carries both branches: **a real UnicodeString / WideChar model
(UTF-16), or an honest refusal.** Dispatching it would mean an agent picking one,
and that choice constrains the language permanently.

## The wall, unchanged since 2026-07-13

`jsonscanner.pp` decodes a `\uXXXX` escape and, for a surrogate pair, does:

```pascal
S := Utf8Encode(WideString(WideChar(u1) + WideChar(u2)));
```

`WideChar(x) + WideChar(y)` is a two-element UTF-16 string. pxx has ONE string
model — bytes — so `WideChar` is a 2-byte ordinal, `+` is integer addition, and
`String(...)` of the result is rejected. **The rejection is correct**; there is
nothing to silently do instead.

## The fork

| option | cost | buys |
| --- | --- | --- |
| **A. Adopt a real UTF-16 model** | a SECOND string model in a compiler whose north star (`ir-as-substrate.md`) is pushing generality down into one substrate. Every backend, every managed-string path, the `PXXStrUnique`/frozen-vs-ansistring split, and the sibling-arm rule that has bitten three times today all get a second arm | `fcl-json`'s `jsonscanner`/`jsonparser` compile; genuine FPC/Delphi source compatibility for `WideChar`/`WideString` code |
| **B. Refuse honestly, document, and move on** | `fcl-json`'s `\uXXXX` surrogate path stays uncompilable, so that corpus item stays out of reach. `fpjson` itself is DONE and unaffected | one string model stays one string model. Consistent with the RTL already being candid at the declaration — `UTF8Decode`/`UTF8Encode` are the identity, `DefaultSystemCodePage` reports `CP_UTF8` because the bytes really do pass through |
| **C. A narrow escape hatch** — a surrogate-pair decoder that produces UTF-8 bytes directly, without a UTF-16 string TYPE | it is a special case, and `normalise-dont-special-case.md` is the note that says the second path is the one that stays broken | unblocks the concrete corpus item without a second model |

## Recommendation

**C, with B as the stated position** — but this is the owner's call and I hold it
weakly.

The compat table in CLAUDE.md is the relevant instrument: *"FPC accepts a form we
reject" → compat, ranked by how much real code uses it.* `WideChar` arithmetic
building a UTF-16 string is not a form much real Pascal reaches for; the specific
thing that wants it is JSON `\uXXXX` decoding, which is a byte-output problem
wearing a UTF-16 hat. So the concrete need can be met without the model, and the
model can stay one.

Against my own recommendation: C is a special case by construction, and this repo
has spent the day proving that special cases are where the rot lives. If the owner
expects real FPC/Delphi corpora to keep arriving with `WideString` in them, A is
the honest answer and the cost should be paid deliberately rather than deferred
one corpus item at a time.

## Why now

frankwasm asked for this ticket, having just finished the wasm string lowering —
`IR_LEA` position dependence, the managed-store path, `PXXStrUnique`, the
frozen-vs-ansistring split — and that context is exactly what option A would
need and is stale within a day. If A is ever going to be chosen, choosing it while
a lane is warm on the string paths is materially cheaper than choosing it later.
That is a scheduling argument, not an argument for A.

---

## Moved to `decided/` 2026-08-30 — the answer AND the implementation are both done

This carried `status: decided` in its frontmatter while sitting in `backlog/`,
so `ready` was still offering it at **p62** — the top of Track U's queue was a
question the owner answered the same day it was asked, and whose implementation
(`feature-unicodestring-model`) closed a few hours later.

Folder and status disagreed and the folder is what the ranker reads. Same shape
as `grant-pasparser-lval-and-rtti-emit-to-frankwasm-for-the-alias-break` retired
tonight: nothing looked broken from either end — the frontmatter was correct,
the resolution was written, the work got done — and the only symptom was a
ranked line nobody could act on.

**The decision was carried out and the acceptance test passes**: `Utf8Encode(
WideString(WideChar(u1) + WideChar(u2)))` produces FPC-identical bytes for both
a BMP pair and a surrogate pair, in a default build with no pxx define. Option B
as decided — one managed-string kind carrying an element width, not a second
kind. See `done/feature-unicodestring-model.md`.
