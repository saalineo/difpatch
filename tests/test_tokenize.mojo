from flux.tokenize import (
    ByteSplitter,
    LineSplitter,
    Splitter,
    TokenizedPair,
    WordSplitter,
    tokenize_pair,
)
from support.prng import Prng


def check[S: Splitter](old: List[Byte], new: List[Byte], s: S) raises:
    var pair = tokenize_pair(Span(old), Span(new), s)
    pair.old.validate(len(old))
    pair.new.validate(len(new))
    # Same ID iff same bytes, across both inputs.
    var seen = Dict[String, UInt32]()
    for side in range(2):
        ref tokens = pair.old if side == 0 else pair.new
        ref src = old if side == 0 else new
        for i in range(len(tokens.ids)):
            var span = tokens.spans[i].copy()
            var key = String()
            for k in range(Int(span.len)):
                key += chr(Int(src[Int(span.start) + k]))
            if key in seen:
                if seen[key] != tokens.ids[i]:
                    raise Error("equal tokens got different IDs")
            else:
                for other in seen.values():
                    if other == tokens.ids[i]:
                        raise Error("different tokens share an ID")
                seen[key] = tokens.ids[i]
    if UInt32(len(seen)) != pair.unique:
        raise Error("unique count mismatch")


def b(s: StringLiteral) -> List[Byte]:
    var out = List[Byte]()
    for x in s.as_bytes():
        out.append(x)
    return out^


def check_all(old: List[Byte], new: List[Byte]) raises:
    check(old, new, LineSplitter())
    check(old, new, WordSplitter())
    check(old, new, ByteSplitter())


def main() raises:
    check_all(b(""), b(""))
    check_all(b(""), b("a\n"))
    check_all(b("\n"), b("\n\n"))
    check_all(b("a"), b("a\n"))
    check_all(b("a\r\nb\n"), b("a\nb\r\n"))
    var bad = List[Byte]()
    bad.append(0xFF)
    bad.append(10)
    bad.append(0xE2)
    bad.append(0x82)
    check_all(bad, b("x"))

    # Missing newline / CRLF must yield distinct line IDs.
    var p = tokenize_pair(Span(b("one")), Span(b("one\n")), LineSplitter())
    if p.old.ids[0] == p.new.ids[0]:
        raise Error("missing-newline line shares ID with terminated line")
    var q = tokenize_pair(Span(b("one\r\n")), Span(b("one\n")), LineSplitter())
    if q.old.ids[0] == q.new.ids[0]:
        raise Error("CRLF line shares ID with LF line")

    # Enough unique tokens to force interner resizes.
    for seed in range(8):
        var rng = Prng(UInt64(seed))
        var data = List[Byte]()
        for _ in range(4000):
            data.append(Byte(97 + rng.bounded(26)))
            if rng.bounded(4) == 0:
                data.append(10)
        check_all(data, data)
    print("tokenize: PASS")
