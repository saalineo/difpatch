from difpatch.simd import find_byte, hash_span


@fieldwise_init
struct Span32(ImplicitlyCopyable):
    """Offset/length into a source buffer; borrows nothing."""
    var start: UInt32
    var len: UInt32


struct Tokens(Movable):
    var ids: List[UInt32]
    var spans: List[Span32]

    def __init__(out self):
        self.ids = List[UInt32]()
        self.spans = List[Span32]()

    def validate(self, src_len: Int) raises:
        """Tokens must tile the source exactly: contiguous, non-empty, no gaps."""
        var cursor = 0
        for span in self.spans:
            if span.len == 0 or Int(span.start) != cursor:
                raise Error("invalid tokens: gap, overlap or empty token")
            cursor += Int(span.len)
        if cursor != src_len:
            raise Error("invalid tokens: do not cover the source")


struct TokenizedPair(Movable):
    var old: Tokens
    var new: Tokens
    var unique: UInt32

    def __init__(out self, var old: Tokens, var new: Tokens, unique: UInt32):
        self.old = old^
        self.new = new^
        self.unique = unique


trait Splitter:
    def token_end(self, src: Span[Byte, _], pos: Int) -> Int:
        """End (exclusive, > pos) of the token that starts at pos."""
        ...


struct LineSplitter(Splitter):
    """A line includes its `\\n` or `\\r\\n`; a final unterminated line has none.
    A lone `\\r` is ordinary content."""

    def __init__(out self):
        pass

    def token_end(self, src: Span[Byte, _], pos: Int) -> Int:
        var i = find_byte(src, pos, 10)
        return i + 1 if i < len(src) else len(src)


struct ByteSplitter(Splitter):
    def __init__(out self):
        pass

    def token_end(self, src: Span[Byte, _], pos: Int) -> Int:
        return pos + 1


def _is_word(b: Byte) -> Bool:
    # Bytes >= 0x80 count as word bytes so UTF-8 (valid or not) is never decoded.
    return (b >= 48 and b <= 57) or (b >= 65 and b <= 90) or b == 95 or (b >= 97 and b <= 122) or b >= 128


def _is_space(b: Byte) -> Bool:
    return b == 32 or (b >= 9 and b <= 13)


struct WordSplitter(Splitter):
    """Runs of word bytes, runs of whitespace, or one other byte."""

    def __init__(out self):
        pass

    def token_end(self, src: Span[Byte, _], pos: Int) -> Int:
        var first = src[pos]
        var end = pos + 1
        if _is_word(first):
            while end < len(src) and _is_word(src[end]):
                end += 1
        elif _is_space(first):
            while end < len(src) and _is_space(src[end]):
                end += 1
        return end


@fieldwise_init
struct _Entry(Copyable):
    var hash: UInt64
    var side: UInt8
    var start: UInt32
    var len: UInt32


def tokenize_pair[
    S: Splitter
](old: Span[Byte, _], new: Span[Byte, _], splitter: S) raises -> TokenizedPair:
    """Tokenize both inputs through one interner so equal tokens share an ID.
    Borrows old/new for the call only; the result owns offsets and IDs."""
    if len(old) > 0xFFFFFFFF or len(new) > 0xFFFFFFFF:
        raise Error("difpatch tokenize: input larger than 4 GiB")

    var entries = List[_Entry]()
    var mask = 1023
    var table = List[UInt32](length=mask + 1, fill=0)  # id + 1; 0 = empty
    var old_tokens = Tokens()
    var new_tokens = Tokens()

    for side in range(2):
        var is_old = side == 0
        var src = old if is_old else new
        var pos = 0
        while pos < len(src):
            var end = splitter.token_end(src, pos)
            if end <= pos or end > len(src):
                raise Error("difpatch tokenize: splitter made no progress")
            var h = hash_span(src, pos, end)
            var slot = Int(h) & mask
            var id = UInt32(0)
            var found = False
            while table[slot] != 0:
                ref e = entries[Int(table[slot]) - 1]
                if e.hash == h and Int(e.len) == end - pos:
                    var rep = old if e.side == 0 else new
                    # Inline 16-byte compare: a helper taking both spans trips the aliasing check.
                    var rp = rep.unsafe_ptr() + Int(e.start)
                    var sp = src.unsafe_ptr() + pos
                    var n_bytes = end - pos
                    var same = True
                    var k = 0
                    while k + 16 <= n_bytes:
                        if not rp.unsafe_load[width=16](k).eq(sp.unsafe_load[width=16](k)).reduce_and():
                            same = False
                            break
                        k += 16
                    while same and k < n_bytes:
                        same = rp.unsafe_load(k) == sp.unsafe_load(k)
                        k += 1
                    if same:
                        id = table[slot] - 1
                        found = True
                        break
                slot = (slot + 1) & mask
            if not found:
                id = UInt32(len(entries))
                entries.append(_Entry(h, UInt8(side), UInt32(pos), UInt32(end - pos)))
                table[slot] = id + 1
                if len(entries) * 2 > mask + 1:  # keep load <= 50%
                    mask = (mask + 1) * 2 - 1
                    table = List[UInt32](length=mask + 1, fill=0)
                    for k in range(len(entries)):
                        var s = Int(entries[k].hash) & mask
                        while table[s] != 0:
                            s = (s + 1) & mask
                        table[s] = UInt32(k) + 1
            ref out = old_tokens if is_old else new_tokens
            out.ids.append(id)
            out.spans.append(Span32(UInt32(pos), UInt32(end - pos)))
            pos = end
    return TokenizedPair(old_tokens^, new_tokens^, UInt32(len(entries)))


def split[S: Splitter](src: Span[Byte, _], splitter: S) -> List[Span32]:
    """Tokenize one buffer into spans only (no interning)."""
    var spans = List[Span32]()
    var pos = 0
    while pos < len(src):
        var end = splitter.token_end(src, pos)
        spans.append(Span32(UInt32(pos), UInt32(end - pos)))
        pos = end
    return spans^
