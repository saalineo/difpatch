<p align="center">
  <img src="assets/logos/difpatch.svg" alt="difpatch logo" width="160" height="160">
</p>

<h1 align="center">difpatch</h1>

A diff and patch engine in Mojo. It turns text into integer tokens, computes a
**minimal** edit script with Myers' algorithm, writes and reads **unified diffs**,
and applies patches strictly, with opt-in leniency for drifted files.

```
text ──▶ tokens (Layer 1) ──▶ edit script (Layer 2) ──▶ hunks / unified diff (Layer 3)
                                                              │
                  patched text ◀── patcher (Layer 3) ◀── parser
```

Everything is exposed from one package: `from difpatch import ...`.

## Install

Once difpatch is listed on the
[Modular community channel](https://github.com/modular/modular-community), add the
channel to your `pixi.toml` and install it:

```toml
channels = ["https://conda.modular.com/max", "https://repo.prefix.dev/modular-community", "conda-forge"]
```

```bash
pixi add difpatch
```

The package is the library only and requires Mojo 1.2.0. To get the CLI, build from source.

## Quick start

From a clone of this repository:

```bash
pixi run build_cli          # builds build/difpatch
build/difpatch old.txt new.txt > change.diff
build/difpatch apply old.txt change.diff > patched.txt
```

```mojo
from difpatch import apply_patch, unified_diff

def main() raises:
    var patch = unified_diff("a\nb\nc\n", "a\nB\nc\n")
    print(patch, end="")
    # --- a/f.txt
    # +++ b/f.txt
    # @@ -1,3 +1,3 @@
    #  a
    # -b
    # +B
    #  c
    print(apply_patch("a\nb\nc\n", patch), end="")   # a\nB\nc\n
```

See the [full documentation](docs/documentation.md) for every type, option, error and known issue.

## API (Layer 4)

| Function | What it does |
|---|---|
| `unified_diff(old, new, context=3, old_label="a/f.txt", new_label="b/f.txt", max_cost=0) -> String` | Unified diff. Returns `""` when the inputs are identical, like `diff` and `git`. |
| `apply_patch(original, patch, max_offset=0, max_fuzz=0) -> String` | Applies a single-file unified diff. **Strict by default**; any rejected hunk raises with the hunk number and the first mismatching line. |
| `diff_lines(old, new, max_cost=0) -> DiffResult` | Line-level edit script. `EditOp` indices are 0-based line numbers. |
| `myers_diff(old: Span[UInt32], new: Span[UInt32], max_cost=0) -> DiffResult` | Low level. Minimal edit script over any two token-ID arrays. |

Lower-level pieces for power users:

- `tokenize_pair(old_bytes, new_bytes, splitter)` with `LineSplitter`, `WordSplitter` or
  `ByteSplitter` (or your own `Splitter`). Equal tokens get equal IDs across both inputs.
  Feed the IDs to `myers_diff` for word- or byte-level diffs.
- `group_hunks`, `format_patch`, `parse_patch`, and `apply_report` (the dry-run /
  reject-report form of the patcher, see below).

### `DiffResult`

`ops: List[EditOp]` where each op is `EQUAL`, `DELETE` or `INSERT` over a run of
tokens, with `old_idx` / `new_idx` cursors. `validate()` checks the invariants:
ops tile both inputs, none is empty, and adjacent ops differ in kind.
`edit_distance()` is the number of inserted plus deleted tokens. Each change block
is emitted as one `DELETE` followed by one `INSERT`.

### Applying patches

```mojo
apply_patch(original, patch)                       # exact position only
apply_patch(original, patch, max_offset=20)        # hunks may drift up to 20 lines
apply_patch(original, patch, max_offset=20, max_fuzz=2)
```

- Nothing is lenient unless you ask. A hunk must match context and removed lines
  byte for byte at its stated position.
- `max_offset` searches outward from the stated position, nearest first. If two
  places match equally well, the hunk is **refused as ambiguous** rather than guessed.
- `max_fuzz` ignores up to N context lines at each end of a hunk. Removed lines are
  never fuzzed.
- Zero-context pure insertions have nothing to anchor on, so they land at their stated
  line regardless of offset.
- `apply_report(original_bytes, patch_bytes, parse_patch(patch_bytes), ApplyOptions(...))`
  returns per-hunk results (`applied`, `offset`, `fuzz`, `message`) and the output built
  from the hunks that did apply. That is the dry run, and each rejected hunk's text span
  is available for a reject file.

## CLI

```
difpatch [diff] OLD NEW [-U N] [--max-cost N]      print a unified diff
difpatch apply FILE PATCH [--offset N] [--fuzz N]  print FILE with PATCH applied
```

Output goes to stdout with nothing added. The exit status is 0 on success and nonzero
on error (including a failed hunk), so it is not `diff(1)`'s "1 means different".
Diff headers always use the labels `a/f.txt` and `b/f.txt`, which makes the output apply
with `patch -p1` to a file named `f.txt`. Inputs must be valid UTF-8.

## How it works

**Layer 1: tokenizer and interner** (`tokenize.mojo`). Splitters return token boundaries over
a byte buffer; tokens are `(offset, length)` spans, so nothing is copied and nothing
borrowed escapes. One hash table is shared by both inputs, so equal tokens share an ID.

- A line token **includes its terminator**. `"one"`, `"one\n"` and `"one\r\n"` are three
  different tokens. A missing final newline is therefore part of the data, not a flag. The
  diff shows it as a change and the formatter prints `\ No newline at end of file`, so
  round-trips are exact, including CRLF files.
- Work is on bytes and never decodes, so invalid UTF-8 cannot break splitting.

**Layer 2: Myers** (`myers.mojo`). Trims the common prefix and suffix, drops tokens that
occur on only one side (they cannot be in any common subsequence, so the distance is
unchanged), then runs bidirectional Myers O(ND) with a middle-point split and recursion.
Space is O(N+M). There is no stored O(D²) trace. The result is always minimal unless you
set `max_cost`.

`max_cost > 0` caps the search at that cost per split and falls back to the furthest point
reached. The script is valid but may be longer than minimal. Use it for huge, mostly
unrelated inputs.

**Layer 3: hunks, formatter, parser, patcher.** Changes whose context windows overlap
(gap ≤ 2·context) share a hunk. Headers follow the format's quirks: a zero count starts at
the line before the change, and a count of 1 is written without `,1`. The parser reads hunks
by their header counts rather than by line prefixes, so content such as `--- x` is not
mistaken for a header. It tolerates git preambles, timestamps after a tab, omitted counts,
section headings, and blank context lines whose trailing space was stripped. It rejects
truncated hunks, hunks with more lines than counted, and multi-file patches.

## Performance

`pixi run bench` times each stage on synthetic corpora (single run, release build,
i5-11400H). Times in ms.

| Corpus | Tokens | Edits | Tokenize | Diff | Format | Parse | Apply |
|---|---:|---:|---:|---:|---:|---:|---:|
| source, small edits (2.4 MiB) | 50k | 40 | 4.2 | 0.8 | 0.0 | 0.0 | 0.6 |
| source, big refactor | 50k | 12,314 | 5.9 | 1.0 | 2.2 | 1.5 | 2.7 |
| logs, two runs (9.6 MiB) | 200k | 7,040 | 14.9 | 3.3 | 4.7 | 3.1 | 7.8 |
| logs, unrelated (1 MiB, `max_cost` 1000) | 20k | 40,000 | 1.2 | 0.2 | 2.8 | 2.5 | 2.0 |
| minified, lines (1 MiB, one line) | 1 | 2 | 0.4 | 0.0 | 2.9 | 2.5 | 1.6 |
| minified, words | 510k | 2 | 12.3 | 0.1 | 0.0 | 0.0 | 0.1 |
| minified, bytes (390 KiB) | 400k | 2 | 5.5 | 0.1 | 0.0 | 0.0 | 0.0 |
| repetitive, 50 distinct lines | 20k | 3,632 | 0.6 | 45.0 | 0.6 | 0.5 | 1.1 |
| repetitive, `max_cost` 500 | 20k | 3,636 | 0.7 | 11.2 | 0.6 | 0.5 | 1.1 |

What the profile showed, and what was done about it:

| Stage | Before | After | Change |
|---|---:|---:|---|
| Tokenize, 2.4 MiB source | 17 ms | 4.2 ms | SIMD newline search, 8-bytes-per-step hash, 16-byte compares in the interner |
| Tokenize, 9.6 MiB logs | 96 ms | 15 ms | same |
| Diff, refactor | 508 ms | 1.0 ms | drop one-sided tokens before Myers (algorithmic, not SIMD) |
| Diff, logs (two runs) | 199 ms | 3.3 ms | same |
| Diff, minified words | 1.0 ms | 0.1 ms | SIMD prefix/suffix trim on `UInt32` |

Things measured and **not** kept:

- **SIMD in the snake loop.** On these corpora snakes are short, and the change made no
  measurable difference (refactor 522 vs 531 ms, logs 190 vs 190 ms), so it was reverted.
- The Myers core still dominates when many lines repeat, since the prepass cannot remove them
  (the "repetitive" rows). Use `max_cost` there.

Buffers are sized once where the size is known (the patcher reserves
`len(original) + inserted bytes`, an exact upper bound), and tokens are spans, so there is no
per-line allocation.

## Testing

```bash
pixi run test          # oracle, tokenizer, Myers, patch, round-trip
pixi run build_cli && pixi run crosscheck
```

- `test_myers` compares every result against an LCS-based oracle for minimal distance and
  checks that rebuilding the new input is exact, with and without `max_cost`.
- `test_patch` covers header quirks, grouping boundaries, parser tolerance, strict
  rejection, offset and fuzz behaviour, ambiguity, partial application, and
  round-trips over random inputs, contexts and trailing-newline variants.
- `tools/crosscheck.py` applies difpatch's output with `git apply` and `patch`, and
  compares changed-line counts with `git diff`.

## Layout

```
src/difpatch/   tokenize, simd, myers, hunks, format, parse, apply, api, types
src/cli.mojo    command-line front end
tests/          oracle, tokenizer, Myers, patch and round-trip tests
tools/          bench.mojo (stage timings), crosscheck.py (git/patch interop)
```

## Limits

- The text API takes `String`, so it needs valid UTF-8. The byte-level pieces
  (`tokenize_pair`, `myers_diff`, `parse_patch`, `apply_report`) do not.
- Single-file patches only. No reverse apply, whitespace-insensitive matching, or git
  extended headers (renames, modes, binary).
- Offsets are `UInt32`: inputs of 4 GiB or more are rejected.
- Without `max_cost`, a very large, very different input can take O(ND) time and
  O(N+M) memory.
- Equal results are not guaranteed to match `diff`'s choice among equally minimal scripts.

## License

[MIT](LICENSE)
