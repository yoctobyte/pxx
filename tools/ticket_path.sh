#!/bin/sh
# Resolve a ticket SLUG to the one file that holds it, or fail loudly.
#
# WHY THIS EXISTS. A ticket moves between devdocs/progress/{urgent,working,
# unfinished,blocked,done,rejected} and the per-lane backlogs, and the natural
# way to add a finding to one is
#
#     cat >> devdocs/progress/<folder>/<slug>.md
#
# which CREATES the file when the folder is wrong. Nothing errors: the append
# succeeds, `git add -A` commits a new file, and the real ticket -- the one with
# the frontmatter, the one `ready` ranks and everyone reads -- never sees a word
# of it. Measured twice in one session on the same ticket, the second time
# after the first had been found and merged: 319 lines and six sections of
# measurements went to a stray in unfinished/ while the ticket sat in working/.
# The second occurrence is the point. A documented trap is not a guard.
#
#     cat >> "$(tools/ticket_path.sh <slug>)"
#
# cannot create a file, because the path comes from a file that already exists.
#
# Also: tools/ticket_path.sh --check-dupes  lists every slug that has more than
# one file, which is what the accident leaves behind. Exits 1 if any.

set -eu

progdir=$(cd "$(dirname "$0")/../devdocs/progress" && pwd)

usage() {
  echo "usage: ticket_path.sh <slug>            print the one file holding <slug>" >&2
  echo "       ticket_path.sh --check-dupes     list slugs held by more than one file" >&2
  exit 2
}

[ $# -eq 1 ] || usage

if [ "$1" = "--check-dupes" ]; then
  # Basename is the slug by construction everywhere in devdocs/progress.
  # README.md is a legitimate per-folder file and is not a slug. Excluding it
  # is what stops this printing nine hits on a tree with no duplicates at all --
  # a guard that flags everything says nothing.
  dupes=$(find "$progdir" -mindepth 2 -name '*.md' ! -name 'README.md' -print \
          | sed 's|.*/||' \
          | sort | uniq -d)
  if [ -z "$dupes" ]; then
    echo "ticket_path: no slug is held by more than one file"
    exit 0
  fi
  echo "ticket_path: SLUGS HELD BY MORE THAN ONE FILE" >&2
  for d in $dupes; do
    echo "  $d" >&2
    find "$progdir" -mindepth 2 -name "$d" -print | sed 's|^|    |' >&2
  done
  exit 1
fi

slug=$1
# Accept a slug with or without the .md, and reject a path outright: the whole
# point is that the CALLER does not choose the folder.
case "$slug" in
  */*) echo "ticket_path: give a SLUG, not a path: $slug" >&2; exit 2 ;;
esac
case "$slug" in
  *.md) ;;
  *) slug="$slug.md" ;;
esac

hits=$(find "$progdir" -mindepth 2 -name "$slug" -print)
n=$(printf '%s' "$hits" | grep -c . || true)

if [ "$n" -eq 0 ]; then
  echo "ticket_path: no ticket named $slug under $progdir" >&2
  exit 1
fi
if [ "$n" -gt 1 ]; then
  echo "ticket_path: $n files hold $slug -- merge them before appending:" >&2
  printf '%s\n' "$hits" | sed 's|^|  |' >&2
  exit 1
fi
printf '%s\n' "$hits"
