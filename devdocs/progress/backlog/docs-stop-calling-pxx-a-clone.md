---
prio: 30
---

# Track D: stop calling PXX a "clone" in the docs

- **Track:** D (docs)
- **Found:** 2026-07-15 (Track W). Maintainer directive: **never** describe PXX
  as a clone — of FPC, Delphi, or anything. It is a from-scratch implementation
  that *targets* compatibility, not a fork/port/clone of anyone's code. Calling
  it a "clone" (even "not a full FPC clone") misrepresents the project.

## Offending lines

- `docs/language/dialect.md:9` — "…for many implemented features, but it is not
  a full FPC clone and it also has PXX-specific extensions." (renders on the
  website's PXX-dialect page)
- `docs/reference/limits.md:22` — "PXX is not a full Free Pascal clone."

(`docs/install/index.md:12` uses `git clone` — a shell command, leave it.)

## Suggested fix

Reword without "clone", keeping the real point (it's not a full FPC
reimplementation of everything):

- dialect.md: "…tracks FPC behaviour for many implemented features, and adds
  PXX-specific extensions on top." (drop the "clone" clause entirely)
- limits.md: "PXX does not reimplement the full Free Pascal language and RTL."

## Rule going forward

Prefer "from-scratch implementation targeting FPC compatibility" / "tracks FPC
behaviour for implemented features". Never "clone".
