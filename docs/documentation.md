# difpatch documentation

Reference for difpatch 0.1.0 on Mojo 1.2.0.

- [Setup](#setup)
- [Concepts](#concepts)
- [High-level API](#high-level-api)
- [Edit scripts](#edit-scripts)
- [Tokenizing](#tokenizing)
- [Hunks and formatting](#hunks-and-formatting)
- [Parsing patches](#parsing-patches)
- [Applying patches](#applying-patches)
- [Command line](#command-line)
- [Errors](#errors)
- [Performance and limits](#performance-and-limits)
- [Contributing](#contributing)

## Setup

From a clone of the repository, point the compiler at `src`:

```bash
pixi run mojo run -I src your_program.mojo
pixi run build_cli          # builds build/difpatch
```

Every public name is imported from the package root:

```mojo
from difpatch import unified_diff, apply_patch
```

## Concepts

| Term | Meaning |
|---|---|
| Token | A slice of the input: a line, a word, a byte, or whatever your splitter returns. |
| Token ID | A `UInt32`. Equal tokens get equal IDs, so diffing compares integers. |
| Edit script | A list of `EQUAL`, `DELETE` and `INSERT` runs that turns the old tokens into the new ones. |
| Hunk | A group of nearby changes plus surrounding context lines. |
| Patch | The unified diff text: two header lines followed by hunks. |
| Offset | How many lines away from its stated position a hunk was applied. |
| Fuzz | How many context lines at each end of a hunk were ignored while matching. |

A line token **includes its terminator**. `"x"`, `"x\n"` and `"x\r\n"` are three
different lines. A lone `\r` is ordinary content.

## High-level API

### `unified_diff`

```mojo
unified_diff(
    old: String,
    new: String,
    context: Int = 3,
    old_label: String = "a/f.txt",
    new_label: String = "b/f.txt",
    max_cost: UInt32 = 0,
) raises -> String
```

Returns the unified diff from `old` to `new`.

| Parameter | Meaning |
|---|---|
| `context` | Unchanged lines kept around each change. `0` or more. |
| `old_label`, `new_label` | Text after `---` and `+++`. |
| `max_cost` | `0` means a minimal diff. See [Performance](#performance-and-limits). |

- Identical inputs return `""`, with no headers.
- Raises if `context` is negative, or if there are changes and a label contains
  `\n` or `\r`.
- Avoid tabs in labels: `parse_patch` reads a label only up to the first tab.

```mojo
from difpatch import unified_diff

def main() raises:
    print(unified_diff("a\nb\n", "a\nc", old_label="a/notes", new_label="b/notes"), end="")
```

Output:

```diff
--- a/notes
+++ b/notes
@@ -1,2 +1,2 @@
 a
-b
+c
\ No newline at end of file
```

### `apply_patch`

```mojo
apply_patch(original: String, patch: String, max_offset: Int = 0, max_fuzz: Int = 0) raises -> String
```

Applies a single-file patch and returns the new text. It is all or nothing: if any
hunk is rejected, it raises with the first rejected hunk's message and returns no text.

- By default every hunk must match byte for byte at its stated line.
- Raises if `max_offset` or `max_fuzz` is negative.
- A blank patch, or one with `---`/`+++` headers and no hunks, returns `original`.
- The labels in the patch are not compared with anything. You choose the input.

```mojo
from difpatch import apply_patch, unified_diff

def main() raises:
    var patch = unified_diff("a\nb\n", "a\nB\n")
    var drifted = String("new first line\na\nb\n")
    try:
        _ = apply_patch(drifted, patch)
    except e:
        print(e)
    print(apply_patch(drifted, patch, max_offset=5), end="")
```

Output:

```text
hunk 1 @@ -1,2 +1,2 @@ does not match at line 1: expected 'a', found 'new first line'
new first line
a
B
```

## Edit scripts

### `diff_lines` and `myers_diff`

```mojo
diff_lines(old: String, new: String, max_cost: UInt32 = 0) raises -> DiffResult
myers_diff(old: Span[UInt32, _], new: Span[UInt32, _], max_cost: UInt32 = 0) raises -> DiffResult
```

`diff_lines` compares text line by line. `myers_diff` compares any two arrays of
token IDs; the IDs can have any value. `diff_ids` is the same function as
`myers_diff` under its internal name.

### `DiffResult`

| Member | Meaning |
|---|---|
| `ops: List[EditOp]` | The edit script, in order. |
| `old_len`, `new_len` | Number of tokens in each input. |
| `edit_distance()` | Inserted plus deleted tokens. |
| `validate()` | Raises if the script is malformed. |

A valid script covers both inputs completely, has no empty op, and never has two
adjacent ops of the same kind. Each change block is at most one `DELETE` followed
by one `INSERT`.

### `EditOp` and `OpTag`

| Field | Meaning |
|---|---|
| `tag` | `OpTag.EQUAL` (0), `OpTag.DELETE` (1) or `OpTag.INSERT` (2). |
| `old_idx` | Position in the old tokens, 0-based. |
| `new_idx` | Position in the new tokens, 0-based. |
| `length` | Number of tokens in the run. |

For `DELETE`, the run is in the old input. For `INSERT`, it is in the new input.
The other index shows where in the other input the change happens.

```mojo
from difpatch import OpTag, diff_lines

def main() raises:
    var result = diff_lines("a\nb\nc\n", "a\nc\nd\n")
    for op in result.ops:
        var name = "equal"
        if op.tag == OpTag.DELETE:
            name = "delete"
        elif op.tag == OpTag.INSERT:
            name = "insert"
        print(name, op.old_idx, op.new_idx, op.length)
    print("distance", result.edit_distance())
```

Output:

```text
equal 0 0 1
delete 1 1 1
equal 2 1 1
insert 3 2 1
distance 2
```

## Tokenizing

### `tokenize_pair`

```mojo
tokenize_pair(old: Span[Byte, _], new: Span[Byte, _], splitter: S) raises -> TokenizedPair
```

Splits both inputs and assigns IDs from one shared table. It works on bytes, so
invalid UTF-8 is accepted. It raises if an input is 4 GiB or larger, or if the
splitter returns an end position that does not advance or runs past the input.

| Type | Fields and methods |
|---|---|
| `TokenizedPair` | `old: Tokens`, `new: Tokens`, `unique: UInt32` (distinct tokens) |
| `Tokens` | `ids: List[UInt32]`, `spans: List[Span32]`, `validate(src_len)` |
| `Span32` | `start`, `len`: byte offset and length in the source |

The result stores offsets only. Keep the source text if you need the token bytes.

### Splitters

| Splitter | Token |
|---|---|
| `LineSplitter` | A line including `\n` or `\r\n`. The last line may have neither. |
| `WordSplitter` | A run of word bytes (ASCII letters, digits, `_`, and all bytes ≥ 0x80), a run of whitespace, or one other byte. |
| `ByteSplitter` | One byte. This can cut a multi-byte UTF-8 character. |

Word diff:

```mojo
from difpatch import OpTag, WordSplitter, myers_diff, tokenize_pair

def main() raises:
    var old = String("the quick fox")
    var new = String("the slow fox")
    var pair = tokenize_pair(old.as_bytes(), new.as_bytes(), WordSplitter())
    for op in myers_diff(Span(pair.old.ids), Span(pair.new.ids)).ops:
        if op.tag == OpTag.EQUAL:
            continue
        var from_old = op.tag == OpTag.DELETE
        var first = Int(op.old_idx if from_old else op.new_idx)
        for i in range(first, first + Int(op.length)):
            var span = pair.old.spans[i] if from_old else pair.new.spans[i]
            var bytes = old.as_bytes() if from_old else new.as_bytes()
            var text = String(from_utf8=bytes[Int(span.start) : Int(span.start + span.len)])
            print("-" if from_old else "+", text)
```

Output:

```text
- quick
+ slow
```

### Custom splitters

Implement the `Splitter` trait. `token_end` returns the exclusive end of the token
starting at `pos`; it must be greater than `pos` and at most `len(src)`.

```mojo
from difpatch import Splitter, myers_diff, tokenize_pair

struct CommaSplitter(Splitter):
    def __init__(out self):
        pass

    def token_end(self, src: Span[Byte, _], pos: Int) -> Int:
        for i in range(pos, len(src)):
            if src[i] == 44:  # ','
                return i + 1
        return len(src)

def main() raises:
    var old = String("a,b,c")
    var new = String("a,x,c")
    var pair = tokenize_pair(old.as_bytes(), new.as_bytes(), CommaSplitter())
    print(myers_diff(Span(pair.old.ids), Span(pair.new.ids)).edit_distance())
```

Output:

```text
2
```

## Hunks and formatting

`unified_diff` is these four steps. Call them yourself to inspect or filter hunks.

| Function | Signature |
|---|---|
| `tokenize_pair` | with `LineSplitter()` |
| `myers_diff` | on `pair.old.ids` and `pair.new.ids` |
| `group_hunks` | `(ops: List[EditOp], context: Int) raises -> List[Hunk]` |
| `format_patch` | `(hunks, old, old_spans, new, new_spans, old_label, new_label) raises -> String` |

```mojo
from difpatch import LineSplitter, format_patch, group_hunks, myers_diff, tokenize_pair

def main() raises:
    var old = String("a\nb\n")
    var new = String("a\nc\n")
    var pair = tokenize_pair(old.as_bytes(), new.as_bytes(), LineSplitter())
    var result = myers_diff(Span(pair.old.ids), Span(pair.new.ids))
    var hunks = group_hunks(result.ops, 3)
    print(len(hunks))
    print(
        format_patch(hunks, old.as_bytes(), pair.old.spans, new.as_bytes(), pair.new.spans, "a/x", "b/x"),
        end="",
    )
```

Output:

```text
1
--- a/x
+++ b/x
@@ -1,2 +1,2 @@
 a
-b
+c
```

`format_patch` expects line tokens, and the assembled patch must be valid UTF-8.
Do not pass it word or byte tokens: the output would not be a usable unified diff.

**`Hunk`** has `old_start`, `old_count`, `new_start`, `new_count` and `ops`.
Starts are 1-based. When a count is `0`, the start is the line *before* the change.

**Grouping:** two changes share a hunk when at most `2 * context` unchanged lines
separate them.

**`hunk_header(old_start, old_count, new_start, new_count)`** returns the
`@@ -a,b +c,d @@` line without a newline. A count of 1 is omitted.

## Parsing patches

```mojo
parse_patch(text: Span[Byte, _]) raises -> ParsedPatch
```

| Type | Fields |
|---|---|
| `ParsedPatch` | `old_label`, `new_label`, `hunks`, `inserted_bytes` |
| `ParsedHunk` | `old_start`, `old_count`, `new_start`, `new_count`, `lines`, `text_start`, `text_end` |
| `PatchLine` | `tag` (the byte for space, `-` or `+`), `start`, `len`, `no_eol` |

`start`, `len`, `text_start` and `text_end` are byte offsets into the patch text,
so keep that text alive and pass the same bytes to `apply_report`.

Accepted:

- Text before the first `---`/`+++` pair, such as a `git diff` preamble.
- Timestamps after a tab in header lines.
- Omitted counts (`@@ -1 +1 @@`) and section headings after the closing `@@`.
- Empty context lines whose leading space was stripped.
- `\ No newline at end of file` markers.
- A `git format-patch` signature (`-- ` and a version number) at the end. Custom
  signature text is rejected.

Rejected with an error:

- Non-blank text with no `---`/`+++` header pair.
- A malformed hunk header, including start line `0` with a nonzero count.
- Any other non-blank text after the headers that is not part of a hunk.
- A truncated hunk, or a hunk with more lines than its header counts.
- A second file in the same patch.

Blank lines between and after hunks are ignored. A patch cut off in the middle of
its final line is accepted, and that line is applied without a newline if it ends
the file.

## Applying patches

```mojo
apply_report(
    original: Span[Byte, _], patch_text: Span[Byte, _], patch: ParsedPatch, opts: ApplyOptions
) raises -> ApplyReport
```

This is the detailed form of `apply_patch`. A rejected hunk does not raise; it is
reported, and the other hunks are still applied. Use it for dry runs, reject files
and non-UTF-8 data.

| Type | Fields |
|---|---|
| `ApplyOptions` | `max_offset`, `max_fuzz`. `ApplyOptions()` is strict. |
| `ApplyReport` | `output: List[Byte]`, `results: List[HunkResult]` (one per hunk, in order) |
| `HunkResult` | `applied`, `offset`, `fuzz`, `message` |

`message` is empty for an exact match. Otherwise it describes the offset and fuzz
used, or why the hunk was rejected. `offset` is positive when the hunk applied
further down than stated.

Check `results` before using `output`: if any hunk failed, the output is partial.

```mojo
from difpatch import ApplyOptions, apply_report, parse_patch

def main() raises:
    var original = String("a\nb\nc\n")
    var patch = String("--- a/f\n+++ b/f\n@@ -1 +1 @@\n-a\n+A\n@@ -3 +3 @@\n-zzz\n+C\n")
    var bytes = patch.as_bytes()
    var parsed = parse_patch(bytes)
    var report = apply_report(original.as_bytes(), bytes, parsed, ApplyOptions())
    for i in range(len(report.results)):
        if not report.results[i].applied:
            print(report.results[i].message)
            ref hunk = parsed.hunks[i]
            print(String(from_utf8=bytes[hunk.text_start : hunk.text_end]), end="")
    print(String(from_utf8=report.output), end="")
```

Output:

```text
hunk 2 @@ -3 +3 @@ does not match at line 3: expected 'zzz', found 'c'
@@ -3 +3 @@
-zzz
+C
A
b
c
```

### Matching rules

1. Hunks are applied in order. A hunk cannot overlap lines already used by an
   earlier one.
2. Fuzz level 0 is tried over the whole offset range first, then 1, and so on up
   to `max_fuzz`.
3. Within one fuzz level the nearest position wins. If two positions at the same
   distance (one above, one below) both match, the hunk is rejected as ambiguous.
4. Each hunk is searched from its own stated line. The offset found for one hunk
   is not carried to the next, so `max_offset` must cover the total drift.
5. Only old-side lines are compared. `new_start` does not affect placement.
6. Removed lines are never fuzzed. Context lines ignored by fuzz keep the bytes
   from your file.
7. Fuzz has **no effect** on a hunk whose old side is all context, which means
   every pure insertion. Such a hunk can still use `max_offset`.
8. A pure insertion with no context has nothing to match, so it goes to its stated
   line. If that line is past the end of the file, a large enough `max_offset`
   appends it at the end.
9. A hunk that would place text after a line with no final newline is rejected.

## Command line

```
difpatch [diff] OLD NEW [-U N] [--max-cost N]
difpatch apply FILE PATCH [--offset N] [--fuzz N]
```

| Option | Applies to | Default | Meaning |
|---|---|---|---|
| `-U N`, `--context N` | diff | 3 | Context lines per hunk. |
| `--max-cost N` | diff | 0 | Search limit; `0` is unlimited. At most 4294967295. |
| `--offset N` | apply | 0 | Maximum line drift. |
| `--fuzz N` | apply | 0 | Maximum ignored context lines per hunk end. |
| `-h`, `--help` | | | Print usage. |

- Results go to stdout. `apply` never modifies files.
- Exit status is `0` on success, **including when the files differ**, and nonzero
  on any error. This differs from `diff`.
- Both files must be valid UTF-8.
- Diff headers are always `a/f.txt` and `b/f.txt`.
- An option that does not apply to the command is accepted and ignored.
- To diff a file literally named `diff` or `apply`, write `difpatch diff apply other`.

```bash
build/difpatch old.txt new.txt > change.diff
build/difpatch apply old.txt change.diff > patched.txt
```

Do not redirect `apply` output onto its own input file: the shell empties the file
before difpatch reads it.

## Errors

All failures raise `Error` with a message. There are no error codes.

| Message contains | Cause |
|---|---|
| `context must be >= 0` | Negative context. |
| `max_offset and max_fuzz must be >= 0` | Negative apply option. |
| `labels cannot contain line breaks` | Newline in a diff label. |
| `input larger than 4 GiB` | Input too large to tokenize. |
| `splitter made no progress` | Faulty custom splitter. |
| `no unified diff header found` | The text is not a unified diff. |
| `malformed hunk header` | Bad `@@` line. |
| `unexpected text` | Non-blank text outside a hunk, such as a damaged header. |
| `is truncated` | The patch ends inside a hunk. |
| `unexpected line` | A hunk line does not fit the header counts. |
| `has more lines than its header counts` | Header counts too small. |
| `stray '\ No newline' marker` | Marker with no line before it. |
| `multiple files in one patch` | Split the patch per file. |
| `does not match` | Hunk context or removed lines differ from the file. |
| `matches equally well` | Ambiguous position; the hunk was not applied. |
| `no newline at end of file` | The hunk would join text onto an unterminated line. |

## Performance and limits

The diff trims the common start and end, drops tokens found on only one side, then
runs bidirectional Myers. Time grows with input size times the number of
differences; memory is linear. Many repeated lines with many changes are the slow
case.

`max_cost` limits the search at each split. The script stays valid but may be
longer than necessary. Try values such as 500 or 1000 for large, very different
inputs. Benchmark figures are in the [README](../README.md#performance), and
`pixi run bench` reproduces the measurements.

| Limit | Detail |
|---|---|
| Input size | Under 4 GiB. Only tokenizing checks this, so apply the same limit to `parse_patch` and `apply_report`. |
| Text API | Requires valid UTF-8. Use the byte-level functions otherwise. |
| Patch scope | One file per patch. |
| Not supported | Reverse apply, ignoring whitespace, renames, mode changes, binary patches. |
| File creation and deletion | `/dev/null` labels have no special meaning; your code creates or deletes files. |

## Contributing

```bash
pixi run test                                  # all test files
pixi run test_patch                            # one area (see pixi.toml)
pixi run build_cli && pixi run crosscheck      # compare with git apply and patch
pixi run bench                                 # stage timings
```

| File in `src/difpatch/` | Contents |
|---|---|
| `__init__.mojo` | Public exports |
| `api.mojo` | High-level functions |
| `types.mojo` | `OpTag`, `EditOp`, `Hunk`, `DiffResult` |
| `tokenize.mojo` | Splitters and the shared token table |
| `simd.mojo` | Vectorized prefix, suffix, byte search and hashing |
| `myers.mojo` | Diff algorithm |
| `hunks.mojo` | Hunk grouping |
| `format.mojo` | Unified diff output |
| `parse.mojo` | Patch parser |
| `apply.mojo` | Patcher |

The command-line front end is `src/cli.mojo`.

## License

[MIT](../LICENSE)
