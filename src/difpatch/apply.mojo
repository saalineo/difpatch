"""Apply a parsed patch to a byte buffer. Strict unless ApplyOptions opts in."""

from difpatch.format import hunk_header
from difpatch.parse import ParsedHunk, ParsedPatch
from difpatch.tokenize import LineSplitter, Span32, split


@fieldwise_init
struct ApplyOptions(Copyable):
    var max_offset: Int  # how far (in lines) a hunk may drift; 0 = exact position only
    var max_fuzz: Int    # context lines ignorable at each end of a hunk; removed lines never are

    def __init__(out self):
        self.max_offset = 0
        self.max_fuzz = 0


struct HunkResult(Copyable):
    var applied: Bool
    var offset: Int
    var fuzz: Int
    var message: String

    def __init__(out self, applied: Bool, offset: Int, fuzz: Int, var message: String):
        self.applied = applied
        self.offset = offset
        self.fuzz = fuzz
        self.message = message^


struct ApplyReport(Movable):
    """Output built from the hunks that applied; rejected hunks are listed in results."""
    var output: List[Byte]
    var results: List[HunkResult]

    def __init__(out self, var output: List[Byte], var results: List[HunkResult]):
        self.output = output^
        self.results = results^


def _same_line(orig: Span[Byte, _], o: Span32, patch: Span[Byte, _], line_start: UInt32, line_len: UInt32) -> Bool:
    if o.len != line_len:
        return False
    for i in range(Int(o.len)):
        if orig[Int(o.start) + i] != patch[Int(line_start) + i]:
            return False
    return True


def _show(src: Span[Byte, _], start: Int, length: Int) -> String:
    var shown = min(length, 40)
    while shown > 0 and (src[start + shown - 1] == 10 or src[start + shown - 1] == 13):
        shown -= 1
    return String(from_utf8_lossy=src[start : start + shown])


struct _Matcher:
    """Old-side view of one hunk: which patch lines must match the original."""
    var old_lines: List[Int]  # indices into hunk.lines for ' ' and '-' lines
    var lead_ctx: Int
    var trail_ctx: Int

    def __init__(out self, hunk: ParsedHunk):
        self.old_lines = List[Int]()
        for i in range(len(hunk.lines)):
            if hunk.lines[i].tag != 43:
                self.old_lines.append(i)
        self.lead_ctx = 0
        while self.lead_ctx < len(self.old_lines) and hunk.lines[self.old_lines[self.lead_ctx]].tag == 32:
            self.lead_ctx += 1
        self.trail_ctx = 0
        while self.trail_ctx < len(self.old_lines) and hunk.lines[self.old_lines[len(self.old_lines) - 1 - self.trail_ctx]].tag == 32:
            self.trail_ctx += 1

    def matches(
        self,
        hunk: ParsedHunk,
        orig: Span[Byte, _],
        lines: List[Span32],
        patch: Span[Byte, _],
        pos: Int,
        cursor: Int,
        fuzz: Int,
    ) -> Bool:
        var n = len(self.old_lines)
        if pos < cursor or pos + n > len(lines):
            return False
        var lead = min(fuzz, self.lead_ctx)
        var trail = min(fuzz, self.trail_ctx)
        if self.lead_ctx == n:  # nothing but context: never let fuzz make the match vacuous
            lead = 0
            trail = 0
        for j in range(lead, n - trail):
            ref pl = hunk.lines[self.old_lines[j]]
            if not _same_line(orig, lines[pos + j], patch, pl.start, pl.len):
                return False
        return True


def apply_report(
    original: Span[Byte, _], patch_text: Span[Byte, _], patch: ParsedPatch, opts: ApplyOptions
) raises -> ApplyReport:
    if opts.max_offset < 0 or opts.max_fuzz < 0:
        raise Error("difpatch apply: max_offset and max_fuzz must be >= 0")
    var lines = split(original, LineSplitter())
    var nlines = len(lines)
    var out = List[Byte](capacity=len(original) + patch.inserted_bytes)  # true upper bound
    var results = List[HunkResult]()
    var cursor = 0  # first original line not yet copied
    var out_unterminated = False

    for hi in range(len(patch.hunks)):
        ref h = patch.hunks[hi]
        var title = "hunk " + String(hi + 1) + " " + hunk_header(UInt32(h.old_start), UInt32(h.old_count), UInt32(h.new_start), UInt32(h.new_count))
        var m = _Matcher(h)
        var nold = len(m.old_lines)
        var p0 = h.old_start - 1 if h.old_count > 0 else h.old_start

        var pos = -1
        var offset = 0
        var fuzz = 0
        var ambiguous = False
        var first_dist = 0
        var last_pos = nlines - nold
        var last_dist = opts.max_offset
        if cursor > last_pos:
            last_dist = -1
        elif p0 < cursor:
            first_dist = cursor - p0
            last_dist = min(last_dist, last_pos - p0)
        elif p0 > last_pos:
            first_dist = p0 - last_pos
            last_dist = min(last_dist, p0 - cursor)
        else:
            last_dist = min(last_dist, max(p0 - cursor, last_pos - p0))
        for f in range(opts.max_fuzz + 1):
            for dist in range(first_dist, last_dist + 1):
                var fwd = m.matches(h, original, lines, patch_text, p0 + dist, cursor, f)
                var back = dist > 0 and m.matches(h, original, lines, patch_text, p0 - dist, cursor, f)
                if fwd and back:
                    ambiguous = True
                elif fwd:
                    pos = p0 + dist
                    offset = dist
                elif back:
                    pos = p0 - dist
                    offset = -dist
                if pos >= 0 or ambiguous:
                    fuzz = f
                    break
            if pos >= 0 or ambiguous:
                break

        if ambiguous:
            results.append(HunkResult(False, 0, 0, title + " matches equally well in more than one place; refusing to guess"))
            continue
        if pos < 0:
            # Explain the strict failure: first mismatching line at the stated position.
            var why = String("does not match")
            var at = p0
            for j in range(nold):
                ref pl = h.lines[m.old_lines[j]]
                if at + j >= nlines:
                    why = "does not match at line " + String(at + j + 1) + ": expected '" + _show(patch_text, Int(pl.start), Int(pl.len)) + "', found end of file"
                    break
                if not _same_line(original, lines[at + j], patch_text, pl.start, pl.len):
                    why = "does not match at line " + String(at + j + 1) + ": expected '" + _show(patch_text, Int(pl.start), Int(pl.len)) + "', found '" + _show(original, Int(lines[at + j].start), Int(lines[at + j].len)) + "'"
                    break
            results.append(HunkResult(False, 0, 0, title + " " + why))
            continue

        # A line without a newline may only be the last line of the output.
        var prev_unterminated = out_unterminated
        if pos > cursor:
            var last = lines[pos - 1]
            prev_unterminated = original[Int(last.start) + Int(last.len) - 1] != 10
        var eol_ok = True
        var oi = 0
        for li in range(len(h.lines)):
            ref pl = h.lines[li]
            if pl.tag == 45:
                oi += 1
                continue
            var terminated: Bool
            if pl.tag == 32:
                var o = lines[pos + oi]
                terminated = original[Int(o.start) + Int(o.len) - 1] == 10
                oi += 1
            else:
                terminated = not pl.no_eol
            if prev_unterminated:
                eol_ok = False
            prev_unterminated = not terminated
        if prev_unterminated and pos + nold != nlines:
            eol_ok = False
        if not eol_ok:
            results.append(HunkResult(False, 0, 0, title + " would put text after a line with no newline at end of file"))
            continue

        if pos > cursor:
            var from_byte = Int(lines[cursor].start)
            var to_byte = Int(lines[pos - 1].start) + Int(lines[pos - 1].len)
            out.extend(original[from_byte:to_byte])
        oi = 0
        for li in range(len(h.lines)):
            ref pl = h.lines[li]
            if pl.tag == 43:
                out.extend(patch_text[Int(pl.start) : Int(pl.start) + Int(pl.len)])
            else:
                if pl.tag == 32:  # keep the file's own bytes, which fuzz may make differ from the patch's
                    var o = lines[pos + oi]
                    out.extend(original[Int(o.start) : Int(o.start) + Int(o.len)])
                oi += 1
        out_unterminated = len(out) > 0 and out[len(out) - 1] != 10
        cursor = pos + nold
        var note = String("")
        if offset != 0 or fuzz != 0:
            note = title + " applied with offset " + String(offset) + ", fuzz " + String(fuzz)
        results.append(HunkResult(True, offset, fuzz, note))

    if cursor < nlines:
        out.extend(original[Int(lines[cursor].start) : len(original)])
    return ApplyReport(out^, results^)
