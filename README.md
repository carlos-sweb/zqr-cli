# zqr

`zqr` is a high-performance command-line QR Code Model 2 encoder and renderer built with [Zig 0.17](https://ziglang.org/). Powered by [z-libqr](https://github.com/carlos-sweb/z-libqr) v1.4.0, [z-args](https://github.com/carlos-sweb/z-args) v0.1.0, and [z-print](https://github.com/carlos-sweb/z-print) v0.1.0.

It exposes all features of the ISO/IEC 18004:2015 specification, supporting four output formats (ANSI half-blocks, ASCII, SVG, and PNG), multi-mode DP segmentation optimization, JIS X 0208 Kanji, GS1/AIM FNC1 modes, ECI, and Structured Append (up to 16 symbols).

---

## Installation & Building

Requires Zig 0.17.0.

```bash
git clone https://github.com/carlos-sweb/zqr-cli.git
cd zqr-cli

# Standard build with PNG (libpng) and SVG support:
zig build -Doptimize=ReleaseFast

# Zero-dependency build (SVG, ANSI, ASCII only, without libpng):
zig build -Denable-png=false -Doptimize=ReleaseFast
```

The resulting binary is located at `zig-out/bin/zqr`.

---

## Usage Overview

```text
zqr <COMMAND> [OPTIONS] [DATA]
zqr -V, --version
zqr -h, --help
```

### Commands

| Command | Alias | Description |
|---|---|---|
| `encode` | `e` | Encode input data and render to SVG, PNG, ANSI half-blocks, or ASCII text |
| `decode` | `d` | Decode QR Code matrix from ASCII text or terminal ANSI rendering |
| `info` | `i` | Analyze data payload capacity and minimum version requirements across ECC levels |

---

## Subcommand: `encode`

Encodes data and outputs the generated QR code to stdout or a file.

```bash
zqr encode [OPTIONS] [DATA]
```

### Options Reference

| Flag | Short | Default | Description |
|---|---|---|---|
| `-o, --output <path>` | `-o` | `stdout` | Output file path or `-` for stdout. Auto-detects format from `.svg`, `.png`, `.txt`. |
| `-f, --format <fmt>` | `-f` | `auto` | Output format: `auto`, `svg`, `png`, `ansi`, `ascii`. |
| `-i, --read-from <path>` | `-i` | `""` | Read payload from file path or `-` for stdin. |
| `-e, --ecc <level>` | `-e` | `medium` | Error correction level: `low` (L, ~7%), `medium` (M, ~15%), `quartile` (Q, ~25%), `high` (H, ~30%). |
| `--qr-version <1..40>` | | | Force exact QR version (1..40). Overrides `--min-version` and `--max-version`. |
| `--min-version <1..40>` | | `1` | Minimum allowable QR version. |
| `--max-version <1..40>` | | `40` | Maximum allowable QR version. |
| `-m, --mask <0..7>` | `-m` | `-1` | Forced mask pattern (`0`..`7`, or `-1` for automatic ISO penalty evaluation). |
| `--kanji` | | `false` | Enable JIS X 0208 double-byte Kanji mode for Japanese Shift-JIS text. |
| `--optimize` / `--no-optimize` | | `true` | Dynamic programming optimal multi-mode segmentation optimizer. |
| `--fnc1 <mode>` | | `none` | FNC1 mode: `none`, `first` (GS1 barcoding), or `second` (AIM application indicator). |
| `--fnc1-app <indicator>` | | `""` | Application indicator for `--fnc1 second`: two digits (`"00"`..`"99"`) or single letter (`"A"`..`"Z"`, `"a"`..`"z"`). |
| `--eci <0..999999>` | | | Extended Channel Interpretation assignment number. |
| `-S, --structured <count>` | `-S` | `""` | Structured Append: `auto` or forced symbol count (`1`..`16`). Requires `--output`. |
| `-s, --scale <px>` | `-s` | `8` | Pixels per module for SVG and PNG rendering. |
| `-q, --quiet-zone <modules>` | `-q` | `4` | Quiet zone margin in modules (ISO standard is 4). |
| `--fg <hex>` | | `#000000FF` | Foreground color in `#RRGGBB` or `#RRGGBBAA` hex. |
| `--bg <hex>` | | `#FFFFFFFF` | Background color in `#RRGGBB` or `#RRGGBBAA` hex. |
| `-h, --help` | `-h` | | Show help for `encode` command. |

---

## Subcommand: `info`

Analyzes input data and reports the exact payload length along with the minimum QR Code version and module dimensions required for each of the four error correction levels.

```bash
$ zqr info "HELLO WORLD"
zqr info: Payload Analysis
  Payload length: 11 bytes

Minimum Version Required by Error Correction Level:
  Low (L)         Version  1 ( 21x21  modules) - ~7% recovery
  Medium (M)      Version  1 ( 21x21  modules) - ~15% recovery (default)
  Quartile (Q)    Version  1 ( 21x21  modules) - ~25% recovery
  High (H)        Version  2 ( 25x25  modules) - ~30% recovery
```

Options:
- `-i, --read-from <path>`: Read payload from file or `-` for stdin.
- `--kanji`: Enable JIS X 0208 Kanji mode analysis.
- `--optimize`: Multi-mode DP segmentation optimizer (default: true).

---

## Subcommand: `decode`

Decodes a QR code from PNG image files, ASCII text (`##`/`  `, `#`/`.`, `1`/`0`, `█`/` `), or terminal ANSI half-block rendering (`▀`). Supports all QR Code Model 2 versions (1..40) with vision-pipeline perspective/orientation recovery, downscaling, and Reed-Solomon and BCH error correction.

```bash
zqr decode [OPTIONS] [FILE]
```

### Options Reference

| Flag | Short | Default | Description |
|---|---|---|---|
| `-i, --read-from <path>` | `-i` | `""` | Read input from file or `-` for stdin. |
| `-o, --output <path>` | `-o` | `""` | Write decoded payload to file (default: stdout). |
| `-v, --verbose` | `-v` | `false` | Print symbol metadata (version, ECC, mask, corrections) to stderr. |
| `-h, --help` | `-h` | | Show help for `decode` command. |

### Exit Codes

| Code | Meaning | Description |
|---|---|---|
| `0` | Success | QR symbol decoded successfully; payload written to stdout. |
| `1` | Decode Error | Corrupt matrix or image, uncorrectable Reed-Solomon/BCH errors, or invalid QR dimensions. |
| `2` | I/O Error | Missing input data, file not found, or read/write I/O failure. |

### Canonical Pipe Examples

PNG pipeline:
```bash
zqr encode "Hello World" -f png | zqr decode -
# Output: Hello World
```

ASCII text matrix pipeline:
```bash
zqr encode "Hello World" -f ascii | zqr decode -
# Output: Hello World
```

With symbol metadata on stderr:
```bash
zqr encode "Hello World" -f png | zqr decode - --verbose
```
Stderr output:
```text
version: 1
ecc: medium
mask: 2
modes_used: byte
errors_corrected_format: 0
errors_corrected_version: 0
errors_corrected_data: 0
has_sa: 0
has_eci: 0
has_fnc1: 0
```

---

## Examples

### 1. Terminal Preview (ANSI Half-Blocks)
When connected to a terminal (TTY) and no output file is given, `zqr` defaults to high-contrast ANSI Unicode half-blocks (`▀` U+2580):
```bash
zqr encode "https://ziglang.org"
```

### 2. Plain Text / ASCII (for logs or headless pipes)
```bash
zqr encode "Server node #42 OK" -f ascii
```

### 3. Scalable Vector Graphics (SVG)
Generates standalone, zero-dependency SVG vector files with merged horizontal runs:
```bash
zqr encode "https://example.com" -o qr.svg
```

### 4. High-Resolution PNG with Custom Colors
```bash
zqr encode "CONFIDENTIAL" -e high -s 12 --fg "#003366FF" --bg "#EEEEEEFF" -o badge.png
```

### 5. Piped Input from Stdin
```bash
cat payload.txt | zqr encode -o output.png
echo -n "123456789" | zqr info
```

### 6. GS1 Barcoding (FNC1 First Position)
```bash
zqr encode "010123456789012810BATCH1" --fnc1 first -o gs1.svg
```

### 7. AIM Barcoding (FNC1 Second Position)
```bash
zqr encode "AIM DATA" --fnc1 second --fnc1-app "A" -o aim.png
```

### 8. Structured Append (Multi-Symbol Sequences)
Splits large payloads across up to 16 linked QR symbols with ISO parity verification.
```bash
# Auto-inserts _01, _02, _03 before extension:
zqr encode "Long payload to be split across symbols..." -S 3 -o backup.png
# Outputs: backup_01.png, backup_02.png, backup_03.png

# Explicit {n} template:
zqr encode "Long payload..." -S auto -o "symbol_{n}.svg"
```

---

## License

MIT License. See [LICENSE](LICENSE) for details.
