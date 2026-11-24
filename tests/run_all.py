from __future__ import annotations

import subprocess


def run(test: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pixi", "run", "mojo", "run", "-I", "src", "-I", "tests", test],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


TESTS = ["oracle", "tokenize", "myers", "patch", "roundtrip"]


def main() -> int:
    for name in TESTS:
        result = run(f"tests/test_{name}.mojo")
        print(result.stdout, end="")
        if result.returncode:
            return result.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
