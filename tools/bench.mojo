from std.time import perf_counter_ns

from difpatch.apply import ApplyOptions, apply_report
from difpatch.format import format_patch
from difpatch.hunks import group_hunks
from difpatch.myers import diff_ids
from difpatch.parse import parse_patch
from difpatch.tokenize import ByteSplitter, LineSplitter, Splitter, WordSplitter, tokenize_pair
from support.prng import Prng



def _word(i: Int) -> String:
    if i == 0: return "let"
    if i == 1: return "fn"
    if i == 2: return "value"
    if i == 3: return "index"
    if i == 4: return "result"
    if i == 5: return "self"
    if i == 6: return "return"
    if i == 7: return "if"
    if i == 8: return "else"
    if i == 9: return "count"
    if i == 10: return "name"
    return "len"


def code_line(mut rng: Prng, i: Int) -> String:
    var s = String("    ")
    for _ in range(3 + rng.bounded(6)):
        s += _word(rng.bounded(12)) + String(rng.bounded(50)) + " "
    return s + "// " + String(i) + "\n"


def source(n: Int, seed: UInt64) -> String:
    var rng = Prng(seed)
    var out = String()
    for i in range(n):
        out += code_line(rng, i)
    return out^


def edit_lines(text: String, every: Int, mode: Int) -> String:
    """Mode 0 replaces every Nth line; mode 1 also drops and inserts blocks (refactor)."""
    var lines = List[String]()
    for l in text.splitlines(keepends=True):
        lines.append(String(l))
    var out = String()
    var n = len(lines)
    for i in range(n):
        if mode == 1 and i % 997 < 120:
            continue  # delete a block...
        if i % every == 0:
            out += "    changed line " + String(i) + "\n"
        else:
            out += lines[i]
        if mode == 1 and i % 997 == 500:
            for j in range(80):  # ...and add a different one elsewhere
                out += "    moved block " + String(i) + "_" + String(j) + "\n"
    return out^


def minified(n: Int, seed: UInt64) -> String:
    var rng = Prng(seed)
    var out = String()
    for i in range(n):
        out += "function f" + String(i) + "(a,b){return a" + String(rng.bounded(9)) + "+b*" + String(rng.bounded(99)) + "}"
    return out^


def logs(n: Int, salt: Int, variant: Bool) -> String:
    """Line i depends only on i; the variant drops every 97th line and rewrites every 53rd."""
    var out = String()
    for i in range(n):
        if variant and i % 97 == 0:
            continue
        var h = (i * 2654435761 + salt) % 1000003
        var status = 200 if variant and i % 53 == 0 else 100 * (2 + h % 3)
        out += "2026-11-24T10:" + String(i // 60 % 60) + ":" + String(i % 60) + " INFO request id=" + String(h % 300) + " status=" + String(status) + "\n"
    return out^


def repetitive(n: Int, seed: UInt64, mutate_every: Int) -> String:
    """Few distinct lines (worst case for the unique-token prepass)."""
    var rng = Prng(seed)
    var out = String()
    for i in range(n):
        var k = rng.bounded(50)
        if mutate_every > 0 and i % mutate_every == 0:
            k = rng.bounded(50)
        out += "line " + String(k) + "\n"
    return out^


def ms(start: Int, end: Int) -> Float64:
    return Float64(end - start) / 1e6


def run[S: Splitter](name: String, old: String, new: String, splitter: S, max_cost: UInt32 = 0) raises:
    var ob = old.as_bytes()
    var nb = new.as_bytes()
    var t0 = perf_counter_ns()
    var pair = tokenize_pair(ob, nb, splitter)
    var t1 = perf_counter_ns()
    var result = diff_ids(Span(pair.old.ids), Span(pair.new.ids), max_cost)
    var t2 = perf_counter_ns()
    var hunks = group_hunks(result.ops, 3)
    var text = format_patch(hunks, ob, pair.old.spans, nb, pair.new.spans, "a", "b")
    var t3 = perf_counter_ns()
    var tb = text.as_bytes()
    var parsed = parse_patch(tb)
    var t4 = perf_counter_ns()
    var rep = apply_report(ob, tb, parsed, ApplyOptions())
    var t5 = perf_counter_ns()
    print(name, "| old", old.byte_length() // 1024, "KiB, tokens", len(pair.old.ids), "| D", result.edit_distance(),
          "| tok", ms(t0, t1), "diff", ms(t1, t2), "fmt", ms(t2, t3), "parse", ms(t3, t4), "apply", ms(t4, t5), "ms")


def main() raises:
    var base = source(50000, 1)
    run("source small edits ", base, edit_lines(base, 2500, 0), LineSplitter())
    run("source refactor    ", base, edit_lines(base, 40, 1), LineSplitter())
    var logs_a = logs(200000, 2, False)
    run("logs (same run)    ", logs_a, logs(200000, 2, True), LineSplitter())
    run("logs (unrelated)   ", logs(20000, 2, False), logs(20000, 99, False), LineSplitter(), 1000)
    var rep_a = repetitive(20000, 7, 0)
    run("repetitive 20k     ", rep_a, repetitive(20000, 7, 10), LineSplitter())
    run("repetitive, capped ", rep_a, repetitive(20000, 7, 10), LineSplitter(), 500)
    var mini = minified(30000, 4)
    var mini2 = mini.replace("f777(", "g777(")
    run("minified (lines)   ", mini, mini2, LineSplitter())
    run("minified (words)   ", mini, mini2, WordSplitter())
    run("minified (bytes)   ", String(mini[byte=:400000]), String(mini2[byte=:400000]), ByteSplitter())
