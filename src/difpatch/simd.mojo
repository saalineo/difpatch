"""SIMD helpers for the hot loops that profiling showed worth vectorizing."""

from std.bit import count_leading_zeros, count_trailing_zeros
from std.memory import pack_bits


def common_prefix(a: Span[UInt32, _], b: Span[UInt32, _], n: Int) -> Int:
    """Length of the common prefix of a and b, looking at no more than n elements."""
    comptime W = 8
    var pa = a.unsafe_ptr()
    var pb = b.unsafe_ptr()
    var i = 0
    while i + W <= n:
        var eq = pa.unsafe_load[width=W](i).eq(pb.unsafe_load[width=W](i))
        if not eq.reduce_and():
            return i + Int(count_trailing_zeros(pack_bits(~eq)))
        i += W
    while i < n and a[i] == b[i]:
        i += 1
    return i


def common_suffix(a: Span[UInt32, _], b: Span[UInt32, _], n: Int) -> Int:
    """Length of the common suffix of a and b, looking at no more than n elements."""
    comptime W = 8
    # Lane windows are [end-W-i, end-i), so the highest mismatching lane ends the common suffix.
    var i = 0
    while i + W <= n:
        var eq = a.unsafe_ptr().unsafe_load[width=W](len(a) - W - i).eq(b.unsafe_ptr().unsafe_load[width=W](len(b) - W - i))
        if not eq.reduce_and():
            return i + Int(count_leading_zeros(pack_bits(~eq)))
        i += W
    while i < n and a[len(a) - 1 - i] == b[len(b) - 1 - i]:
        i += 1
    return i


def find_byte(src: Span[Byte, _], start: Int, needle: Byte) -> Int:
    """Index of the first `needle` at or after start, or len(src)."""
    comptime W = 32
    var p = src.unsafe_ptr()
    var n = len(src)
    var i = start
    var target = SIMD[DType.uint8, W](needle)
    while i + W <= n:
        var eq = p.unsafe_load[width=W](i).eq(target)
        if eq.reduce_or():
            return i + Int(count_trailing_zeros(pack_bits(eq)))
        i += W
    while i < n and src[i] != needle:
        i += 1
    return i


def hash_span(src: Span[Byte, _], start: Int, end: Int) -> UInt64:
    """8 bytes per step multiply-fold hash (the byte-wise FNV was serial and slow)."""
    comptime K = UInt64(0x9E3779B97F4A7C15)
    var n = end - start
    var p = src.unsafe_ptr() + start
    var h = K ^ UInt64(n)
    var i = 0
    while i + 8 <= n:
        var w = (p + i).bitcast[UInt64]().unsafe_load[alignment=1]()
        h = (h ^ w) * K
        h ^= h >> 32
        i += 8
    var tail = UInt64(0)
    var shift = UInt64(0)
    while i < n:
        tail |= UInt64(p[i]) << shift
        shift += 8
        i += 1
    h = (h ^ tail) * K
    return h ^ (h >> 29)
