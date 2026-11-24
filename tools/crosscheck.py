from __future__ import annotations

import argparse
import random
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


VOCABULARY = ["", " ", "\t", "alpha", "beta", "gamma", "--- a/f.txt", "+++ b/f.txt", "@@ -1 +1 @@"]


def render(lines: list[str], trailing_newline: bool) -> str:
    return "\n".join(lines) + ("\n" if trailing_newline else "")


def random_pair(seed: int) -> tuple[str, str]:
    rng = random.Random(seed)
    old = [rng.choice(VOCABULARY) for _ in range(rng.randrange(13))]
    new = old.copy()
    for _ in range(rng.randrange(9)):
        action = rng.randrange(4)
        if action == 0 or not new:
            new.insert(rng.randrange(len(new) + 1), rng.choice(VOCABULARY))
        elif action == 1:
            del new[rng.randrange(len(new))]
        elif action == 2:
            new[rng.randrange(len(new))] = rng.choice(VOCABULARY)
        else:
            left, right = rng.randrange(len(new)), rng.randrange(len(new))
            new[left], new[right] = new[right], new[left]
    return render(old, bool(rng.randrange(2))), render(new, bool(rng.randrange(2)))


def changed_lines(patch: str) -> int:
    in_hunk = False
    changed = 0
    for line in patch.splitlines():
        if line.startswith("@@"):
            in_hunk = True
        elif in_hunk and line.startswith(("+", "-")):
            changed += 1
    return changed


def changed_lines_self_test() -> None:
    patch = """--- a/f.txt
+++ b/f.txt
@@ -1 +1 @@
---- a/f.txt
++++ b/f.txt
"""
    assert changed_lines(patch) == 2


def git_changed_lines(old: Path, new: Path) -> int:
    result = subprocess.run(["git", "diff", "--no-index", "--numstat", old, new], text=True, capture_output=True, check=False)
    if not result.stdout:
        return 0
    added, deleted, *_ = result.stdout.split("\t", 2)
    return int(added) + int(deleted)


def save_failure(seed: int, old: str, new: str, patch: str) -> Path:
    directory = Path("tools/failures") / f"seed-{seed}"
    directory.mkdir(parents=True, exist_ok=True)
    (directory / "old.txt").write_text(old)
    (directory / "new.txt").write_text(new)
    (directory / "patch.diff").write_text(patch)
    return directory


def check_apply(command: list[str], repo: Path, expected: str) -> tuple[bool, str]:
    result = subprocess.run(command, cwd=repo, text=True, capture_output=True, check=False)
    actual = (repo / "f.txt").read_text()
    return result.returncode == 0 and actual == expected, result.stderr


def check_case(difpatch: Path, seed: int, tolerance: int) -> tuple[bool, str]:
    old, new = random_pair(seed)
    with tempfile.TemporaryDirectory(prefix="difpatch-crosscheck-") as raw:
        root = Path(raw)
        old_path, new_path, patch_path = root / "old.txt", root / "new.txt", root / "patch.diff"
        old_path.write_text(old)
        new_path.write_text(new)
        result = subprocess.run([difpatch, "diff", old_path, new_path], text=True, capture_output=True, check=False)
        patch = result.stdout
        patch_path.write_text(patch)
        if result.returncode:
            saved = save_failure(seed, old, new, patch)
            return False, f"seed {seed}: difpatch failed ({result.stderr.strip()}); saved {saved}"

        if old == new:
            # Identical inputs give an empty patch (as diff and git do); git apply refuses empty input.
            return (True, "") if not patch else (False, f"seed {seed}: expected an empty patch for identical files")

        git_lines = git_changed_lines(old_path, new_path)
        difpatch_lines = changed_lines(patch)
        if difpatch_lines > git_lines + tolerance:
            saved = save_failure(seed, old, new, patch)
            return False, f"seed {seed}: difpatch changed {difpatch_lines}, git reference {git_lines}; saved {saved}"
        if difpatch_lines != git_lines:
            print(f"warning seed {seed}: difpatch changed {difpatch_lines}, git reference {git_lines}")

        for name, command in (("git apply", ["git", "apply", "patch.diff"]), ("patch", ["patch", "-p1", "--batch", "-i", "patch.diff"])):
            repo = root / name.replace(" ", "-")
            repo.mkdir()
            (repo / "f.txt").write_text(old)
            shutil.copy2(patch_path, repo / "patch.diff")
            if name == "git apply":
                subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            accepted, detail = check_apply(command, repo, new)
            if not accepted:
                saved = save_failure(seed, old, new, patch)
                return False, f"seed {seed}: {name} rejected or mismatched ({detail.strip()}); saved {saved}"
    return True, ""


def main() -> int:
    changed_lines_self_test()
    parser = argparse.ArgumentParser()
    parser.add_argument("--difpatch", type=Path, required=True)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--cases", type=int, default=32)
    parser.add_argument("--tolerance", type=int, default=0)
    args = parser.parse_args()
    if not args.difpatch.is_file():
        parser.error(f"difpatch executable does not exist: {args.difpatch}")
    for seed in range(args.seed, args.seed + args.cases):
        ok, message = check_case(args.difpatch.resolve(), seed, args.tolerance)
        if not ok:
            print(message, file=sys.stderr)
            return 1
    print(f"cross-check: PASS ({args.cases} seeds starting at {args.seed})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
