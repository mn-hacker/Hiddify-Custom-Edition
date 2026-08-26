#!/usr/bin/env python3
"""Watashi Manager progress window.

It runs a command, listens for the ####percent####title####text#### lines the
installer already prints, and paints them in the colours of the panel.
The log fills the whole screen and can be read with the arrow keys, so an
error never hides behind the newest line. When the command fails, the window
waits so the log can be read before it disappears.
Nothing here is required for the install to work: if anything at all goes
wrong, the command is handed straight to the terminal instead.
Only the python standard library is used, so no package is ever fetched.
"""

import os
import re
import select
import shutil
import signal
import subprocess
import sys
import time

try:
    import termios
    import tty
except Exception:
    termios = None
    tty = None

STEP = re.compile(r"^####(.*?)####(.*?)####(.*?)####\s*$")
PAINTED = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]|\x1b[()][AB0]|\x1b[=>]|[\r\x07]")

VIOLET = (124, 58, 237)
LILAC = (167, 139, 250)
CYAN = (34, 211, 238)
MUTED = (139, 146, 165)
MINT = (16, 185, 129)
AMBER = (245, 158, 11)
ROSE = (239, 68, 68)
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
KEEP = 6000
HOLD = 120.0


def spaced(word):
    """The name with air between the letters, the way the shell writes it."""
    out = ""
    for ch in word:
        out += "  " if ch == " " else ch + " "
    return out.rstrip()


def colour_mode():
    if os.environ.get("WATASHI_TUI", "") in ("0", "off", "no", "false"):
        return "none"
    term = os.environ.get("TERM", "")
    if term in ("", "dumb"):
        return "none"
    if os.environ.get("COLORTERM", "") in ("truecolor", "24bit"):
        return "deep"
    if "256" in term:
        return "cube"
    return "basic"


def deep_colour():
    return colour_mode() != "none"


BASIC = {
    (124, 58, 237): 95,
    (167, 139, 250): 95,
    (59, 130, 246): 94,
    (34, 211, 238): 96,
    (16, 185, 129): 92,
    (245, 158, 11): 93,
    (239, 68, 68): 91,
    (139, 146, 165): 37,
}


def basic_code(rgb):
    key = tuple(rgb)
    if key in BASIC:
        return BASIC[key]
    r, g, b = key
    top = max(r, g, b, 1)
    t = top * 7 // 10
    hi = (1 if r >= t else 0) + (2 if g >= t else 0) + (4 if b >= t else 0)
    return {1: 91, 2: 92, 3: 93, 4: 94, 5: 95, 6: 96}.get(hi, 97)


class Ink(object):
    def __init__(self, mode):
        if mode is True:
            mode = "deep"
        elif mode is False:
            mode = "none"
        self.mode = mode
        self.deep = mode != "none"

    def fg(self, rgb):
        if self.mode == "deep":
            return "\033[38;2;%d;%d;%dm" % tuple(rgb)
        if self.mode == "cube":
            r, g, b = tuple(rgb)
            idx = 16 + 36 * ((r * 5 + 127) // 255) + 6 * ((g * 5 + 127) // 255)
            idx += (b * 5 + 127) // 255
            return "\033[38;5;%dm" % idx
        if self.mode == "basic":
            return "\033[%dm" % basic_code(rgb)
        return ""

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


class Keys(object):
    """The keyboard, borrowed politely and always given back."""

    NAMES = {
        "j": "down",
        "k": "up",
        " ": "pgdn",
        "b": "pgup",
        "g": "home",
        "G": "end",
        "f": "follow",
        "q": "quit",
        "Q": "quit",
        "\r": "quit",
        "\n": "quit",
    }
    MOVES = {
        "A": "up",
        "B": "down",
        "5": "pgup",
        "6": "pgdn",
        "H": "home",
        "F": "end",
    }

    def __init__(self):
        self.fd = None
        self.saved = None

    def take(self):
        if termios is None or tty is None:
            return False
        try:
            if not sys.stdin.isatty():
                return False
            self.fd = sys.stdin.fileno()
            self.saved = termios.tcgetattr(self.fd)
            tty.setcbreak(self.fd)
            self.drop()
            return True
        except Exception:
            self.fd = None
            self.saved = None
            return False

    def drop(self):
        """Throw away whatever was typed while nobody was listening."""
        if self.fd is None or termios is None:
            return
        try:
            termios.tcflush(self.fd, termios.TCIFLUSH)
        except Exception:
            pass

    def give_back(self):
        self.drop()
        if self.fd is not None and self.saved is not None and termios is not None:
            try:
                termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
            except Exception:
                pass
        self.fd = None
        self.saved = None

    def read(self):
        if self.fd is None:
            return []
        try:
            data = os.read(self.fd, 1024).decode("utf-8", "replace")
        except Exception:
            return []
        out = []
        i = 0
        while i < len(data):
            ch = data[i]
            if ch == "\033":
                chunk = data[i : i + 5]
                hit = ""
                for mark, name in self.MOVES.items():
                    if chunk.startswith("\033[" + mark) or chunk.startswith("\033O" + mark):
                        hit = name
                        break
                if hit:
                    out.append(hit)
                    i += 4 if "~" in chunk[:4] else 3
                    continue
                i += 1
                continue
            name = self.NAMES.get(ch, "")
            if name:
                out.append(name)
            i += 1
        return out


class Window(object):
    def __init__(self, title, subtitle):
        self.ink = Ink(colour_mode())
        self.title = title
        self.subtitle = subtitle
        self.step = "Please wait"
        self.text = ""
        self.pct = 0
        self.lines = []
        self.anchor = 0
        self.follow = True
        self.log_h = 10
        self.note = ""
        self.beat = 0
        self.painted = 0.0
        self.opened = False
        self.keys_live = False

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

    def feed(self, row, handle=None):
        row = row.rstrip("\n")
        if handle:
            handle.write(row + "\n")
        found = STEP.match(row.strip())
        if found:
            pct, step, text = found.group(1), found.group(2), found.group(3)
            try:
                self.pct = max(0, min(100, int(float(pct))))
            except Exception:
                pass
            if step:
                self.step = step
            self.text = text
            return True
        clean = PAINTED.sub("", row).rstrip()
        if clean.strip():
            self.lines.append(clean)
            if len(self.lines) > KEEP:
                del self.lines[: len(self.lines) - KEEP]
                self.anchor = max(0, self.anchor - 1)
        return False

    def tint(self, row):
        low = row.lower()
        for bad in ("error", "failed", "failure", "fatal", "cannot", "traceback"):
            if bad in low:
                return ROSE
        if "warn" in low:
            return AMBER
        return MUTED

    def wrap(self, rows, w):
        out = []
        for row in rows:
            tint = self.tint(row)
            if not row:
                out.append(("", tint))
                continue
            while len(row) > w:
                out.append((row[:w], tint))
                row = row[w:]
            out.append((row, tint))
        return out

    def key(self, name):
        total = len(self.lines)
        page = max(self.log_h - 1, 1)
        floor = max(0, total - self.log_h)
        if name in ("up", "pgup", "home") and self.follow:
            self.follow = False
            self.anchor = floor
        if name == "up":
            self.anchor = max(0, self.anchor - 1)
        elif name == "down":
            self.anchor += 1
        elif name == "pgup":
            self.anchor = max(0, self.anchor - page)
        elif name == "pgdn":
            self.anchor += page
        elif name == "home":
            self.anchor = 0
        elif name == "end":
            self.follow = True
        elif name == "follow":
            self.follow = not self.follow
            if not self.follow:
                self.anchor = floor
        if not self.follow and self.anchor >= floor:
            self.anchor = floor
            if name in ("down", "pgdn", "end"):
                self.follow = True
        self.paint(True)

    def paint(self, force=False):
        now = time.time()
        if not force and now - self.painted < 0.08:
            return
        self.painted = now
        self.beat += 1
        ink = self.ink
        size = shutil.get_terminal_size((80, 24))
        width = max(size.columns, 40)
        rows = max(size.lines, 14)
        frame = width - 4
        if frame < 36:
            frame = width
        side = self.middle(width, frame)
        head = []
        head.append("")
        mark = spaced(WORD)
        letters = []
        for i, ch in enumerate(mark):
            tint = GRAD[min(int(i * len(GRAD) / max(len(mark), 1)), len(GRAD) - 1)]
            letters.append("%s%s%s" % (ink.bold(), ink.fg(tint), ch))
        head.append("%s%s%s" % (self.middle(width, len(mark)), "".join(letters), ink.off()))
        name = self.title.split(" ")
        crown = "%s%s%s%s" % (ink.bold(), ink.fg(LILAC), name[0], ink.off())
        if len(name) > 1:
            crown += " %s%s%s%s" % (ink.bold(), ink.fg(CYAN), " ".join(name[1:]), ink.off())
        bare = re.sub(r"[^a-z]", "", self.title.lower())
        if self.title and "watashi" not in bare:
            head.append("%s%s" % (self.middle(width, len(self.title)), crown))
        if self.subtitle:
            head.append(
                "%s%s%s%s"
                % (self.middle(width, len(self.subtitle)), ink.fg(MUTED), self.subtitle, ink.off())
            )
        stamp = os.environ.get("WS_VERSION_LINE", "").strip()
        if stamp:
            head.append(
                "%s%s%s%s" % (self.middle(width, len(stamp)), ink.fg(MINT), stamp, ink.off())
            )
        head.append("")
        bar_w = max(frame - 8, 12)
        filled = int(bar_w * self.pct / 100.0)
        bar = []
        for i in range(bar_w):
            tint = GRAD[int(i * (len(GRAD) - 1) / max(bar_w - 1, 1))]
            bar.append("%s%s" % (ink.fg(tint), "\u2588" if i < filled else "\u2591"))
        head.append(
            "%s%s%s %s%s%3d%%%s"
            % (side, "".join(bar), ink.off(), ink.bold(), ink.fg(CYAN), self.pct, ink.off())
        )
        head.append("")
        line = self.step
        if self.text:
            line = "%s   %s" % (self.step, self.text)
        line = line[: frame - 2]
        head.append(
            "%s%s%s%s%s" % (self.middle(width, len(line)), ink.bold(), ink.fg(LILAC), line, ink.off())
        )
        head.append("")

        log_h = rows - len(head) - 4
        if log_h < 3:
            log_h = 3
        self.log_h = log_h
        inner = max(frame - 4, 20)
        total = len(self.lines)
        if self.follow:
            source = self.lines[-(log_h + 60) :]
            shown = self.wrap(source, inner)[-log_h:]
            where = "live   %d lines" % total
        else:
            source = self.lines[self.anchor : self.anchor + log_h + 60]
            shown = self.wrap(source, inner)[:log_h]
            where = "paused   line %d of %d" % (min(self.anchor + 1, max(total, 1)), total)
        while len(shown) < log_h:
            shown.append(("", MUTED))

        label = " LOG "
        top = "\u256d\u2500" + label + "\u2500" * max(frame - 4 - len(label), 0) + "\u2500\u256e"
        foot = "\u2570" + "\u2500" * max(frame - 2, 0) + "\u256f"
        out = ["\033[H\033[2J"]
        for row in head:
            out.append(row + "\n")
        out.append("%s%s%s%s\n" % (side, ink.fg(VIOLET), top, ink.off()))
        for row, tint in shown:
            out.append(
                "%s%s\u2502%s %s%-*s%s %s\u2502%s\n"
                % (
                    side,
                    ink.fg(VIOLET),
                    ink.off(),
                    ink.fg(tint),
                    inner,
                    row[:inner],
                    ink.off(),
                    ink.fg(VIOLET),
                    ink.off(),
                )
            )
        out.append("%s%s%s%s\n" % (side, ink.fg(VIOLET), foot, ink.off()))
        if self.note:
            hint = self.note
        elif self.keys_live:
            hint = "up down scroll   space page   g top   G bottom   f %s   %s" % (
                "pause" if self.follow else "follow",
                where,
            )
        else:
            hint = where
        hint = hint[: frame - 2]
        out.append("%s%s%s%s%s" % (side, ink.faint(), ink.fg(MUTED), hint, ink.off()))
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
    keys = Keys()
    win.keys_live = keys.take()
    try:
        signal.signal(signal.SIGWINCH, lambda *_: win.paint(True))
    except Exception:
        pass
    child = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        stdin=subprocess.DEVNULL if win.keys_live else None,
    )
    win.open()
    win.paint(True)
    out_fd = child.stdout.fileno()
    rest = b""
    try:
        while True:
            watch = [out_fd]
            if win.keys_live:
                watch.append(keys.fd)
            try:
                ready, _, _ = select.select(watch, [], [], 0.2)
            except Exception:
                ready = [out_fd]
            if win.keys_live and keys.fd in ready:
                for name in keys.read():
                    if name != "quit":
                        win.key(name)
            if out_fd in ready:
                try:
                    chunk = os.read(out_fd, 65536)
                except OSError:
                    chunk = b""
                if not chunk:
                    break
                rest += chunk
                while b"\n" in rest:
                    raw, rest = rest.split(b"\n", 1)
                    if win.feed(raw.decode("utf-8", "replace"), handle):
                        win.paint(True)
            win.paint()
        if rest.strip():
            win.feed(rest.decode("utf-8", "replace"), handle)
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
        hold = os.environ.get("WATASHI_LOG_HOLD", "")
        if win.keys_live and code != 0 and hold not in ("0", "off", "no"):
            win.note = "the run ended with code %d   -   up down to read the log, q to leave" % code
            keys.drop()
            win.paint(True)
            end = time.time() + HOLD
            while time.time() < end:
                try:
                    ready, _, _ = select.select([keys.fd], [], [], 0.4)
                except Exception:
                    break
                if ready:
                    names = keys.read()
                    if "quit" in names:
                        break
                    for name in names:
                        win.key(name)
                    win.paint(True)
        keys.give_back()
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
