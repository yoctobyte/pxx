---
slug: bug-a-a-case-of-string-on-a-widestring-matches-nothing-under-pxx-wide-payload
title: "case-of-string on a WideString matches nothing under {$define PXX_WIDE_PAYLOAD}"
track: A
prio: 35
type: bug
blocked-by: []
status: open
owner: ""
created: 2026-09-07
found-by: frankS
summary: "`ws := 'abc'; case ws of 'abc': ...` takes the branch by default and under fpc, and takes NO branch under -dPXX_WIDE_PAYLOAD. Pure ASCII, so it is not the encoding question the chore ticket exists to settle. It is the ENTIRE blast radius of forcing the define across the conformance corpus: 406 pass / 5 fail against 411 / 0, and all five failures (tcase0/12/13/28/29) are this one mechanism. Cause not measured -- print the widths the comparison receives before fixing."
---

# A case-of-string on a WideString matches nothing under {$define PXX_WIDE_PAYLOAD}

```pascal
var ws: widestring;
begin
  ws := 'abc';
  case ws of
    'abc': i := 1;
  end;
end.
```

| | result |
| --- | --- |
| pxx, default | `match=1` |
| fpc 3.2.2 | `match=1` |
| pxx, `-dPXX_WIDE_PAYLOAD` | **`match=0`** |

**The repro is pure ASCII, and that is the point.** This is not the UTF-8 versus
UTF-16 semantics question that
[[chore-a-decide-whether-widestring-can-come-out-from-behind-pxx-wide-payload]]
exists to settle — on ASCII both readings agree about content, so nothing here
turns on which reading is right. Whatever the cause, it is not an
encoding-semantics divergence, and it needs no non-ASCII data to reproduce or to
fix.

**MEASURED vs INFERRED, kept apart deliberately.** Measured: the three rows in
the table above, and that all five corpus failures are case-of-string on wide
selectors. NOT measured: *why*. The obvious reading is that the labels stay
narrow while the selector becomes UTF-16 under the define, so the comparison
runs at two different widths — but that is a guess from the shape, nobody has
printed the label's width, and the last time this campaign guessed at a width
question the answer was three bugs that survived an ASCII probe. Print what the
comparison actually receives before fixing it.

## Why it matters now

It is **the entire blast radius of step 1** of that chore ticket. Forcing the
define across the conformance corpus (frankS, 2026-09-07, compiler
`19bee89a03e6`) gives `406 pass, 5 fail` against a `411 / 0 / 89` baseline, and
all five failures are this one mechanism:

    tcase0.pp  exit 12 (want 0)     tcase12.pp exit 1     tcase13.pp exit 1
    tcase28.pp exit 1               tcase29.pp exit 1

All five declare `widestring` and `unicodestring` and case on them; none is a
compile error. `tcase0.pp` is the readable one — it cases the same
embedded-NUL string through `string`, `shortstring`, `widestring` and
`unicodestring`, clearing one bit of its halt code per type. **Exit 12 is bits 4
and 8**: the narrow two match and the two wide ones do not.

The chore ticket's rule is *"if it finds a handful, they are ordinary bug tickets
and this stays open behind them"*. This is the handful, and it is one bug rather
than five.

## What it does NOT establish

The other 406 rows passing under the define is **not** evidence that the define
is safe for them. The corpus is overwhelmingly ASCII, where a UTF-8 byte count
and a UTF-16 unit count are the same number — the chore ticket records three
bugs in that campaign surviving on exactly that reading. A red under the define
is informative; a green is not. Steps 2 and 4 over `lib/**` and `examples/**`
with non-ASCII data remain unrun.
