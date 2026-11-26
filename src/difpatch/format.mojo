"""Render hunks as unified diff text."""

from difpatch.tokenize import Span32
from difpatch.types import Hunk, OpTag


def _range(start: UInt32, count: UInt32) -> String:
    # A count of 1 is written as just the start.
    if count == 1:
        return String(start)
    return String(start) + "," + String(count)


def hunk_header(old_start: UInt32, old_count: UInt32, new_start: UInt32, new_count: UInt32) -> String:
    return "@@ -" + _range(old_start, old_count) + " +" + _range(new_start, new_count) + " @@"


def _push(mut out: List[Byte], text: String):
    out.extend(text.as_bytes())


def _validate_label(label: String) raises:
    for b in label.as_bytes():
        if b == 10 or b == 13:
            raise Error("difpatch format: labels cannot contain line breaks")


def _push_line(mut out: List[Byte], prefix: Byte, src: Span[Byte, _], span: Span32):
    out.append(prefix)
    var end = Int(span.start) + Int(span.len)
    out.extend(src[Int(span.start) : end])
    if src[end - 1] != 10:
        _push(out, "\n\\ No newline at end of file\n")


def format_patch(
    hunks: List[Hunk],
    old: Span[Byte, _],
    old_spans: List[Span32],
    new: Span[Byte, _],
    new_spans: List[Span32],
    old_label: String,
    new_label: String,
) raises -> String:
    if len(hunks) == 0:
        return ""
    _validate_label(old_label)
    _validate_label(new_label)
    var out = List[Byte]()
    _push(out, "--- " + old_label + "\n+++ " + new_label + "\n")
    for hi in range(len(hunks)):
        ref hunk = hunks[hi]
        _push(out, hunk_header(hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count) + "\n")
        for op in hunk.ops:
            for k in range(Int(op.length)):
                if op.tag == OpTag.INSERT:
                    _push_line(out, 43, new, new_spans[Int(op.new_idx) + k])
                elif op.tag == OpTag.DELETE:
                    _push_line(out, 45, old, old_spans[Int(op.old_idx) + k])
                else:
                    _push_line(out, 32, old, old_spans[Int(op.old_idx) + k])
    return String(from_utf8=out)
