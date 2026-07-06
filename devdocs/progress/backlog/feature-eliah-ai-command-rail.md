---
prio: 45  # auto
---

# feature: Eliah AI command rail + console pane

- **Type:** feature (Track B)
- **Status:** backlog (suggestion — deferred)
- **Track:** B
- **Parent:** feature-eliah-shell
- **Opened:** 2026-06-24

## Goal

An AI agent as a first-class **command source** on Eliah's existing command
surface: a console pane where natural-language requests ("link the OK button's
click to SaveFile") are turned into the same selection/command operations a menu
or shortcut issues — no layout or mode special-casing.

## Why deferred

The command surface + shared selection model already exist and are exercised by
the `Link` and `Wire OnClick` commands (see
`devdocs/developer/eliah-command-surface.md`). An AI rail mainly adds **networking +
a request/response protocol**; it does not deepen the local designer/editor
testing loop, so it is split out as a suggestion rather than blocking M5.

The one genuinely new capability it would exercise is the **networking stack**
(HTTP client / streaming to a model endpoint) — useful as a real consumer of the
RTL's networking if/when that is a priority.

## Scope (when picked up)

- A console pane (input + transcript) wired as another command source.
- A thin command protocol: parse/route an instruction to existing commands
  (select <name>, wire <comp>.<event> -> <target>, rename, …) on the shared model.
- Networking to a model endpoint (Claude API) — the actual new infrastructure.
- No new mutation paths: everything goes through the same `THandler` commands +
  `garin` logic the menus use, so AI actions are undoable + identical to manual.

## Acceptance

Typing an instruction in the console performs the same operation as the
equivalent menu/shortcut command, through the shared selection model; the
networking path is covered; no command logic is duplicated for the AI source.

## Log
- 2026-06-24 — filed as a suggestion while finishing M5; AI deferred per the
  decision that it adds little to local testing beyond networking.
