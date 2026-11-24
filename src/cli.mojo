from std.sys import argv

from flux.api import unified_diff


def main() raises:
    var args = argv()
    if len(args) != 4:
        raise Error("usage: flux diff OLD NEW")

    var command = String(args[1])
    if command != "diff":
        raise Error("usage: flux diff OLD NEW")

    var old_file = open(args[2], "r")
    var old = old_file.read()
    old_file.close()
    var new_file = open(args[3], "r")
    var new = new_file.read()
    new_file.close()

    # unified_diff owns the ---/+++ header contract, including these defaults.
    print(unified_diff(old, new, old_label="a/f.txt", new_label="b/f.txt"))
