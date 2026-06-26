# Public documentation conventions

This tree is the **user-facing documentation**, published to the project website
straight from git: the site pulls this repo and renders `docs/`. There is no
separate docs repo and no generated output committed here — just authored
Markdown.

## Owned by Track D

Per `devdocs/dev/parallel-tracks.md`, Track D owns `docs/**` and nothing else.
Prose only — no `compiler/**`, no `lib/**`. A gap found while writing → file a
ticket in `devdocs/progress/backlog`, don't fix code.

## Conventions

- **Plain Markdown + YAML front-matter**, generator-agnostic (any of mkdocs /
  Docusaurus / Hugo / a custom puller can render it). Each page starts with:
  ```yaml
  ---
  title: Page Title
  order: 10        # sort order within its section
  ---
  ```
- **One H1 per page** (the rendered title may come from front-matter instead).
- **Relative links** between pages (`./getting-started/`) so they resolve both
  on GitHub and on the published site.
- **Every code block that claims to work must actually compile and run** on the
  pinned compiler (`stable_linux_amd64/default/pinned`). Paste real output. A doc
  example is a mini conformance test — if it stops compiling, the docs are wrong
  or the compiler regressed (file a ticket).
- Assets (images, etc.) go in `docs/assets/`.

## Layout

```
docs/
  index.md            landing / overview
  install/            installation and setup
  getting-started/    first program and next steps
  features/           user-visible feature overview
  language/           language reference (Pascal basics, dialect, compatibility)
  targets/            native/cross targets and interop
  library/            RTL / standard library reference
  reference/          CLI/configuration/reference material
  guides/             tutorials / how-tos
  assets/             images and other static files
```

Sections grow as the docs do; keep `index.md` linking the live top-level pages.
