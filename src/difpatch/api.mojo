def unified_diff(
    old: String,
    new: String,
    context: Int = 3,
    old_label: String = "a/f.txt",
    new_label: String = "b/f.txt",
) raises -> String:
    # The API owns ---/+++ headers; the CLI only supplies its default labels.
    _ = old
    _ = new
    _ = context
    _ = old_label
    _ = new_label
    raise Error("difpatch unified_diff: not implemented (Phase 1 foundations only)")


def apply_patch(original: String, patch: String) raises -> String:
    _ = original
    _ = patch
    raise Error("difpatch apply_patch: not implemented (Phase 1 foundations only)")
