from difpatch.myers import diff_ids
from difpatch.types import DiffResult
from support.oracle import minimal_edit_distance, reconstruct
from support.prng import Prng


def strs(ids: List[UInt32]) -> List[String]:
    var out = List[String]()
    for id in ids:
        out.append(String(id))
    return out^


def check(old: List[UInt32], new: List[UInt32], max_cost: UInt32) raises:
    var result = diff_ids(Span(old), Span(new), max_cost)
    result.validate()
    var rebuilt = reconstruct(strs(old), strs(new), result.ops)
    if rebuilt != strs(new):
        raise Error("myers: reconstruct differs from new")
    var minimal = minimal_edit_distance(strs(old), strs(new))
    var got = Int(result.edit_distance())
    if max_cost == 0 and got != minimal:
        raise Error("myers: not minimal: " + String(got) + " vs " + String(minimal))
    if got < minimal:
        raise Error("myers: shorter than minimal")


def ids(*values: Int) -> List[UInt32]:
    var out = List[UInt32]()
    for v in values:
        out.append(UInt32(v))
    return out^


def check_both(old: List[UInt32], new: List[UInt32]) raises:
    check(old, new, 0)
    check(old, new, 2)


def main() raises:
    check_both(ids(), ids())
    check_both(ids(), ids(1, 2))
    check_both(ids(1, 2), ids())
    check_both(ids(1, 2, 3), ids(1, 2, 3))
    check_both(ids(1, 2, 3), ids(4, 5, 6))
    check_both(ids(1, 2, 3, 4), ids(1, 2))
    check_both(ids(1, 2, 3, 4), ids(3, 4))
    check_both(ids(9, 1, 2, 8), ids(9, 5, 8))
    check_both(ids(1, 2, 3, 4, 5, 6, 7), ids(2, 4, 6, 8))
    check_both(ids(1, 2, 3, 4, 5), ids(1, 9, 3, 8, 5))  # tokens unique to one side
    check_both(ids(7, 7, 1, 7), ids(2, 1, 2))
    check_both(ids(4000000000, 1, 4294967295), ids(2, 4000000000, 3))

    for seed in range(300):
        var rng = Prng(UInt64(seed))
        var alphabet = 2 + rng.bounded(6 if seed % 2 == 0 else 60)  # wide alphabets exercise the unique-token prepass
        var old = List[UInt32]()
        for _ in range(rng.bounded(40)):
            old.append(UInt32(rng.bounded(alphabet)))
        var new = List[UInt32]()
        for v in old:
            var r = rng.bounded(6)
            if r == 0:
                continue
            new.append(v)
            if r == 1:
                new.append(UInt32(rng.bounded(alphabet)))
        for _ in range(rng.bounded(4)):
            new.append(UInt32(rng.bounded(alphabet)))
        check_both(old, new)
    print("myers: PASS")
