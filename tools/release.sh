#!/usr/bin/env bash
# tools/release.sh — PXX release tool.
#
#   Dry-run by DEFAULT (no side effects): builds all host binaries, generates the
#   per-target SHA256 manifest, runs the full gate + selfcheck, assembles dist/,
#   and reports what *would* be tagged/published. Creates NO tag, cuts NO release.
#
#   --publish        actually cut the release: create the annotated tag + push it
#                    (fires .github/workflows/release.yml). Only side-effecting path.
#   --local          with --publish: `gh release create` from the locally-built
#                    dist/ assets instead of tag-driven CI.
#   --no-seatbelt    skip the human-state confirmations (for scripted/CI use).
#   --selftest       run the version-bump unit tests only (pure, no repo state) + exit.
#   -h | --help      this help.
#
# Versioning: semver tags vMAJOR.MINOR.PATCH[-CHANNEL.N], CHANNEL in alpha<beta<rc.
# The maintainer never hand-types a version — it is computed from the last tag and
# chosen from a menu. See docs/progress/backlog/feature-release-packaging.md.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---- configuration ------------------------------------------------------------
HOST_TARGETS=(x86_64 i386 aarch64 arm32)        # arches the compiler binary RUNS on
EMIT_ONLY_TARGETS=(xtensa riscv32)              # emit-only (no host self-host)
COMPILER="compiler/pascal26"
COMPILER_SRC="compiler/compiler.pas"
XFAIL_FILE="tools/release-xfail.txt"
DIST="dist"
# Codename theme: mathematicians/computing pioneers, alphabetical — the tool
# suggests the next unused initial; the maintainer may override.
CODENAME_POOL=(Babbage Curry Dijkstra Euler Floyd Goedel Hopper Iverson \
               Knuth Lovelace McCarthy Naur Pascal Ritchie Stroustrup Turing \
               Wirth Yourdon Zuse)

PUBLISH=0; LOCAL=0; SEATBELT=1; BUILD_FOR=""

# ---- semver: parse + bump (pure functions — unit-tested via --selftest) --------
# Tag grammar:  v<maj>.<min>.<patch>            (stable)
#               v<maj>.<min>.<patch>-<chan>.<n> (prerelease; chan = alpha|beta|rc)
# Globals set by sv_parse: SV_MAJ SV_MIN SV_PAT SV_CHAN SV_N  (SV_CHAN='' if stable)
sv_parse() {
  local v="${1#v}" core pre
  if [[ "$v" == *-* ]]; then core="${v%%-*}"; pre="${v#*-}"; else core="$v"; pre=""; fi
  IFS='.' read -r SV_MAJ SV_MIN SV_PAT <<<"$core"
  if [[ -n "$pre" ]]; then
    SV_CHAN="${pre%%.*}"; SV_N="${pre#*.}"
  else
    SV_CHAN=""; SV_N=0
  fi
  [[ "$SV_MAJ$SV_MIN$SV_PAT" =~ ^[0-9]+$ ]] || { echo "bad version: $1" >&2; return 1; }
  if [[ -n "$SV_CHAN" ]]; then
    case "$SV_CHAN" in alpha|beta|rc) ;; *) echo "bad channel: $SV_CHAN" >&2; return 1;; esac
    [[ "$SV_N" =~ ^[0-9]+$ ]] || { echo "bad prerelease number: $SV_N" >&2; return 1; }
  fi
}

# channel rank for ordering: alpha=1 beta=2 rc=3 stable=4
sv_chan_rank() { case "$1" in alpha) echo 1;; beta) echo 2;; rc) echo 3;; "") echo 4;; *) echo 0;; esac; }

# compute_next <current-version> <op> [<channel-for-pre-from-stable>]
# ops: patch minor major pre channel promote
compute_next() {
  local cur="$1" op="$2" startchan="${3:-alpha}"
  sv_parse "$cur"
  case "$op" in
    patch)   echo "v${SV_MAJ}.${SV_MIN}.$((SV_PAT+1))" ;;
    minor)   echo "v${SV_MAJ}.$((SV_MIN+1)).0" ;;
    major)   echo "v$((SV_MAJ+1)).0.0" ;;
    pre)     # bump the prerelease counter within the current channel
             [[ -n "$SV_CHAN" ]] || { echo "ERR: not a prerelease (no channel to bump)" >&2; return 1; }
             echo "v${SV_MAJ}.${SV_MIN}.${SV_PAT}-${SV_CHAN}.$((SV_N+1))" ;;
    channel) # advance alpha->beta->rc (reset counter to 1)
             case "$SV_CHAN" in
               alpha) echo "v${SV_MAJ}.${SV_MIN}.${SV_PAT}-beta.1" ;;
               beta)  echo "v${SV_MAJ}.${SV_MIN}.${SV_PAT}-rc.1" ;;
               rc)    echo "ERR: rc -> use 'promote' to go stable" >&2; return 1 ;;
               "")    echo "ERR: stable has no channel; bump patch/minor/major first" >&2; return 1 ;;
             esac ;;
    promote) # drop the prerelease suffix -> stable
             [[ -n "$SV_CHAN" ]] || { echo "ERR: already stable" >&2; return 1; }
             echo "v${SV_MAJ}.${SV_MIN}.${SV_PAT}" ;;
    *) echo "ERR: unknown op $op" >&2; return 1 ;;
  esac
}

# sv_gt <a> <b>  -> exit 0 if a strictly greater than b (semver, prerelease-aware)
sv_gt() {
  local a="$1" b="$2" am an ar bm bn br
  sv_parse "$a"; am=$SV_MAJ; an=$SV_MIN; ap=$SV_PAT; ac=$SV_CHAN; aN=$SV_N
  sv_parse "$b"; bm=$SV_MAJ; bn=$SV_MIN; bp=$SV_PAT; bc=$SV_CHAN; bN=$SV_N
  if (( am != bm )); then (( am > bm )); return; fi
  if (( an != bn )); then (( an > bn )); return; fi
  if (( ap != bp )); then (( ap > bp )); return; fi
  ar=$(sv_chan_rank "$ac"); br=$(sv_chan_rank "$bc")
  if (( ar != br )); then (( ar > br )); return; fi
  (( aN > bN ))
}

# ---- version-bump unit tests (--selftest) -------------------------------------
selftest() {
  local fail=0
  check() { # check <expr-result> <expected> <label>
    if [[ "$1" == "$2" ]]; then echo "ok   $3"; else echo "FAIL $3: got '$1' want '$2'"; fail=1; fi
  }
  check "$(compute_next v0.1.0 patch)"   v0.1.1            "patch"
  check "$(compute_next v0.1.0 minor)"   v0.2.0            "minor"
  check "$(compute_next v0.1.9 major)"   v1.0.0            "major"
  check "$(compute_next v0.2.0-beta.1 pre)"     v0.2.0-beta.2   "pre-counter"
  check "$(compute_next v0.2.0-alpha.3 channel)" v0.2.0-beta.1  "advance alpha->beta"
  check "$(compute_next v0.2.0-beta.2 channel)"  v0.2.0-rc.1    "advance beta->rc"
  check "$(compute_next v0.2.0-rc.4 promote)"     v0.2.0         "promote rc->stable"
  # ordering
  sv_gt v0.1.1 v0.1.0          && echo "ok   gt patch"      || { echo "FAIL gt patch"; fail=1; }
  sv_gt v0.2.0-beta.1 v0.2.0-alpha.9 && echo "ok   gt channel" || { echo "FAIL gt channel"; fail=1; }
  sv_gt v0.2.0 v0.2.0-rc.9     && echo "ok   gt stable>rc"  || { echo "FAIL gt stable>rc"; fail=1; }
  sv_gt v0.1.0 v0.1.1          && { echo "FAIL gt regression"; fail=1; } || echo "ok   reject regression"
  sv_gt v0.2.0-alpha.1 v0.2.0-beta.1 && { echo "FAIL gt skip"; fail=1; } || echo "ok   reject alpha<beta"
  [[ $fail -eq 0 ]] && echo "--selftest: ALL PASS" || { echo "--selftest: FAILURES"; return 1; }
}

# ---- helpers ------------------------------------------------------------------
die() { echo "release: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

last_tag() { git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || echo ""; }

suggest_codename() {
  # next pool entry whose initial isn't already used by an existing tag's notes;
  # cheap heuristic: count existing release codenames recorded in the ledger.
  local ledger="$REPO_ROOT/docs/release-notes/CODENAMES"
  local used=0
  [[ -f "$ledger" ]] && used="$(grep -c . "$ledger" 2>/dev/null || echo 0)"
  echo "${CODENAME_POOL[$(( used % ${#CODENAME_POOL[@]} ))]}"
}

# Interactive version menu. Echoes the chosen tag on stdout; prompts on stderr.
# RELEASE_BUMP env (patch|minor|major|pre|channel|promote) bypasses the prompt.
choose_version() {
  local cur="$1" op chosen
  if [[ -n "${RELEASE_BUMP:-}" ]]; then op="$RELEASE_BUMP"; else
    {
      echo "current: ${cur:-<none>}"
      echo "  1) patch    -> $(compute_next "${cur:-v0.0.0}" patch 2>/dev/null)"
      echo "  2) minor    -> $(compute_next "${cur:-v0.0.0}" minor 2>/dev/null)"
      echo "  3) major    -> $(compute_next "${cur:-v0.0.0}" major 2>/dev/null)"
      echo "  4) pre      -> $(compute_next "$cur" pre 2>/dev/null || echo '(needs a channel)')"
      echo "  5) channel  -> $(compute_next "$cur" channel 2>/dev/null || echo '(stable/rc: n/a)')"
      echo "  6) promote  -> $(compute_next "$cur" promote 2>/dev/null || echo '(already stable)')"
    } >&2
    read -rp "pick [1-6]: " pick >&2
    case "$pick" in 1) op=patch;; 2) op=minor;; 3) op=major;; 4) op=pre;; 5) op=channel;; 6) op=promote;; *) die "bad pick";; esac
  fi
  chosen="$(compute_next "${cur:-v0.0.0}" "$op")" || die "version compute failed"
  echo "$chosen"
}

# ---- main ---------------------------------------------------------------------
usage() { sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local args=("$@") i
  for ((i=0;i<${#args[@]};i++)); do case "${args[$i]}" in
    --publish) PUBLISH=1;; --local) LOCAL=1;; --no-seatbelt) SEATBELT=0;;
    --build-for) BUILD_FOR="${args[$((++i))]}";;
    --selftest) selftest; exit $?;;
    -h|--help) usage; exit 0;;
    *) die "unknown arg: ${args[$i]} (try --help)";;
  esac; done

  cd "$REPO_ROOT"
  [[ -f "$COMPILER_SRC" ]] || die "run from a PXX checkout (no $COMPILER_SRC)"

  # CI / non-interactive: build dist + manifest + gate + selfcheck for an EXISTING
  # tag. No version menu, no tagging — the caller (release.yml) publishes dist/.
  if [[ -n "$BUILD_FOR" ]]; then
    local cn; cn="$(grep -F "$BUILD_FOR " "$REPO_ROOT/docs/release-notes/CODENAMES" 2>/dev/null | awk '{print $2}' | head -1)"
    echo "==> build-for: $BUILD_FOR (codename ${cn:-none})"
    run_gate
    build_dist "$BUILD_FOR" "${cn:-unnamed}"
    run_selfcheck "$BUILD_FOR"
    echo "==> build-for: dist/pxx-$BUILD_FOR ready for publish"
    exit 0
  fi

  local cur tag codename
  cur="$(last_tag)"
  tag="$(choose_version "$cur")"
  echo "==> candidate tag: $tag"

  # monotonicity guard
  if [[ -n "$cur" ]]; then
    sv_gt "$tag" "$cur" || die "computed $tag is not strictly greater than last $cur (regression)"
  fi
  git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists"

  codename="${RELEASE_CODENAME:-}"
  if [[ -z "$codename" ]]; then
    local sug; sug="$(suggest_codename)"
    read -rp "codename [$sug]: " codename || true
    codename="${codename:-$sug}"
  fi
  echo "==> codename: $codename"

  run_gate
  build_dist "$tag" "$codename"
  run_selfcheck "$tag"

  echo
  echo "================ REHEARSAL COMPLETE ================"
  echo " tag:      $tag"
  echo " codename: $codename"
  echo " dist:     $DIST/pxx-$tag/  (+ tarball, MANIFEST.sha256)"
  if [[ $PUBLISH -eq 0 ]]; then
    echo " mode:     DRY-RUN — nothing tagged or published."
    echo "           re-run with --publish to cut it for real."
    exit 0
  fi
  publish "$tag" "$codename"
}

# Full verification surface; any failure not in the xfail registry aborts.
run_gate() {
  echo "==> gate: full verification suite"
  local x="$REPO_ROOT/$XFAIL_FILE"
  echo "    (xfail registry: ${XFAIL_FILE} — known gaps tolerated, all else fatal)"
  # Track A gate + library + demos. demos is parsed against the xfail list.
  make test
  make cross-bootstrap
  make lib-test
  # demos: tolerate only registered xfails
  local out; out="$(make demos 2>&1)" || true
  echo "$out"
  local bad=0 line src
  while IFS= read -r line; do
    case "$line" in
      *FAIL*) src="$(awk '{for(i=1;i<=NF;i++) if($i ~ /\.pas$/) print $i}' <<<"$line")"
              if [[ -n "$src" ]] && grep -qxF "$src" "$x" 2>/dev/null; then
                echo "    xfail (known): $src"
              else
                echo "    UNREGISTERED FAILURE: ${src:-$line}"; bad=1
              fi;;
    esac
  done <<<"$out"
  [[ $bad -eq 0 ]] || die "gate: unregistered demo failure(s) — fix, or add to $XFAIL_FILE with a ticket ref"
  echo "==> gate: PASS"
}

# Cross-build every host binary, hash, assemble the dist tree + manifest + tarball.
build_dist() {
  # Layout mirrors dev so the compiler's ExeDir resolution holds verbatim: the
  # binary lives in compiler/ (ExeDir), builtin/ inside it, lib/ as ../lib.
  local tag="$1" codename="$2" d="$DIST/pxx-$tag" t
  echo "==> build: host binaries + manifest"
  rm -rf "$d"; mkdir -p "$d/compiler"
  : > "$d/MANIFEST.sha256"
  for t in "${HOST_TARGETS[@]}"; do
    echo "    --target=$t"
    ./"$COMPILER" --target="$t" "$COMPILER_SRC" "$d/compiler/pxx-$t" >/dev/null
    ( cd "$d" && sha256sum "compiler/pxx-$t" >> MANIFEST.sha256 )
  done
  cp -a lib "$d/lib"
  [[ -d compiler/builtin ]] && cp -a compiler/builtin "$d/compiler/builtin"
  cp -a examples "$d/examples" 2>/dev/null || true
  cp -a tools/setup.sh "$d/setup.sh" 2>/dev/null || true
  cp -a tools/selfcheck.sh "$d/selfcheck.sh" 2>/dev/null || true
  printf 'PXX %s — codename "%s"\nSelf-hosting Pascal compiler. Run ./setup.sh, then `pxx`.\n' \
    "$tag" "$codename" > "$d/README"
  ( cd "$DIST" && tar czf "pxx-$tag.tar.gz" "pxx-$tag" )
  echo "==> build: $d + pxx-$tag.tar.gz"
}

# Reproduce-from-this-host check: recompute the manifest, compare to the built one.
run_selfcheck() {
  local tag="$1" d="$DIST/pxx-$tag" t h1 h2 tmp
  echo "==> selfcheck: reproduce manifest from this host"
  tmp="$(mktemp -d)"
  for t in "${HOST_TARGETS[@]}"; do
    ./"$COMPILER" --target="$t" "$COMPILER_SRC" "$tmp/pxx-$t" >/dev/null
    h1="$(sha256sum "$tmp/pxx-$t" | awk '{print $1}')"
    h2="$(awk -v f="compiler/pxx-$t" '$2==f{print $1}' "$d/MANIFEST.sha256")"
    [[ "$h1" == "$h2" ]] || die "selfcheck: $t does not reproduce ($h1 != $h2)"
    echo "    $t reproduces OK"
  done
  rm -rf "$tmp"
}

# Side-effecting. Human-state seatbelt, then tag+push (CI) or gh release (--local).
publish() {
  local tag="$1" codename="$2"
  echo "==> publish guards"
  [[ -z "$(git status --porcelain)" ]] || die "working tree dirty — commit/stash first"
  git fetch -q origin || true
  [[ -z "$(git -C "$REPO_ROOT" rev-list "@{u}..HEAD" 2>/dev/null)$(git rev-list "HEAD..@{u}" 2>/dev/null)" ]] \
    || die "not in sync with origin — pull/push first"
  if [[ $SEATBELT -eq 1 ]]; then
    local ans
    for q in "is it stable?" "are you tipsy?" "is it past midnight?"; do
      read -rp "$q [y/N] " ans || true
      case "$q:$ans" in
        "is it stable?:y"|"is it stable?:Y") ;;                       # want yes
        "is it stable?:"*) die "seatbelt: come back when it's stable";;
        "are you tipsy?:n"|"are you tipsy?:N"|"are you tipsy?:") ;;    # want no
        "are you tipsy?:"*) die "seatbelt: sober up first";;
        "is it past midnight?:n"|"is it past midnight?:N"|"is it past midnight?:") ;;
        "is it past midnight?:"*) die "seatbelt: ship in daylight";;
      esac
    done
  fi
  read -rp "PUBLISH $tag (codename $codename)? type the tag to confirm: " confirm || true
  [[ "$confirm" == "$tag" ]] || die "confirmation mismatch — aborted"

  mkdir -p "$REPO_ROOT/docs/release-notes"
  echo "$tag $codename" >> "$REPO_ROOT/docs/release-notes/CODENAMES"

  if [[ $LOCAL -eq 1 ]]; then
    have gh || die "--local needs the gh CLI"
    # Prefer a hand-authored body at docs/release-notes/<tag>.md; fall back to
    # GitHub's auto-generated notes when none is prepared.
    local notes_args=(--generate-notes) nf="$REPO_ROOT/docs/release-notes/$tag.md"
    [[ -f "$nf" ]] && { notes_args=(--notes-file "$nf"); echo "==> release body: $nf"; }
    gh release create "$tag" "$DIST/pxx-$tag.tar.gz" "$DIST/pxx-$tag/MANIFEST.sha256" \
      --title "PXX $tag — $codename" "${notes_args[@]}"
  else
    git tag -a "$tag" -m "PXX $tag — codename $codename"
    git push origin "$tag"     # fires .github/workflows/release.yml
    echo "==> pushed $tag — CI release workflow will build + publish."
  fi
}

main "$@"
