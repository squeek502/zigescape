zigescape
=========

A tool for converting between binary data and [Zig](https://ziglang.org/) string literals.

The original motivation for this was to be able to easily turn inputs found via fuzz testing into strings that can be used in Zig test cases ([like in the tests added by this commit](https://github.com/ziglang/zig/pull/9880/commits/36f1f4f9fe39492367445b60153d7217533fb379)).

Basic example (more can be found below):

```sh
$ echo '00 01 02 03 04' | xxd -r -p | zigescape
"\x00\x01\x02\x03\x04"
```

or with the `--hex` option, this can be done directly:

```sh
$ zigescape --hex "00 01 02 03 04"
"\x00\x01\x02\x03\x04"
```

## Building / Installation

### Precompiled binaries

1. Go to the [latest release](https://github.com/squeek502/zigescape/releases/latest)
2. Download the relevant asset for your OS
3. Rename to `zigescape` or `zigescape.exe` and give it executable permission (if necessary on your OS)
4. Move the executable somewhere in your `PATH`

### From Source

Requires latest master of Zig.

2. `zig build`
3. The compiled binary will be in `zig-out/bin`
4. `mv` or `ln` the binary somewhere in your `PATH`

## Usage

```
Usage: zigescape [-hsx] [-o <PATH>] <INPUT>

<INPUT>: Either a path to a file, or a Zig string literal (if using --string),
         or a series of hex bytes in string format (if using --hex).
         If <INPUT> is not specified, then stdin is used.

Available options:

-h, --help             Display this help and exit.

-o, --output <PATH>    Output file path (stdout is used if not specified).

-s, --string           Specifies that the input is a Zig string literal.
                       Output will be the parsed string.

-x, --hex              Specifies that the input is a series of hex bytes
                       in string format (e.g. "0A B4 10").
                       Output will be a Zig string literal.
```

## Examples

### Converting *to* a string literal:

```
zigescape path/to/file
```

or

```
zigescape < path/to/file
```

or, if you want to output to a file:

```
zigescape path/to/file -o path/to/outfile
```

or, if you want to convert from a series of hex bytes in string format:

```
zigescape --hex "00 01 02 03 04"
```

### Converting *from* string literal

> Note: shell escaping of arguments can mess with the string literal before it gets parsed, so it's best to use single quotes to bypass shell escaping. 

```
zigescape --string '"hello world\n"'
```

The double quotes are optional, `zigescape` will add them if they are missing:

```
zigescape --string 'hello world\n'
```

To convert from a series of hex bytes to a string literal and then into a binary file:

```
zigescape --hex "00 01 02 03 04" | zigescape --string -o outfile.bin
```

### Some silly examples

`cat`ing a file by converting it to a string literal and then parsing it to stdout:

```
zigescape path/to/file | zigescape --string
```

Copying a file by converting it to a string literal and then parsing it:

```
zigescape path/to/file.orig | zigescape --string -o path/to/file.copy
```
