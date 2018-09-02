#!/usr/bin/env perl

# This script reads in two sources of data:
#
# 1) Tox TCS specification in JSON format (tcs_points.json)
# 2) Compliance sheets for various Tox software (tox_software/*.json)
#
# Then it produces a "compliance matrix", combining all TSC points and
# software in a 2D table.
#
# Please use option -h for all command line options.
#
# Davor Ocelic <docelic@crystallabs.io>
# Sat Sep  1 17:53:23 CEST 2018

# TODO:
# - Add total compliance scores/percentages
# - Add more filtering options (e.g. only desktop clients, only mobile clients, etc.)
# - Add more comparison options (e.g. app1 vs app2 vs app3)
# - Generate text parts (e.g. "TCS point 1.0.1 is implemented by <clients>")
# - Add "X" button to every column and row, and minimal JavaScript to remove the respective column or row

# Here goes:

# Various initializations and checks

use warnings;
use strict;
use feature 'say';
BEGIN {
  eval { require JSON };
  if($@) { say "Please install dependencies: libjson-perl"; exit 1}
}
use Fatal qw/open close read write/;
use Data::Dumper qw/Dumper/;
$Data::Dumper::Terse++;
use Tie::IxHash;
use Getopt::Long qw/GetOptions/;
use subs qw/read_file err usage/;
my $json = JSON->new->allow_nonref->pretty;

# Definition of default config and data

my %C= (
  # Options
  output_file => '-', # - == STDOUT
  output_format => 'html', # raw | data | html | markdown?

  tcs_points_file => 'tcs_points.json',
  tox_software_glob => 'tox_software/*.json',

  dump_tcs_points => 0,
  dump_tox_software => 0,
  dump_tcs_matrix => 1,
);

# Command line options (they update default/existing values in %C)

tie my %getopt, 'Tie::IxHash';
%getopt = (
  'output_file|output-file|file=s' => "Output file for ALL outgoing data ( - == STDOUT)",
  'output_format|output-format|format|fmt|f=s' => "Output format for ALL outgoing data (raw | data | html)",

  'tcs_points_file|tcs-points-file|tcspoints|points=s' => "Name of input JSON containing TCS points",
  'tox_software_glob|tox-software-glob|software|glob=s' => "Glob pattern to use when finding Tox software JSONs",

  'dump_tcs_points|dump-tcs-points|dump-points|dpoints|di!' => "Dump TCS points?",
  'dump_tox_software|dump-tox_software|dump-software|dsoftware|ds!' => "Dump Tox software?",
  'dump_tcs_matrix|dump-tcs_matrix|dump-matrix|dmatrix|dm!' => "Dump TCS matrix?",
);

unless(GetOptions(
  \%C,
  keys(%getopt),
  'help!' => sub { print usage; exit },
)) { die "Error parsing options. Please use --help for usage instructions.\n"}

# Basic initialization and special cases based on cmdline options

$C{tcs_points} = load_tcs_points();
$C{tox_software} = load_tox_software();
$C{tcs_strings} = flatten_tcs_points();

dump_tcs_points() if $C{dump_tcs_points};
dump_tox_software() if $C{dump_tox_software};

# Main/standard work starts here

$C{tcs_matrix} = produce_tcs_matrix();

print dump_tcs_matrix() if $C{dump_tcs_matrix};

exit;

###########################################################
# Helpers below

# Reads file at once and returns contents as string
sub read_file {
  { local $/ = undef;
    open my $fh, '<', $_[0];
    my $data = <$fh>;
    close $fh;
    return $data
  }
}

# Prints error message, then exits program if $code is supplied and greater than 0
sub err {
  my( $msg, $code) = @_;
  print STDERR $msg;
  if($code) {
    print STDERR "; exiting.\n";
    exit $code
  } else {
    print STDERR ".\n"
  }
}

# Returns complete, multiline usage/help string
sub usage {
  my $content = "Usage: $0 <options>\n\nOptions:\n";
  while(($_, my $desc) = each %getopt) {
    #my $arg = ( $_ =~ s/=.$//) ? " ARG" : "";
    my $negated = s/!//;
    my $has_arg = s/=.$//;

    my ($name, @aliases) = split /\|/;
    @aliases= map { length > 1 ? "--$_" : "-$_"} @aliases;

    my $dfl = $negated ?  ($C{$name} ? "true" : "false") : $C{$name};

    local $" = ", ";
    $content .= "  --$name, @aliases\n";
    $content .= "    Description: $desc\n";
    $content .= "    Can disable: yes (prefix with --no-)\n" if $negated;
    $content .= "    Current value: $dfl\n";
    $content .= "\n";
  }
  $content
}

# Returns hashref containing decoded contents of tcs_points.json
sub load_tcs_points {
 $json->decode(read_file $C{tcs_points_file})
}

# Returns hashref of all JSONs found and decoded after glob expansion of tox_software_glob.
# Hash key is software's short name, hash value is the decoded JSON
sub load_tox_software {
  my @software = <$C{tox_software_glob}>;
  my %data;

  for(@software) {
    my $struct = $json->decode(read_file $_);
    $data{$$struct{shortname}} = $struct;
  }

  \%data
}

# Dumps TCS points the way they look to the program.
# In case of format 'raw', dumps the raw result of JSON decode.
# In case of format 'data', returns the result after flattening points' keys.
# Example:
#  raw: { 1 => { 0 => { 1 => ... }}}
#  data: { "1.0.1" => ...}
sub dump_tcs_points {
  my $content;

  if( $C{output_format} eq 'raw') {
    $content = $json->encode( $C{tcs_points});
  } elsif( $C{output_format} eq 'data') {
    $content = $json->encode( $C{tcs_strings});
  } else {
    err "Unsupported output format, please use --fmt raw | data", 1;
  }

  open my $out, ">$C{output_file}";
  print $out $content;
  close $out;
  exit 0
}

# Dumps Tox software points the way they look to the program.
# In case of format 'raw', dumps the raw result of JSON decode.
# In case of format 'data', returns current (possibly modified) data in memory.
sub dump_tox_software {
  my $content;

  if( $C{output_format} eq 'raw') {
    $content = $json->encode( load_tox_software())
  } elsif( $C{output_format} eq 'data') {
    $content = $json->encode( $C{tox_software});
  } else {
    err "Unsupported output format, please use --fmt raw | data", 1;
  }

  open my $out, ">$C{output_file}";
  print $out $content;
  close $out;
  exit 0
}

# Converts nested TCS hierarchy (as specified in tcs_points.json) into flat
# hash structure of: ( tcs_name => { TCS point data } )
#
# Example input ("section" => { "point" => "paragraph" => { ... data ...}}):
#   "4" => { "0" => "1" => { name: "test"}}
#
# Example output ("s.i.p" => { ... data ... }):
#   "4.0.1" => { name: "test" }
#
sub flatten_tcs_points {
  my %data;

  my $section = $C{tcs_points};
  while(my($sk,$point) = each %{$$section{points}}) {
    while(my($ik,$paragraph) = each %{$$point{points}}) {
      while(my($pk,$pidata) = each %{$$paragraph{points}}) {
        my $key = "$sk.$ik.$pk";
        $data{$key} = { 
          name => $key,
          %$pidata,
        };
        $data{$key}{url} ||= $$paragraph{url} || $$point{url};
      }
    }
  }

  \%data
}

# Dumps TCS matrix. This is the main focus of the script and multiple
# options affect the final output from this function.
sub dump_tcs_matrix {
  my $content;

  if( $C{output_format} eq 'raw') {
    $content = Dumper $C{tcs_matrix}
  } elsif( $C{output_format} eq 'data') {
    $content = $json->encode( $C{tcs_matrix});
  } elsif( $C{output_format} eq 'html') {
    $content = produce_html_output()
  } else {
    err "Unknown output format, please use --fmt html | raw | data", 1;
  }

  open my $out, ">$C{output_file}";
  print $out $content;
  close $out;
  exit 0
}

# Sort function that sorts TCS points in numerically-correct way
# (e.g. point "2.2.2" comes before "2.2.10"; "2.2.10" comes before "2.3.1")
sub compare_point {
  my @a = split /\./, $_[0];
  my @b = split /\./, $_[1];
  ( $a[0] <=> $b[0]) ||
  ( $a[1] <=> $b[1]) ||
  ( $a[2] <=> $b[2])
}

# Most important functions follow

# Iterates through all points and selected software. For each pair, it creates
# hash with computed TCS compliance data, then saves it to
# $data{ $tcs_point }{ $software } = { ... computed data ... }
sub produce_tcs_matrix {
  my %data;
  tie %data, 'Tie::IxHash';

  my @points = sort { compare_point($a,$b) } keys %{$C{tcs_strings}};
  my @software = sort keys %{$C{tox_software}};

  for my $i(@points) {
    for my $s(@software) {
      my $tcs_point = $C{tcs_strings}{$i};
      my $software = $C{tox_software}{$s};
      my $software_point = $C{tox_software}{$s}{points}{$i};

      my $computed = compute_compliance( $tcs_point, $software);

      unless( $data{$i}) {
        $data{$i}= {};
      }
      $data{$i}{$s} = $computed
    }
  }

  \%data
}

# Computes compliance. This needs to be computed rather than just taken
# from input data because the final status may depend on the combination
# of multiple TCS points and software's state.
# (e.g. consider this case:
# TCS point x.y.z is required IF software implements point a.b.c, or otherwise
# it does not apply.)
sub compute_compliance {
  my($ti, $s) = @_;
  my $si = $$s{points}{$$ti{name}};

  my %data = ();
  $data{comment} = "$$s{shortname}\n$$ti{name} = ${\( status2string($$si{compliant}) )}.\n" . ($$si{comment} ? "$$si{comment}\n" : '');
  $data{comment_flag} = $$si{comment} ? '*' : ''; # Change * to + if autogenerated comments get marked with * (15 lines below)
  $data{compliant} = $si ? $$si{compliant} : undef;

  # Figure out if this point must be complied to.
  my $must = $$ti{required};
  if( $$ti{depends_on}) {
    # TODO this code does not support looking up through a dependency chain, but one level only.
    my $dep_point = $$ti{depends_on};
    my $negated = ( $dep_point =~ s/!//g);
    $must = $$s{points}{ $dep_point }{compliant} ? $must : undef;
    $must = !$must if $negated;

    my $verb = status2string($must, "requires", "does not require", "does not apply to");
    my $dep_val = status2string($$s{points}{ $dep_point }{compliant});
    if( defined $$s{points}{ $dep_point }{compliant}) {
      $data{comment} .= "TCS $verb $$ti{name} due to $dep_point = $dep_val.\n";
      #$data{comment_flag} ||= '*'
    } elsif(!defined $$s{points}{ $dep_point }{compliant}) {
      $data{comment} .= "TCS requirement for $$ti{name} is unknown due to $dep_point = $dep_val.\n";
      #$data{comment_flag} ||= '*'
    }
  }
  $data{must} = $must;

  \%data
}

# Converts tri-state value (1,0,undef) into string/word representation
sub status2string {
  my( $must, $yes, $no, $na) = @_;
  if( defined $must) {
    if ($must) {
      return $yes || 'Yes'
    } else {
      return $no || 'No'
    }
  } else {
    return $na || 'Unknown'
  }
  err "Unhandled value of 'must': $must", 1;
}

# Produces HTML output based on all in-memory data.
sub produce_html_output {
  my $content = preamble();

  # Produce table header
  $content.= "<tr><th>TCS</th>";
  for(sort keys %{$C{tox_software}}) {
    my $sw = $C{tox_software}{$_};
    #if( $$sw{name} ne $$sw{shortname}) {
      my $name_string = $$sw{name};
      if( $$sw{name} ne $$sw{shortname}) {
        $name_string.= " ($$sw{shortname})";
      }
      my $platforms = join ', ', @{$$sw{platforms}};
      $_ = qq|<a href="$$sw{url}" title="$name_string\nTox $$sw{type} for $platforms\nHomepage: $$sw{url}\nLanguage: $$sw{language}\nLicense: $$sw{license}">$_</a>|;
    #} else {
    # $_ = qq|<a href="$$sw{url}">$_</a>|
    #}
    $content .= "<th>$_</th>"
  }
  $content .= "</tr>";

  # Produce cells data
  while(my($point,$point_softwares) = each %{$C{tcs_matrix}}) {
    $content .= qq|<tr><th><a href="$C{tcs_strings}{$point}{url}">$point</a></th>|;
    for my $software(sort keys %$point_softwares) {
      my $status = $$point_softwares{$software};
      my $display_value;

      # status == {
      #   comment => ''
      #   comment_flag => ''/*/+
      #   compliant => 1/0
      #   must => 1/0
      # }

      my $class = (defined $$status{must}) ? ($$status{must} ? "must" : "should") : "n-a";
      if( !defined $$status{compliant}) {
        $display_value = '?'; #(defined $$status{must}) ? '?' : 'N/A';
        $class .= ' unknown'
      } else {
        if( $$status{compliant}) {
          $display_value = 'Yes';
          $class .= ' compliant'
        } else {
          $class .= ' non-compliant';
          #if( defined $$status{must}) {
            $display_value = 'No';
          #} else {
          # $display_value = 'N/A';
          #}
        }
      }

      #if($$status{comment}) {
        $display_value = qq|<span title="$$status{comment}">$display_value$$status{comment_flag}</span>|;
      #} else {
      #  $display_value = qq|<span>$display_value</span>|
      #}

      $content .= "<td class='$class'>$display_value</td>";
    }
    $content .= "</tr>";
  }

  # Produce footer
  $content .= postamble();

  $content;
}

###########################################################
# Uninteresting parts below

sub preamble {
qq|<!DOCTYPE html>
<html lang="en">
<head>
<style>
th {
    padding-top: 11px;
    padding-bottom: 11px;
    /* #414141 is Tox website color. Use #4CAF50 if green is OK */
    background-color: #414141;
    /* #f5ad1a is Tox website color. Use white if white is OK */
    color: #f5ad1a;
}
td, th {
    border: 1px solid #ddd;
    text-align: center;
    padding: 8px;
    padding-top: 8px;
    padding-bottom: 8px;
}
td a, th a {
  color: #f5ad1a;
  text-decoration: none;
}
td a:hover, th a:hover {
  color: #f5ad1a;
  text-decoration: underline;
}
tr:nth-child(even) {
  background-color: #f2f2f2;
}
*, ::before, ::after {
    box-sizing: inherit;
}
table{
    font-size: 16px;
    font-family: "Trebuchet MS", Arial, Helvetica, sans-serif;
    border-collapse: collapse;
    border-spacing: 0;
}
html, body {
    font-family: Droid Sans,Verdana,sans-serif;
    font-size: 15px;
    line-height: 1.5;
    margin-bottom: 1em;
}
.pad {
  padding: 5px;
  width: 2em;
  display: inline-block;
  text-align: center;
}
.must.compliant {
  background-color: #5dba9e;
}
.must.non-compliant {
  background-color: #c77979;
}
.should.compliant {
  background-color: #5dba9e;
}
.should.non-compliant {
  background-color: #dedb7d; /* #ded840 */
}
.n-a.compliant {
}
.n-a.non-compliant {
}
.unknown {
}
</style>
</head>
<body>

<h1>$C{tcs_points}{name}</h1>

<p><a href="$C{tcs_points}{url}">$C{tcs_points}{url}</a></p>

<p>$C{tcs_points}{description}</p>

<p><strong>Legend:</strong><br>
<span class="pad must compliant">Yes</span> &mdash; point is required or recommended by TCS, and software implements it.<br>
<span class="pad must non-compliant">No</span> &mdash; point is required by TCS, but software does not implement it.<br>
<span class="pad should non-compliant">No</span> &mdash; point is recommended by TCS, but software does not implement it.<br>
<span class="pad n-a compliant">Yes</span> &mdash; TCS does not apply, but software implements point.<br>
<span class="pad n-a non-compliant">No</span> &mdash; TCS does not apply, and software does not implement point.<br>
<span class="pad unknown">?</span> &mdash; status is unknown, and pull requests containing updated information are welcome.<br>
</p>

<table cellspacing="8" cellpadding="0" border="0">
|
}

sub postamble {
qq|
</table>
</body>
</html>
|
}
