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
    # THE THIRD DEFECT, AND THE ONE WITH SIXTY VICTIMS. `.*` is single-line and
    # a bullet's VALUE is not. Confirmed against git on
    # done/bug-c-duktape-double-formatting.md: the bullet read
    # `- **Status:** backlog -- found 2026-07-09, once the segfault was fixed
    # (b30ccf88)` wrapping onto `  and duktape actually ran JS.`, and `resolve`
    # wrote `done` over the first line, DELETING it and orphaning the second.
    # Older than both 2026-09-06 fixes and neither addressed it. There is no safe
    # truncation, so the bullet is left alone and the frontmatter takes the write.
    "wrapped-value-is-not-truncated-frontmatter-takes-the-write": (
        "---\ntrack: T\n---\n\n# t\n\n"
        "- **Owner:** frankB -- took it 2026-08-02 while settling\n"
        "  the link-libc profile / loader-vs-link decision\n",
        lambda out: "took it 2026-08-02 while settling" in out
        and "the link-libc profile / loader-vs-link decision" in out
        and "owner: claude@xeon" in out
        and "- **Owner:** claude@xeon" not in out,
    ),
    # CONTROL. The guard must not fire on an adjacent BULLET, or every claim on
    # an ordinary ticket stops updating the bullet and the two forms drift apart
    # again -- which is the defect f1758c6f4 had just fixed.
    "SINGLE-LINE-annotated-value-is-not-truncated-either": (
        # THE HALF NO CENSUS CAN FIND. `_bullet_value_continues` asks whether the
        # value WRAPPED -- the shape that leaves an orphan behind, which is the
        # shape a scan can see, and NOT the shape that loses text. This bullet
        # has no continuation, so before the trigger was widened it took the
        # ordinary single-line path and `.*$` ate the date with nothing left
        # over to notice it by. 67 board-wide, 26 of them OPEN.
        "---\ntrack: U\nstatus: backlog\n---\n\n# t\n\n"
        "- **Status:** backlog \u2014 opened 2026-07-12.\n",
        lambda out: ("- **Status:** backlog \u2014 opened 2026-07-12." in out
                     and "\nstatus: done\n" in out),
        "Status", "done",
    ),
    "double-hyphen-is-the-same-separator": (
        "---\ntrack: T\nstatus: backlog\n---\n\n# t\n\n"
        "- **Status:** backlog -- found 2026-07-09 (commit b30ccf88)\n",
        lambda out: ("commit b30ccf88" in out and "\nstatus: done\n" in out),
        "Status", "done",
    ),
    "a-BARE-value-is-still-replaced-IN-THE-BULLET": (
        # NEGATIVE CONTROL for the widened trigger, and the one that matters:
        # no annotation and no continuation means nothing the tool cannot
        # interpret, so the bullet write must still happen. If this regressed,
        # every ordinary claim would stop updating the bullet and the two forms
        # would drift apart again -- the defect f1758c6f4 had just fixed.
        "---\ntrack: T\n---\n\n# t\n\n- **Status:** backlog\n",
        lambda out: "- **Status:** done" in out and "backlog" not in out,
        "Status", "done",
    ),
    "a-HYPHENATED-value-is-not-an-annotation": (
        # ` -- ` needs surrounding whitespace. A hyphen inside a value must not
        # read as a separator, or an owner like `frank-optimize` would freeze
        # the bullet forever.
        "---\ntrack: T\n---\n\n# t\n\n- **Owner:** frank-optimize\n",
        lambda out: "- **Owner:** claude@xeon" in out and "frank-optimize" not in out,
    ),
    "an-adjacent-bullet-is-not-a-continuation": (
        "---\ntrack: T\n---\n\n# t\n\n- **Owner:** \n- **Track:** T\n",
        lambda out: "- **Owner:** claude@xeon" in out and "- **Track:** T" in out,
    ),
}


def main() -> int:
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="setfield-devtest-"))
    failed = []
    for name, case in CASES.items():
        # (text, extra) writes Owner; (text, extra, marker, value) picks a field.
        text, extra = case[0], case[1]
        marker, value = (case[2], case[3]) if len(case) == 4 else ("Owner", "claude@xeon")
        p = tmp / f"{name}.md"
        p.write_text(text, encoding="utf-8")
        progress.set_field(p, marker, value)
        out = p.read_text(encoding="utf-8")
        ok = value in out and extra(out)
        print(("  ok   " if ok else "  FAIL ") + name)
        if not ok:
            failed.append(name)
            print("    got: " + repr(out))
    print("FAILED: " + ", ".join(failed) if failed else "all set_field cases pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
