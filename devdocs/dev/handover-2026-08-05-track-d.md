# Handover 2026-08-05 — Track D (docs) + Track W (website)

Notes to self. You are **Track D**: you own `docs/**` — prose the website
publishes verbatim from git. You do not touch `compiler/**` or `lib/**`; a gap
you find gets a ticket in the owning lane. Read `CLAUDE.md` first.

This session also did **Track W** work (the website), which lives in a *separate
private repo* at `~/pxx-website` (`git@github.com:yoctobyte/pxx-website`, branch
`main`). Public docs content stays in this repo; the app, deploy config and
secrets stay in that one.

## The single most important habit from this session

**Run the example before you document it.** Every real finding came from
executing something, not reading it:

- `print(int(mm))` printing `0` is what uncovered a silent compiler bug that had
  been shipping in a library shim.
- Rendering the benchmark page and *looking at the screenshot* is what found
  colour-by-rank, the missing colour slots, and the wedge artifact. The markup
  diff looked fine.
- Diffing the CLI parser against `reference/cli.md` is what found six
  undocumented flags. Reading the page found none of them.

Corollary: **check a bug is still a bug before documenting it.** A gotcha I
wrote on 2026-08-02 was fixed by Track N within two days, and my own docs were
still describing it as broken today. Re-verify gotchas at the start of a session.

## What landed in `docs/**`

| commit | what |
| --- | --- |
| `f510c2f1d` | unlinked the blog from docs nav |
| `47ccc4d4c` | moved the AI interview to `devdocs/developer/historic/` (relic, not user docs) |
| `63e663d51` | documented 6 missing CLI flags; gave Nil Python a `status.md` section |
| `a03d51f1c` | zero-dependency output + wrapper-free imports promoted to the intro pages |
| `9e4fd5545` | documented the `mimic_` shims and `--no-shims` |
| `ce89ff14b` | `status.md` stopped hand-writing numbers; defers to the live pages |

Standing decisions:

- **`status.md` carries no figures.** The site generates them from tstate on
  every content pull. Prose that restates a number is prose that decays; it now
  says "deliberately no figures" so the next writer doesn't helpfully add some.
- **The two "byte-identical" claims are different** and public copy must not
  blur them (self-host fixedpoint = our binary vs our previous binary; corpora =
  program *output* vs a gcc-built oracle's output). `CLAUDE.md` has the table.
- The interview relic stays in `devdocs/developer/historic/`. Don't re-publish.

## Tickets I filed, and what became of them

| ticket | outcome | lesson |
| --- | --- | --- |
| `bug-nilpy-typed-const-import-reads-zero` | **done** | correct scope by experiment before filing; my first read blamed the import boundary, the real cause was any NilPy-main build |
| `bug-t-bench-sub-second-timings-quantized-to-50ms` | **done** | |
| `feature-t-bench-record-host-hardware-specs` | **rejected — duplicate** of `feature-t-bench-hardware-provenance` (filed a day earlier, now **done**) | **search the board before filing.** Same gap, found from the other end |

`tstate/meta/hosts.json` now exists and carries full hardware per host, so that
work landed under the other ticket.

## Track W — the website

Deploy is **manual on purpose** (auto-deploy would let a compromised GitHub
account run code on the host):

```bash
ssh ian@via
cd /opt/pxx-website && git pull --ff-only && sudo systemctl restart pxxweb
```

The checkout is owned by `ian`, not `pxxweb` — the app user cannot modify the
code it runs. Keep it that way. Content (`var/pxx`) needs no deploy: a push
webhook pulls it within seconds, with a 5-minute timer as the self-healing
floor, and `/status/` shows content age so staleness is visible.

**After any `static/` change, purge the Cloudflare cache.** CSS is served with
`max-age=14400`, so new markup runs against a four-hour-old stylesheet and the
change looks like it silently failed — this cost a round trip. Asset URLs are
deliberately unfingerprinted (the user owns the cache and prefers clean URLs);
the purge is the mechanism and it is in `deploy/README.md`.

Charts: colour is keyed by **series name**, never by index into a sorted list —
`-O2` must be the same hue in every panel. The palette is validated with the
dataviz skill's script (`--pairs all`, both light and dark) and grouped by which
series actually share a chart; the grouping *is* the CVD safety, so don't
re-order it to look tidy. Lines break at host changes and at time gaps, because
a stroke across a hole asserts continuity the data doesn't have.

## Open, waiting on the user

- **Cross-host benchmark calibration.** The `1.4534` borg→plexus factor is
  estimated from temporal adjacency, not measured: no commit was ever benchmarked
  on both boxes. A real calibration is ready to run — compile once on borg, `scp`
  the *identical static binary* to plexus (pxx output is zero-dependency, so this
  is exact), min-of-5 both sides. Blocked only on both boxes being idle; the user
  will say when. Don't run it while `testmgr --bench` is live — that corrupts
  their measurements to improve mine.
- **`www.pxxc.org` returns 000.** Needs the Cloudflare dashboard for the account
  owning the zone; cannot be done from `via`.
- The site's own blog publishes nothing — both posts in `pxxweb/content/blog/`
  are underscore-prefixed. Deliberate for now.

## Traps

- **`BOARD.md` conflicts on every rebase.** It is generated. Don't hand-merge:
  `tools/progress.sh board-md`, `git add`, `git rebase --continue`.
- **`pkill -f "flask run --port 16299"` kills your own shell** — the pattern
  matches the command line running it (exit 144). Use `1629[9]`.
- The dataviz validator only runs its CLI when `argv[1]` ends in
  `validate_palette.js`; copy it into a dir with `{"type":"module"}` in
  `package.json` and keep the filename.
- Reading the user's clipboard screenshot: `python3 -gi` GTK
  `Gtk.Clipboard.get(...).wait_for_image()` → save PNG → Read it. `xsel` is
  text-only and won't do.
- Screenshot a page with `google-chrome --headless --screenshot`. Do this before
  claiming a visual change works.
