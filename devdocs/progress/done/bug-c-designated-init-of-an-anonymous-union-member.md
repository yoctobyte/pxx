---
slug: bug-c-designated-init-of-an-anonymous-union-member
track: C
prio: 70
type: bug
status: done
owner: pxx2
created: 2026-11-27
closed: 2026-11-28
found-by: pxx2 (wlroots 0.20.2 replay for Panorama, tools/replay/compdb.py)
tags: [cfront, initializers, wlroots]
summary: "`.hdmi_metadata_type1 = { .eotf = ..., ... }`, a designator naming a member that lives inside an anonymous union and gives it its own brace, was read by CInitWalkRecord as the anonymous union's brace: the inner designators were then looked up in the union, not in the member's struct, and the unit was refused. wlroots' backend/drm/atomic.c (struct hdr_output_metadata) was the one unit of 248 that failed. The anonymous-brace branch now applies only to a POSITIONAL brace; a designated one goes to the member it names. Test c_desanon26 against gcc."
---

# A designated member inside an anonymous union, with its own brace

```c
struct hdr_output_metadata {
  __u32 metadata_type;
  union { struct hdr_metadata_infoframe hdmi_metadata_type1; };
};
struct hdr_output_metadata m = {
  .metadata_type = 0,
  .hdmi_metadata_type1 = { .eotf = 2, .metadata_type = 0, ... },
};
```

`FindUField` resolves `.hdmi_metadata_type1` through the anonymous union, so
the walker stands on the right member. The next test, though, was "is the
field at this position an anonymous record and is a `{` next?", meant for a
positional `{ ... }` that initialises the anonymous union itself. It does not
ask whether a designator just named a member, so the brace went to the
union and `.eotf` was looked up there.

Fix (cparser.inc, CInitWalkRecord): a `named` flag, set when the designator
resolved, and the anonymous-brace branch requires `not named`.

Test test/c_desig_anon_member.c (row c_desanon26): statics and locals,
designated members of anonymous unions and structs with and without their
own brace, nested designators, positional anonymous braces beside them;
output identical to gcc's. wlroots 248/248 after.
