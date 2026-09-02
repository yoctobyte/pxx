---
track: T
prio: 45
type: bug
status: backlog
found: 2026-09-02
found-by: claude-T
owner: ""
blocked-by: []
summary: "33 open tickets carry no `track:` frontmatter field, 30 of them in RANKED folders. The ranker still lanes them, via a cascade of fallbacks — a `feature-track-t-*` slug prefix, a `Track X` mention in the decl line, a `Track` bullet in the body. Any tool that reads `fm.get('track')` sees nothing for all 33. Two instruments, one answering about a field that is not there. Surfaced when a backlog sweep nearly mis-filed two tickets the ranker had been lanting as T all along; progress.py's own comment records the same class biting in the opposite direction on 2026-07-15."
---

# Lane attribution has two instruments and they disagree

## The two readings

`progress.py`'s track resolution is a **cascade** (`~line 630`):

1. `Track R` in the decl line (the `Type` + `Track` body bullets);
2. slug prefix — `if self.slug.startswith("feature-track-t-"): return "T"`;
3. `Track T` in decl prose, *if* frontmatter `track:` is empty or `T`;
4. only then `explicit = normalize_track(self.fm.get("track", ""))`, and failing
   that, a `Track` bullet from the body.

So the ranker lanes a ticket with **no `track:` field at all**, from the slug or
from prose. A consumer that reads the frontmatter field directly gets nothing.
Both are behaving as written; they are answering different questions.

## Scale — this is not two tickets

Open tickets with no `track:` field:

| folder | count |
|---|---|
| backlog-cfront | 7 |
| backlog-core | 6 |
| backlog-pascal | 4 |
| backlog-libs | 4 |
| unfinished | 3 |
| low-prio | 3 |
| **working** | **2** |
| backlog-tools, backlog-nilpy, backlog_new, blocked | 1 each |
| **total** | **33** (30 in RANKED folders) |

Two are in `working/` — actively claimed, and their lane is inferred rather than
declared.

## How it surfaced, and the prior instance

The 2026-09-02 backlog sweep read the frontmatter field.
`feature-t-nilpy-cpython-differential-fuzzer` and
`feature-twatch-full-tier-coverage-age` have no such field, so they were nearly
swept as unowned while the ranker had been treating them as Track T throughout.
They landed in `low-prio/`, which is recoverable — a folder that deleted, or a
dispatcher that skipped them, would not have been.

`progress.py:637` already records the same disagreement running the **other**
way: a prose "Track T" mention on a fuzzer-filed bug overrode the real lane and
*"stranded three fuzzer-filed A/P bugs under T on 2026-07-15"*
(`bug-t-progress-track-detection-prose-mention`). That was patched by letting an
explicit field break the tie — which fixes the case where the field exists. It
does nothing for the 33 where it does not.

## Why it is worth fixing rather than tolerating

A lane is who gets dispatched. An inferred lane is invisible to anything that is
not the ranker, so every new tool that wants to ask "whose is this?" either
reimplements the cascade or silently disagrees with it. That is the same shape
as `chore-t-split-lib-test-into-jobs-that-name-what-failed` and the
`would_pin`/permission reading: the artefact is not lying, it is answering a
question other than the one being asked.

## Suggested fix

Make the cascade's answer **durable** rather than recomputed: one command that
writes the resolved track back into frontmatter for any ticket lacking it, run
once over the 33, plus a `check` rule that a ranked ticket must carry an explicit
`track:`. That collapses two instruments to one without changing any current
attribution — the cascade stays as the resolver, it just stops being the only
reader that knows.

Positive control if this is taken: `feature-t-nilpy-cpython-differential-fuzzer`
must come out `T` (the ranker's current answer), and none of the 33 may change
lane as a side effect of being written down.
