from difpatch import DiffResult, EditOp, Hunk, OpTag
from support.oracle import lcs_length, minimal_edit_distance, reconstruct
from support.prng import Prng, copy_lines, mutate, random_lines


def assert_true(condition: Bool, message: String) raises:
    if not condition:
        raise Error(message)


def assert_rejected(result: DiffResult, name: String) raises:
    var rejected = False
    try:
        result.validate()
    except e:
        _ = e
        rejected = True
    assert_true(rejected, "validate accepted " + name)


def same_lines(left: List[String], right: List[String]) -> Bool:
    if len(left) != len(right):
        return False
    for index in range(len(left)):
        if left[index] != right[index]:
            return False
    return True


def has_duplicate(lines: List[String]) -> Bool:
    for left in range(len(lines)):
        for right in range(left + 1, len(lines)):
            if lines[left] == lines[right]:
                return True
    return False


def has_diff_syntax(lines: List[String]) -> Bool:
    for line in lines:
        if line == "--- a/f.txt" or line == "+++ b/f.txt" or line == "@@ -1,2 +1,2 @@":
            return True
    return False


def main() raises:
    var lcs_left: List[String] = ["a", "b", "c", "b", "d", "a", "b"]
    var lcs_right: List[String] = ["b", "d", "c", "a", "b", "a"]
    assert_true(lcs_length(lcs_left, lcs_right) == 4, "wrong known LCS length")
    assert_true(minimal_edit_distance(lcs_left, lcs_right) == 5, "wrong known edit distance")

    var first_rng = Prng(0)
    var second_rng = Prng(0)
    var first_lines = random_lines(first_rng)
    var second_lines = random_lines(second_rng)
    assert_true(same_lines(first_lines, second_lines), "same seed generated different lines")
    var first_mutation = mutate(first_rng, copy_lines(first_lines), first_rng.bounded(8))
    var second_mutation = mutate(second_rng, copy_lines(second_lines), second_rng.bounded(8))
    assert_true(same_lines(first_mutation, second_mutation), "same seed generated different mutations")

    var seed_zero = Prng(0)
    var seed_one = Prng(1)
    assert_true(seed_zero.next_u32() != seed_one.next_u32(), "different seeds produced the same output")

    var saw_empty_input = False
    var saw_duplicate = False
    var saw_diff_syntax = False
    for seed in range(256):
        var generator = Prng(UInt64(seed))
        var lines = random_lines(generator)
        if len(lines) == 0:
            saw_empty_input = True
        if has_duplicate(lines):
            saw_duplicate = True
        if has_diff_syntax(lines):
            saw_diff_syntax = True
    assert_true(saw_empty_input, "generator never produced an empty input")
    assert_true(saw_duplicate, "generator never produced duplicate lines")
    assert_true(saw_diff_syntax, "generator never produced diff syntax")

    var good_ops: List[EditOp] = [
        EditOp(OpTag.EQUAL, 0, 0, 1),
        EditOp(OpTag.DELETE, 1, 1, 1),
        EditOp(OpTag.INSERT, 2, 1, 2),
        EditOp(OpTag.EQUAL, 2, 3, 1),
    ]
    var good = DiffResult(good_ops^, 3, 4)
    good.validate()
    assert_true(good.edit_distance() == 3, "wrong edit distance")

    var old: List[String] = ["same", "gone", "tail"]
    var new: List[String] = ["same", "fresh", "fresh", "tail"]
    var rebuild_ops: List[EditOp] = [
        EditOp(OpTag.EQUAL, 0, 0, 1),
        EditOp(OpTag.DELETE, 1, 1, 1),
        EditOp(OpTag.INSERT, 2, 1, 2),
        EditOp(OpTag.EQUAL, 2, 3, 1),
    ]
    var rebuilt = reconstruct(old, new, rebuild_ops)
    assert_true(len(rebuilt) == len(new), "reconstruct returned wrong length")
    for index in range(len(new)):
        assert_true(rebuilt[index] == new[index], "reconstruct returned wrong line")

    var empty_ops: List[EditOp] = [EditOp(OpTag.EQUAL, 0, 0, 0)]
    assert_rejected(DiffResult(empty_ops^, 0, 0), "empty op")

    var adjacent_ops: List[EditOp] = [
        EditOp(OpTag.EQUAL, 0, 0, 1),
        EditOp(OpTag.EQUAL, 1, 1, 1),
    ]
    assert_rejected(DiffResult(adjacent_ops^, 2, 2), "unmerged adjacent ops")

    var gap_ops: List[EditOp] = [EditOp(OpTag.EQUAL, 1, 0, 1)]
    assert_rejected(DiffResult(gap_ops^, 1, 1), "gap")

    var overlap_ops: List[EditOp] = [
        EditOp(OpTag.EQUAL, 0, 0, 1),
        EditOp(OpTag.DELETE, 0, 1, 1),
    ]
    assert_rejected(DiffResult(overlap_ops^, 2, 1), "overlap")

    var total_ops: List[EditOp] = [EditOp(OpTag.EQUAL, 0, 0, 1)]
    assert_rejected(DiffResult(total_ops^, 2, 1), "wrong totals")

    var unknown_ops: List[EditOp] = [EditOp(99, 0, 0, 1)]
    assert_rejected(DiffResult(unknown_ops^, 1, 1), "unknown tag")

    var hunk_ops: List[EditOp] = [EditOp(OpTag.EQUAL, 0, 0, 1)]
    var hunk = Hunk(1, 1, 1, 1, hunk_ops^)
    var hunks: List[Hunk] = []
    hunks.append(hunk^)
    var movable_ops: List[EditOp] = [EditOp(OpTag.EQUAL, 0, 0, 1)]
    var movable_result = DiffResult(movable_ops^, 1, 1)
    var results: List[DiffResult] = []
    results.append(movable_result^)
    print("oracle tests: PASS")
