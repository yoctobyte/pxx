---
slug: bug-t-claim-truncates-a-prose-status-line-the-guard-against-it-runs-first
track: T
prio: 45
type: bug
status: new
owner: ""
blocked-by: []
summary: "MEASURED on a live ticket. `progress.sh claim` replaces a prose `- **Status:** <word> — <explanation>` bullet with the single word `working`, destroying the explanation. The guard against exactly this EXISTS, is correct, and RUNS -- `sync_status_to_folder` (progress.py:2676) matches only the bare one-word form and its comment says truncating an explanation is worse than a stale word. It is called by `move_ticket`, declines correctly, and is then OVERWRITTEN one line later by `set_field(dst, \"Status\", \"working\")` (:3019), whose pattern ends `.*$` and has no guard at all. Two mechanisms for one concept; the guarded one loses. `resolve` and `unfinish` (:3114, :3210) take the same path."
---

# `claim` truncates a prose Status line, and the guard against it runs first

- **Found:** 2026-08-31 by frankA (Track A), claiming
  `feature-signal-siginfo-ucontext`. **Track T's file — not edited.**
- **Not hypothetical.** That ticket has no frontmatter `summary`, so its body
  Status line was the only routing information a reader had.

## Measured

```
$ tools/progress.sh claim feature-signal-siginfo-ucontext frankA
$ diff <(git show HEAD^:.../unfinished/<slug>.md) <(git show HEAD:.../working/<slug>.md)
-owner: claude-acp
+owner: frankA
-- **Status:** unfinished — items 1 (SA_SIGINFO/ucontext) and 3 (sigaltstack) DONE; item 4's compiler half done (__pxxSigNum), its RTL half is Track B. Items 2 (--threadsafe) and 5 (SIGPIPE) remain, plus parking the signal number on the other four targets.
+- **Status:** working
```

Restored by hand. Nothing warned; `claim` printed success.

## The mechanism, and why it is worth more than a one-line fix

`progress.py` has **two** functions that write that bullet:

| | pattern | guarded? |
| --- | --- | --- |
| `sync_status_to_folder` :2676 | `^(\s*-\s*\*\*Status:\*\*\s*)(\w+)\s*$` | **yes** — one bare word only |
| `set_field` :2750 | `^(\s*-?\s*\*\*Status:\*\*\s*).*$` | **no** — `.*$` eats the line |

`move_ticket` calls the guarded one (:2731). `claim` then calls the unguarded
one (:3019) **on the next line**. So the guard is not missing, not stale, and
not wrong — it runs, it correctly declines, and it is immediately overwritten.

Its own comment states the intended policy exactly:

> Only the bare `- **Status:** word` form. A bullet that continues into a
> sentence ("unfinished -- agent half done, parked awaiting X") is prose
> carrying a reason, and silently truncating someone's explanation to one word
> is a worse outcome than a stale word.

That policy is correct and is currently unenforceable, because a second
mechanism serving the same concept does not know about it.
`devdocs/dev/normalise-dont-special-case.md` calls the shape: two paths for one
concept, and the second is the one that stays broken.

## Suggested shape, T's call

`set_field` is right for `Owner` — one value, whole-line replacement is what you
want — and wrong for `Status`, which carries prose. Either give `set_field` the
same one-word condition when `marker == "Status"`, or drop the three
`set_field(..., "Status", ...)` calls entirely and let `move_ticket`'s
`sync_status_to_folder` be the only writer (it already runs on every path that
moves a ticket, which is every path that changes status).

The second is smaller and deletes a case rather than adding one.

**Whichever way: the guard needs a positive control** — a test asserting a prose
Status line SURVIVES a claim. The current guard has never been able to protect
anything through `claim`, and nothing said so.

`resolve` (:3210) and the `unfinished` path (:3114) call `set_field` the same
way and have the same exposure — **and `resolve` was then observed doing it, in
the same session, on the same ticket**: a restored 6-line Status bullet was
flattened to the bare word `done` an hour after the `claim` instance. So this is
not one command with an oversight; it is the shared writer, and both callers
reproduce it on demand. That also makes the positive control easy to specify:
claim a ticket with a prose Status line, resolve it, and assert the prose
survived both.

## Related

- [[a-documented-trap-is-not-a-guard]]
- `devdocs/dev/normalise-dont-special-case.md`
