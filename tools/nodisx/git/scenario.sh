#!/bin/sh
# scenario.sh DIR SECTION: one section of git's test, run in DIR with the git
# on PATH (test.sh runs it with gcc's build, then with pxx's, and compares
# what each prints). Fixed names, dates and time zone, no system or user
# configuration, so the object ids are the same for any correct git.
set -eu
D=$1; SEC=$2
export TZ=UTC LC_ALL=C HOME=$D/home GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Ada GIT_AUTHOR_EMAIL=ada@nodisx.test
export GIT_COMMITTER_NAME=Bob GIT_COMMITTER_EMAIL=bob@nodisx.test
n=0
at() { n=$((n + 1)); export GIT_AUTHOR_DATE="2026-11-27T10:$(printf %02d $n):00Z" GIT_COMMITTER_DATE="2026-11-27T11:$(printf %02d $n):00Z"; }
mkdir -p "$HOME"
cd "$D"
lines() { i=1; while [ $i -le "$1" ]; do echo "line $i of $2"; i=$((i + 1)); done; }

case $SEC in
history)
  git init -q -b main r && cd r
  lines 40 a > a; lines 10 b > b; git add a b; at; git commit -qm 'one: a and b'
  sed 's/line 7 /line seven /' a > a.t && mv a.t a; echo extra >> b; at; git commit -qam 'two: edit'
  git log --format='%H %an %cn %ad %s' --date=iso-strict
  git show --stat --format=%s HEAD
  git diff HEAD~1 HEAD
  git cat-file -p HEAD^{tree}
  git rev-list --count HEAD
  ;;
branches)
  git init -q -b main r && cd r
  lines 30 a > a; git add a; at; git commit -qm base
  git switch -q -c feature; sed 's/line 3 /line three /' a > a.t && mv a.t a; at; git commit -qam feature
  git switch -q main; echo 'tail' >> a; at; git commit -qam main-tail
  at; git merge -q --no-edit feature
  git log --graph --format='%h %s' --all
  git tag -a v1 -m 'release v1'; at; echo more >> a; git commit -qam after-tag
  git describe
  git branch --list --format='%(refname:short) %(objectname:short)'
  git switch -q -c topic HEAD~1; echo t1 > t; git add t; at; git commit -qm t1; echo t2 >> t; at; git commit -qam t2
  at; git rebase -q main
  git log --format='%s %H' main..topic
  at; git cherry-pick -q main~0 2>&1 || true
  git log -1 --format='%s'
  ;;
worktree)
  git init -q -b main r && cd r
  lines 20 a > a; mkdir -p d/e; lines 5 x > d/e/x; git add .; at; git commit -qm base
  echo dirty >> a; echo new > n
  git status --short; git status --porcelain=v2 --branch | grep -v '^# branch.oid'
  at; git stash push -q -u -m wip; git stash list; git status --short
  git stash pop -q; git status --short
  git add -A; git diff --cached --stat; git restore --staged n; git status --short
  git grep -n 'line 1' -- '*.x' a
  git blame -s a | head -3
  git ls-files -s
  git mv a b; git rm -q --cached d/e/x; git status --short
  ;;
objects)
  git init -q -b main r && cd r
  # 3 MB of deterministic, poorly compressible data, then a small change to it
  awk 'BEGIN { x = 7; for (i = 0; i < 300000; i++) { x = (x * 1103515245 + 12345) % 2147483648; printf "%08x\n", x } }' > big
  lines 2000 txt > text; git add .; at; git commit -qm big
  sed '100000s/.*/changed/' big > big.t && mv big.t big; at; git commit -qam big2
  git cat-file -s HEAD:big; git rev-parse HEAD:big HEAD~1:big
  git count-objects -v | grep -E '^(count|in-pack|packs)'
  git gc -q --aggressive
  git count-objects -v | grep -E '^(count|in-pack|packs)'
  git verify-pack -v .git/objects/pack/pack-*.idx | awk '/^[0-9a-f]{40} / { print $1, $2, $3 } /^chain/ { print }' | sort
  git fsck --full --strict 2>&1
  git archive --format=tar --prefix=r/ HEAD | sha256sum
  git archive --format=zip HEAD text | sha256sum
  git bundle create ../all.bundle --all 2>/dev/null; git bundle verify -q ../all.bundle 2>&1; git bundle list-heads ../all.bundle
  ;;
sha256)
  git init -q -b main --object-format=sha256 r && cd r
  lines 10 s > s; git add s; at; git commit -qm sha256
  git rev-parse HEAD HEAD^{tree} HEAD:s
  git cat-file -p HEAD
  git fsck --full 2>&1
  ;;
clone-file)
  git init -q -b main src && cd src
  lines 50 c > c; git add c; at; git commit -qm c1; echo c2 >> c; at; git commit -qam c2
  cd ..
  git clone -q --no-local src c-full; git -C c-full log --format='%H %s'
  git clone -q --depth 1 "file://$D/src" c-shallow; git -C c-shallow log --format='%H %s'
  git clone -q --bare src b.git; git -C b.git for-each-ref --format='%(refname) %(objectname)'
  cd c-full; echo c3 >> c; at; git commit -qam c3; git push -q origin HEAD:refs/heads/pushed 2>&1
  git -C ../src log --format='%H %s' pushed
  ;;
clone-http)
  # $URL is the dumb-HTTP root of a bare repository test.sh serves (http or
  # https); $GIT_SSL_CAINFO the test CA
  git clone -q "$URL" got 2>&1
  git -C got log --format='%H %s'
  git -C got fsck --full 2>&1
  git -C got fetch -q origin 2>&1
  git ls-remote "$URL" 2>&1
  ;;
*) echo "scenario: no section $SEC" >&2; exit 2 ;;
esac
