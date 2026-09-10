from . import platform
from . import seam
from . import textfile
from . import probe

# `who()` is a CALL and not a constant read, because two modules that came to
# agree on a constant would be indistinguishable through a constant.
subject = (platform.KEY_ESCAPE, platform.who())
control = (seam.KEY_ESCAPE, seam.who())
flat_subject = (textfile.MARKER, textfile.who())
flat_control = (probe.MARKER, probe.who())
