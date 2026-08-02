---
summary: "How Track T's findings reach an agent or a human: polling, never webhooks. 60s is the baseline; adaptive backoff is allowed but the daemon must not grow a time-based one."
type: decide
track: U
prio: 60
status: resolved
resolved: 2026-08-02
---

## DECISION 2026-08-02 — poll, never webhooks

**User's call, given verbally at the xeon box, written back here per
`two-box-protocol.md` ("a verbal decision must be written back into its ticket,
or the peer never sees it").**

> No webhooks. A 60 second poll interval is sane. We might be adaptive — if
> nothing new for a while, poll somewhat less frequently.

So: **every return path in Track T is a poll.** No inbound HTTP, no callback
URL, no service that must be reachable. This covers the daemon's view of
origin, the agent-side verdict watch, and any host-local alerting.

## Why polling wins here, concretely

Not a general preference — it follows from what this fleet is:

- **No inbound reachability.** Both boxes sit behind a home NAT. A webhook
  needs an endpoint the sender can reach, which means a tunnel or a relay: a
  new always-on service, a new secret, and a new way for the fleet to be
  silently broken while looking fine.
- **Origin is already the transport.** State goes through git and only git
  (`two-box-protocol.md`). A verdict is a commit; noticing it is a `fetch`.
  A webhook would be a *second* channel carrying the same fact, and the one
  thing the protocol is emphatic about is not letting a side channel become
  the record.
- **A poll fails visibly, a webhook fails silently.** A poller that stops
  polling is a process you can see is gone (`trackt health`). A webhook that
  stops arriving looks exactly like "nothing happened" — which is the failure
  mode this whole ticket family exists to eliminate.
- **The latency is not the bottleneck** (see below), so the thing a webhook
  buys is the thing we do not need.

## The daemon must NOT grow a time-based backoff

Recorded because "be adaptive" reads like an invitation to add one, and it
would make things worse.

`twatch`'s main loop already sleeps `interval` **only when `did_work` is
false** — and the idle chain below a new sha is: full-matrix backfill → opt
differential sweep → bench → bisect step → fuzz. With `idle_fuzz` on (default,
and on in xeon's config, which is only `{"autoticket": true}`) the fuzzer never
finishes, so the daemon reaches that `time.sleep(interval)` essentially never.

That is **work-gated polling, which is strictly better than time-based
backoff**: it already fetches only when there is nothing else to do, and it
never delays a fetch that had work waiting behind it. Adding "poll less often
when quiet" on top would be a no-op at best, and at worst would insert a delay
in front of the one cycle that had something to do.

The adaptive half of the decision therefore applies to *future* pollers that
do not have this structure — the host-local health check, anything new — not
to the daemon.

## Numbers as they stand

| loop | interval | note |
|---|---|---|
| daemon → origin (`twatch --interval`) | 60s + 20s debounce | work-gated; the sleep is rarely reached |
| `twatch --follow <sha>` | 30s | agent-facing; only runs while someone waits, exits on verdict |
| host-local health check | 5-10 min (not built — [[task-t-xeon-host-local-health-alerting]]) | poll `trackt health`, deliver on non-zero |

`--follow` **stays at 30s** rather than being unified to 60. It is not a
background loop: it exists only while an agent is blocked on a verdict, it
terminates when the verdict lands, and its cost is one `git fetch` of an
already-local-network origin. Halving its responsiveness would tax exactly the
case the whole offload model was built to serve. 60s there would be harmless,
just slightly worse; if uniformity is later preferred, change the default and
note it here.

## What actually governs verdict latency

Worth stating so nobody tunes the wrong number: the poll interval is not the
bottleneck. A push preempts the full backfill, the opt sweep and the fuzzer
(`abort_check`, ~30s granularity), but **the bench phase is deliberately not
preemptible** (~2-3 min). So worst-case time-to-notice a push is dominated by
bench plus the 20s debounce — an order of magnitude above any interval anyone
would pick. Tracked as [[feature-t-bench-idle-must-be-preemptible]].

# decide: how do Track T findings reach anyone?

The question this resolves: with the dev loop cut to ~15s and breadth offloaded
to the watcher ([[meta-t-dev-throughput-and-track-a-t-integration]]), the return
path became the product. Two shapes were available — push (webhook/callback into
the waiting session) or pull (poll origin). The above picks pull, permanently,
and records why, so it is not relitigated every time a new notifier is wired.
