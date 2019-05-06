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
my @mods2 = ("CLRunner",  "DataRun",  "MDRipper",  "OpRun", "Retrier", "ToolProbe", "RSyncer");
map({push(@mods, "DPUT/$_.pm");} @mods2);
#my $fname = "../DPUT/DataRun.pm";

#sub fullmd_create (
#  my (@files, %opts) = @_;
my $fullmd = "";
my $createhtml = 0;
for (@mods) {
  my $fname = "../$_";
  if (!-f $fname) { die("No file: '$fname' !"); }
  my $md = DPUT::MDRipper->new()->rip($fname);
  $fullmd .= $md;
  #print($md);
  if (createhtml) {
    my $html = markdown($md);
    #print($html);
    my $outfname = "./".basename($fname).".html";
    print(STDERR "Suggested name: '$outfname'\n");
    file_write($outfname, $html);
  }
}
#  return $fullmd;
#} # sub
# Write README.md
my $fullfn = "../README.md";
print(STDERR "Writing Main Module document: '$fullfn'\n");

file_write($fullfn, $fullmd);
