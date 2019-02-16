#!/usr/bin/perl
use strict;
use warnings;
use lib(".");
use lib("..");
use DPUT::MDRipper;
use DPUT;
use Text::Markdown 'markdown';
use File::Basename;
use Data::Dumper;
my @mods = ("DPUT.pm",);
my @mods2 = ("CLRunner",  "DataRun",  "MDRipper",  "OpRun", "Retrier", "ToolProbe");
map({push(@mods, "DPUT/$_.pm");} @mods2);
#my $fname = "../DPUT/DataRun.pm";
for (@mods) {
  my $fname = "../$_";
  if (!-f $fname) { die("No file: '$fname' !"); }
  my $md = DPUT::MDRipper->new()->rip($fname);
  #print($md);
  my $html = markdown($md);
  #print($html);
  my $outfname = "./".basename($fname).".html";
  print(STDERR "Suggested name: '$outfname'\n");
  file_write($outfname, $html);
}
