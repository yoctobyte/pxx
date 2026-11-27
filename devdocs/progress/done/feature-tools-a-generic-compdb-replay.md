---
slug: feature-tools-a-generic-compdb-replay
track: tools
prio: 60
type: feature
status: done
owner: pxx2
created: 2026-11-27
closed: 2026-11-27
tags: [tools, replay, meson, panorama, systemd, gnome]
related: [feature-crtl-wlroots-gaps, feature-c-std-c23, umbrella-pxx-compiles-systemd]
summary: "tools/replay/compdb.py: any build that writes compile_commands.json (meson, ninja -t compdb, CMake, bear) replayed through pxx --emit-obj, with a census of the refusals. units (compdb to a tab-separated unit list, dropped flag kinds counted), replay (objects, logs, results.tsv, census), census (again from the logs). The unit list is made fresh from each build's database, so a package's options can change. First user: wlroots 0.20.2 for Panorama (216 units). Meant for the meson children of the systemd and GNOME C-base umbrellas too."
---

# A generic replay from a compilation database

Path B's replay-cc.py and Nodisx's units-from-make.sh read make logs. meson
(wlroots, systemd, GLib) writes `compile_commands.json` itself, and so can
CMake and, through bear, make. `tools/replay/compdb.py` starts there.

    compdb.py units BUILD/compile_commands.json UNITS
    JOBS=4 compdb.py replay UNITS OUT        # OUT/objs/..., OUT/results.tsv, the census
    compdb.py census OUT

Kept from each command: -D, -U, -I, -include, -isystem/-iquote/-idirafter
(as -I, in place), -std=, -ffile-prefix-map= and -fmacro-prefix-map=. A
launcher (ccache, distcc) is skipped. Everything else is dropped and each
dropped kind is printed once with its count, so a new build's surprises
show. C++ and assembler entries are counted and skipped. The census cuts
locations and search lists off the first error, so one gap counts once.
PXX_NO_HOST_INCLUDE=1 replays without the host's headers; PXXFLAGS adds
words.

Compile only. Linking, and the on-site recipe form (relative paths, a
gen.tar of generated files), come with the first consumer that needs them.
