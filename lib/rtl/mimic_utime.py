"""mimic_utime -- MicroPython's `utime`: its `time` module under the old
micro-library name, with MicroPython's SHAPES where they differ from CPython's.

WHY A MODULE OF ITS OWN, and not an alias of `time` as the other u-names are.
MicroPython and CPython disagree on three functions, and device drivers depend
on MicroPython's answer: `(YY, MM, mday, hh, mm, ss, wday, yday) =
utime.localtime()` unpacks exactly eight items (the DS3231 drivers do this in
three files), where CPython's struct_time has nine. The rule (frankuser,
2026-09-25): MicroPython's semantics under MicroPython's name, CPython's under
CPython's. No CPython program can import `utime`, so these shapes cost a
CPython program nothing, and `time` stays CPython-shaped.

  localtime([secs]), gmtime([secs])
      an 8-TUPLE (year, month, mday, hour, minute, second, weekday, yearday),
      weekday 0 = Monday, yearday from 1. There is no time zone (as on
      MicroPython), so the two are the same function.
  mktime(t)
      the inverse: t has 8 or 9 items, the weekday and yearday in it are
      ignored, and the answer is an INT. CPython's takes 9 and returns a float.
  time()
      whole seconds, an int, as MicroPython's is.

THE EPOCH IS 1970-01-01, and that is a DIVERGENCE from MicroPython's esp32
port, which counts from 2000-01-01. That port defines neither
MICROPY_EPOCH_IS_1970 nor MICROPY_EPOCH_IS_2000, and py/mpconfig.h then defaults
to 2000 (read in MicroPython v1.26.1, 647c8b96). The unix port sets 1970. We
use 1970 so that utime.time() and time.time() agree. It matters only to a program
that STORES raw seconds and reads them back on a MicroPython board; one that
converts with localtime/mktime, as the drivers do, cannot tell.

Everything else is `time`'s: sleep, sleep_ms, sleep_us, ticks_ms, ticks_us,
ticks_cpu, ticks_diff, ticks_add.
"""
import time as _time


def localtime(secs=None):
    if secs is None:
        secs = _time.time()
    g = _time.gmtime(secs)
    return (g.tm_year, g.tm_mon, g.tm_mday, g.tm_hour, g.tm_min, g.tm_sec,
            g.tm_wday, g.tm_yday)


def gmtime(secs=None):
    return localtime(secs)


def mktime(t):
    if len(t) < 8 or len(t) > 9:
        raise TypeError("mktime needs a tuple of length 8 or 9")
    days = _time.DaysFromCivil(t[0], t[1], t[2])
    return days * 86400 + t[3] * 3600 + t[4] * 60 + t[5]


def time():
    return int(_time.time())


def sleep(seconds):
    _time.sleep(seconds)


def sleep_ms(ms):
    _time.sleep_ms(ms)


def sleep_us(us):
    _time.sleep_us(us)


def ticks_ms():
    return _time.ticks_ms()


def ticks_us():
    return _time.ticks_us()


def ticks_cpu():
    return _time.ticks_cpu()


def ticks_diff(ticks1, ticks2):
    return _time.ticks_diff(ticks1, ticks2)


def ticks_add(ticks, delta):
    return _time.ticks_add(ticks, delta)
