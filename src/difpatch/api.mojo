from difpatch.apply import ApplyOptions, apply_report
from difpatch.hunks import group_hunks
from difpatch.format import format_patch
from difpatch.myers import diff_ids
from difpatch.parse import parse_patch
from difpatch.types import DiffResult
from difpatch.tokenize import LineSplitter, tokenize_pair


def myers_diff(old: Span[UInt32, _], new: Span[UInt32, _], max_cost: UInt32 = 0) raises -> DiffResult:
    return diff_ids(old, new, max_cost)


def diff_lines(old: String, new: String, max_cost: UInt32 = 0) raises -> DiffResult:
    var pair = tokenize_pair(old.as_bytes(), new.as_bytes(), LineSplitter())
    return diff_ids(Span(pair.old.ids), Span(pair.new.ids), max_cost)


def unified_diff(
    old: String,
    new: String,
    context: Int = 3,
    old_label: String = "a/f.txt",
    new_label: String = "b/f.txt",
    max_cost: UInt32 = 0,
) raises -> String:
    """Unified diff of old -> new; empty string when they are identical."""
    # The API owns ---/+++ headers; the CLI only supplies its default labels.
    var old_bytes = old.as_bytes()
    var new_bytes = new.as_bytes()
    var pair = tokenize_pair(old_bytes, new_bytes, LineSplitter())
    var result = diff_ids(Span(pair.old.ids), Span(pair.new.ids), max_cost)
    var hunks = group_hunks(result.ops, context)
    return format_patch(hunks, old_bytes, pair.old.spans, new_bytes, pair.new.spans, old_label, new_label)


def apply_patch(
    original: String, patch: String, max_offset: Int = 0, max_fuzz: Int = 0
) raises -> String:
    """Apply a single-file unified diff. Strict by default: every hunk must match
    exactly where it says. Any rejected hunk raises; use apply_report for a dry run."""
    var patch_bytes = patch.as_bytes()
    var parsed = parse_patch(patch_bytes)
    var report = apply_report(original.as_bytes(), patch_bytes, parsed, ApplyOptions(max_offset, max_fuzz))
    for result in report.results:
        if not result.applied:
            raise Error(result.message)
    return String(from_utf8=report.output)
