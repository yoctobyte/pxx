# docs/site — public documentation (Track C)

This tree is the **user-facing documentation**, published to the project website
straight from git: the site pulls this repo and renders `docs/site/`. There is no
separate docs repo and no generated output committed here — just authored
Markdown.

## Owned by Track C

Per `docs/dev/parallel-tracks.md`, Track C owns `docs/site/**` and nothing else.
Prose only — no `compiler/**`, no `lib/**`. A gap found while writing → file a
ticket in `docs/progress/backlog`, don't fix code.

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
- **Relative links** between pages (`./getting-started.md`) so they resolve both
  on GitHub and on the published site.
- **Every code block that claims to work must actually compile and run** on the
  pinned compiler (`stable_linux_amd64/default/pinned`). Paste real output. A doc
  example is a mini conformance test — if it stops compiling, the docs are wrong
  or the compiler regressed (file a ticket).
- Assets (images, etc.) go in `docs/site/assets/`.

## Layout

```
docs/site/
  index.md            landing / overview
  getting-started.md  install + first program
  language/           language reference (types, classes, properties, …)
  library/            RTL / standard library reference
  guides/             tutorials / how-tos
  assets/             images and other static files
```

Sections grow as the docs do; keep `index.md` linking the live top-level pages.
