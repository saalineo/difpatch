@fieldwise_init
struct PatchLine(Copyable):
    var tag: UInt8      # ' ', '-' or '+'
    var start: UInt32   # payload offset in the patch text
    var len: UInt32     # payload bytes; includes the terminator unless no_eol
    var no_eol: Bool


struct ParsedHunk(Movable):
    var old_start: Int
    var old_count: Int
    var new_start: Int
    var new_count: Int
    var lines: List[PatchLine]
    var text_start: Int  # the hunk's own bytes in the patch, for reject output
    var text_end: Int

    def __init__(out self, old_start: Int, old_count: Int, new_start: Int, new_count: Int, text_start: Int):
        self.old_start = old_start
        self.old_count = old_count
        self.new_start = new_start
        self.new_count = new_count
        self.lines = List[PatchLine]()
        self.text_start = text_start
        self.text_end = text_start


struct ParsedPatch(Movable):
    var old_label: String
    var new_label: String
    var hunks: List[ParsedHunk]
    var inserted_bytes: Int

    def __init__(out self):
        self.old_label = ""
        self.new_label = ""
        self.hunks = List[ParsedHunk]()
        self.inserted_bytes = 0


def _starts_with(text: Span[Byte, _], pos: Int, lit: StringLiteral) -> Bool:
    var b = lit.as_bytes()
    if pos + len(b) > len(text):
        return False
    for i in range(len(b)):
        if text[pos + i] != b[i]:
            return False
    return True


def _line_end(text: Span[Byte, _], pos: Int) -> Int:
    for i in range(pos, len(text)):
        if text[i] == 10:
            return i + 1
    return len(text)


def _line_no(text: Span[Byte, _], pos: Int) -> Int:
    var n = 1
    for i in range(min(pos, len(text))):
        if text[i] == 10:
            n += 1
    return n


def _label(text: Span[Byte, _], pos: Int) -> String:
    var end = _line_end(text, pos)
    var stop = pos + 4
    while stop < end and text[stop] != 9 and text[stop] != 10 and text[stop] != 13:
        stop += 1
    return String(from_utf8_lossy=text[pos + 4 : stop])


def _digits(text: Span[Byte, _], mut p: Int, end: Int) raises -> Int:
    var start = p
    var v = 0
    while p < end and text[p] >= 48 and text[p] <= 57:
        v = v * 10 + Int(text[p] - 48)
        p += 1
        if v > 0x7FFFFFFF:
            raise Error("number too large")
    if p == start:
        raise Error("expected a number")
    return v


def _expect(text: Span[Byte, _], mut p: Int, lit: StringLiteral) raises:
    if not _starts_with(text, p, lit):
        raise Error("expected '" + String(lit) + "'")
    p += len(lit.as_bytes())


def _parse_header(text: Span[Byte, _], pos: Int, end: Int) raises -> ParsedHunk:
    var p = pos
    _expect(text, p, "@@ -")
    var a = _digits(text, p, end)
    var b = 1
    if p < end and text[p] == 44:
        p += 1
        b = _digits(text, p, end)
    _expect(text, p, " +")
    var c = _digits(text, p, end)
    var d = 1
    if p < end and text[p] == 44:
        p += 1
        d = _digits(text, p, end)
    _expect(text, p, " @@")
    if (a == 0 and b > 0) or (c == 0 and d > 0):
        raise Error("start line 0 needs a line count of 0")
    return ParsedHunk(a, b, c, d, pos)


def _mark_no_eol(text: Span[Byte, _], mut hunk: ParsedHunk, at: Int) raises:
    if len(hunk.lines) == 0 or hunk.lines[len(hunk.lines) - 1].no_eol:
        raise Error("difpatch parse: stray '\\ No newline' marker at line " + String(_line_no(text, at)))
    ref last = hunk.lines[len(hunk.lines) - 1]
    var end = Int(last.start) + Int(last.len)
    if text[end - 1] == 10:  # the patch's own line terminator is not file content
        last.len -= 1
    last.no_eol = True


def _is_blank(text: Span[Byte, _], start: Int, end: Int) -> Bool:
    for i in range(start, end):
        if text[i] != 32 and text[i] != 10 and text[i] != 13 and text[i] != 9:
            return False
    return True


def _is_signature(text: Span[Byte, _], pos: Int) -> Bool:
    """The `git format-patch` trailer: "-- ", a version line, then only blank lines."""
    # shortcut: custom --signature text is rejected; widen only if users need it.
    if not (_starts_with(text, pos, "-- \n") or _starts_with(text, pos, "-- \r\n")):
        return False
    var version = _line_end(text, pos)
    if version >= len(text) or text[version] < 48 or text[version] > 57:
        return False
    return _is_blank(text, _line_end(text, version), len(text))


def parse_patch(text: Span[Byte, _]) raises -> ParsedPatch:
    var patch = ParsedPatch()
    var n = len(text)
    var pos = 0
    var found = False
    while pos < n:
        var e = _line_end(text, pos)
        if _starts_with(text, pos, "--- ") and _starts_with(text, e, "+++ "):
            found = True
            break
        pos = e
    if not found:
        if not _is_blank(text, 0, n):
            raise Error("difpatch parse: no unified diff header found")
        return patch^  # blank patch = no changes
    patch.old_label = _label(text, pos)
    pos = _line_end(text, pos)
    patch.new_label = _label(text, pos)
    pos = _line_end(text, pos)

    while pos < n:
        var e = _line_end(text, pos)
        if _starts_with(text, pos, "@@ "):
            var hunk: ParsedHunk
            try:
                hunk = _parse_header(text, pos, e)
            except err:
                raise Error("difpatch parse: malformed hunk header at line " + String(_line_no(text, pos)) + ": " + String(err))
            var old_rem = hunk.old_count
            var new_rem = hunk.new_count
            pos = e
            while old_rem > 0 or new_rem > 0:
                if pos >= n:
                    raise Error("difpatch parse: hunk " + String(len(patch.hunks) + 1) + " is truncated")
                var le = _line_end(text, pos)
                var c = text[pos]
                if c == 92:  # '\'
                    _mark_no_eol(text, hunk, pos)
                    pos = le
                    continue
                var tag = c
                var payload = pos + 1
                if c == 10 or (c == 13 and le - pos == 2):  # blank line: context with its trailing space stripped
                    tag = 32
                    payload = pos
                if tag == 32 and old_rem > 0 and new_rem > 0:
                    old_rem -= 1
                    new_rem -= 1
                elif tag == 45 and old_rem > 0:
                    old_rem -= 1
                elif tag == 43 and new_rem > 0:
                    new_rem -= 1
                    patch.inserted_bytes += le - payload
                else:
                    raise Error("difpatch parse: unexpected line " + String(_line_no(text, pos)) + " in hunk " + String(len(patch.hunks) + 1))
                hunk.lines.append(PatchLine(tag, UInt32(payload), UInt32(le - payload), False))
                pos = le
            if pos < n and text[pos] == 92:
                _mark_no_eol(text, hunk, pos)
                pos = _line_end(text, pos)
            var signed = _is_signature(text, pos)
            if pos < n and not signed:  # more hunk lines than the header promised
                var c = text[pos]
                var next_e = _line_end(text, pos)
                var next_file = _starts_with(text, pos, "--- ") and _starts_with(text, next_e, "+++ ")
                if not next_file and (c == 32 or c == 43 or c == 45):
                    raise Error("difpatch parse: hunk " + String(len(patch.hunks) + 1) + " has more lines than its header counts")
            hunk.text_end = pos
            patch.hunks.append(hunk^)
            if signed:
                break
        elif (_starts_with(text, pos, "--- ") and _starts_with(text, e, "+++ ")) or _starts_with(text, pos, "diff "):
            raise Error("difpatch parse: multiple files in one patch are not supported (line " + String(_line_no(text, pos)) + ")")
        elif _is_blank(text, pos, e):
            pos = e
        else:  # skipping it could silently drop a hunk with a damaged header
            raise Error("difpatch parse: unexpected text at line " + String(_line_no(text, pos)))
    return patch^
