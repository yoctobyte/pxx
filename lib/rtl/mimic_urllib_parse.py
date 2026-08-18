# SPDX-License-Identifier: 0BSD
"""mimic_urllib_parse -- CPython's `urllib.parse`: splitting a URL into pieces.

Reached as `from urllib.parse import ...` or, via `six.moves`, as
`urllib_parse`. The NilPy import resolver maps the dotted module name to this
file and announces it as a shim. Not named for the upstream package: no file in
this tree carries an upstream name.

WHY THIS ONE IS WRITABLE EXACTLY. URL splitting is string work against a
published grammar (RFC 3986) with no platform behind it — no network, no
encoding tables, no version drift. The bodies below follow CPython's
`Lib/urllib/parse.py`, and every rule that could plausibly be guessed wrong was
read off a running CPython rather than remembered. Correct here means "returns
the same six fields", which test/lib_mimic_urllib_parse.npy checks by running
the same file both ways.

THE FOUR RULES A PLAUSIBLE IMPLEMENTATION GETS WRONG, all of them observable
from the one corpus caller:

  * **The scheme is lower-cased.** `HTTP://x` parses as scheme `http`. A
    sanitizer comparing `uri.scheme not in allowed_protocols` against a
    lower-case allow-list lets `JavaScript:` through if this is missed. That is
    a security-relevant difference, not a cosmetic one.
  * **Params are split off the path for SOME schemes only.** `a/b;p=1` yields
    params `p=1`, but `data:text/html;base64,AAA` keeps the whole thing in
    `path` — because `data` is not in `uses_params`. Get this wrong and the
    corpus's `data:` content-type check reads a truncated path.
  * **A scheme must look like one.** A leading letter then letters, digits,
    `+`, `-`, `.`; otherwise there is no scheme and the colon stays in the
    path. So `1a:b` has no scheme.
  * **An unbalanced `[` or `]` in the netloc raises ValueError.** This is not an
    edge case to shrug at: `html5lib/filters/sanitizer.py` wraps its
    `urlparse()` call in `try/except ValueError` and DELETES the attribute when
    it fires. A shim that returned a result instead would keep an attribute the
    sanitizer meant to drop.

SCOPE. The corpus calls exactly one name — `urlparse` — and reads `.scheme` and
`.path`. `urlsplit`, the two un-split inverses, and `quote`/`unquote` are here
because they are the same grammar walked forwards and backwards, and a caller
reaching for one reaches for the others.

DELIBERATELY ABSENT: `urljoin`. It is not more of the same — it is RFC 3986
§5.2's reference resolution, a dozen interacting rules about relative paths,
`.` and `..` removal, and inheriting parts of a base URL. A half-right
`urljoin` returns a plausible URL that points somewhere else, which is the
worst failure this module could have. Also absent: `parse_qs`/`urlencode` (the
query-string layer, a separate job), and the `SplitResult`/`ParseResult`
`_replace`/`geturl` conveniences.
"""

# Exactly CPython's list, in its order. Membership decides whether `;params`
# is split off the path, so an omission here silently changes results.
uses_params = ['', 'ftp', 'hdl', 'prospero', 'http', 'imap', 'https', 'shttp',
               'rtsp', 'rtsps', 'rtspu', 'sip', 'sips', 'mms', 'sftp', 'tel']

_SCHEME_CHARS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+-."
_SCHEME_START = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
_HEX = "0123456789ABCDEFabcdef"


class SplitResult:
    """`urlsplit`'s five fields. CPython's is a named tuple; this exposes the
    attribute access and indexing that callers actually use."""

    def __init__(self, scheme, netloc, path, query, fragment):
        self.scheme = scheme
        self.netloc = netloc
        self.path = path
        self.query = query
        self.fragment = fragment

    def __getitem__(self, i):
        return (self.scheme, self.netloc, self.path, self.query,
                self.fragment)[i]

    def __len__(self):
        return 5

    def __eq__(self, other):
        return tuple(self) == tuple(other)


class ParseResult:
    """`urlparse`'s six fields — `urlsplit`'s five plus `params`."""

    def __init__(self, scheme, netloc, path, params, query, fragment):
        self.scheme = scheme
        self.netloc = netloc
        self.path = path
        self.params = params
        self.query = query
        self.fragment = fragment

    def __getitem__(self, i):
        return (self.scheme, self.netloc, self.path, self.params, self.query,
                self.fragment)[i]

    def __len__(self):
        return 6

    def __eq__(self, other):
        return tuple(self) == tuple(other)


def _valid_scheme(s):
    """A scheme is a letter followed by letters, digits, `+`, `-` or `.`."""
    if not s:
        return False
    if s[0] not in _SCHEME_START:
        return False
    for ch in s:
        if ch not in _SCHEME_CHARS:
            return False
    return True


def _split_netloc(url):
    """Take the `//netloc` off the front of what follows the scheme.

    Raises ValueError on unbalanced IPv6 brackets, exactly as CPython does —
    html5lib's sanitizer depends on that exception being raised.
    """
    end = len(url)
    for c in "/?#":
        i = url.find(c, 2)
        if i >= 0 and i < end:
            end = i
    netloc = url[2:end]
    if ("[" in netloc and "]" not in netloc) or ("]" in netloc and "[" not in netloc):
        raise ValueError("Invalid IPv6 URL")
    return netloc, url[end:]


def urlsplit(url, scheme="", allow_fragments=True):
    """Split a URL into scheme, netloc, path, query, fragment.

    Unlike `urlparse` this does NOT pull `;params` out of the path.
    """
    netloc = ""
    query = ""
    fragment = ""
    i = url.find(":")
    if i > 0 and _valid_scheme(url[:i]):
        scheme = url[:i].lower()
        url = url[i + 1:]
    if url[:2] == "//":
        netloc, url = _split_netloc(url)
    if allow_fragments and "#" in url:
        i = url.find("#")
        url, fragment = url[:i], url[i + 1:]
    if "?" in url:
        i = url.find("?")
        url, query = url[:i], url[i + 1:]
    return SplitResult(scheme, netloc, url, query, fragment)


def urlparse(url, scheme="", allow_fragments=True):
    """Split a URL into six fields, pulling `;params` off the LAST path segment.

    Params are only split for the schemes in `uses_params` — which is why
    `data:text/html;base64,AAA` keeps its semicolon in the path.
    """
    s = urlsplit(url, scheme, allow_fragments)
    params = ""
    path = s.path
    if s.scheme in uses_params and ";" in path:
        i = path.rfind("/")
        if i >= 0:
            j = path.find(";", i)
        else:
            j = path.find(";")
        if j >= 0:
            path, params = path[:j], path[j + 1:]
    return ParseResult(s.scheme, s.netloc, path, params, s.query, s.fragment)


def urlunsplit(parts):
    """The inverse of `urlsplit`."""
    scheme, netloc, url, query, fragment = (parts[0], parts[1], parts[2],
                                            parts[3], parts[4])
    if netloc or (scheme and url[:2] != "//"):
        if url and url[:1] != "/":
            url = "/" + url
        url = "//" + netloc + url
    if scheme:
        url = scheme + ":" + url
    if query:
        url = url + "?" + query
    if fragment:
        url = url + "#" + fragment
    return url


def urlunparse(parts):
    """The inverse of `urlparse`: re-attaches `;params` before un-splitting."""
    scheme, netloc, url, params, query, fragment = (
        parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
    if params:
        url = url + ";" + params
    return urlunsplit((scheme, netloc, url, query, fragment))


def quote(s, safe="/"):
    """Percent-encode a string. `/` is safe by default, as in CPython."""
    always = ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
              "0123456789_.-~")
    out = ""
    for ch in s:
        if ch in always or ch in safe:
            out = out + ch
        else:
            for b in ch.encode("utf-8"):
                out = out + "%%%02X" % b
    return out


def unquote(s):
    """Undo percent-encoding. A `%` not followed by two hex digits is left
    alone, which is CPython's behaviour and not an error."""
    out = b""
    i = 0
    n = len(s)
    while i < n:
        if s[i] == "%" and i + 2 < n + 1 and i + 2 < n + 1:
            h = s[i + 1:i + 3]
            if len(h) == 2 and h[0] in _HEX and h[1] in _HEX:
                out = out + bytes([int(h, 16)])
                i = i + 3
                continue
        out = out + s[i].encode("utf-8")
        i = i + 1
    return out.decode("utf-8")
