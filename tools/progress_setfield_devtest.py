#!/usr/bin/env python3
"""Devtest for progress.set_field — the write path behind `claim` / `resolve`.

Guards a SILENT failure: set_field used to only replace an existing
`- **Marker:** ...` bullet, so a YAML-frontmatter-only ticket was written back
unchanged while the CLI printed success. On a two-box fleet the claim is the
distributed mutex, so a claim that does not stick means two agents doing the
same work (bug-t-claim-silently-no-ops-owner-on-yaml-only-tickets).

No repo state touched: temp files only.
"""
import pathlib
import sys
import tempfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import progress  # noqa: E402

CASES = {
    # name:            (input, extra assertion on the result)
    "yaml-only": (
        "---\ntrack: T\nprio: 45\ntype: bug\n---\n\n# title\n\nbody\n",
        lambda out: out.startswith("---\ntrack: T\nprio: 45\ntype: bug\nowner: claude@xeon\n---"),
    ),
    "yaml-with-existing-key": (
        "---\ntrack: T\nowner: old-agent\nprio: 45\n---\n\n# title\n",
        lambda out: "old-agent" not in out,
    ),
    "bullet-style-preserved": (
        "---\ntrack: A\n---\n\n# title\n\n- **Owner:** old-agent\n- **Type:** bug\n",
        # a ticket that uses the bullet form keeps it — no duplicate YAML key
        lambda out: "- **Owner:** claude@xeon" in out and "owner:" not in out.split("# title")[0],
    ),
    "no-frontmatter": (
        "# title\n\nplain body, no frontmatter at all\n",
        lambda out: out.startswith("---\nowner: claude@xeon\n---\n"),
    ),
    "EMPTY-bullet-is-filled-in-place-not-below-the-blank-line": (
        # THE NEWLINE BUG, BOTH SIDES. `park` writes an EMPTY bullet by design.
        # With `\\s*` spanning newlines, set_field then matched
        # `- **Owner:** \\n\\n` and wrote the value AFTER the blank line -- a bare
        # word floating in the prose with the bullet still empty -- and
        # first_bullet_value read that stray line back, so the round trip was
        # self-consistent and produced a corrupt file. Measured live 2026-09-06
        # on feature-pascal-corpus-fpc-testsuite: a `claim` after a `park` put
        # `frankS` on its own line two lines below an empty Owner bullet.
        "---\ntrack: P\n---\n\n# title\n\n- **Owner:** \n\nBody prose starts here.\n",
        lambda out: ("- **Owner:** claude@xeon" in out
                     and "\n\nclaude@xeon\n" not in out
                     and "Body prose starts here." in out),
    ),
    "an-EMPTY-bullet-reads-as-EMPTY-not-as-the-next-paragraph": (
        # The read side on its own. Nothing is written here that matters; the
        # assertion is about what first_bullet_value says of the INPUT shape.
        "---\ntrack: P\n---\n\n# title\n\n- **Track:** \n\nfrankS\n",
        lambda out: progress.first_bullet_value(
            "---\ntrack: P\n---\n\n# t\n\n- **Track:** \n\nfrankS\n", "Track") == "",
    ),
    "prose-decoy": (
        # a `owner:`-looking line in PROSE must not be mistaken for the field
        "---\ntrack: T\n---\n\n# title\n\nThe log said `owner: someone-else` in prose.\n",
        lambda out: "owner: someone-else" in out
        and out.startswith("---\ntrack: T\nowner: claude@xeon\n---"),
    ),
}


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="setfield-devtest-"))
    failed = []
    for name, (text, extra) in CASES.items():
        p = tmp / f"{name}.md"
        p.write_text(text, encoding="utf-8")
        progress.set_field(p, "Owner", "claude@xeon")
        out = p.read_text(encoding="utf-8")
        ok = "claude@xeon" in out and extra(out)
        print(("  ok   " if ok else "  FAIL ") + name)
        if not ok:
            failed.append(name)
            print("    got: " + repr(out))
    print("FAILED: " + ", ".join(failed) if failed else "all set_field cases pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
