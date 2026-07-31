---
track: T
prio: 30
type: bug
---

# `progress.sh claim`/`resolve` silently no-op when a ticket lacks the expected body line

- **Type:** bug (tooling) — **Track T** (T owns `tools/progress.py`)
- **Found:** 2026-07-31, working `bug-pascal-transitive-unit-crashes-at-startup-unless-named-first`.

`cmd_claim` (`tools/progress.py`) calls `set_field(dst, "Owner", args.owner)`,
which only works by REGEX-REPLACING an existing `- **Owner:** ...` line in the
ticket's Markdown body:

```python
def set_field(path: Path, marker: str, value: str) -> None:
    text = path.read_text(encoding="utf-8")
    pat = re.compile(rf"^(\s*-?\s*\*\*{re.escape(marker)}:\*\*\s*).*$", re.I | re.M)
    text = pat.sub(rf"\g<1>{value}", text, count=1)
    path.write_text(text, encoding="utf-8")
```

If the ticket file has no such line to begin with (many tickets, including the
one that surfaced this, only have a `- **Type:** ...` line and nothing for
Owner/Status), `pat.sub` matches nothing and silently writes the file back
UNCHANGED. `cmd_claim` still prints `"claimed <slug> -> working/ (owner:
<owner>)."` and exits 0 — there is no signal that the write did nothing.
`tools/progress.sh check` later flags `NO-OWNER: <slug> is in working/ but has
no Owner`, which is the first (and only) sign anything went wrong, potentially
much later and in a different session than the one that ran `claim`.

## Repro

Any ticket file whose body has no existing `- **Owner:**` (or `- **Status:**`)
line, run through `claim`: the tool reports success, the file is unchanged.

## Fix direction

`set_field` should INSERT the field (e.g. right after the frontmatter's
closing `---`, or as a new body line near the top) when no existing line
matches, not silently no-op. Same applies to `Status`. Worth an assertion/log
when the substitution count is 0, at minimum, even if the insert-when-missing
behavior needs more design (where exactly to insert, matching the varied
ticket body conventions already in the tree).

## Gate

`tools/testmgr.py --tier full` per T's own tooling gate; a quick regression:
`claim` on a ticket with no existing Owner/Status line, assert the file
actually gained one and `check` reports no NO-OWNER for it.
