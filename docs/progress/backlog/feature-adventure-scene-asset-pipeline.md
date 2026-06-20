# Adventure scene asset pipeline

- **Type:** feature
- **Status:** backlog
- **Owner:** —
- **Opened:** 2026-06-20
- **Blocked-by:** feature-image-ascii-renderer-library
- **Relation:** Demo integration ticket. The reusable work belongs in Track B
  libraries; the adventure engine should stay thin and data-driven.

## Goal

Add optional visual scene assets to `examples/adventure` without moving image
processing into the game. Source assets live outside the Pascal engine; the
runtime consumes pre-rendered ANSI scene files.

## Asset layout sketch

```text
examples/adventure/prompts/
  cpu_die.md
  ram_bank.md

examples/adventure/scenes/
  cpu_die/
    neon-terminal.png
    technical-illustration.png
    pixel-art.png

examples/adventure/scenes_ansi/
  cpu_die_neon-terminal.ansi
  cpu_die_technical-illustration.ansi
  cpu_die_pixel-art.ansi
```

## World integration

Extend `world.dat` with an optional field:

```text
scene = cpu_die
```

The engine should:

- load a matching `.ansi` scene when present;
- pick one variant deterministically from the game seed or room id;
- fall back to the existing built-in ASCII art if no scene file exists.

## Acceptance

- At least three rooms have prompt files with multiple rendering suggestions.
- At least one room has two or more `.ansi` variants.
- The game remains playable without any scene files.
- The adventure engine only loads and prints `.ansi`; PNG decoding/conversion
  stays in library/tooling tickets.

## Notes

- This intentionally makes the demo more attractive while preserving the
  library boundary.
- Runtime PNG decoding is not required for this ticket.

