from difpatch.api import apply_patch, unified_diff
from support.prng import Prng, copy_lines, join_lines, mutate, random_lines


def expect_round_trip(seed: UInt64, old: String, new: String) raises:
    try:
        var patch = unified_diff(old, new)
        var rebuilt = apply_patch(old, patch)
        if rebuilt != new:
            raise Error("round-trip seed " + String(seed) + ": patch result differs")
    except e:
        raise Error("round-trip seed " + String(seed) + ": " + String(e))


def main() raises:
    expect_round_trip(0, "", "")
    expect_round_trip(1, "", "one\n")
    expect_round_trip(2, "one\n", "")
    expect_round_trip(3, "same\n", "same\n")
    expect_round_trip(4, "old\n", "new\n")
    expect_round_trip(5, "one", "one\n")
    expect_round_trip(6, "one\n", "one")

    for seed in range(64):
        var rng = Prng(UInt64(seed))
        var old_lines = random_lines(rng)
        var edit_count = rng.bounded(8)
        var new_lines = mutate(rng, copy_lines(old_lines), edit_count)
        var old = join_lines(old_lines, rng.bounded(2) == 0)
        var new = join_lines(new_lines, rng.bounded(2) == 0)
        expect_round_trip(UInt64(seed), old, new)
