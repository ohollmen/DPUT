#!/usr/bin/perl
# # docrip.pl - Extract MD Documentation out of project files
# 
# docrip.pl allows to extract segments of Markdown (MD) documentation out of code
# files and create a higher level documentation out of them.
# It requires files (subject to extraction) to be listed/manifested in a small simple
# "single file per line" file which will pe passed on command line (by --fnlist).
# Hints on the rules of Markdown formatting within comments can be found in the (Markdown)
# documentation of DPUT::MDRipper.
#
# ## Module Files list (--fnlist)
# 
# The files to extract Documentation are taken from file given by --fnlist.
# 
# If the file contains names that are relative to particular directory, the name of
# that directory can be passed in --basepath. If you run utility in the the directory
# (to which names are relative to), passing --basepath will be unnecessary (as open()
#  will resolve the names as relative names successfully).
# 
# ## Output produced
# If 
# ## Example
# The documentation of DPUT Module itself is created with a following command (run in the examples dir):
# ```
# # Generate README.md
# examples/docrip.pl genmd --fnlist modulelist.txt --basepath ../ --outfn ../README.md
# # Generate HTML for visual QA
# examples/docrip.pl genhtml --fnlist modulelist.txt --basepath ../ --outfn ../README.html
# ```
use strict;
use warnings;
use lib(".");
use lib("..");
use DPUT::MDRipper;
use DPUT;
use Text::Markdown 'markdown';
use File::Basename;
use Data::Dumper;
use Getopt::Long;
use JSON;

my %opts = ("basepath" => "", "fnlist" => "", "outfn" => "", "outpath" => "");
my @optmeta = ("basepath=s", "fnlist=s", "outfn=s", "outpath=s");
my $ops = { genhtml => \&generatedoc, genmd => \&generatedoc, genjson => \&generatedoc };
my $op = shift(@ARGV);
my $oplist = join(', ', map({"$_"} keys(%$ops)));
if (!$op) { die("No op passed. Try: $oplist\n"); }
if (!$ops->{$op}) { die("No op '$op'. Try: $oplist\n"); }
GetOptions(\%opts, @optmeta);
if (!$opts{'fnlist'}) { die("No Filename list (--fnlist) passed!\n"); }
if (!-f $opts{'fnlist'}) { die("Filename list '$opts{'fnlist'}' (passed by --fnlist) does not exist!\n"); }
my $flist = DPUT::file_read($opts{'fnlist'}, 'lines' => 1, 'rtrim' => 1);
if (ref($flist) ne 'ARRAY') { die("File list not turned into an array !\n"); }
$ops->{$op}->();
exit(0);

# Generate Documentation in MD, HTML or JSON data structure (containing doc in all formats).
sub generatedoc {
  #my ($foo) = @_;
  if ($op eq 'genhtml') { $opts{html} = 1; } # Add 'htmlcont'
  my $docs = DPUT::MDRipper::docs_create($flist, %opts);
  if ($op eq 'genjson') { print(to_json($docs, { pretty => 1 })); return; }
  elsif ($op eq 'genmd') {
    my $cont = join('\n', map({ $_->{mdcont}; } @$docs));
    if ($opts{outfn}) {
      if ($opts{outfn} !~ m/\.md$/) { print(STDERR "Warning: Filename does not have .md suffix !\n"); }
      file_write($opts{outfn}, $cont,); # lines => 1
      print(STDERR "Wrote:", $opts{outfn}, "\n");
    }
    else { print($cont); }
  }
  elsif ($op eq 'genhtml') {
    my $cont = join('\n', map({ $_->{htmlcont}; } @$docs));
    if ($opts{outfn}) {
      if ($opts{outfn} !~ m/\.html$/) { print(STDERR "Warning: Filename does not have .html suffix !\n"); }
      file_write($opts{outfn}, $cont,); # lines => 1
      print(STDERR "Wrote:", $opts{outfn}, "\n");
    }
    else { print($cont); }
  }
}
