struct Prng:
    var state: UInt64

    def __init__(out self, seed: UInt64):
        var mixed = seed + UInt64(0x9E3779B97F4A7C15)
        mixed = (mixed ^ (mixed >> 30)) * UInt64(0xBF58476D1CE4E5B9)
        mixed = (mixed ^ (mixed >> 27)) * UInt64(0x94D049BB133111EB)
        self.state = mixed ^ (mixed >> 31)

    def next_u32(mut self) -> UInt32:
        self.state ^= self.state << 13
        self.state ^= self.state >> 7
        self.state ^= self.state << 17
        return UInt32(self.state >> 32)

    def bounded(mut self, bound: Int) -> Int:
        if bound <= 0:
            return 0
        return Int(self.next_u32() % UInt32(bound))


def random_line(mut rng: Prng) -> String:
    var choice = rng.bounded(10)
    if choice == 0:
        return ""
    if choice == 1:
        return " "
    if choice == 2:
        return "\t"
    if choice == 3:
        return "alpha"
    if choice == 4:
        return "beta"
    if choice == 5:
        return "gamma"
    if choice == 6:
        return "--- a/f.txt"
    if choice == 7:
        return "+++ b/f.txt"
    if choice == 8:
        return "@@ -1,2 +1,2 @@"
    return "same"


def random_lines(mut rng: Prng, max_lines: Int = 12) -> List[String]:
    var lines: List[String] = []
    for _ in range(rng.bounded(max_lines + 1)):
        lines.append(random_line(rng))
    return lines^


def copy_lines(lines: List[String]) -> List[String]:
    var copied: List[String] = []
    for index in range(len(lines)):
        copied.append(lines[index].copy())
    return copied^


def insert_line(var lines: List[String], index: Int, value: String) -> List[String]:
    var result: List[String] = []
    for current in range(len(lines) + 1):
        if current == index:
            result.append(value)
        if current < len(lines):
            result.append(lines[current].copy())
    return result^


def delete_line(var lines: List[String], index: Int) -> List[String]:
    var result: List[String] = []
    for current in range(len(lines)):
        if current != index:
            result.append(lines[current].copy())
    return result^


def replace_line(var lines: List[String], index: Int, value: String) -> List[String]:
    var result: List[String] = []
    for current in range(len(lines)):
        if current == index:
            result.append(value)
        else:
            result.append(lines[current].copy())
    return result^


def swap_lines(var lines: List[String], left: Int, right: Int) -> List[String]:
    var result: List[String] = []
    for current in range(len(lines)):
        if current == left:
            result.append(lines[right].copy())
        elif current == right:
            result.append(lines[left].copy())
        else:
            result.append(lines[current].copy())
    return result^


def mutate(mut rng: Prng, var lines: List[String], edits: Int) -> List[String]:
    for _ in range(edits):
        var choice = rng.bounded(4)
        if choice == 0 or len(lines) == 0:
            lines = insert_line(lines^, rng.bounded(len(lines) + 1), random_line(rng))
        elif choice == 1:
            lines = delete_line(lines^, rng.bounded(len(lines)))
        elif choice == 2:
            lines = replace_line(lines^, rng.bounded(len(lines)), random_line(rng))
        else:
            var left = rng.bounded(len(lines))
            lines = swap_lines(lines^, left, rng.bounded(len(lines)))
    return lines^


def join_lines(lines: List[String], trailing_newline: Bool) -> String:
    var text = ""
    for index in range(len(lines)):
        text += lines[index]
        if index + 1 < len(lines) or trailing_newline:
            text += "\n"
    return text
