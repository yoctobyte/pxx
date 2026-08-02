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
