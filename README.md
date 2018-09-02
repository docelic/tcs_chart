# Tox Client Standard (TCS) - Compliance Data and Chart Generator

Tox TCS is located at: https://tox.gitbooks.io/tox-client-standard/content/index.html.

## Introduction

TCS points have been converted to parsable JSON format and stored in `tcs_points.json`.

Tox software's compliance sheets are found in `tox_software/*.json`.

When `generate.pl` is run with default options, it reads both files and produces a complete compliance table, in HTML format, printed to STDOUT.
Please run `./generate.pl -h` for all command line options.

Users will most likely want to configure options "output file" (`-o`), and possibly "point condition" (`-pc`) and "software condition" (`-sc`).
The first one configures the output file; the other two specify which subset of TCS points and/or software should be included in the report.

Using options `-pc` or `-sc` requires at least minimal familiarity with Perl. In both options, variable `$x` is a hash reference of the item being examined. Arbitrary Perl code can be run, and the item will be included in the output if the code block ends with a true value.

## Usage

```
# Basic usage, complete table is printed as HTML to STDOUT
./generate.pl   # (or   perl generate.pl)

# Dump complete table to file /tmp/chart.html
./generate.pl -o /tmp/chart.html

# Only include Tox software of type "client" into the chart:
./generate.pl -sc '$$x{type} eq "client"'

# Show only TCS points from section "2", and only software which
# is compliant with TCS point 1.0.1 or contains regular expression "ox"
# in its full name:
./generate.pl -pc '$$x{name} =~ /^2/' -sc '$$x{points}{"1.0.1"}{compliant} || $$x{name} =~ /ox/'

# Use option -pc or -sc to quickly dump the structure of element $x
./generate.pl -pc 'print Dumper $x; exit'
```

## HTML Output Example

Example of the output can be previewed at https://hcoop.net/~docelic/tcs_full.html
