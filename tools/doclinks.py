#!/usr/bin/env python3
"""Check the external links in docs/**, and that the ones we delegate CONTENT to
still carry that content.

Why this exists
---------------
`docs/reference/status.md` deliberately carries no figures any more.  It says
"For current numbers, read the live status pages, not this page" and points at
pxxc.org.  That was the right call -- a hand-written number rots the day it is
written -- but it moved the failure mode somewhere this repo cannot see it:

    before   a number goes stale   VISIBLE to a reader who checks, self-correcting
    now      a URL 404s            INVISIBLE from the checkout, the link is fine

So a plain 200 check is not enough.  A landing page, a redirect to the site root,
or a report rendered empty all return 200 while the public page promises figures
and delivers none -- which is strictly worse than the stale snapshot it replaced,
because the reader is told exactly where to look.  Hence MARKERS below: for the
URLs that carry delegated content we assert the page still looks like the report
it is advertised as.

Offline is SKIP, never FAIL.  A network check that hard-fails is a check people
delete, and it must not turn a docs lane that works on a train into one that does
not.  Exit 1 only for a link that is genuinely wrong.

Usage:  tools/doclinks.py [--root docs] [--timeout 15] [-v]
"""

import argparse
import os
import re
import socket
import sys
import urllib.error
import urllib.request

# A URL in prose, minus the punctuation that ends an English sentence or closes
# a markdown link.  Trailing ')' is dropped only when unbalanced, so a URL with
# parentheses in its own path survives.
URL = re.compile(r'https?://[^\s<>"\'\\`)\]]+[^\s<>"\'\\`)\].,;:!?]')

# Not links.  `https://` inside an inline code fence is documentation OF a URL
# shape, and example.com is an intentional placeholder -- both would otherwise
# be reported forever, which is how a checker gets ignored and then deleted.
IGNORE = re.compile(r'^https?://(www\.)?example\.(com|org)|^https?://`')

# The pages docs/** delegates CONTENT to.  Substrings that must survive in the
# rendered text -- deliberately weak (a word, not a number), because the point is
# "this is still that report", not "this report says what it said last week".
# Every marker set is satisfied by the live page as of 2026-08-30.
MARKERS = {
    'pxxc.org/status/conformance': ['pass', 'fail'],
    'pxxc.org/status/tests':       ['GREEN', 'RED'],
    'pxxc.org/status/benchmarks':  ['fib', 'sieve'],
    'pxxc.org/status/flow':        ['filed', 'closed'],
    'pxxc.org/status':             ['backlog', 'resolved'],
}

TAGS = re.compile(r'<(script|style)[^>]*>.*?</\1>|<[^>]+>', re.S | re.I)


def markers_for(url):
    """Longest matching prefix wins, so /status/tests does not match bare /status."""
    key = url.split('://', 1)[-1].rstrip('/')
    best = None
    for k in MARKERS:
        if key.startswith(k) and (best is None or len(k) > len(best)):
            best = k
    return MARKERS.get(best, [])


def collect(root):
    """[(url, path, lineno)] over every .md under root, in file order."""
    out = []
    for dirpath, _, names in os.walk(root):
        for n in sorted(names):
            if not n.endswith('.md'):
                continue
            p = os.path.join(dirpath, n)
            with open(p, encoding='utf-8', errors='replace') as fh:
                for i, line in enumerate(fh, 1):
                    for m in URL.finditer(line):
                        u = m.group(0)
                        if not IGNORE.search(u):
                            out.append((u, p, i))
    return out


def fetch(url, timeout):
    """(status, text) -- status None means the host could not be reached."""
    req = urllib.request.Request(url, headers={
        'User-Agent': 'pxx-doclinks/1 (+docs link check)'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read(400_000)
            enc = r.headers.get_content_charset() or 'utf-8'
            return r.status, body.decode(enc, 'replace')
    except urllib.error.HTTPError as e:
        return e.code, ''
    except (urllib.error.URLError, socket.timeout, OSError):
        return None, ''


def online(timeout):
    try:
        socket.create_connection(('1.1.1.1', 443), timeout=min(timeout, 5)).close()
        return True
    except OSError:
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', default='docs')
    ap.add_argument('--timeout', type=float, default=15.0)
    ap.add_argument('-v', '--verbose', action='store_true')
    a = ap.parse_args()

    found = collect(a.root)
    # One request per distinct URL; report every site that cites it.
    sites = {}
    for u, p, n in found:
        sites.setdefault(u, []).append((p, n))

    print('%s: %d external link(s), %d distinct'
          % (a.root, len(found), len(sites)))

    if not online(a.timeout):
        print('SKIP: no network. %d link(s) unchecked -- this is not a failure.'
              % len(sites))
        return 0

    bad, checked = [], 0
    for u in sorted(sites):
        st, text = fetch(u, a.timeout)
        where = ', '.join('%s:%d' % w for w in sites[u])
        if st is None:
            # One unreachable host while the network is up is a real signal, but
            # it is also what a captive portal or a rate limit looks like.
            bad.append((u, where, 'unreachable'))
        elif not (200 <= st < 300):
            bad.append((u, where, 'HTTP %s' % st))
        else:
            checked += 1
            want = markers_for(u)
            if want:
                flat = TAGS.sub(' ', text)
                miss = [w for w in want if w.lower() not in flat.lower()]
                if miss:
                    # 200 but not the promised report: the failure this tool is for.
                    bad.append((u, where, 'reachable but missing %s -- the page '
                                'docs delegates content to no longer looks like '
                                'that report' % ', '.join(repr(m) for m in miss)))
                elif a.verbose:
                    print('  ok   %s  [%s]' % (u, ' '.join(want)))
            elif a.verbose:
                print('  ok   %s' % u)

    for u, where, why in bad:
        print('BROKEN %s\n       %s\n       cited at %s' % (u, why, where))

    print('checked %d, BROKEN %d' % (checked, len(bad)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
