#!/usr/bin/env bash
# factsheet.sh -- regenerate the project fact sheet from the repo, every time.
#
# WHY THIS EXISTS. A draft blog post carried a fact sheet measured on
# 2026-08-14. Sixteen days later EVERY NUMBER IN IT HAD ROTTED -- commits
# +42%, done/ +49%, compiler lines +33%, and seven more. A launch post
# published from that table would have been wrong in ten places at once.
#
# That is the defect the comment-invariant audit characterises: a sentence and
# the thing that makes it true, able to change independently. The rule it lands
# on is "write the command in the comment, or write a sentence carrying no
# number". This IS that command.
#
# So: never paste these numbers anywhere without pasting this invocation next
# to them, and re-run it before publishing anything that quotes them.
#
#   tools/factsheet.sh          # human-readable table
#   tools/factsheet.sh --md     # markdown, for pasting into a draft

set -uo pipefail
cd "$(dirname "$0")/.."

MD=0
[ "${1:-}" = "--md" ] && MD=1

count_in() { find "$1" -maxdepth 1 -name "$2" 2>/dev/null | wc -l; }

P=devdocs/progress
commits=$(git rev-list --count HEAD)
done_n=$(count_in "$P/done" '*.md')
backlog_n=$(( $(count_in "$P/backlog" '*.md') + $(count_in "$P/backlog_new" '*.md') ))
rejected_n=$(count_in "$P/rejected" '*.md')
# Resolved decisions live in their own status dir, NOT in done/. Counting
# done/decide-* gives 1 where the answer is 116 -- measured 2026-08-30, after
# this script's first run disagreed with a hand count and the hand count won.
decided_n=$(( $(count_in "$P/decided" '*.md') + $(count_in "$P/done" 'decide-*.md') ))
open_dec=0
for d in urgent backlog backlog_new unfinished blocked; do
    open_dec=$(( open_dec + $(count_in "$P/$d" 'decide-*.md') ))
done
# The pin ledger is a file, not a commit-message pattern: history.log gets one
# line per pin and VERSION holds the current number. Grepping commit subjects
# gave 143 against a true 393 -- the message convention has changed over time
# and the ledger has not.
pins=$(wc -l < stable_linux_amd64/default/history.log 2>/dev/null || echo '?')
# Recursive: compiler/builtin/** is compiler source too. A top-level-only glob
# gives 214k against a true 250k -- a 14% undercount from one missing subdir.
compiler_lines=$(find compiler -type f \( -name '*.pas' -o -name '*.inc' \) \
                 -exec cat {} + 2>/dev/null | wc -l)
lib_lines=$(find lib -type f \( -name '*.pas' -o -name '*.c' -o -name '*.h' \) \
            -exec cat {} + 2>/dev/null | wc -l)

# The one figure that did NOT drift across five thousand commits, which is what
# makes it a property rather than a snapshot -- and the more honest thing to
# quote, since the load-bearing claim is the human/agent split.
trailered=$(git log --format='%b' | grep -c 'Co-Authored-By: Claude')
ratio=$(( trailered * 100 / (commits > 0 ? commits : 1) ))

emit() {
    if [ "$MD" = 1 ]; then printf '| %s | %s |\n' "$1" "$2"
    else printf '  %-34s %s\n' "$1" "$2"; fi
}

if [ "$MD" = 1 ]; then
    printf '| measure | value |\n| --- | --- |\n'
else
    echo "pxx fact sheet -- $(git rev-parse --short HEAD), $(git log -1 --format=%cd --date=short)"
    echo
fi

emit "commits"                       "$commits"
emit "commits with an agent trailer" "$trailered (${ratio}%)"
emit "tickets finished (done/)"      "$done_n"
emit "  of which decisions"          "$decided_n"
emit "tickets open (backlog)"        "$backlog_n"
emit "open decisions (Track U)"      "$open_dec"
emit "tickets rejected"              "$rejected_n"
emit "pins"                          "$pins"
emit "compiler lines (.pas + .inc)"  "$compiler_lines"
emit "library lines (lib/**)"        "$lib_lines"

if [ "$MD" = 0 ]; then
    echo
    echo "  These move fast: between 2026-08-14 and 2026-08-30, commits rose 42%"
    echo "  and done/ 49%. Quote the invocation, not the table. The agent-trailer"
    echo "  RATIO is the figure that has held steady, so it is the one to cite."
fi
