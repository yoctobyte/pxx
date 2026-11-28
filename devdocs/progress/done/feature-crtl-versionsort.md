---
slug: feature-crtl-versionsort
track: crtl
prio: 50
type: feature
status: done
owner: pxx2
created: 2026-11-28
closed: 2026-11-28
found-by: pxx2 (Panorama all-pxx program: libinput 1.31.1 through compdb.py replay)
tags: [crtl, dirent]
summary: "GNU versionsort(3), the scandir comparator that orders digit runs as numbers (event9 before event10), was missing. libinput's path seat and quirks loader use it. Added next to alphasort, over crtl's existing strverscmp. Test: c_vsort26, scandir over event1/event9/event10/event100/mouse2, against gcc."
---

# Crtl versionsort

crtl_names.inc regenerated (873 functions).
