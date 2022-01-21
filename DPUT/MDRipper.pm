package DPUT::MDRipper;
use DPUT;
use strict;
use warnings;
use File::Basename;

our $VERSION = '0.0.1';

# # MDRipper - Rip Markdown documentation out of (any) files
# 
# Markdown ripper uses a simple methodology for ripping MD content
# out of files.
# - Any lines starting with RegExp patter "^# " will be ripped
# - TODO: allow "minlines" config var to eliminate blocks ofd less
#   contiguous lines than number in "minlines"
# - Return MD document content
# - process one file at the time (mutiple files may be processed via same instance)

# ## DPUT::MDRipper->new(%opts);
# Construct new Markdown ripper.
sub new {
  my ($class, %opts) = @_;
  my $mdr = {};
  map({ $mdr->{$_} = $opts{$_}} keys(%opts));
  bless($mdr, $class);
  return $mdr
}

# ## $mdripper->rip($fname, %opts)
# Rip Markdown content from a single file, whose name is passed as parameter.
# Current settings of instance are used for this op.
# Return Mardown content.
sub rip {
  my ($mdr, $fname, %opts) = @_;
  my $lines = eval { file_read($fname, 'lines' => 1); };
  if ($@) { die("MDRipper: Error loading file '$fname' for processing: $@\n");}
  my @mdlines;
  # TODO: More complex or semi-complex MD-lines-block based ("state machine") algorithm ?
  # Needed to space the sections w. extra newline
  # This automatically strips '^##'
  #@mdlines = grep({ /^# /; } @$lines);
  # Semi-complex - does not remember blocks after parsing BUT adds extra "\n" after each block
  my $in = 0; # In MD block (state)
  for (@$lines) {
    if (/^# /) {
      #print("MDLINE: $_\n");
      if (!$in) {  $in = 1; } # Transition from non-MD to MD
      push(@mdlines, $_);
    }
    # No match, but $in - End of block (Add exact "# \n" to be able to strip "# ")
    elsif ($in) { push(@mdlines, "# \n"); $in = 0; }
    else {} # Other
  }
  @mdlines = map({ substr($_, 2); } @mdlines);
  return(join('', @mdlines)); # "\n" should be there
}

# ## DPUT::MDRipper::docs_create($files, %opts);
# 
# Create Markdown output on set of code files.
# Code files should contain segments/snippets of MD documentation.
# Creates an an Array of Objects with:
# - fname - Name for Original file (codefile, e.g. perl, python, shell) subject to extraction
# - mdcont - Markdown content (to be e.g. saved to file at end)
# - htmlcont - HTML content (in case MD-to-HTML conversion *was* done)
# - mdfn - Tentative / Suggested MD filename
# - htmlfn - Tentative / Suggested HTML filename
sub docs_create {
  my ($files, %opts) = @_;
  if (!$files || (ref($files) ne 'ARRAY' )) { die("No code files to extract MD from\n"); }
  #my $fullmd = "";
  #my $createhtml = 0;
  my @docs = ();
  for my $fname (@$files) {
    # my $fname = "../$_";
    if ($opts{basepath}) { $fname = "$opts{basepath}/$fname"; }
    if (!-f $fname) { die("No code file: '$fname' !"); }
    # Processes one whole file at the time
    my $md = DPUT::MDRipper->new()->rip($fname);
    my $e = {'fname' => $fname, 'mdcont' => $md};
    
    my $bn = basename($fname);
    if ($bn =~ m/\.\w+$/) { $bn =~ s/\.\w+$//; $e->{'mdfn'} = "$bn.md"; }
    else { print(STDERR "No suffix for code file !"); $e->{'mdfn'} = "$fname.md"; }
    #$fullmd .= $md;
    #print($md);
    if ($opts{'html'}) { # $createhtml
      eval("use Text::Markdown;");
      # my $html =
      $e->{'htmlcont'} = Text::Markdown::markdown($md);
      #print($html);
      # my $outfname = "./".basename($fname).".html";
      $e->{'htmlfn'} = "$bn.html";
      print(STDERR "Suggested HTML name: '$e->{'htmlfn'}'\n");
      #file_write($outfname, $html);
    }
    push(@docs, $e);
  }
  #return $fullmd;
  return \@docs;
}
