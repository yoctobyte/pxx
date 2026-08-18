# SPDX-License-Identifier: 0BSD
"""mimic_urllib_request -- `urllib.request`, present and REFUSING.

Reached as `from urllib.request import urlopen`, which the NilPy import
resolver maps to this file (dotted module name -> `mimic_urllib_request`) and
announces as a shim.

READ THIS BEFORE ASSUMING THE MODULE WORKS. Nothing here fetches anything.
`urlopen` raises. This file exists so that a program which *imports*
`urllib.request` compiles, and so that the failure -- if the program actually
calls it -- happens at the call with an explanation, instead of at the import
with `no unit named urllib_request` that says nothing about why.

That is the same call `mimic_six.with_metaclass` makes, and the reason is the
same: refusing loudly is a better answer than an approximation, and a far
better answer than absence when the absence is what a caller trips over first.

WHY NOT IMPLEMENT IT YET -- AND IT IS SMALLER THAN IT LOOKS. The client this
needs already exists: `lib/rtl/http.pas`, gated by `make lib-test` as http +
redirect + keepalive + pool + gzip + cookie + json, https over the TLS seam. So
the remaining work is a Python FACE on an existing unit -- the response object,
the error mapping, and the binding question of whether it should be a `.pas`
shim like `mimic_codecs.pas` -- not an HTTP implementation. Left undone here
only because no library file is blocked on it. Filed as
feature-b-mimic-urllib-request-over-the-rtl-http-stack. When that lands, this
file gets a real `urlopen` and the refusal below comes out.

THE ONE CORPUS CALLER, and why it does not need it to work.
`webencodings/mklabels.py` is a code GENERATOR, not part of the library: it
downloads the WHATWG encodings index and prints the `labels.py` that
webencodings ships pre-generated. Running it needs the network; compiling it
does not, and the checked-in `labels.py` it produces is what the library
actually uses. So the honest score for this shim is "one more file compiles,
zero more files run" -- which is exactly what a shim that refuses should claim.
"""

_UNSUPPORTED = (
    "urllib.request is a stub in this build: it makes importing code compile, "
    "but nothing here performs HTTP. See "
    "feature-b-mimic-urllib-request-over-the-rtl-http-stack "
    "(lib/rtl/mimic_urllib_request.py)")


def urlopen(url, data=None, timeout=0):
    """Refuses. See the module docstring."""
    raise NotImplementedError(_UNSUPPORTED)


def urlretrieve(url, filename=None):
    """Refuses. See the module docstring."""
    raise NotImplementedError(_UNSUPPORTED)


class Request:
    """The request object callers build before handing it to `urlopen`.

    Constructing one is harmless and side-effect free, so this part is real:
    it holds what it was given. It is `urlopen` that cannot honour it.
    """

    def __init__(self, url, data=None, headers=None, method=None):
        self.full_url = url
        self.data = data
        self.headers = headers
        if headers is None:
            self.headers = {}
        self.method = method

    def get_full_url(self):
        return self.full_url

    def add_header(self, key, val):
        self.headers[key] = val
