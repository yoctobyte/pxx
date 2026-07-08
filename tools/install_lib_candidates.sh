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
#   tools/install_lib_candidates.sh [all|lua|tiny-regex-c|freebsd-regex|sqlite|c-testsuite|zlib|tcc|cjson|stb|cglm|enet] ...
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

CTESTSUITE_URL="https://github.com/c-testsuite/c-testsuite"
CTESTSUITE_COMMIT="5c7275656d751de0e68b2d340a95b5681858ed07"

ZLIB_URL="https://github.com/madler/zlib"
ZLIB_COMMIT="51b7f2abdade71cd9bb0e7a373ef2610ec6f9daf"   # v1.3.1 release tag
TCC_URL="https://github.com/TinyCC/tinycc"
TCC_COMMIT="a338258d309c888bde96b2d1f206299231a54ddf"   # mob, 2026-07 snapshot

CJSON_URL="https://github.com/DaveGamble/cJSON"
CJSON_COMMIT="acc76239bee01d8e9c858ae2cab296704e52d916"   # v1.7.18 tag

STB_URL="https://github.com/nothings/stb"
STB_COMMIT="31c1ad37456438565541f4919958214b6e762fb4"   # master, 2026-07 snapshot

CGLM_URL="https://github.com/recp/cglm"
CGLM_COMMIT="46f46e5dcb84bc5bfcc07675f026077272704f0c"   # master, 2026-07 snapshot

ENET_URL="https://github.com/lsalzman/enet"
ENET_COMMIT="5a9c537fd464b3c6d3c55e1d3bd47588faf71b42"   # master, 2026-07 snapshot

SQLITE_VERSION="3.46.0"
SQLITE_ZIP="sqlite-amalgamation-3460000"
SQLITE_URL="https://www.sqlite.org/2024/${SQLITE_ZIP}.zip"
SQLITE_SHA256="712a7d09d2a22652fb06a49af516e051979a3984adb067da86760e60ed51a7f5"

say() { printf '%s\n' "==> $*"; }
die() { printf '%s\n' "error: $*" >&2; exit 1; }

# Refuse to run unless library_candidates/ is ignored — keeps fetched source out
# of the repo. git check-ignore exits 0 when the path IS ignored.
guard_ignored() {
  if ! git -C "$ROOT" check-ignore -q "$DEST/"; then
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

fetch_cjson() {
  if present cjson; then say "cjson present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$CJSON_URL" .cjson-tmp "$CJSON_COMMIT" cJSON.c cJSON.h LICENSE
  rm -rf "$DEST/cjson"; mkdir -p "$DEST/cjson/src"
  cp -a "$DEST/.cjson-tmp/cJSON.c" "$DEST/.cjson-tmp/cJSON.h" "$DEST/cjson/src/"
  cp -a "$DEST/.cjson-tmp/LICENSE" "$DEST/cjson/LICENSE" 2>/dev/null || true
  rm -rf "$DEST/.cjson-tmp"
  cat > "$DEST/cjson/PROVENANCE.md" <<EOF
# cJSON Candidate
Upstream: ${CJSON_URL}
Commit: ${CJSON_COMMIT} (v1.7.18)
Paths: cJSON.c, cJSON.h -> src/ (Makefile CJSON_SRC layout), LICENSE
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: see LICENSE (MIT).
EOF
  say "cjson -> $DEST/cjson"
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

fetch_c_testsuite() {
  if present c-testsuite; then say "c-testsuite present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$CTESTSUITE_URL" c-testsuite "$CTESTSUITE_COMMIT" tests/single-exec LICENSE README.md
  cat > "$DEST/c-testsuite/PROVENANCE.md" <<EOF
# c-testsuite Candidate
Upstream: ${CTESTSUITE_URL}
Commit: ${CTESTSUITE_COMMIT}
Paths: tests/single-exec/ (220 conformance tests + .expected + .tags), LICENSE, README.md
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: see LICENSE (MIT).
EOF
  say "c-testsuite -> $DEST/c-testsuite"
}

fetch_zlib() {
  if present zlib; then say "zlib present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$ZLIB_URL" zlib "$ZLIB_COMMIT"
  cat > "$DEST/zlib/PROVENANCE.md" <<EOF
# zlib Candidate
Upstream: ${ZLIB_URL}
Commit: ${ZLIB_COMMIT} (v1.3.1 release tag)
Paths: full source tree (*.c, *.h) + test/example.c, test/minigzip.c for oracle.
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: zlib license (see LICENSE / zlib.h header).
EOF
  say "zlib -> $DEST/zlib"
}

fetch_tcc() {
  if present tcc; then say "tcc present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$TCC_URL" tcc "$TCC_COMMIT"
  # tcc needs a generated config.h (./configure) and tccdefs_.h (c2str) before
  # any .c compiles. Generate them with the host toolchain once; they are part of
  # the vendored (gitignored) tree, not committed.
  ( cd "$DEST/tcc" && ./configure >/dev/null 2>&1 && make tccdefs_.h >/dev/null 2>&1 ) \
    || say "tcc: WARN config.h / tccdefs_.h generation failed (need host gcc)"
  cat > "$DEST/tcc/PROVENANCE.md" <<EOF
# TinyCC Candidate
Upstream: ${TCC_URL}
Commit: ${TCC_COMMIT}
Setup: ./configure (config.h) + make tccdefs_.h (c2str) run at fetch time.
Paths: full source tree (*.c, *.h). Vendor source — gitignored, never committed.
License: LGPL (see COPYING).
EOF
  say "tcc -> $DEST/tcc"
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
fetch_stb() {
  if present stb; then say "stb present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$STB_URL" stb "$STB_COMMIT"
  cat > "$DEST/stb/PROVENANCE.md" <<EOF
# stb Candidate (single-header C libraries)
Upstream: ${STB_URL}
Commit: ${STB_COMMIT}
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: MIT / public domain dual (see LICENSE in headers).
First probe: game-library ladder (feature-game-library-candidate-suite).
EOF
  say "stb -> $DEST/stb"
}

fetch_cglm() {
  if present cglm; then say "cglm present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$CGLM_URL" cglm "$CGLM_COMMIT"
  cat > "$DEST/cglm/PROVENANCE.md" <<EOF
# cglm Candidate (header-only C graphics math)
Upstream: ${CGLM_URL}
Commit: ${CGLM_COMMIT}
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: MIT.
First probe: game-library ladder (feature-game-library-candidate-suite).
EOF
  say "cglm -> $DEST/cglm"
}

fetch_enet() {
  if present enet; then say "enet present (FORCE=1 to re-fetch) — skip"; return 0; fi
  fetch_commit "$ENET_URL" enet "$ENET_COMMIT"
  cat > "$DEST/enet/PROVENANCE.md" <<EOF
# ENet Candidate (reliable-UDP networking C library)
Upstream: ${ENET_URL}
Commit: ${ENET_COMMIT}
Installed by tools/install_lib_candidates.sh. Vendor source — gitignored, never committed.
License: MIT.
First probe: game-library ladder (feature-game-library-candidate-suite).
EOF
  say "enet -> $DEST/enet"
}

  case "$t" in
    all)           fetch_lua; fetch_tiny_regex; fetch_freebsd_regex; fetch_sqlite; fetch_c_testsuite; fetch_zlib; fetch_tcc; fetch_cjson; fetch_stb; fetch_cglm; fetch_enet ;;
    lua)           fetch_lua ;;
    cjson)         fetch_cjson ;;
    stb)           fetch_stb ;;
    cglm)          fetch_cglm ;;
    enet)          fetch_enet ;;
    tiny-regex-c)  fetch_tiny_regex ;;
    freebsd-regex) fetch_freebsd_regex ;;
    sqlite)        fetch_sqlite ;;
    c-testsuite)   fetch_c_testsuite ;;
    zlib)          fetch_zlib ;;
    tcc)           fetch_tcc ;;
    *) die "unknown candidate '$t' (want: all|lua|tiny-regex-c|freebsd-regex|sqlite|c-testsuite|zlib|tcc|cjson)" ;;
  esac
done
say "done. library_candidates/ stays gitignored — nothing entered the repo."
