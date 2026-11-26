from std.sys import argv

from difpatch.api import apply_patch, unified_diff

comptime USAGE = """usage:
  difpatch [diff] OLD NEW [-U N] [--max-cost N]    print a unified diff
  difpatch apply FILE PATCH [--offset N] [--fuzz N]  print FILE with PATCH applied

  -U N, --context N  context lines per hunk (default 3)
  --max-cost N       bound the diff search; faster on huge unrelated files, may not be minimal
  --offset N         let hunks drift up to N lines (default 0: exact position only)
  --fuzz N           ignore up to N context lines at hunk ends (default 0)"""


def read_text(path: String) raises -> String:
    var file = open(path, "r")
    var bytes = file.read_bytes()
    file.close()
    try:
        return String(from_utf8=bytes)
    except:
        raise Error(path + ": not valid UTF-8 (difpatch's text API needs UTF-8 input)")


def number(flag: String, value: String) raises -> Int:
    try:
        var n = Int(value)
        if n < 0:
            raise Error("negative")
        return n
    except:
        raise Error(flag + " needs a non-negative integer, got '" + value + "'")


def main() raises:
    var args = argv()
    var positional = List[String]()
    var context = 3
    var max_cost = 0
    var offset = 0
    var fuzz = 0
    var i = 1
    while i < len(args):
        var arg = String(args[i])
        if arg == "-h" or arg == "--help":
            print(USAGE)
            return
        if arg == "-U" or arg == "--context" or arg == "--max-cost" or arg == "--offset" or arg == "--fuzz":
            if i + 1 >= len(args):
                raise Error(arg + " needs a value")
            var n = number(arg, String(args[i + 1]))
            if arg == "-U" or arg == "--context":
                context = n
            elif arg == "--max-cost":
                if n > 0xFFFFFFFF:
                    raise Error(arg + " must be at most 4294967295")
                max_cost = n
            elif arg == "--offset":
                offset = n
            else:
                fuzz = n
            i += 2
        else:
            positional.append(arg)
            i += 1

    var command = String("diff")
    if len(positional) > 0 and (positional[0] == "diff" or positional[0] == "apply"):
        command = positional[0]
        _ = positional.pop(0)
    if len(positional) != 2:
        raise Error(USAGE)

    var first = read_text(positional[0])
    var second = read_text(positional[1])
    if command == "apply":
        # FILE then PATCH; the result goes to stdout exactly as computed (no added newline).
        print(apply_patch(first, second, offset, fuzz), end="")
    else:
        # unified_diff owns the ---/+++ header contract, including these default labels.
        print(unified_diff(first, second, context, "a/f.txt", "b/f.txt", UInt32(max_cost)), end="")
