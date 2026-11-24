from difpatch.types import EditOp, OpTag


def lcs_length(left: List[String], right: List[String]) -> Int:
    var row = List[Int](length=len(right) + 1, fill=0)
    for left_index in range(len(left)):
        var diagonal = 0
        for right_index in range(len(right)):
            var above = row[right_index + 1]
            if left[left_index] == right[right_index]:
                row[right_index + 1] = diagonal + 1
            elif row[right_index] > row[right_index + 1]:
                row[right_index + 1] = row[right_index]
            diagonal = above
    return row[len(right)]


def minimal_edit_distance(left: List[String], right: List[String]) -> Int:
    return len(left) + len(right) - 2 * lcs_length(left, right)


def reconstruct(old: List[String], new: List[String], ops: List[EditOp]) raises -> List[String]:
    var rebuilt: List[String] = []
    for op in ops:
        if op.tag == OpTag.EQUAL:
            for offset in range(Int(op.length)):
                var old_index = Int(op.old_idx) + offset
                var new_index = Int(op.new_idx) + offset
                if old_index >= len(old) or new_index >= len(new) or old[old_index] != new[new_index]:
                    raise Error("reconstruct: EQUAL op does not cover equal lines")
                rebuilt.append(old[old_index].copy())
        elif op.tag == OpTag.INSERT:
            for offset in range(Int(op.length)):
                var new_index = Int(op.new_idx) + offset
                if new_index >= len(new):
                    raise Error("reconstruct: INSERT op exceeds new input")
                rebuilt.append(new[new_index].copy())
        elif op.tag == OpTag.DELETE:
            if Int(op.old_idx + op.length) > len(old):
                raise Error("reconstruct: DELETE op exceeds old input")
        else:
            raise Error("reconstruct: unknown op tag")
    return rebuilt^
