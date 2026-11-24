from difpatch.simd import common_prefix, common_suffix
from difpatch.types import DiffResult, EditOp, OpTag


struct _Builder(Movable):
    var ops: List[EditOp]
    var old_cursor: UInt32
    var new_cursor: UInt32
    var pending_del: UInt32
    var pending_ins: UInt32

    def __init__(out self):
        self.ops = List[EditOp]()
        self.old_cursor = 0
        self.new_cursor = 0
        self.pending_del = 0
        self.pending_ins = 0

    def delete(mut self, n: Int):
        self.pending_del += UInt32(n)

    def insert(mut self, n: Int):
        self.pending_ins += UInt32(n)

    def _flush(mut self):
        if self.pending_del > 0:
            self.ops.append(EditOp(OpTag.DELETE, self.old_cursor, self.new_cursor, self.pending_del))
            self.old_cursor += self.pending_del
            self.pending_del = 0
        if self.pending_ins > 0:
            self.ops.append(EditOp(OpTag.INSERT, self.old_cursor, self.new_cursor, self.pending_ins))
            self.new_cursor += self.pending_ins
            self.pending_ins = 0

    def finish(deinit self) -> List[EditOp]:
        self._flush()
        return self.ops^

    def equal(mut self, n: Int):
        if n == 0:
            return
        self._flush()
        var count = UInt32(n)
        if len(self.ops) > 0 and self.ops[len(self.ops) - 1].tag == OpTag.EQUAL:
            self.ops[len(self.ops) - 1].length += count
        else:
            self.ops.append(EditOp(OpTag.EQUAL, self.old_cursor, self.new_cursor, count))
        self.old_cursor += count
        self.new_cursor += count


@fieldwise_init
struct _Split(Copyable):
    var found: Bool
    var x: Int
    var y: Int


def _bisect(
    a: Span[UInt32, _],
    b: Span[UInt32, _],
    a_lo: Int,
    n: Int,
    b_lo: Int,
    m: Int,
    max_cost: Int,
    mut vf: List[Int],
    mut vb: List[Int],
) -> _Split:
    var delta = n - m
    var front = (delta & 1) != 0
    var max_d = (n + m + 1) // 2
    var limited = max_cost > 0 and max_cost < max_d
    if limited:
        max_d = max_cost
    var off = max_d + 1
    var vlen = 2 * max_d + 3
    if len(vf) < vlen:
        vf.resize(vlen, -1)
        vb.resize(vlen, -1)
    for i in range(vlen):
        vf[i] = -1
        vb[i] = -1
    vf[off + 1] = 0
    vb[off + 1] = 0
    var k1s = 0
    var k1e = 0
    var k2s = 0
    var k2e = 0
    for d in range(max_d):
        var k1 = -d + k1s
        while k1 < d + 1 - k1e:
            var ko = off + k1
            var x1: Int
            if k1 == -d or (k1 != d and vf[ko - 1] < vf[ko + 1]):
                x1 = vf[ko + 1]
            else:
                x1 = vf[ko - 1] + 1
            var y1 = x1 - k1
            while x1 < n and y1 < m and a[a_lo + x1] == b[b_lo + y1]:
                x1 += 1
                y1 += 1
            vf[ko] = x1
            if x1 > n:
                k1e += 2
            elif y1 > m:
                k1s += 2
            elif front:
                var k2o = off + delta - k1
                if k2o >= 0 and k2o < vlen and vb[k2o] != -1:
                    if x1 >= n - vb[k2o]:
                        return _Split(True, x1, y1)
            k1 += 2
        var k2 = -d + k2s
        while k2 < d + 1 - k2e:
            var ko = off + k2
            var x2: Int
            if k2 == -d or (k2 != d and vb[ko - 1] < vb[ko + 1]):
                x2 = vb[ko + 1]
            else:
                x2 = vb[ko - 1] + 1
            var y2 = x2 - k2
            while x2 < n and y2 < m and a[a_lo + n - x2 - 1] == b[b_lo + m - y2 - 1]:
                x2 += 1
                y2 += 1
            vb[ko] = x2
            if x2 > n:
                k2e += 2
            elif y2 > m:
                k2s += 2
            elif not front:
                var k1o = off + delta - k2
                if k1o >= 0 and k1o < vlen and vf[k1o] != -1:
                    var fx = vf[k1o]
                    if fx >= n - x2:
                        return _Split(True, fx, fx - (k1o - off))
            k2 += 2
    if not limited:
        return _Split(False, 0, 0)  # no commonality (delete all, insert all)
    # shortcut: cost limit hit; split at the furthest point seen, not minimal.
    var best = -1
    var bx = 0
    var by = 0
    for i in range(vlen):
        var k = i - off
        if vf[i] != -1 and vf[i] <= n and vf[i] - k <= m and vf[i] - k >= 0 and 2 * vf[i] - k > best:
            best = 2 * vf[i] - k
            bx = vf[i]
            by = vf[i] - k
        if vb[i] != -1 and vb[i] <= n and vb[i] - k <= m and vb[i] - k >= 0 and 2 * vb[i] - k > best:
            best = 2 * vb[i] - k
            bx = n - vb[i]
            by = m - (vb[i] - k)
    return _Split(best > 0, bx, by)


def _solve(
    a: Span[UInt32, _],
    b: Span[UInt32, _],
    var a_lo: Int,
    var a_hi: Int,
    var b_lo: Int,
    var b_hi: Int,
    max_cost: Int,
    mut vf: List[Int],
    mut vb: List[Int],
    mut out: _Builder,
) raises:
    var window_a = a[a_lo:a_hi]
    var window_b = b[b_lo:b_hi]
    var prefix = common_prefix(window_a, window_b, min(len(window_a), len(window_b)))
    a_lo += prefix
    b_lo += prefix
    out.equal(prefix)
    window_a = a[a_lo:a_hi]
    window_b = b[b_lo:b_hi]
    var suffix = common_suffix(window_a, window_b, min(len(window_a), len(window_b)))
    a_hi -= suffix
    b_hi -= suffix
    if a_lo == a_hi:
        out.insert(b_hi - b_lo)
    elif b_lo == b_hi:
        out.delete(a_hi - a_lo)
    else:
        var split = _bisect(a, b, a_lo, a_hi - a_lo, b_lo, b_hi - b_lo, max_cost, vf, vb)
        if not split.found:
            out.delete(a_hi - a_lo)
            out.insert(b_hi - b_lo)
        else:
            if (split.x == 0 and split.y == 0) or (split.x == a_hi - a_lo and split.y == b_hi - b_lo):
                raise Error("difpatch myers: split made no progress")
            _solve(a, b, a_lo, a_lo + split.x, b_lo, b_lo + split.y, max_cost, vf, vb, out)
            _solve(a, b, a_lo + split.x, a_hi, b_lo + split.y, b_hi, max_cost, vf, vb, out)
    out.equal(suffix)


def diff_ids(
    old: Span[UInt32, _], new: Span[UInt32, _], max_cost: UInt32 = 0
) raises -> DiffResult:
    """Edit script turning old into new. max_cost 0 = unlimited (always minimal);
    otherwise a non-minimal but valid script once the search exceeds that cost."""
    # Trim first (SIMD): the prepass below is O(N) and pointless on the shared ends.
    var prefix = common_prefix(old, new, min(len(old), len(new)))
    var suffix = common_suffix(old[prefix:], new[prefix:], min(len(old), len(new)) - prefix)
    var a_end = len(old) - suffix
    var b_end = len(new) - suffix
    var out = _Builder()
    out.equal(prefix)
    var vf = List[Int]()
    var vb = List[Int]()

    # A token absent from the other side can never be matched, so dropping it leaves the
    # minimal distance unchanged while shrinking the quadratic part of the search.
    var top = UInt32(0)
    for i in range(prefix, a_end):
        top = max(top, old[i])
    for i in range(prefix, b_end):
        top = max(top, new[i])
    var in_old = List[Bool](length=Int(top) + 1, fill=False)
    var in_new = List[Bool](length=Int(top) + 1, fill=False)
    for i in range(prefix, a_end):
        in_old[Int(old[i])] = True
    for i in range(prefix, b_end):
        in_new[Int(new[i])] = True
    var kept_old = List[UInt32]()
    var map_old = List[Int]()
    for i in range(prefix, a_end):
        if in_new[Int(old[i])]:
            kept_old.append(old[i])
            map_old.append(i)
    var kept_new = List[UInt32]()
    var map_new = List[Int]()
    for i in range(prefix, b_end):
        if in_old[Int(new[i])]:
            kept_new.append(new[i])
            map_new.append(i)

    if len(kept_old) == a_end - prefix and len(kept_new) == b_end - prefix:
        _solve(old, new, prefix, a_end, prefix, b_end, Int(max_cost), vf, vb, out)
    else:
        var inner = _Builder()
        _solve(Span(kept_old), Span(kept_new), 0, len(kept_old), 0, len(kept_new), Int(max_cost), vf, vb, inner)
        var old_cursor = prefix
        var new_cursor = prefix
        for op in inner^.finish():
            if op.tag != OpTag.EQUAL:
                continue
            for k in range(Int(op.length)):
                var o = map_old[Int(op.old_idx) + k]
                var n = map_new[Int(op.new_idx) + k]
                out.delete(o - old_cursor)
                out.insert(n - new_cursor)
                out.equal(1)
                old_cursor = o + 1
                new_cursor = n + 1
        out.delete(a_end - old_cursor)
        out.insert(b_end - new_cursor)
    out.equal(suffix)
    return DiffResult(out^.finish(), UInt32(len(old)), UInt32(len(new)))
