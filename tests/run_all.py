from __future__ import annotations

import subprocess
import sys
import os


STUB_ERRORS = (
    "flux unified_diff: not implemented (Phase 1 foundations only)",
    "flux apply_patch: not implemented (Phase 1 foundations only)",
)


def run(test: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["pixi", "run", "mojo", "run", "-I", "src", "-I", "tests", test],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def main() -> int:
    oracle = run("tests/test_oracle.mojo")
    print(oracle.stdout, end="")
    if oracle.returncode:
        return oracle.returncode

    roundtrip = run("tests/test_roundtrip.mojo")
    print(roundtrip.stdout, end="")
    if os.environ.get("FLUX_EXPECT_RED") == "1":
        if roundtrip.returncode == 0 or not any(error in roundtrip.stdout for error in STUB_ERRORS):
            print("round-trip test did not fail from a Phase 1 API stub", file=sys.stderr)
            return 1
        print("all Phase 1 checks: PASS (round-trip is intentionally red)")
        return 0
    return roundtrip.returncode


if __name__ == "__main__":
    raise SystemExit(main())
