# Bug tracking

Lightweight, file-based bug tracker. One bug per Markdown file. The **folder is
the status** — moving a file between folders is the only state change.

## Folders (lifecycle)

| Folder | Meaning |
| --- | --- |
| `discovered/` | Reported, not yet being worked. Holds the symptom + repro. |
| `working/` | Someone is actively fixing it. |
| `fixed/` | Resolved. Keep the file as a record; note the fix and any regression test. |
| `unfixed/` | Parked: wontfix, deferred, blocked, or can't-reproduce. Say why. |

Normal flow: `discovered/` → `working/` → `fixed/`. A bug may instead land in
`unfixed/` from anywhere.

## File convention

- Name: `YYYY-MM-DD-short-slug.md` (discovery date + a slug). The name does not
  change when the file moves between folders.
- Start with a `#` title, then `**Found:**` and `**Status:**` lines.
- Include a **minimal repro** and, once known, the **workaround** and
  **suspected cause**.
- When moving to `fixed/`, append a `## Fix` section: commit hash, what changed,
  and the regression test that now covers it.

## How agents use it

- New correctness bug found mid-task: drop a file in `discovered/` (don't derail
  the current task to fix it unless asked).
- Picking one up: `git mv` it to `working/`, edit as you learn more.
- Done: add the `## Fix` section and `git mv` to `fixed/`.

These files are docs only — adding/moving them does not touch compiler source,
so they skip the self-host gate.
