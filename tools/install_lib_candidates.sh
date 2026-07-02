#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Fetch third-party library candidates into library_candidates/ (gitignored).
#
# Policy: external/third-party source NEVER lives in the repo — only this tool
# that installs it on demand. library_candidates/ is in .gitignore; this script
# refuses to run if that ever stops being true (so a fetched tree can't be
# committed by accident). Each candidate is pinned to an upstream commit/version
# and gets a PROVENANCE.md recording it.
#
# Usage:
#   tools/install_lib_candidates.sh [all|lua|tiny-regex-c|freebsd-regex|sqlite] ...
#   FORCE=1 tools/install_lib_candidates.sh lua      # re-fetch even if present
#
# Default target is `all`.
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DEST="$ROOT/library_candidates"
FORCE="${FORCE:-0}"

# Pinned upstream versions (bump here, re-run).
LUA_VERSION="5.4.7"
LUA_URL="https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz"
LUA_SHA256="9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30"

TINYREGEX_URL="https://github.com/kokke/tiny-regex-c"
TINYREGEX_COMMIT="f2632c6d9ed25272987471cdb8b70395c2460bdb"

FREEBSD_URL="https://github.com/freebsd/freebsd-src"
FREEBSD_COMMIT="22d66952555c86a5b7d1d499b48906c3a5f4c13d"

SQLITE_VERSION="3.46.0"
SQLITE_ZIP="sqlite-amalgamation-3460000"
SQLITE_URL="https://www.sqlite.org/2024/${SQLITE_ZIP}.zip"
SQLITE_SHA256="712a7d09d2a22652fb06a49af516e051979a3984adb067da86760e60ed51a7f5"

say() { printf '%s\n' "==> $*"; }
die() { printf '%s\n' "error: $*" >&2; exit 1; }

# Refuse to run unless library_candidates/ is ignored — keeps fetched source out
# of the repo. git check-ignore exits 0 when the path IS ignored.
guard_ignored() {
  if ! git -C "$ROOT" check-ignore -q "$DEST"; then
    die "library_candidates/ is NOT gitignored — refusing to fetch (would risk committing third-party source). Add 'library_candidates/' to .gitignore first."
  fi
}

present() {  # $1 = subdir; true if a non-empty tree already exists and not FORCE
  [ "$FORCE" != "1" ] && [ -d "$DEST/$1" ] && [ -n "$(ls -A "$DEST/$1" 2>/dev/null)" ]
}

fetch_lua() {
  if present lua; then say "lua present (FORCE=1 to re-fetch) — skip"; return 0; fi
  command -v curl >/dev/null 2>&1 || die "curl required for lua"
  say "fetching lua-${LUA_VERSION}"
  tmp="$(mktemp -d)"
  curl -fsSL "$LUA_URL" -o "$tmp/lua.tgz"
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$tmp/lua.tgz" | cut -d' ' -f1)"
    [ "$got" = "$LUA_SHA256" ] || die "lua sha256 mismatch: got $got want $LUA_SHA256"
  fi
  rm -rf "$DEST/lua"; mkdir -p "$DEST/lua"
  tar -xzf "$tmp/lua.tgz" -C "$tmp"
  cp -a "$tmp/lua-${LUA_VERSION}/." "$DEST/lua/"
  rm -rf "$tmp"
  cat > "$DEST/lua/PROVENANCE.md" <<EOF
# Lua Candidate
Upstream: https://www.lua.org/
Version: lua-${LUA_VERSION} (${LUA_URL})
SHA256: ${LUA_SHA256}
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
EOF
  say "lua -> $DEST/lua"
}

# Shallow-fetch one upstream commit into $2, optionally sparse to remaining paths.
fetch_commit() {  # $1=url $2=destsubdir $3=commit ; $4.. = sparse paths (optional)
  url="$1"; sub="$2"; commit="$3"; shift 3
  command -v git >/dev/null 2>&1 || die "git required"
  say "fetching $sub @ ${commit%??????????????????????????}…"
  tmp="$(mktemp -d)"
  git -C "$tmp" init -q
  git -C "$tmp" remote add origin "$url"
  if [ "$#" -gt 0 ]; then
    git -C "$tmp" config core.sparseCheckout true
    git -C "$tmp" sparse-checkout init >/dev/null 2>&1 || true
    git -C "$tmp" sparse-checkout set "$@" >/dev/null 2>&1 || {
      : > "$tmp/.git/info/sparse-checkout"
      for p in "$@"; do printf '%s\n' "$p" >> "$tmp/.git/info/sparse-checkout"; done
    }
  fi
  git -C "$tmp" fetch -q --depth 1 origin "$commit"
  git -C "$tmp" checkout -q FETCH_HEAD
  rm -rf "$DEST/$sub"; mkdir -p "$DEST/$sub"
  ( cd "$tmp" && tar --exclude=.git -cf - . ) | ( cd "$DEST/$sub" && tar -xf - )
  rm -rf "$tmp"
}

fetch_tiny_regex() {
  if present tiny-regex-c; then say "tiny-regex-c present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$TINYREGEX_URL" tiny-regex-c "$TINYREGEX_COMMIT"
  cat > "$DEST/tiny-regex-c/PROVENANCE.md" <<EOF
# Tiny Regex C Candidate
Upstream: ${TINYREGEX_URL}
Commit: ${TINYREGEX_COMMIT}
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: see LICENSE (Unlicense / public-domain-style).
EOF
  say "tiny-regex-c -> $DEST/tiny-regex-c"
}

fetch_freebsd_regex() {
  if present freebsd-regex; then say "freebsd-regex present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$FREEBSD_URL" .freebsd-tmp "$FREEBSD_COMMIT" \
    lib/libc/regex include/regex.h COPYRIGHT
  rm -rf "$DEST/freebsd-regex"; mkdir -p "$DEST/freebsd-regex"
  cp -a "$DEST/.freebsd-tmp/lib/libc/regex/." "$DEST/freebsd-regex/"
  cp -a "$DEST/.freebsd-tmp/include/regex.h" "$DEST/freebsd-regex/" 2>/dev/null || true
  cp -a "$DEST/.freebsd-tmp/COPYRIGHT" "$DEST/freebsd-regex/FREEBSD-COPYRIGHT" 2>/dev/null || true
  rm -rf "$DEST/.freebsd-tmp"
  cat > "$DEST/freebsd-regex/PROVENANCE.md" <<EOF
# FreeBSD Regex Candidate
Upstream: ${FREEBSD_URL}
Commit: ${FREEBSD_COMMIT}
Paths: lib/libc/regex/, include/regex.h, top-level COPYRIGHT (-> FREEBSD-COPYRIGHT)
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: see COPYRIGHT (Henry Spencer / Berkeley) + FREEBSD-COPYRIGHT.
EOF
  say "freebsd-regex -> $DEST/freebsd-regex"
}

fetch_sqlite() {
  if present sqlite; then say "sqlite present (FORCE=1 to re-fetch) — skip"; return 0; fi
  command -v curl >/dev/null 2>&1 || die "curl required for sqlite"
  command -v unzip >/dev/null 2>&1 || die "unzip required for sqlite"
  say "fetching sqlite-${SQLITE_VERSION} amalgamation"
  tmp="$(mktemp -d)"
  curl -fsSL "$SQLITE_URL" -o "$tmp/sqlite.zip"
  if command -v sha256sum >/dev/null 2>&1; then
    got="$(sha256sum "$tmp/sqlite.zip" | cut -d' ' -f1)"
    [ "$got" = "$SQLITE_SHA256" ] || die "sqlite sha256 mismatch: got $got want $SQLITE_SHA256"
  fi
  unzip -o -q "$tmp/sqlite.zip" -d "$tmp"
  rm -rf "$DEST/sqlite"; mkdir -p "$DEST/sqlite"
  cp -a "$tmp/${SQLITE_ZIP}/." "$DEST/sqlite/"   # flatten the amalgamation subdir
  rm -rf "$tmp"
  cat > "$DEST/sqlite/PROVENANCE.md" <<EOF
# SQLite Candidate
Upstream: https://www.sqlite.org/
Version: ${SQLITE_VERSION} amalgamation (${SQLITE_URL})
SHA256: ${SQLITE_SHA256}
Files: sqlite3.c, sqlite3.h, sqlite3ext.h, shell.c
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: public domain (see sqlite3.c header).
EOF
  say "sqlite -> $DEST/sqlite"
}

guard_ignored
mkdir -p "$DEST"

[ "$#" -eq 0 ] && set -- all
for t in "$@"; do
  case "$t" in
    all)           fetch_lua; fetch_tiny_regex; fetch_freebsd_regex; fetch_sqlite ;;
    lua)           fetch_lua ;;
    tiny-regex-c)  fetch_tiny_regex ;;
    freebsd-regex) fetch_freebsd_regex ;;
    sqlite)        fetch_sqlite ;;
    *) die "unknown candidate '$t' (want: all|lua|tiny-regex-c|freebsd-regex|sqlite)" ;;
  esac
done
say "done. library_candidates/ stays gitignored — nothing entered the repo."
