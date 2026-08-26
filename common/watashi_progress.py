#!/usr/bin/env python3
"""Watashi Manager progress window.

It runs a command, listens for the ####percent####title####text#### lines the
installer already prints, and paints them in the colours of the panel.
Nothing here is required for the install to work: if anything at all goes
wrong, the command is handed straight to the terminal instead.
Only the python standard library is used, so no package is ever fetched.
"""

import os
import re
import shutil
import signal
import subprocess
import sys
import time
from collections import deque

STEP = re.compile(r"^####(.*?)####(.*?)####(.*?)####\s*$")

VIOLET = (124, 58, 237)
LILAC = (167, 139, 250)
CYAN = (34, 211, 238)
MUTED = (139, 146, 165)
MINT = (16, 185, 129)
GRAD = [
    (124, 58, 237),
    (137, 71, 240),
    (112, 94, 243),
    (86, 118, 245),
    (62, 142, 243),
    (46, 168, 241),
    (36, 190, 239),
    (34, 205, 238),
    (58, 216, 240),
]

WORD = "WATASHI MANAGER"


def spaced(word):
    """The name with air between the letters, the way the shell writes it."""
    out = ""
    for ch in word:
        out += "  " if ch == " " else ch + " "
    return out.rstrip()


def deep_colour():
    if os.environ.get("COLORTERM", "") in ("truecolor", "24bit"):
        return True
    term = os.environ.get("TERM", "")
    return "256" in term or term.startswith("xterm") or term.startswith("screen")


class Ink(object):
    def __init__(self, deep):
        self.deep = deep

    def fg(self, rgb):
        if not self.deep:
            return ""
        return "\033[38;2;%d;%d;%dm" % rgb

    def off(self):
        return "\033[0m"

    def bold(self):
        return "\033[1m"

    def faint(self):
        return "\033[2m"


def skin_wanted():
    if os.environ.get("WATASHI_TUI", "") in ("0", "off", "no", "false"):
        return False
    if os.environ.get("TERM", "") in ("", "dumb"):
        return False
    return sys.stdout.isatty()


def split_args(argv):
    title = "WATASHI MANAGER"
    subtitle = ""
    log = ""
    rest = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--title" and i + 1 < len(argv):
            title = argv[i + 1]
            i += 2
        elif a == "--subtitle" and i + 1 < len(argv):
            subtitle = argv[i + 1]
            i += 2
        elif a == "--log" and i + 1 < len(argv):
            log = argv[i + 1]
            i += 2
        else:
            rest.append(a)
            i += 1
    return title, subtitle, log, rest


class Window(object):
    def __init__(self, title, subtitle):
        self.ink = Ink(deep_colour())
        self.title = title
        self.subtitle = subtitle
        self.step = "Please wait"
        self.text = ""
        self.pct = 0
        self.tail = deque(maxlen=5)
        self.beat = 0
        self.painted = 0.0
        self.opened = False

    def open(self):
        sys.stdout.write("\033[?1049h\033[?25l")
        sys.stdout.flush()
        self.opened = True

    def close(self):
        if self.opened:
            sys.stdout.write("\033[?25h\033[?1049l\033[0m")
            sys.stdout.flush()
            self.opened = False

    def middle(self, width, w):
        pad = (width - w) // 2
        return " " * max(pad, 0)

    def paint(self, force=False):
        now = time.time()
        if not force and now - self.painted < 0.09:
            return
        self.painted = now
        self.beat += 1
        ink = self.ink
        size = shutil.get_terminal_size((80, 24))
        width = max(size.columns, 40)
        out = ["\033[H\033[2J", "\n"]
        mark = spaced(WORD)
        letters = []
        for i, ch in enumerate(mark):
            tint = GRAD[min(int(i * len(GRAD) / max(len(mark), 1)), len(GRAD) - 1)]
            letters.append("%s%s%s" % (ink.bold(), ink.fg(tint), ch))
        out.append(
            "%s%s%s\n" % (self.middle(width, len(mark)), "".join(letters), ink.off())
        )
        name = self.title.split(" ")
        head = "%s%s%s%s" % (ink.bold(), ink.fg(LILAC), name[0], ink.off())
        if len(name) > 1:
            head += " %s%s%s%s" % (ink.bold(), ink.fg(CYAN), " ".join(name[1:]), ink.off())
        out.append("%s%s\n" % (self.middle(width, len(self.title)), head))
        if self.subtitle:
            out.append(
                "%s%s%s%s\n"
                % (self.middle(width, len(self.subtitle)), ink.fg(MUTED), self.subtitle, ink.off())
            )
        stamp = os.environ.get("WS_VERSION_LINE", "").strip()
        if stamp:
            out.append(
                "%s%s%s%s\n"
                % (self.middle(width, len(stamp)), ink.fg(MINT), stamp, ink.off())
            )
        out.append("\n")
        bar_w = min(width - 12, 52)
        if bar_w < 10:
            bar_w = 10
        filled = int(bar_w * self.pct / 100.0)
        bar = []
        for i in range(bar_w):
            tint = GRAD[int(i * (len(GRAD) - 1) / max(bar_w - 1, 1))]
            if i < filled:
                bar.append("%s\u2588" % ink.fg(tint))
            else:
                bar.append("%s\u2591" % ink.fg(MUTED))
        out.append(
            "%s%s%s %s%3d%%%s\n"
            % (
                self.middle(width, bar_w + 5),
                "".join(bar),
                ink.off(),
                ink.fg(CYAN),
                self.pct,
                ink.off(),
            )
        )
        out.append("\n")
        line = self.step
        if self.text:
            line = "%s   %s" % (self.step, self.text)
        line = line[: width - 4]
        out.append(
            "%s%s%s%s%s\n"
            % (self.middle(width, len(line)), ink.bold(), ink.fg(LILAC), line, ink.off())
        )
        out.append("\n")
        for row in self.tail:
            row = row[: width - 6]
            out.append("   %s%s%s%s\n" % (ink.faint(), ink.fg(MUTED), row, ink.off()))
        sys.stdout.write("".join(out))
        sys.stdout.flush()


def hand_over(cmd, log):
    """Run the command with no window at all."""
    if not cmd:
        return 0
    handle = None
    if log:
        try:
            handle = open(log, "a", buffering=1, errors="replace")
        except Exception:
            handle = None
    child = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    while True:
        raw = child.stdout.readline()
        if not raw:
            break
        row = raw.decode("utf-8", "replace")
        sys.stdout.write(row)
        sys.stdout.flush()
        if handle:
            handle.write(row)
    child.stdout.close()
    code = child.wait()
    if handle:
        handle.close()
    return code


def run(title, subtitle, log, cmd):
    win = Window(title, subtitle)
    handle = None
    if log:
        try:
            folder = os.path.dirname(log)
            if folder and not os.path.isdir(folder):
                os.makedirs(folder)
            handle = open(log, "a", buffering=1, errors="replace")
        except Exception:
            handle = None
    child = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    win.open()
    win.paint(True)
    try:
        while True:
            raw = child.stdout.readline()
            if not raw:
                break
            row = raw.decode("utf-8", "replace").rstrip("\n").rstrip("\r")
            if handle:
                handle.write(row + "\n")
            found = STEP.match(row)
            if found:
                pct, step, text = found.group(1), found.group(2), found.group(3)
                try:
                    win.pct = max(0, min(100, int(float(pct))))
                except Exception:
                    pass
                if step:
                    win.step = step
                win.text = text
                win.paint(True)
            else:
                if row.strip():
                    win.tail.append(row.strip())
                win.paint()
    except KeyboardInterrupt:
        try:
            child.send_signal(signal.SIGINT)
        except Exception:
            pass
    finally:
        try:
            child.stdout.close()
        except Exception:
            pass
        code = child.wait()
        win.close()
        if handle:
            handle.close()
    return code


def main():
    title, subtitle, log, cmd = split_args(sys.argv[1:])
    if not cmd:
        return 0
    if not skin_wanted():
        return hand_over(cmd, log)
    try:
        return run(title, subtitle, log, cmd)
    except Exception:
        sys.stdout.write("\033[?25h\033[?1049l\033[0m")
        sys.stdout.flush()
        return hand_over(cmd, log)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.stdout.write("\033[?25h\033[?1049l\033[0m")
        sys.exit(130)
