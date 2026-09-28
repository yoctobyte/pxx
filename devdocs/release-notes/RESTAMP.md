# Restamping the beta 0.1 pages for the final pin

On release day, the owner names the pin the release is frozen on, `vNNN`.
These steps turn the pages that say "this release is v441" into pages that say
`vNNN`. They leave alone every line that says what was **measured** with
v441, because that is history. Run from the repository root, in a clean
checkout at the commit that will be tagged. Nothing here commits, tags or
pushes.

## 1. The pin exists

```sh
tail -1 stable_linux_amd64/default/pin.log      # "pinned vNNN <sha256> ... <source commit>"
git log -1 --format='%h %s' --grep='chore(stable): pin vNNN --'
```

Both must name `vNNN`. The first gives the binary sha256 and the SOURCE
commit, the tree the binary was built from. The second gives the pin commit,
the one that checked the binary in. The release pages name the pin commit and
the sha256; the notes' header comment also names the source tree.

## 2. Pin markers

```sh
python3 devdocs/release-notes/restamp.py markers
```

This recomputes every `(vNNN)` and `(next pin)` marker in "## Since v441" of
`devdocs/release-notes/v0.1.0-beta.1.md` from `pin.log`, by
`git merge-base --is-ancestor` against each pin's source commit. It prints each
marker it changed. It can be run on any day.

## 3. Identity lines

```sh
python3 devdocs/release-notes/restamp.py identity --pin vNNN
git diff --stat      # expect AGENTS.md, CLAUDE.md, the two release-notes pages, known-issues.md
```

It applies seven patterns, ten lines in all. If one of them was reworded since this script
was written, it stops, prints the pattern that failed, and leaves that file
alone; edit that line by hand and update the pattern in `restamp.py`.

## 4. What needs a person

```sh
python3 devdocs/release-notes/restamp.py check --pin vNNN
```

It lists:

- the lines in "Since v441" whose commit `vNNN` does not carry. Drop them, or
  move them to a "After this release" note.
- every row of known-issues "Fixed since v441". Each one is fixed in the
  release now, so move it to "Fixed in this release". It should also have a
  line in the release notes; add one if it has none.
- the draft wording: the DRAFT comments, and the "(draft)" title and banner of
  `docs/release-notes/index.md`.

Then, by hand:

- **"Blaise at a glance"**: re-check each "open with vNNN" item against the
  final pin (`del`, the OpenSSL targets) and each "(next pin)" fix it names.
- **"Since v441" becomes "Fixed since the draft"**, or stays as it is. That is
  the owner's call; the markers are correct either way.
- The body of the release notes still describes v441 in places ("This release
  is pin v441" is gone after step 3, but the Known limits bullets on
  `__thread` and on memory leaks describe v441). Every bullet that a later fix
  changed needs its "(fixed in vNNN)" note.

## 5. Before committing

```sh
git grep -n wififive                 # must print nothing
git diff                             # read all of it
```

The restamp was tested on 2026-09-28 against v447, in a scratch branch that
was then deleted; see the commit that added this file.
