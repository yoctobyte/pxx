# SPDX-License-Identifier: 0BSD
"""mimic_argparse -- CPython's `argparse`, the subset real call sites reach.

Reached as `import argparse` through the NilPy import resolver's `mimic_`
fallback. Named by what it is, not by the upstream module, for the reason
[[mimic_heapq]] gives.

SCOPE IS THE CALL SITES, NOT THE MODULE. What is here is what That Space
Program's two entry points (tsp/__main__.py, tsp/view/__main__.py) do with
argparse, and it grows when a new caller needs more:

    ArgumentParser(prog=, description=, formatter_class=)
    add_argument(*names, action="store_true"|"store_false"|"store", type=,
                 default=, choices=, nargs=None|"?"|"*"|"+", dest=, help=,
                 metavar=, required=)
    add_subparsers(dest=, required=).add_parser(name, help=, description=)
    set_defaults(**kw)       parse_args(argv=None)       error(msg)
    print_help() / format_help() / print_usage() / format_usage()

ABSENT, AND LOUD RATHER THAN APPROXIMATED: every other `action` (append,
count, store_const, version, ...), mutually exclusive groups, argument groups,
parents=, fromfile_prefix_chars, parse_known_args, intermixed parsing. An
unsupported `action` raises ValueError at add_argument, so it is found on the
first run instead of parsing to a wrong namespace.

THE PARSE IS CPYTHON'S ALGORITHM, NOT AN EQUIVALENT ONE. A command line is
classified into a pattern of 'O' (option), 'A' (argument) and '-' ('--'), and
positionals are matched against that pattern greedily with backtracking, as
CPython's regular expressions do; a run of empty trailing matches is deferred
when an option follows, which is what lets `node add --pro 3 Tux` bind `Tux` to
the optional positional after the option. Option prefixes (`--prog` for
`--prograde`), `--opt=value`, bundled short flags (`-qq`), negative numbers as
arguments, and subparsers handing their unrecognised arguments back to the
parent are all CPython's rules, because a program's users type them.

THE MESSAGES ARE CPYTHON 3.14's, BYTE FOR BYTE, and so are usage and help:
people read these, and test/test_nilpy_argparse_* diffs them against python3.
Where this differs, knowingly:
  * no colour. 3.14 colours help and errors on a terminal; a pipe gets plain
    text from both, and that is what the tests compare.
  * the width is $COLUMNS, else 80, as CPython's shutil.get_terminal_size() on
    a pipe. On a terminal CPython asks the tty for its width; this does not.
  * help text is wrapped by a greedy word wrap that splits at the hyphens
    textwrap would split at; a single word wider than the column is not
    broken.
  * `type=` given a def words its error with the function's repr, not its
    name (`invalid <function at 0x...> value`), because a NilPy function value
    has no __name__ yet (bug-n-a-function-value-has-no-name). Builtin types
    and classes are named correctly.
"""

import os
import sys

SUPPRESS = "==SUPPRESS=="
OPTIONAL = "?"
ZERO_OR_MORE = "*"
ONE_OR_MORE = "+"
PARSER = "A..."


class HelpFormatter:
    pass


class RawDescriptionHelpFormatter(HelpFormatter):
    pass


class RawTextHelpFormatter(RawDescriptionHelpFormatter):
    pass


class ArgumentDefaultsHelpFormatter(HelpFormatter):
    pass


class ArgumentError(Exception):
    def __init__(self, action_name, message):
        Exception.__init__(self, message)
        self.argument_name = action_name
        self.message = message

    def __str__(self):
        if self.argument_name is None:
            return self.message
        return "argument " + self.argument_name + ": " + self.message


class ArgumentTypeError(Exception):
    pass


class Namespace:
    def __init__(self, **kwargs):
        self._values = {}
        for k in kwargs:
            self._values[k] = kwargs[k]

    def __getattr__(self, name):
        if name in self._values:
            return self._values[name]
        raise AttributeError("'Namespace' object has no attribute '" + name + "'")

    def __contains__(self, key):
        return key in self._values

    def __eq__(self, other):
        return self._values == other._values

    def __repr__(self):
        parts = []
        for k in self._values:
            parts.append(k + "=" + repr(self._values[k]))
        return "Namespace(" + ", ".join(parts) + ")"

    def _set(self, name, value):
        self._values[name] = value

    def _has(self, name):
        return name in self._values


def _terminal_width():
    cols = os.environ.get("COLUMNS", "")
    if cols.isdigit() and int(cols) > 0:
        return int(cols)
    return 80


def _is_negative_number(s):
    # CPython: '^-\d+$|^-\d*\.\d+$'
    if len(s) < 2 or s[0] != "-":
        return False
    body = s[1:]
    if body.isdigit():
        return True
    head, sep, tail = body.partition(".")
    if sep == "" or tail == "" or not tail.isdigit():
        return False
    return head == "" or head.isdigit()


def _type_name(conv):
    try:
        return conv.__name__
    except AttributeError:
        return repr(conv)


class _Action:
    def __init__(self, option_strings, dest, nargs, default, typ, choices,
                 required, help, metavar, kind):
        self.option_strings = option_strings
        self.dest = dest
        self.nargs = nargs
        self.default = default
        self.type = typ
        self.choices = choices
        self.required = required
        self.help = help
        self.metavar = metavar
        self.kind = kind            # "store", "store_true", "store_false", "help", "parsers"
        self.parsers = {}           # kind == "parsers": name -> ArgumentParser
        self.parser_names = []      # in the order they were added
        self.choice_help = []       # (name, help) for each add_parser(help=)

    def name(self):
        # CPython's _get_action_name
        if self.option_strings:
            return "/".join(self.option_strings)
        if self.metavar is not None and self.metavar != SUPPRESS:
            return self.metavar
        if self.dest is not None and self.dest != SUPPRESS:
            return self.dest
        if self.choices is not None:
            return "{" + ",".join(self._choice_strs()) + "}"
        return None

    def _choice_strs(self):
        out = []
        for c in self.choices:
            out.append(str(c))
        return out


class _SubParsersAction:
    """What add_subparsers() returns: the one thing a caller does with it is
    add_parser."""

    def __init__(self, action, prog_prefix, parser_class_args):
        self._action = action
        self._prog_prefix = prog_prefix
        self._width_args = parser_class_args

    def add_parser(self, name, **kwargs):
        help = kwargs.get("help", None)
        if "prog" not in kwargs or kwargs["prog"] is None:
            kwargs["prog"] = self._prog_prefix + " " + name
        if "help" in kwargs:
            del kwargs["help"]
        parser = ArgumentParser(**kwargs)
        self._action.parsers[name] = parser
        self._action.parser_names.append(name)
        self._action.choices = self._action.parser_names
        if help is not None:
            self._action.choice_help.append((name, help))
        return parser


class ArgumentParser:
    def __init__(self, prog=None, usage=None, description=None, epilog=None,
                 formatter_class=None, add_help=True, **kwargs):
        if prog is None:
            prog = os.path.basename(sys.argv[0]) if sys.argv else "python"
        self.prog = prog
        self.usage = usage
        self.description = description
        self.epilog = epilog
        self.formatter_class = formatter_class
        self._actions = []
        self._option_actions = {}
        self._defaults = {}
        self._subparsers = None
        self._has_negative_number_optionals = False
        if add_help:
            self._add_action(_Action(["-h", "--help"], SUPPRESS, 0, SUPPRESS,
                                     None, None, False,
                                     "show this help message and exit", None,
                                     "help"))

    # -- building ----------------------------------------------------------

    def _add_action(self, action):
        self._actions.append(action)
        for s in action.option_strings:
            self._option_actions[s] = action
            if _is_negative_number(s):
                self._has_negative_number_optionals = True
        return action

    def add_argument(self, *names, **kwargs):
        kind = kwargs.get("action", None)
        if kind is None:
            kind = "store"
        if kind != "store" and kind != "store_true" and kind != "store_false":
            raise ValueError("argparse (mimic): action=" + repr(kind) +
                             " is not supported by this shim")
        if len(names) == 0:
            raise ValueError("argparse (mimic): add_argument needs a name")
        option_strings = []
        dest = kwargs.get("dest", None)
        if names[0][:1] == "-":
            long_name = None
            for n in names:
                if n[:1] != "-":
                    raise ValueError("invalid option string " + repr(n) +
                                     ": must start with a character '-'")
                option_strings.append(n)
                if long_name is None and n[:2] == "--" and len(n) > 2:
                    long_name = n
            if dest is None:
                if long_name is not None:
                    dest = long_name[2:]
                else:
                    dest = names[0][1:]
                dest = dest.replace("-", "_")
            required = kwargs.get("required", False)
        else:
            if len(names) > 1:
                raise ValueError("invalid option string " + repr(names[1]) +
                                 ": must start with a character '-'")
            if dest is not None:
                raise ValueError("dest supplied twice for positional argument," +
                                 " did you mean metavar?")
            dest = names[0]
            nargs = kwargs.get("nargs", None)
            required = not (nargs == OPTIONAL or nargs == ZERO_OR_MORE)
        if kind == "store_true" or kind == "store_false":
            nargs = 0
            if "default" in kwargs:
                default = kwargs["default"]
            else:
                default = kind == "store_false"
        else:
            nargs = kwargs.get("nargs", None)
            if nargs is not None and nargs != OPTIONAL and nargs != ZERO_OR_MORE \
                    and nargs != ONE_OR_MORE:
                raise ValueError("argparse (mimic): nargs=" + repr(nargs) +
                                 " is not supported by this shim")
            default = kwargs.get("default", None)
        if dest in self._defaults:
            default = self._defaults[dest]
        action = _Action(option_strings, dest, nargs, default,
                         kwargs.get("type", None), kwargs.get("choices", None),
                         required, kwargs.get("help", None),
                         kwargs.get("metavar", None), kind)
        return self._add_action(action)

    def add_subparsers(self, **kwargs):
        if self._subparsers is not None:
            self.error("cannot have multiple subparser arguments")
        dest = kwargs.get("dest", None)
        if dest is None:
            dest = SUPPRESS
        action = _Action([], dest, PARSER, None, None, None,
                         kwargs.get("required", False), kwargs.get("help", None),
                         kwargs.get("metavar", None), "parsers")
        action.choices = []
        # the subparsers' prog: this parser's usage prefix, which is the prog
        # plus any positionals before the subcommand
        prefix = self.prog
        for a in self._actions:
            if not a.option_strings:
                prefix = prefix + " " + self._format_args(a, a.dest)
        self._subparsers = action
        self._add_action(action)
        return _SubParsersAction(action, prefix, None)

    def set_defaults(self, **kwargs):
        for k in kwargs:
            self._defaults[k] = kwargs[k]
        for a in self._actions:
            if a.dest in kwargs:
                a.default = kwargs[a.dest]

    def get_default(self, dest):
        for a in self._actions:
            if a.dest == dest and a.default is not None:
                return a.default
        return self._defaults.get(dest, None)

    # -- parsing -----------------------------------------------------------

    def parse_args(self, args=None, namespace=None):
        if args is None:
            args = sys.argv[1:]
        else:
            args = list(args)
        if namespace is None:
            namespace = Namespace()
        extras = []
        try:
            self._parse_into(args, namespace, extras)
        except ArgumentError as err:
            self.error(str(err))
        if extras:
            self.error("unrecognized arguments: " + " ".join(extras))
        return namespace

    def _parse_into(self, arg_strings, namespace, extras):
        for a in self._actions:
            if a.dest != SUPPRESS and not namespace._has(a.dest):
                if a.default != SUPPRESS:
                    namespace._set(a.dest, a.default)
        for k in self._defaults:
            if not namespace._has(k):
                namespace._set(k, self._defaults[k])
        _Parse(self, arg_strings, namespace, extras).run()

    def _parse_optional(self, arg_string):
        # CPython's _parse_optional: None means "an argument", else a list of
        # (action, option_string, sep, explicit_arg); action None is unknown
        if not arg_string:
            return None
        if arg_string[0] != "-":
            return None
        if arg_string in self._option_actions:
            return [(self._option_actions[arg_string], arg_string, None, None)]
        if len(arg_string) == 1:
            return None
        option_string, sep, explicit_arg = arg_string.partition("=")
        if sep and option_string in self._option_actions:
            return [(self._option_actions[option_string], option_string, sep,
                     explicit_arg)]
        tuples = self._get_option_tuples(arg_string)
        if tuples:
            return tuples
        if _is_negative_number(arg_string):
            if not self._has_negative_number_optionals:
                return None
        if " " in arg_string:
            return None
        return [(None, arg_string, None, None)]

    def _get_option_tuples(self, option_string):
        result = []
        if option_string[1] == "-":
            option_prefix, sep, explicit_arg = option_string.partition("=")
            if not sep:
                sep = None
                explicit_arg = None
            for s in self._option_actions:
                if s.startswith(option_prefix):
                    result.append((self._option_actions[s], s, sep, explicit_arg))
        else:
            option_prefix, sep, explicit_arg = option_string.partition("=")
            if not sep:
                sep = None
                explicit_arg = None
            short_prefix = option_string[:2]
            short_explicit = option_string[2:]
            for s in self._option_actions:
                if s == short_prefix:
                    result.append((self._option_actions[s], s, "", short_explicit))
                elif s.startswith(option_prefix):
                    result.append((self._option_actions[s], s, sep, explicit_arg))
        return result

    def _get_value(self, action, arg_string):
        conv = action.type
        if conv is None:
            return arg_string
        try:
            return conv(arg_string)
        except ArgumentTypeError as err:
            raise ArgumentError(action.name(), str(err))
        except (TypeError, ValueError):
            raise ArgumentError(action.name(), "invalid " + _type_name(conv) +
                                " value: " + repr(arg_string))

    def _check_value(self, action, value):
        if action.choices is None:
            return
        for c in action.choices:
            if c == value:
                return
        raise ArgumentError(action.name(), "invalid choice: " + repr(value) +
                            " (choose from " + ", ".join(action._choice_strs()) + ")")

    def _get_values(self, action, arg_strings):
        # CPython's _get_values, for the nargs this shim accepts
        if action.nargs == PARSER:
            value = [self._get_value(action, arg_strings[0])] + arg_strings[1:]
            self._check_value(action, value[0])
            return value
        if not arg_strings and action.nargs == OPTIONAL:
            if action.option_strings:
                value = None        # const, which this shim does not take
            else:
                value = action.default
            if isinstance(value, str):
                value = self._get_value(action, value)
            return value
        if not arg_strings and action.nargs == ZERO_OR_MORE and \
                not action.option_strings:
            if action.default is not None:
                value = action.default
            else:
                value = []
            return value
        if len(arg_strings) == 1 and (action.nargs is None or
                                      action.nargs == OPTIONAL):
            value = self._get_value(action, arg_strings[0])
            self._check_value(action, value)
            return value
        if action.nargs == 0:
            return None
        value = []
        for s in arg_strings:
            value.append(self._get_value(action, s))
        for v in value:
            self._check_value(action, v)
        return value

    # -- output ------------------------------------------------------------

    def _format_args(self, action, default_metavar):
        if action.metavar is not None:
            metavar = action.metavar
        elif action.choices is not None:
            metavar = "{" + ",".join(action._choice_strs()) + "}"
        else:
            metavar = default_metavar
        if action.nargs is None:
            return metavar
        if action.nargs == OPTIONAL:
            return "[" + metavar + "]"
        if action.nargs == ZERO_OR_MORE:
            return "[" + metavar + " ...]"
        if action.nargs == ONE_OR_MORE:
            return metavar + " [" + metavar + " ...]"
        if action.nargs == PARSER:
            return metavar + " ..."
        return ""

    def _invocation(self, action):
        if not action.option_strings:
            if action.metavar is not None:
                return action.metavar
            if action.choices is not None:
                return "{" + ",".join(action._choice_strs()) + "}"
            return action.dest
        if action.nargs == 0:
            return ", ".join(action.option_strings)
        return ", ".join(action.option_strings) + " " + \
            self._format_args(action, action.dest.upper())

    def _usage_parts(self):
        opt_parts = []
        pos_parts = []
        for a in self._actions:
            if a.help == SUPPRESS:
                continue
            if a.option_strings:
                if a.nargs == 0:
                    part = a.option_strings[0]
                else:
                    part = a.option_strings[0] + " " + \
                        self._format_args(a, a.dest.upper())
                if not a.required:
                    part = "[" + part + "]"
                opt_parts.append(part)
        for a in self._actions:
            if a.help == SUPPRESS:
                continue
            if not a.option_strings:
                part = self._format_args(a, a.dest)
                if part:
                    pos_parts.append(part)
        return opt_parts, pos_parts

    def format_usage(self):
        return self._format_usage("usage: ") + "\n"

    def _format_usage(self, prefix):
        width = _terminal_width() - 2
        if self.usage is not None:
            return prefix + self.usage.replace("%(prog)s", self.prog)
        prog = self.prog
        opt_parts, pos_parts = self._usage_parts()
        parts = [prog] + opt_parts + pos_parts
        usage = " ".join(parts)
        text_width = width
        if len(prefix) + len(usage) > text_width:
            if len(prefix) + len(prog) <= 0.75 * text_width:
                indent = " " * (len(prefix) + len(prog) + 1)
                if opt_parts:
                    lines = _get_lines([prog] + opt_parts, indent, text_width, prefix)
                    lines = lines + _get_lines(pos_parts, indent, text_width, None)
                elif pos_parts:
                    lines = _get_lines([prog] + pos_parts, indent, text_width, prefix)
                else:
                    lines = [prog]
            else:
                indent = " " * len(prefix)
                lines = _get_lines(opt_parts + pos_parts, indent, text_width, None)
                if len(lines) > 1:
                    lines = _get_lines(opt_parts, indent, text_width, None) + \
                        _get_lines(pos_parts, indent, text_width, None)
                lines = [prog] + lines
            usage = "\n".join(lines)
        return prefix + usage

    def format_help(self):
        width = _terminal_width() - 2
        max_help_position = min(24, max(width - 20, 4))
        raw_description = isinstance_formatter(self.formatter_class,
                                               RawDescriptionHelpFormatter)
        raw_text = isinstance_formatter(self.formatter_class, RawTextHelpFormatter)

        positionals = []
        optionals = []
        for a in self._actions:
            if a.help == SUPPRESS:
                continue
            if a.option_strings:
                optionals.append(a)
            else:
                positionals.append(a)

        # the widest invocation over every section decides the help column
        max_len = 0
        for a in positionals + optionals:
            n = len(self._invocation(a)) + 2
            if n > max_len:
                max_len = n
            for name, h in a.choice_help:
                n = len(name) + 4
                if n > max_len:
                    max_len = n
        help_position = min(max_len + 2, max_help_position)

        out = self._format_usage("usage: ") + "\n\n"
        if self.description is not None:
            out = out + _fill_text(self.description, max(width, 11), "",
                                   raw_description) + "\n\n"
        sections = [("positional arguments", positionals), ("options", optionals)]
        for heading, actions in sections:
            if not actions:
                continue
            out = out + heading + ":\n"
            for a in actions:
                out = out + _format_action(self._invocation(a), a.help, 2,
                                           help_position, width, raw_text)
                for name, h in a.choice_help:
                    out = out + _format_action(name, h, 4, help_position, width,
                                               raw_text)
            out = out + "\n"
        if self.epilog is not None:
            out = out + _fill_text(self.epilog, max(width, 11), "",
                                   raw_description) + "\n\n"
        while out.endswith("\n"):
            out = out[:-1]
        return out + "\n"

    # A caller's `file=` is written to; the default streams are named at the
    # write instead of being passed around as values. CPython's own spelling is
    # `self.print_usage(_sys.stderr)`, and under NilPy a stream held in a
    # variable is a bare fd with no methods, so `file.write` would raise at run
    # time (bug-n-a-sys-stream-in-a-variable-has-no-methods-and-fails-at-run-time).
    # Revert to passing the stream when that ticket lands.
    def print_usage(self, file=None):
        if file is None:
            sys.stdout.write(self.format_usage())
        else:
            file.write(self.format_usage())

    def print_help(self, file=None):
        if file is None:
            sys.stdout.write(self.format_help())
        else:
            file.write(self.format_help())

    def exit(self, status=0, message=None):
        if message:
            sys.stderr.write(message)
        sys.exit(status)

    def error(self, message):
        sys.stderr.write(self.format_usage())
        self.exit(2, self.prog + ": error: " + message + "\n")


def isinstance_formatter(cls, base):
    # formatter_class is a CLASS, not an instance; walk its bases by name so a
    # caller's own subclass of a Raw formatter is honoured too
    if cls is None:
        return False
    if cls is base:
        return True
    if base is RawDescriptionHelpFormatter and cls is RawTextHelpFormatter:
        return True
    return False


def _get_lines(parts, indent, text_width, prefix):
    lines = []
    line = []
    indent_length = len(indent)
    if prefix is not None:
        line_len = len(prefix) - 1
    else:
        line_len = indent_length - 1
    for part in parts:
        if line_len + 1 + len(part) > text_width and line:
            lines.append(indent + " ".join(line))
            line = []
            line_len = indent_length - 1
        line.append(part)
        line_len = line_len + len(part) + 1
    if line:
        lines.append(indent + " ".join(line))
    if prefix is not None and lines:
        lines[0] = lines[0][indent_length:]
    return lines


def _normalize_ws(text):
    return " ".join(text.split())


def _is_letter(c):
    return c.isalpha()


def _chunks(word):
    # textwrap's break_on_hyphens: a word splits after a hyphen that follows
    # two letters (or letter-hyphen-letter) and precedes a letter
    out = []
    start = 0
    i = 1
    while i < len(word) - 1:
        if word[i] == "-" and _is_letter(word[i + 1]):
            two = i >= 2 and _is_letter(word[i - 1]) and _is_letter(word[i - 2])
            lhl = i >= 3 and _is_letter(word[i - 1]) and word[i - 2] == "-" and \
                _is_letter(word[i - 3])
            if two or lhl:
                out.append(word[start:i + 1])
                start = i + 1
        i = i + 1
    out.append(word[start:])
    return out


def _wrap(text, width):
    words = _normalize_ws(text).split(" ")
    chunks = []
    for w in words:
        if w == "":
            continue
        if chunks:
            chunks.append(" ")
        for c in _chunks(w):
            chunks.append(c)
    lines = []
    cur = []
    cur_len = 0
    for c in chunks:
        if c == " " and not cur:
            continue
        if cur and cur_len + len(c) > width:
            while cur and cur[-1] == " ":
                cur_len = cur_len - 1
                cur = cur[:-1]
            lines.append("".join(cur))
            cur = []
            cur_len = 0
            if c == " ":
                continue
        cur.append(c)
        cur_len = cur_len + len(c)
    while cur and cur[-1] == " ":
        cur = cur[:-1]
    if cur:
        lines.append("".join(cur))
    return lines


def _fill_text(text, width, indent, raw):
    if raw:
        out = []
        for line in text.splitlines():
            out.append(indent + line)
        return "\n".join(out)
    lines = _wrap(text, width - len(indent))
    out = []
    for line in lines:
        out.append(indent + line)
    return "\n".join(out)


def _format_action(header, help, indent, help_position, width, raw):
    help_width = max(width - help_position, 11)
    action_width = help_position - indent - 2
    if not help:
        return " " * indent + header + "\n"
    if len(header) <= action_width:
        out = " " * indent + header + " " * (action_width - len(header)) + "  "
        indent_first = 0
    else:
        out = " " * indent + header + "\n"
        indent_first = help_position
    if help.strip():
        if raw:
            lines = help.splitlines()
        else:
            lines = _wrap(help, help_width)
        out = out + " " * indent_first + lines[0] + "\n"
        for line in lines[1:]:
            out = out + " " * help_position + line + "\n"
    else:
        out = out + "\n"
    return out


class _Parse:
    """One parse of one parser over one argument list: CPython's
    _parse_known_args, with its closures as methods."""

    def __init__(self, parser, arg_strings, namespace, extras):
        self.p = parser
        self.arg_strings = arg_strings
        self.ns = namespace
        self.extras = extras
        self.seen = []
        self.positionals = []
        for a in parser._actions:
            if not a.option_strings:
                self.positionals.append(a)
        # classify: 'O' option, 'A' argument, '-' the '--' marker
        self.option_indices = {}
        pattern = []
        i = 0
        after_dashes = False
        for s in arg_strings:
            if after_dashes:
                pattern.append("A")
            elif s == "--":
                pattern.append("-")
                after_dashes = True
            else:
                tuples = parser._parse_optional(s)
                if tuples is None:
                    pattern.append("A")
                else:
                    self.option_indices[i] = tuples
                    pattern.append("O")
            i = i + 1
        self.pattern = "".join(pattern)

    def take_action(self, action, argument_strings, option_string=None):
        self.seen.append(action)
        values = self.p._get_values(action, argument_strings)
        kind = action.kind
        if kind == "help":
            self.p.print_help()
            sys.exit(0)
        elif kind == "store_true":
            self.ns._set(action.dest, True)
        elif kind == "store_false":
            self.ns._set(action.dest, False)
        elif kind == "parsers":
            name = values[0]
            rest = values[1:]
            if action.dest != SUPPRESS:
                self.ns._set(action.dest, name)
            sub = action.parsers[name]
            subns = Namespace()
            sub_extras = []
            try:
                sub._parse_into(rest, subns, sub_extras)
            except ArgumentError as err:
                sub.error(str(err))
            for k in subns._values:
                self.ns._set(k, subns._values[k])
            for e in sub_extras:
                self.extras.append(e)
        else:
            self.ns._set(action.dest, values)

    def consume_optional(self, start_index):
        tuples = self.option_indices[start_index]
        if len(tuples) > 1:
            names = []
            for t in tuples:
                names.append(t[1])
            raise ArgumentError(None, "ambiguous option: " +
                                self.arg_strings[start_index] +
                                " could match " + ", ".join(names))
        action, option_string, sep, explicit_arg = tuples[0]
        pending = []
        stop = start_index + 1
        while True:
            if action is None:
                self.extras.append(self.arg_strings[start_index])
                return start_index + 1
            if explicit_arg is not None:
                arg_count = _match_count(_optional_spec(action), "A")
                if arg_count == 0 and option_string[1] != "-" and explicit_arg != "":
                    if sep or explicit_arg[0] == "-":
                        raise ArgumentError(action.name(), "ignored explicit argument " +
                                            repr(explicit_arg))
                    pending.append((action, [], option_string))
                    option_string = "-" + explicit_arg[0]
                    if option_string in self.p._option_actions:
                        action = self.p._option_actions[option_string]
                        explicit_arg = explicit_arg[1:]
                        if not explicit_arg:
                            sep = None
                            explicit_arg = None
                        elif explicit_arg[0] == "=":
                            sep = "="
                            explicit_arg = explicit_arg[1:]
                        else:
                            sep = ""
                    else:
                        self.extras.append("-" + explicit_arg)
                        stop = start_index + 1
                        break
                elif arg_count == 1:
                    stop = start_index + 1
                    pending.append((action, [explicit_arg], option_string))
                    break
                else:
                    raise ArgumentError(action.name(), "ignored explicit argument " +
                                        repr(explicit_arg))
            else:
                start = start_index + 1
                arg_count = _match_count(_optional_spec(action), self.pattern[start:])
                if arg_count < 0:
                    raise ArgumentError(action.name(), _nargs_error(action.nargs))
                stop = start + arg_count
                pending.append((action, self.arg_strings[start:stop], option_string))
                break
        for action, args, option_string in pending:
            self.take_action(action, args, option_string)
        return stop

    def consume_positionals(self, start_index):
        counts = _match_partial(self.positionals, self.pattern[start_index:])
        n = 0
        for arg_count in counts:
            action = self.positionals[n]
            args = self.arg_strings[start_index:start_index + arg_count]
            if action.nargs == PARSER:
                if self.pattern[start_index] == "-":
                    args = args[1:]
            else:
                seg = self.pattern[start_index:start_index + arg_count]
                if "-" in seg:
                    k = args.index("--")
                    args = args[:k] + args[k + 1:]
            start_index = start_index + arg_count
            self.take_action(action, args)
            n = n + 1
        self.positionals = self.positionals[n:]
        return start_index

    def run(self):
        max_option_index = -1
        for k in self.option_indices:
            if k > max_option_index:
                max_option_index = k
        start_index = 0
        while start_index <= max_option_index:
            next_option = start_index
            while next_option <= max_option_index:
                if next_option in self.option_indices:
                    break
                next_option = next_option + 1
            if start_index != next_option:
                end = self.consume_positionals(start_index)
                if end > start_index:
                    start_index = end
                    continue
                start_index = end
            if start_index not in self.option_indices:
                for s in self.arg_strings[start_index:next_option]:
                    self.extras.append(s)
                start_index = next_option
            start_index = self.consume_optional(start_index)
        stop_index = self.consume_positionals(start_index)
        for s in self.arg_strings[stop_index:]:
            self.extras.append(s)

        required = []
        for a in self.p._actions:
            if a in self.seen:
                continue
            if a.required:
                required.append(a.name())
            elif a.default is not None and isinstance(a.default, str) and \
                    self.ns._has(a.dest) and a.default is self.ns._values[a.dest]:
                self.ns._set(a.dest, self.p._get_value(a, a.default))
        if required:
            raise ArgumentError(None, "the following arguments are required: " +
                                ", ".join(required))


def _nargs_error(nargs):
    if nargs is None:
        return "expected one argument"
    if nargs == OPTIONAL:
        return "expected at most one argument"
    if nargs == ONE_OR_MORE:
        return "expected at least one argument"
    return "expected " + str(nargs) + " arguments"


# -- the pattern matcher ---------------------------------------------------
#
# CPython builds one regular expression per nargs and matches the whole
# command-line pattern with re. Every nargs pattern this shim accepts is a
# short sequence of "one character class, repeated between lo and hi times",
# so a spec is a list of (chars, lo, hi) and a backtracking matcher over those
# gives the same greedy-first answer re does.

_MANY = 1000000


def _positional_spec(action):
    n = action.nargs
    if n is None:
        return [("-", 0, _MANY), ("A", 1, 1), ("-", 0, _MANY)]
    if n == OPTIONAL:
        return [("-", 0, _MANY), ("A", 0, 1), ("-", 0, _MANY)]
    if n == ZERO_OR_MORE:
        return [("-", 0, _MANY), ("A-", 0, _MANY)]
    if n == ONE_OR_MORE:
        return [("-", 0, _MANY), ("A", 1, 1), ("A-", 0, _MANY)]
    if n == PARSER:
        return [("-", 0, _MANY), ("A", 1, 1), ("-AO", 0, _MANY)]
    return [("-", 0, _MANY)]        # nargs 0


def _optional_spec(action):
    n = action.nargs
    if n is None:
        return [("A", 1, 1)]
    if n == OPTIONAL:
        return [("A", 0, 1)]
    if n == ZERO_OR_MORE:
        return [("A", 0, _MANY)]
    if n == ONE_OR_MORE:
        return [("A", 1, 1), ("A", 0, _MANY)]
    return []                       # nargs 0


def _match_count(spec, pattern):
    # length of the greedy match of one optional's spec at the start of
    # pattern, or -1 for no match
    ends = _match_groups([spec], pattern)
    if ends is None:
        return -1
    return ends[0]


def _match_groups(specs, pattern):
    # match the concatenation of specs at the start of pattern; returns the
    # length each spec consumed, or None
    items = []          # (chars, lo, hi, group index)
    g = 0
    for spec in specs:
        for chars, lo, hi in spec:
            items.append((chars, lo, hi, g))
        g = g + 1
    lens = [0] * len(specs)
    if _match_from(items, 0, pattern, 0, lens):
        return lens
    return None


def _match_from(items, k, pattern, pos, lens):
    if k == len(items):
        return True
    chars, lo, hi, g = items[k]
    # how far can this item run?
    n = 0
    while n < hi and pos + n < len(pattern) and pattern[pos + n] in chars:
        n = n + 1
    if n < lo:
        return False
    while n >= lo:
        lens[g] = lens[g] + n
        if _match_from(items, k + 1, pattern, pos + n, lens):
            return True
        lens[g] = lens[g] - n
        n = n - 1
    return False


def _match_partial(actions, pattern):
    # CPython's _match_arguments_partial
    i = len(actions)
    while i > 0:
        specs = []
        for a in actions[:i]:
            specs.append(_positional_spec(a))
        lens = _match_groups(specs, pattern)
        if lens is not None:
            end = 0
            for n in lens:
                end = end + n
            if end < len(pattern) and pattern[end] == "O":
                while lens and not lens[-1]:
                    lens = lens[:-1]
            return lens
        i = i - 1
    return []
