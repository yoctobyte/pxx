# SPDX-License-Identifier: 0BSD
"""mimic_six_moves -- the `six.moves` names this build can honestly provide.

Reached as `from six.moves import ...`, which the NilPy import resolver maps to
this file and announces as a shim.

WHAT `six.moves` IS. Not a library — a redirection table. Every member is a
RE-EXPORT of a stdlib module that was renamed between Python 2 and 3, so this
file cannot contain anything; it can only forward to modules that exist. That
is why `lib/rtl/mimic_six.py` left it out and said so, and why this file's
contents are one import and a note about what is missing.

WHAT IS HERE: `urllib_parse`, forwarding to `lib/rtl/mimic_urllib_parse.py`.
That is the half of `six.moves` this tree can answer, and it is the half
`html5lib/filters/sanitizer.py` wants.

DELIBERATELY ABSENT, and they are not oversights:

  * `http_client` — needs an HTTP client. `lib/rtl/http.pas` exists and does
    the work, but nothing yet puts a Python `http.client` face on it. See
    feature-b-mimic-urllib-request-over-the-rtl-http-stack.
    `html5lib/_inputstream.py` imports it, so that file stops here rather than
    getting a stub that would fetch nothing.
  * `urllib` — six.moves' `urllib` is itself a synthetic package bundling
    `urllib.request`, `.parse` and `.error`. Its request half is the same
    missing HTTP client.
  * everything else six.moves offers (`range`, `zip`, `cStringIO`,
    `configparser`, ...). Adding a name here is one line, and it should be
    added when a real caller wants it, measured — not pre-emptively, because a
    forwarding table that lists names it cannot really deliver is worse than
    one that is honestly short.

A caller reaching for an absent name gets a loud unresolved-name error at the
import, naming the name.
"""

# The platonic spelling, and it works: a shim re-exporting another module by
# its dotted name resolves correctly as of pin v351. It did NOT before that
# pin -- re-exporting by the MAPPED shim name lost the binding and only the
# literal `import mimic_urllib_parse` form worked. Recorded because the
# workaround was written down as necessary before it turned out not to be.
import urllib.parse as urllib_parse
