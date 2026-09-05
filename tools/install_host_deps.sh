#!/usr/bin/env sh
# SPDX-License-Identifier: MPL-2.0
# Install the DISTRO packages the test tiers need on a Debian/Ubuntu host.
#
# The missing member of the tools/install_*.sh family. The others each provision
# one thing -- qemu, the esp32 target, external/, library_candidates/, the cross
# sysroots -- and nothing owned the plain apt set, so it lived only in shell
# history. That is why this file exists:
#
#   2026-09-05, seven's 24.04 -> 26.04 dist-upgrade REMOVED fpc, libgtk-3-dev
#   and libgtk2.0-dev. fpc killed `make bootstrap` outright, which is loud. The
#   gtk headers were quiet: the five test_c_gtk* jobs went red, tickets were
#   auto-filed, and NOTHING IN THE TREE RECORDED THAT THE BUILD HOST'S PACKAGE
#   SET WAS THE VARIABLE. Reproducing the box was archaeology through
#   /var/log/apt/history.log. With this file it is one command.
#
# Usage:
#   tools/install_host_deps.sh           install anything missing
#   tools/install_host_deps.sh --check   report what is missing; exit 1 if any
#
# no-vendor-tracked: out-of-scope -- installs SYSTEM packages via apt-get.
# Nothing is written into the working tree, so it cannot put third-party source
# under a tracked path. Declared rather than inferred, exactly as
# tools/install_qemu.sh does; tools/check_no_vendor_tracked.sh treats every
# tools/install_*.sh as in-scope until it says otherwise.
set -eu

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# Each entry is "package  # what breaks without it". The comment is the point:
# a bare list decays into cargo cult the first time someone wonders whether an
# entry is still needed. Every one below was derived by MEASURING the tree --
# the headers it #includes, the sonames it binds by name, the tools its recipes
# probe with `command -v` -- not by copying a previous install line.
DEPS='
build-essential     # gcc/g++/make/libc6-dev: every C recipe and the C oracle
fpc                 # THE BOOTSTRAP ORACLE. `make bootstrap` refuses without it
binutils            # readelf/objcopy: 177 recipes parse readelf output
clang               # test-emit-obj PIE-link arm; SKIPS SILENTLY if absent
gdb                 # debug-info recipes (test-debug-g)
ccache              # build cache; recipes assume it on the PATH

libc6-dev           # -ldl -lm -lresolv -lcrypt, and every <sys/*.h>
zlib1g-dev          # libz.so.1 -- the zlib corpus
libssl-dev          # libssl.so.3 -- the TLS suite
libffi-dev          # esp-idf host build
python3-dev         # Python.h/pythread.h/structmember.h -- test_cpyext_*.npy
libsqlite3-dev      # libsqlite3 -- test-sqlite-threads, test-sqlite-parity
tcl-dev             # libtcl8.6.so.0 -- lib/pcl/tk.pas
tk-dev              # libtk8.6.so.0  -- lib/pcl/tk.pas, the tkinter demo
# BOTH gtk dev packages. Do NOT restate here which one serves the four
# `uses gtk` tests -- that answer moves. The last-resort fallback in the resolver
# is a HARDCODED absolute path in compiler/pasparser_proc.inc, and THAT LINE IS
# THE SOURCE OF TRUTH. Find it by PATTERN, never by line number:
#     grep -n "ConcatThree.*usr/include/gtk" compiler/pasparser_proc.inc
# It names /usr/include/gtk-N.0/gtk/<name>.h for whichever N is current.
# Cited this way because the line NUMBER is itself a value that moves: this
# comment said :3428 and the flip below shifted it to :3439 in the same commit
# that changed N, so a line-number citation was stale the moment it mattered.
# tools/testmgr.py has it right and got there first -- _USES_FALLBACK_RE regexes
# the ConcatThree call out of the compiler source rather than storing a position.
# It has been 2 and is now 3 (flipped by a409e19b5, owner ruling of 2026-08-31,
# gtk3 is a sane default in 2026). Deliberately not restating the current value
# again: this comment has been wrong twice already and the whole point is that
# :3428 answers it and prose cannot. test_c_gtk3_stock was never affected -- it
# says `uses gtk3_c` and reads /usr/include/gtk-3.0 directly, never the fallback.
# INSTALL BOTH -- the ATTRIBUTION moves, the REQUIREMENT does not. These two rows
# have gone correct-then-wrong twice in twelve hours, both times because someone
# (me, both times) copied the CURRENT VALUE of :3428 into prose beside a package
# name. A manifest pinned to a literal that another lane is moving is a time
# bomb; cite the ADDRESS of the literal, not its value.
libgtk2.0-dev
libgtk-3-dev

xvfb                # 6 GUI jobs; testmgr treats xvfb as an exclusive resource
xdotool             # gui_realwindow() real-window-size assertion; SKIPS SILENTLY
wabt                # wasm-validate -- wasm32_gap_census invalid-ENCODING bucket
csmith              # C fuzz generator (see idle_fuzz; kept installed, may be off)
creduce             # reducer
cvise               # reducer
clang-format        # cvise/creduce reduction passes

python3-flask       # tools/twatch_web.py, the watcher UI
python3-markdown    # tools/requirements-docs.txt

git curl wget unzip openssl   # fetchers/hashers used by tools/install_*.sh
'

# KNOWN AND DELIBERATE, so nobody spends a pass re-deciding: after the
# 24.04 -> 26.04 upgrade seven still carries noble-era libpython3.12-minimal,
# libpython3.12-stdlib and libpython3.12t64 while python3 is 3.14. They are NOT
# self-referential residue -- `linux-tools-6.8.0-139` depends on libpython3.12t64
# and that kernel is retained on purpose as the fallback, which is also why
# `apt-get autoremove` correctly declines to take them. They clear when the old
# kernel goes. Do not force-remove them to tidy up: `apt-get remove
# libpython3.12t64` takes linux-tools-6.8.0-139{,-generic} with it, and with them
# /usr/lib/linux-tools-6.8.0-139/perf -- the KERNEL-MATCHED perf for the fallback
# you are keeping in order to be able to boot it.
# The box does not lose perf outright: /usr/bin/perf (linux-perf 7.0.0-31.31,
# reports 7.0.14, links libpython3.14) is a separate binary and is unaffected.
# Note linux-tools-7.0.0-31 ships NO perf on this release -- linux-perf provides
# it -- so the two are not a matched pair and only the 6.8 one is at risk.
# Unrelated to packaging: perf COUNTS here but only as root.
# /proc/sys/kernel/perf_event_paranoid is 4, so unprivileged
# `perf stat -e instructions:u` reports "No supported events found" while
# `sudo perf stat -e instructions:u /bin/true` returns a real count. If you need
# a load-independent instruction counter, it is available -- it is denied, not
# missing. Changing the sysctl is a security-posture decision, not a fix here.

# qemu is deliberately NOT in DEPS: tools/install_qemu.sh owns it, including the
# 24.04->26.04 rename (qemu-user-static is a PURE VIRTUAL package on resolute,
# so it must be resolved by Candidate:, not by existence). One owner per thing.

have() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"; }

# True only when apt can ACTUALLY install this name here. `apt-cache policy`
# prints `Candidate: (none)` for a name that survives as a transitional or
# virtual stub -- `apt-cache show`, `apt-cache showpkg` and `dpkg-query` all
# succeed on such a name while `apt-get install` fails. Same shape as
# apt_has_candidate() in tools/install_esp32_target.sh, deliberately.
installable() {
  [ -n "$(apt-cache policy "$1" 2>/dev/null |
          awk '/Candidate:/ && $2 != "(none)" {print $2}')" ]
}

missing='' ; unavailable=''
for pkg in $(printf '%s\n' "$DEPS" | sed 's/#.*//' | tr -s ' \t' '\n' | grep -v '^$'); do
  have "$pkg" && continue
  if installable "$pkg"; then missing="$missing $pkg"
  else unavailable="$unavailable $pkg"; fi
done

[ -n "$unavailable" ] && printf 'warn: no installation candidate on this release for:%s\n' "$unavailable" >&2

if [ -z "$missing" ]; then
  echo "host deps: all present"
  [ -n "$unavailable" ] && exit 1
  exit 0
fi

if [ "$CHECK" = 1 ]; then
  printf 'host deps MISSING:%s\n' "$missing"
  echo "run: tools/install_host_deps.sh"
  exit 1
fi

printf 'host deps: installing:%s\n' "$missing"
# shellcheck disable=SC2086
sudo apt-get install -y $missing
echo "host deps: done -- re-run with --check to confirm"
