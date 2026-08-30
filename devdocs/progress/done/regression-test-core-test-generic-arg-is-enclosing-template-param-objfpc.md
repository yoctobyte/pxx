---
prio: 70
track: P
status: done
owner: frankA
---

> **Track guessed as P** from the test source. The ranker reads frontmatter, so this line — not the body — decides who works it; correct it if the guess is wrong.

> **origin/master has advanced 11 commit(s) since this sha.** Re-verify at current HEAD before acting — the callback is tagged to the sha that was tested, which may no longer be the state of the tree.

# regression: test-core#src:test/test_generic_arg_is_enclosing_template_param_objfpc.pas red at 1d8b44e59042 (auto-filed by twatch)

- **Type:** regression (auto-filed by Track T watcher, host plexus). Untriaged.
- **Found:** 2026-08-30T02:19:22Z
- **Test source:** test/test_generic_arg_is_enclosing_template_param_objfpc.pas tools/expect_same.sh

## Repro
`tools/testmgr.py --tier native --job 'test-core#src:test/test_generic_arg_is_enclosing_template_param_objfpc.pas'` at 1d8b44e590426d333f7936404e0235b83ccdf7af

## Range
> **The named sha `1d8b44e59042` CANNOT be the cause** — it touches no buildable file (docs / tickets / tstate only). It is the sha that was TESTED, i.e. the upper bound of an untested range; the cause is somewhere below it.

bad `1d8b44e59042`, last good `0bcef8f3f2ab`, 3 commit(s) in range — the watcher narrows this by idle bisect; check tstate/TSTATE.md for the current range.

## Log tail
```
pascal26:16: error: unknown type: TKey
(tail)
pascal26:16: error: unknown type: TKey
  near: TKey   class Val  >>> TKey  end 

```

*Stub ticket: signal only. Track T agent (face 2) enriches or a dev track
takes it from the repro line.*

---

## RESOLVED, 2026-08-30 (frankA, Track P) — the track guess was right, the "one root bug" guess was not, and the cause was MINE

**Lane confirmed: P.** The frontmatter guess stands; this is the Pascal generic
sweep in `pasparser_generic.inc`.

### It is a regression I introduced, in `8b85e4881`, four hours ago

A/B across four binaries, on this ticket's own test:

| binary | verdict |
| --- | --- |
| `pinned` | FAIL `16: unknown type: TKey` |
| `a60f92ba830a` (HEAD before my whitelist) | **ok** |
| `22c67e5ea61e` (HEAD after my whitelist) | FAIL |
| HEAD + the fix below | **ok** |

So it was broken, fixed by someone between `pinned` and `a60f92ba830a`, and
**re-broken by me**. Note the watcher filed this at 02:19 and my commit landed at
04:08 — the auto-filed red is the *earlier* instance, and HEAD is red for a
different, newer reason wearing the same message. Two causes, one error string.

### Cause: my whitelist asserted a limit that is false in objfpc

shard0-6-2's fix tests what precedes a generic header's name, and I wrote:

> *A declaration's left-hand side can only follow the `type` keyword or the `;`
> that ended the previous declaration.*

That is true of the **Delphi** surface and false of **objfpc**, which writes
`generic TDict<TKey, TValue> = class` — preceded by `generic`, which lexes as an
ordinary `tkIdent`. Every objfpc header therefore failed the header test, its
parameters were never harvested, and `C: specialize TCmp<TKey>` was minted as a
CONCRETE specialization instead of being deferred — so `TCmp`'s own `Val: T`
streamed as `Val: TKey` and came back `unknown type: TKey` at line 16, inside a
declaration that is fine.

Fixed by adding the `generic` arm. Measured, not assumed: the **Delphi spelling
of the identical shape passes on all four binaries above and on FPC** — which is
precisely why it never showed up.

### The control lesson, and it is the same one twice in one night

`test_generic_bound_name_harvest.pas` tested only the **over-collect** direction
(a use must not donate its arguments). The **under-collect** direction — a
genuine header's parameters must still BE collected — was never asserted, so a
whitelist that rejected every objfpc header passed it.

A whitelist can fail in two directions and I controlled one. This is the second
time tonight my control set was drawn from the same idea as the fix; the first
was `bug-p-...-shadowing-declaration-as-a-use`, where I tested a blacklist with
the one spelling it already handled. **Both directions are asserted now**, in
that same file, with the asymmetry written into its header.

### The "fourth symptom" hypothesis is a NEGATIVE — worth stating plainly

The dispatch suggested this might fold into
[[bug-p-a-nested-type-of-the-enclosing-template-is-minted-as-a-concrete-generic-argument]]
as a fourth symptom of one unscoped blacklist. **It does not.** At HEAD, after
this fix:

- this ticket's test — **passes**
- `test/test_generic_nested_type_as_argument.pas` — still fails, and with a
  *different* error: `35: unknown type: TPair`, not `TKey`

That file is also no longer failing the way pxx-a5 recorded it (`unknown type:
PT`); my bodyless-generic fix `8e4d175d2` moved it. So the count of symptoms
behind that root ticket is smaller than three, and its remaining repro has
shifted twice tonight. **Whoever takes it should re-reduce before trusting any
error text in it.**

### Verified

- `tools/gate.sh quick` **GREEN**; self-host fixedpoint `eb3b0fd5c642`.
- This ticket's test: `ok objfpc inline specialize` / `total ok 1 / 1`.
- The updated harvest test fails on the broken binary `22c67e5ea61e`
  (`69: unknown type: TKey`) and passes here — so the new arm demonstrably
  catches the regression rather than merely accompanying the fix.
- Every earlier guard still green: `boundharvest 45 A 10 1111111111`,
  `shadow 12 10`, `ptrspec 7 1`, `bodiless 7 3 1`.
- Oracle: FPC prints the same line for the harvest test.
- 2026-08-30 — resolved, commit aadd83621.
