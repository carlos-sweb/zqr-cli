# zqr

`zqr` is a command-line QR Code Model 2 **encoder and decoder** built with [Zig 0.17](https://ziglang.org/).
It is powered by [z-libqr](https://github.com/carlos-sweb/z-libqr) **v1.6.4**, [z-args](https://github.com/carlos-sweb/z-args) v0.1.0, and [z-print](https://github.com/carlos-sweb/z-print) v0.1.0.

**CLI version: 0.4.3.**

Encode supports four output formats (ANSI half-blocks, ASCII, SVG, and PNG), multi-mode DP segmentation, JIS X 0208 Kanji, GS1/AIM FNC1, ECI, and Structured Append (up to 16 symbols).
Decode accepts PNG images (magic-byte detection), ASCII matrices, and ANSI half-block terminal renderings, with perspective/rotation/mirror/dark-mode recovery via z-libqr’s image pipeline.

---

## Requirements

- **Zig 0.17.0** (see `minimum_zig_version` in `build.zig.zon`). Verify with `zig version`.
- Optional: system **libpng** when building with `-Denable-png=true` (default). Needed for PNG encode and PNG decode.
- Dependencies are fetched by URL + hash from `build.zig.zon` (not a Zig package registry).

---

## Installation & Building

```bash
git clone https://github.com/carlos-sweb/zqr-cli.git
cd zqr-cli

# Standard build (PNG encode + PNG decode via libpng):
zig build -Doptimize=ReleaseFast

# Without libpng (SVG, ANSI, ASCII encode; ASCII/ANSI decode only):
zig build -Denable-png=false -Doptimize=ReleaseFast
```

Binary: `zig-out/bin/zqr`.

```bash
zqr -V
# zqr 0.4.3 (z-libqr 1.6.4)
```

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
| `encode` | `e` | Encode data and render to SVG, PNG, ANSI half-blocks, or ASCII |
| `decode` | `d` | Decode from PNG image, ASCII matrix, or ANSI half-block text (file or stdin) |
| `info` | `i` | Analyze payload capacity and minimum version across ECC levels |

---

## Subcommand: `encode`

```bash
zqr encode [OPTIONS] [DATA]
```

### Options

| Flag | Short | Default | Description |
|---|---|---|---|
| `-o, --output <path>` | `-o` | `stdout` | Output file or `-` for stdout. Format from `.svg`, `.png`, `.txt` when `-f auto`. |
| `-f, --format <fmt>` | `-f` | `auto` | `auto`, `svg`, `png`, `ansi`, `ascii`. |
| `-i, --read-from <path>` | `-i` | `""` | Read payload from file or `-` for stdin. |
| `-e, --ecc <level>` | `-e` | `medium` | `low` / `medium` / `quartile` / `high` (or `l`/`m`/`q`/`h`). |
| `--qr-version <1..40>` | | | Force exact version. Overrides min/max. |
| `--min-version <1..40>` | | `1` | Minimum version. |
| `--max-version <1..40>` | | `40` | Maximum version. |
| `-m, --mask <0..7>` | `-m` | `-1` | Forced mask, or `-1` for automatic ISO penalty. |
| `--kanji` | | `false` | Enable JIS X 0208 Kanji mode. |
| `--optimize` / `--no-optimize` | | `true` | Multi-mode DP optimizer. |
| `--fnc1 <mode>` | | `none` | `none`, `first` (GS1), or `second` (AIM). |
| `--fnc1-app <indicator>` | | `""` | For `--fnc1 second`: `"00"`..`"99"` or a letter `"A"`..`"Z"`. |
| `--eci <0..999999>` | | | ECI assignment number. |
| `-S, --structured <count>` | `-S` | `""` | Structured Append: `auto` or `1`..`16`. Requires `--output`. |
| `-s, --scale <px>` | `-s` | `8` | Pixels per module (SVG/PNG). |
| `-q, --quiet-zone <modules>` | `-q` | `4` | Quiet zone (ISO default 4). |
| `--dot-shape <shape>` | | `square` | Data module shape: `square` or `rounded` (smooth blob). |
| `--eye-shape <shape>` | | `square` | Finder pattern shape: `square` or `rounded` (1:1:3:1:1 circles). |
| `--fg <hex>` | | `#000000FF` | Foreground `#RRGGBB` or `#RRGGBBAA`. |
| `--bg <hex>` | | `#FFFFFFFF` | Background `#RRGGBB` or `#RRGGBBAA`. |
| `-h, --help` | `-h` | | Encode help. |

---

## Subcommand: `decode`

Decodes one QR symbol from:

- **PNG** — detected by the 8-byte magic `\x89PNG\r\n\x1a\n` (not by file extension alone).
- **ASCII** — `##`/`  `, `#`/`.`, `1`/`0`, `█`/` `.
- **ANSI half-blocks** — `▀` (U+2580) terminal rendering.

```bash
zqr decode [OPTIONS] [FILE]
```

`FILE` or `-i` / `-` reads from a path or stdin.

### Options

| Flag | Short | Default | Description |
|---|---|---|---|
| `-i, --read-from <path>` | `-i` | `""` | Read input from file or `-` for stdin. |
| `-o, --output <path>` | `-o` | `""` | Write payload to file (default: stdout). |
| `-v, --verbose` | `-v` | `false` | Print symbol metadata to **stderr** as `key: value` lines. |
| `-h, --help` | `-h` | | Decode help. |

### `--verbose` format

Lines are written to stderr, one `key: value` per line. Always present:

```text
version: <1..40>
ecc: low|medium|quartile|high
mask: <0..7>
modes_used: <comma-separated: numeric,alphanumeric,byte,kanji,eci,fnc1,structured_append>
errors_corrected_format: <u8>
errors_corrected_version: <u8>
errors_corrected_data: <u16>
has_sa: 0|1
has_eci: 0|1
has_fnc1: 0|1
```

When `has_sa: 1`, also: `sa_position`, `sa_total`, `sa_parity` (hex).
When `has_eci: 1`, also: `eci`.
When `has_fnc1: 1`, also: `fnc1_mode` (`first`|`second`) and optionally `fnc1_app_indicator`.

### Exit codes

| Code | Meaning | When |
|---|---|---|
| `0` | Success | Payload written to stdout (or `-o`). |
| `1` | Decode / usage error | Corrupt matrix/image, RS/BCH failure, invalid dimensions, bad flags, etc. |
| `2` | I/O error | Missing input, file not found, access denied, read/write failure. |

(Root dispatch in `src/main.zig`: I/O-class errors → 2; everything else → 1.)

### Canonical pipes

```bash
zqr encode "Hello World" -f png | zqr decode -
# Hello World

zqr encode "Hello World" -f ascii | zqr decode -
# Hello World

zqr encode "Hello World" -f png | zqr decode - --verbose
# payload on stdout; metadata on stderr
```

---

## Subcommand: `info`

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

Options: `-i/--read-from`, `--kanji`, `--optimize` / `--no-optimize`, `-h/--help`.

---

## Examples

### Encode — four formats

```bash
# ANSI half-blocks (default on a TTY with no -o)
zqr encode "https://ziglang.org"

# ASCII (pipes / logs)
zqr encode "Server node #42 OK" -f ascii

# SVG
zqr encode "https://example.com" -o qr.svg

# PNG with custom colors
zqr encode "CONFIDENTIAL" -e high -s 12 --fg "#003366FF" --bg "#EEEEEEFF" -o badge.png
```

### Custom shapes and colors (SVG / PNG)

Both SVG and PNG output support custom foreground/background colors and rounded shapes:

```bash
# Rounded smooth blobs with rounded circular eyes (SVG):
zqr encode "https://example.com" -f svg --dot-shape rounded --eye-shape rounded -o rounded.svg

# Rounded modules with custom dark blue foreground and off-white background (PNG):
zqr encode "https://example.com" -f png --dot-shape rounded --eye-shape rounded \
  --fg "#1A1A2EFF" --bg "#F5F5F5FF" -s 16 -o elegant.png

# Square data modules with rounded concentric finder eyes:
zqr encode "https://example.com" -f svg --dot-shape square --eye-shape rounded -o hybrid.svg
```

### Decode

```bash
zqr decode qr.png
zqr decode -i qr.txt --verbose
zqr decode -i qr.png -o payload.bin
```

### Stdin / pipes

```bash
cat payload.txt | zqr encode -o output.png
echo -n "123456789" | zqr info
```

### FNC1 / Structured Append (encode)

```bash
zqr encode "010123456789012810BATCH1" --fnc1 first -o gs1.svg
zqr encode "AIM DATA" --fnc1 second --fnc1-app "A" -o aim.png

# Structured Append: requires -o; inserts _01, _02, … or uses {n} in the path
zqr encode "Long payload..." -S 3 -o backup.png
# → backup_01.png, backup_02.png, backup_03.png
zqr encode "Long payload..." -S auto -o "symbol_{n}.svg"
```

---

## Known limitations

- **PNG downscale:** decode downscales images with `max(width, height) > 1024` proportionally into a ≤1024×1024 box (area box average) before vision decode (`src/png_loader.zig`).
- **One QR per image:** the image decoder returns a single best finder triad (z-libqr Phase B); it does not iterate multiple codes in one frame.
- **Structured Append:** encode can split into up to 16 symbols. Decode of each symbol reports SA metadata via `--verbose` (`has_sa`, `sa_position`, `sa_total`, `sa_parity`) and does **not** reassemble the full sequence — the caller must join fragments (same contract as z-libqr).
- **PNG disabled build:** with `-Denable-png=false`, PNG encode and PNG decode are unavailable; use SVG/ANSI/ASCII.

Library-level details (tiers, C ABI, GF tables, etc.): see [z-libqr](https://github.com/carlos-sweb/z-libqr).

---

## License

MIT License for zqr-cli. See [LICENSE](LICENSE).

This CLI depends on **z-libqr**, which includes code derived from Project Nayuki’s QR Code generator (MIT) and quirc (ISC). Those notices live in the [z-libqr LICENSE](https://github.com/carlos-sweb/z-libqr/blob/main/LICENSE); they are not duplicated here.
