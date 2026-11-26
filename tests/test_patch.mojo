from difpatch.api import apply_patch, diff_lines, myers_diff, unified_diff
from difpatch.apply import ApplyOptions, apply_report
from difpatch.parse import parse_patch
from support.prng import Prng, copy_lines, join_lines, mutate, random_lines


def expect_eq(name: String, got: String, want: String) raises:
    if got != want:
        raise Error(name + ": got\n" + got + "\nwant\n" + want)


def expect_fails(name: String, original: String, patch: String, needle: String, max_offset: Int = 0, max_fuzz: Int = 0) raises:
    try:
        _ = apply_patch(original, patch, max_offset, max_fuzz)
    except e:
        if needle not in String(e):
            raise Error(name + ": wrong error: " + String(e))
        return
    raise Error(name + ": expected failure")


def expect_invalid_labels(name: String, old_label: String, new_label: String) raises:
    try:
        _ = unified_diff("a\n", "b\n", 3, old_label, new_label)
    except e:
        if "line breaks" not in String(e):
            raise Error(name + ": wrong error: " + String(e))
        return
    raise Error(name + ": expected failure")


def count_hunks(patch: String) -> Int:
    var n = 0
    for line in patch.splitlines():
        if line.startswith("@@"):
            n += 1
    return n


def numbered(count: Int, changed: List[Int]) -> String:
    var s = String()
    for i in range(1, count + 1):
        s += ("X" if i in changed else "L") + String(i) + "\n"
    return s


def main() raises:
    # Public API surface.
    var dl = diff_lines("a\nb\n", "a\nc\n")
    if dl.edit_distance() != 2 or dl.old_len != 2 or dl.new_len != 2:
        raise Error("diff_lines")
    var ia: List[UInt32] = [1, 2, 3]
    var ib: List[UInt32] = [1, 3]
    if myers_diff(Span(ia), Span(ib)).edit_distance() != 1:
        raise Error("myers_diff")

    # Formatter quirks.
    expect_eq("replace", unified_diff("a\nb\nc\n", "a\nB\nc\n"), "--- a/f.txt\n+++ b/f.txt\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n")
    expect_eq("identical", unified_diff("a\n", "a\n"), "")
    expect_eq("into empty", unified_diff("", "x\n"), "--- a/f.txt\n+++ b/f.txt\n@@ -0,0 +1 @@\n+x\n")
    expect_eq("to empty", unified_diff("x\n", ""), "--- a/f.txt\n+++ b/f.txt\n@@ -1 +0,0 @@\n-x\n")
    expect_eq("no eol", unified_diff("one", "one\n"), "--- a/f.txt\n+++ b/f.txt\n@@ -1 +1 @@\n-one\n\\ No newline at end of file\n+one\n")
    expect_eq("ctx0 insert", unified_diff("a\nb\n", "a\nx\nb\n", 0), "--- a/f.txt\n+++ b/f.txt\n@@ -1,0 +2 @@\n+x\n")
    expect_invalid_labels("old label newline", "bad\nlabel", "b/f.txt")
    expect_invalid_labels("new label carriage return", "a/f.txt", "bad\rlabel")

    # Grouping: gap of 6 lines merges at context 3, a gap of 7 splits.
    var old = numbered(10, List[Int]())
    expect_eq("merge", String(count_hunks(unified_diff(old, numbered(10, [2, 9])))), "1")
    expect_eq("split", String(count_hunks(unified_diff(numbered(11, List[Int]()), numbered(11, [2, 10])))), "2")

    # Parser tolerance: git preamble, timestamps, omitted counts, section heading, stripped blank context.
    expect_eq("git style", apply_patch("a\n\n\n", "diff --git a/f b/f\nindex 1..2 100644\n--- a/f\t2020-01-01\n+++ b/f\t2020-01-02\n@@ -1,3 +1,3 @@ def f():\n a\n-\n+B\n\n"), "a\nB\n\n")
    expect_eq("blank patch", apply_patch("keep\n", ""), "keep\n")
    # Content lines that look like headers must stay content.
    var tricky = "a\n--- x\n+++ y\n"
    expect_eq("tricky", apply_patch(tricky, unified_diff(tricky, "a\n--- x\n+++ z\n")), "a\n--- x\n+++ z\n")
    expect_fails("truncated", "a\n", "--- a\n+++ b\n@@ -1,2 +1,2 @@\n a\n", "truncated")
    expect_fails("two files", "a\n", "--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n--- c\n+++ d\n", "multiple files")
    expect_fails("overlong", "a\n", "--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n+c\n", "more lines")
    expect_fails("overlong deletion prefix", "a\n", "--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n--extra\n", "more lines")
    expect_fails("overlong insertion prefix", "a\n", "--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n+++extra\n", "more lines")

    # A damaged later header must fail, never silently drop its hunk.
    var first = String("--- a\n+++ b\n@@ -1 +1 @@\n-a\n+A\n")
    for header in ["@@-3 +3 @@", "@ -3 +3 @@", "x@@ -3 +3 @@"]:
        expect_fails("damaged " + header, "a\nb\nc\n", first + header + "\n-c\n+C\n", "unexpected text")
    expect_fails("damaged only header", "a\n", "--- a\n+++ b\n@@-1 +1 @@\n-a\n+A\n", "unexpected text")
    expect_eq("trailing blank lines", apply_patch("a\n", first + "\n \t\r\n"), "A\n")
    # Start 0 is only legal for an empty range; it used to index line -1 and abort.
    expect_fails("old start 0", "a\n", "--- a\n+++ b\n@@ -0,1 +1 @@\n-z\n+A\n", "malformed hunk header")
    expect_fails("new start 0", "a\n", "--- a\n+++ b\n@@ -1 +0 @@\n-a\n+A\n", "malformed hunk header")

    # The git format-patch signature is not hunk content; anything else there still fails.
    expect_eq("signature", apply_patch("a\n", first + "-- \n2.50.0\n\n"), "A\n")
    expect_eq("signature crlf", apply_patch("a\n", first + "-- \r\n2.50.0\r\n"), "A\n")
    expect_fails("fake signature", "a\n", first + "-- \nnot a version\n", "more lines")
    expect_fails("hunk after signature", "a\n", first + "-- \n2.50.0\n@@ -3 +3 @@\n-c\n+C\n", "more lines")
    expect_fails("negative offset", "a\n", first, "must be >= 0", -1)
    expect_fails("negative fuzz", "a\n", first, "must be >= 0", 0, -1)

    # Strict patcher: error names the hunk; drift needs an explicit offset budget.
    var base = numbered(12, List[Int]())
    var patch = unified_diff(base, numbered(12, [6]))
    var drifted = "new1\nnew2\n" + base
    expect_fails("drift strict", drifted, patch, "hunk 1")
    expect_eq("drift offset", apply_patch(drifted, patch, 5), "new1\nnew2\n" + numbered(12, [6]))
    expect_fails("offset too small", drifted, patch, "hunk 1", 1)
    expect_eq("huge offset", apply_patch("a\n", "--- a\n+++ b\n@@ -2000000000 +2000000000 @@\n-a\n+b\n", 2_000_000_000), "b\n")
    var report = apply_report(drifted.as_bytes(), patch.as_bytes(), parse_patch(patch.as_bytes()), ApplyOptions(5, 0))
    if report.results[0].offset != 2:
        raise Error("report offset")
    # Ambiguity is refused, not guessed.
    expect_fails("ambiguous", "z\nz\nz\n", "--- a\n+++ b\n@@ -2 +2 @@\n-q\n+r\n", "does not match")
    expect_fails("tie", "q\nx\nq\n", "--- a\n+++ b\n@@ -2 +2 @@\n-q\n+r\n", "more than one place", 1)
    # Fuzz may drop context, never removed lines.
    expect_eq("fuzz ctx", apply_patch("q\nb\nc\n", "--- a\n+++ b\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n", 0, 1), "q\nB\nc\n")
    expect_fails("fuzz removed", "a\nXX\nc\n", "--- a\n+++ b\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n", "hunk 1", 0, 2)
    # Applying twice must fail.
    var once = apply_patch(base, patch)
    expect_fails("twice", once, patch, "hunk 1")
    # A good hunk survives a bad neighbour in the report.
    var two = unified_diff(numbered(30, List[Int]()), numbered(30, [2, 28]))
    var broken = numbered(30, List[Int]()).replace("L28", "ZZ")
    var rep2 = apply_report(broken.as_bytes(), two.as_bytes(), parse_patch(two.as_bytes()), ApplyOptions())
    if not rep2.results[0].applied or rep2.results[1].applied:
        raise Error("partial report wrong")

    # Round trip over contexts and trailing-newline variants; plus the drift safety property.
    for seed in range(200):
        var rng = Prng(UInt64(seed) + 1000)
        var old_lines = random_lines(rng)
        var new_lines = mutate(rng, copy_lines(old_lines), rng.bounded(8))
        var o = join_lines(old_lines, rng.bounded(2) == 0)
        var n = join_lines(new_lines, rng.bounded(2) == 0)
        var ctx = rng.bounded(6)
        var p = unified_diff(o, n, ctx)
        expect_eq("roundtrip " + String(seed), apply_patch(o, p), n)
    # Drift with unique lines: always lands on the right spot (zero-context pure inserts are positional only).
    for seed in range(100):
        var rng = Prng(UInt64(seed) + 5000)
        var count = 5 + rng.bounded(20)
        var changed = List[Int]()
        for _ in range(1 + rng.bounded(3)):
            changed.append(1 + rng.bounded(count))
        var p = unified_diff(numbered(count, List[Int]()), numbered(count, changed), 1 + rng.bounded(4))
        var extra = 1 + rng.bounded(6)
        var lead = String()
        for i in range(extra):
            lead += "drift" + String(i) + "\n"
        expect_eq("drift " + String(seed), apply_patch(lead + numbered(count, List[Int]()), p, 10), lead + numbered(count, changed))
    print("patch: PASS")
