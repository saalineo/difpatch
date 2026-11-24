struct OpTag:
    comptime EQUAL = UInt32(0)
    comptime DELETE = UInt32(1)
    comptime INSERT = UInt32(2)


@fieldwise_init
struct EditOp(Copyable):
    var tag: UInt32
    var old_idx: UInt32
    var new_idx: UInt32
    var length: UInt32


@fieldwise_init
struct Hunk(Movable):
    """Unified diff uses 1-based starts; count 0 starts one line before a change."""
    var old_start: UInt32
    var old_count: UInt32
    var new_start: UInt32
    var new_count: UInt32
    var ops: List[EditOp]


@fieldwise_init
struct DiffResult(Movable):
    var ops: List[EditOp]
    var old_len: UInt32
    var new_len: UInt32

    def edit_distance(self) -> UInt32:
        var distance = UInt32(0)
        for op in self.ops:
            if op.tag != OpTag.EQUAL:
                distance += op.length
        return distance

    def validate(self) raises:
        var old_cursor = UInt32(0)
        var new_cursor = UInt32(0)
        var previous_tag = UInt32(3)
        for op in self.ops:
            if op.length == 0:
                raise Error("invalid diff result: empty op")
            if op.tag != OpTag.EQUAL and op.tag != OpTag.DELETE and op.tag != OpTag.INSERT:
                raise Error("invalid diff result: unknown tag")
            if op.tag == previous_tag:
                raise Error("invalid diff result: adjacent ops share a tag")
            if op.old_idx != old_cursor or op.new_idx != new_cursor:
                raise Error("invalid diff result: ops do not tile both inputs")
            if op.tag == OpTag.EQUAL:
                old_cursor += op.length
                new_cursor += op.length
            elif op.tag == OpTag.DELETE:
                old_cursor += op.length
            else:
                new_cursor += op.length
            previous_tag = op.tag
        if old_cursor != self.old_len or new_cursor != self.new_len:
            raise Error("invalid diff result: lengths do not match ops")
