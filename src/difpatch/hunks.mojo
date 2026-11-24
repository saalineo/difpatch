from difpatch.types import EditOp, Hunk, OpTag


def group_hunks(ops: List[EditOp], context: Int) raises -> List[Hunk]:
    """Changes whose EQUAL gap is <= 2*context share a hunk (their context overlaps)."""
    if context < 0:
        raise Error("difpatch: context must be >= 0")
    var hunks = List[Hunk]()
    var n = len(ops)
    var i = 0
    while i < n:
        if ops[i].tag == OpTag.EQUAL:
            i += 1
            continue
        var j = i
        while True:
            while j < n and ops[j].tag != OpTag.EQUAL:
                j += 1
            if j + 1 < n and Int(ops[j].length) <= 2 * context:
                j += 1
            else:
                break
        var body = List[EditOp]()
        if i > 0:
            var lead = min(context, Int(ops[i - 1].length))
            if lead > 0:
                var shift = ops[i - 1].length - UInt32(lead)
                body.append(
                    EditOp(OpTag.EQUAL, ops[i - 1].old_idx + shift, ops[i - 1].new_idx + shift, UInt32(lead))
                )
        for k in range(i, j):
            body.append(ops[k].copy())
        if j < n:
            var trail = min(context, Int(ops[j].length))
            if trail > 0:
                body.append(EditOp(OpTag.EQUAL, ops[j].old_idx, ops[j].new_idx, UInt32(trail)))
        var old_count = UInt32(0)
        var new_count = UInt32(0)
        for op in body:
            if op.tag != OpTag.INSERT:
                old_count += op.length
            if op.tag != OpTag.DELETE:
                new_count += op.length
        # A zero count means "the line before the change", so the 1-based start is the 0-based index.
        var old_start = body[0].old_idx + (UInt32(1) if old_count > 0 else UInt32(0))
        var new_start = body[0].new_idx + (UInt32(1) if new_count > 0 else UInt32(0))
        hunks.append(Hunk(old_start, old_count, new_start, new_count, body^))
        i = j
    return hunks^
