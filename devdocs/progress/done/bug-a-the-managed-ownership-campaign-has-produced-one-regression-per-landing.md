---
slug: bug-a-the-managed-ownership-campaign-has-produced-one-regression-per-landing
track: A
prio: 85
type: bug
blocked-by: [bug-a-pointer-cast-of-an-owned-string-retains-it-for-the-rest-of-the-program]
status: done
found: 2026-09-01
found-by: frankZ
owner: unassigned
summary: "Four of the six reds standing between the tree and a green full tier are four landings of one campaign — the managed-ownership seam — and each one's bisect window holds exactly one buildable commit, which is that campaign's. Same session, same evening, five fixes, four new reds. The individual bugs are worth fixing; the finding is the RATE, and it is only visible from a lane that reads the whole red set."
---

# The managed-ownership campaign is producing one regression per landing

Measured 2026-09-01 by frankZ at `db706c2da`, binary `59699dc0833f8110`, from
Track T's bisect windows on seven plus local reproduction of each.

## The table is the whole ticket

| red | the ONE buildable commit in its bisect window | that commit's subject |
| --- | --- | --- |
| `test-threads#test_threadsafe_refcount_lockfree` (`fail=3`, 5/5) | `b788c5865` | one helper for the string-to-pointer ownership seam, and the three that were still leaking |
| `test-core#test_rtl_fpc_compat_helpers` (SIGSEGV) | `65e15e5ab` | give a dynamic array reaching a pointer destination an owner too |
| `test-core#test_interface_byval_param_no_leak` (24/25) | `1308ef1f8` | release an interface function result, and flush a bare loop body |
| `test-threads#test_exception_threads_race` (SIGSEGV, 3/3) | `620989250` | every caught exception object leaked on every backend, both Pascal shapes |

A fifth landing in the same campaign, `4af4645ba` *"a discarded managed
function result had no owner, so it just leaked"*, sits among them.

**All five carry the same `Claude-Session` id.** One session, one evening, one
seam, five fixes, four new reds — and each red's window was narrowed by Track
T independently of this reading.

Each failure lands squarely on its own commit's subject, which is what makes
the attribution more than a coincidence of ordering:

- `refcount_lockfree` reads the count through `PWord(Int64(Pointer(v)) - 16)^`
  — **through the pointer cast `b788c5865` changed** — and exactly the three
  `rc=1` rows fail while the saturation rows pass.
  [[bug-a-pointer-cast-of-an-owned-string-retains-it-for-the-rest-of-the-program]]
- `rtl_fpc_compat_helpers` faults at `DynArraySize+79` (read off its own
  `--proc-map`), after every row has printed and before the summary — a
  **dynamic array** header read during teardown, against `65e15e5ab`.
  Reproduces only with `-Fulib/rtl`, which is what the recipe passes; without
  it the same source exits 0.
- `interface_byval_param_no_leak` fails one row of 25:
  `timing: nested call, function-result temp still holds it = 1 want 0` — an
  **interface function-result temp**, against `1308ef1f8`.
- `exception_threads_race` faults at `PXXClassFinalizeManaged+119` — finalising
  a class's **managed fields**, i.e. the exception object's, against
  `620989250`, which changed who frees a caught exception. Deterministic 3/3,
  no output at all, so it dies before the first of its two rows.

## Why this is a ticket and not four

`b788c5865`'s own header already says it: *"SIXTH, SEVENTH AND EIGHTH INSTANCE
OF ONE SHAPE... Three was already a design flaw; eight settles what the common
cause is."* It is right about the ORIGINAL defect. What it does not say — and
could not, from inside one commit — is that the generalisation is landing at a
rate of about one new red per fix.

That is a rate nobody in the campaign can see. Each session sees its own
commit go green against its own repro; the next tier sweep attributes the red
to whoever reads it next. **It took a lane holding the whole red set at once
for the four to line up**, which is the argument for having one.

Nothing here says the campaign is wrong or should stop. Eight instances of one
shape is exactly the thing worth generalising, and
`devdocs/dev/root-cause-over-microfix.md` says the overhaul is usually the
smaller job. The claim is narrower and it is about VERIFICATION: a change to
where ownership is decided reaches every managed type, and the per-fix gate
(`make compiler/pascal26` plus one repro) cannot see it, because `compiler.pas`
exercises almost none of the managed surface. Five landings, five green gates,
four reds.

## The cheap thing that would have caught all four

The four failing programs cost well under a minute between them and none needs
the full tier:

```
./compiler/pascal26 -Fulib/rtl test/test_rtl_fpc_compat_helpers.pas        /tmp/a && /tmp/a
./compiler/pascal26 --threadsafe test/test_threadsafe_refcount_lockfree.pas /tmp/b && /tmp/b
./compiler/pascal26 test/test_interface_byval_param_no_leak.pas            /tmp/c && /tmp/c
./compiler/pascal26 --threadsafe test/test_exception_threads_race.pas      /tmp/d && /tmp/d
```

`-Fulib/rtl` is load-bearing on the first — without it the crash does not
happen — which is its own small lesson about carrying the recipe's flags into
a repro.

Whether that belongs in `gate.sh quick` or as a habit for this campaign is a
judgement for whoever owns the seam, not for me.

## Not claimed

Filed, not fixed. The seam is under active generalisation by one session and a
second pair of hands in it would be the tenth instance of the shape rather
than a fix. Blocks [[umbrella-one-full-tier-run-with-no-red-tier]].

## Resolved — all four green

All four reproduced at HEAD exactly as filed, and all four are green at
`d5e0a1e48`:

| program | before | after |
| --- | --- | --- |
| `test_rtl_fpc_compat_helpers` | SIGSEGV | 23 / 23 |
| `test_threadsafe_refcount_lockfree` | fail=3 | fail=0 |
| `test_interface_byval_param_no_leak` | 24 / 25 | 25 / 25 |
| `test_exception_threads_race` | SIGSEGV | rc=0 |

Two causes, not four. Three of them were one: the park fired on already-owned
values, whose release lands at the enclosing scope's exit. The fourth was the
interface function-result temp sitting on the end-of-statement queue when FPC
holds it to scope exit.

**The verification claim is the part worth keeping, and it was right.** An
ownership change reaches every managed type, and `make compiler/pascal26` plus
one repro cannot see it — `compiler.pas` exercises almost none of the managed
surface. Five landings, five green gates, four reds. CLAUDE.md already says the
fixedpoint cannot see a construct the compiler never writes; the commits that
caused this quoted that rule and still did not run four programs costing under a
minute between them. `-Fulib/rtl` being load-bearing on the first is exactly the
kind of thing that makes a repro set worth writing down rather than
reconstructing.

Fixed in commit d5e0a1e48.

## Log
- 2026-09-01 — resolved; this names the commit that carried the resolve, which is not always the one that carried the change — commit PENDING-COMMIT.
