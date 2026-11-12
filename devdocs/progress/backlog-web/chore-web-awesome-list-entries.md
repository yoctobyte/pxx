---
slug: chore-web-awesome-list-entries
track: W
type: chore
prio: 10
status: backlog
found: 2026-11-12
found-by: owner
owner: ""
blocked-by: []
summary: "Add pxx to the curated GitHub \"awesome\" lists (Pascal, ESP32, compilers, ...): one pull request per list, one line each. USER-TRIGGERED: wait until pxx is stable enough to be worth a stranger's first try. The entry line is already chosen."
---

# Add pxx to the "awesome" lists

- **Type:** chore (outreach)
- **Track:** W (website)
- **Status:** backlog, filed 2026-11-12. **Do not start without the owner saying
  go.** The gate is "stable enough", not a version number, and only the owner
  calls it.
- **Related:** [[feature-promo-launch-plan]] (this is a piece of its visibility
  work)

## What
"Awesome lists" are GitHub repos that are a single curated README of links on
one topic. People use them as a starting point ("which Pascal compilers
exist?"), they rank in search, and they stay up for years. Being listed is a
small, permanent signpost read by exactly the niche that would care.

One pull request per list, each adding one line.

## The entry line (owner's choice, 2026-11-12)

```
[pxx](https://pxxc.org) - Self-hosting Pascal/C/Python cross-compiler: x86, ARM, RISC-V, ESP32; Linux, WASM.
```

- Adapt only to a list's own format (dash or colon, period or none, length
  cap). Keep the content.
- Once a BSD target lands, "BSD" may be added after "WASM". Updating an entry
  later is just another pull request.
- No marketing words, no version or pin numbers: the line has to stay true
  for years.

## Candidate lists (verify each exists and is maintained before use)
- Pascal / Delphi / Free Pascal lists
- ESP32 / ESP-IDF lists
- Compilers / programming-language-implementation lists
- MicroPython / embedded Python lists (tact: pxx is native code, not
  MicroPython)

## Per list
1. Read its CONTRIBUTING: some require a minimum star count, a project age, or
   alphabetical order.
2. Put the line in the right section, in the list's format.
3. Open the pull request; the owner reviews each one before it is sent.

## Done when
Every suitable list has an open or merged pull request, and the ones that
refused are noted here with their reason.
