#!/usr/bin/perl
use strict;
use warnings;
use lib (".");
use lib ("..");
use Data::Dumper;
#use JSON;
use DPUT;
my $samplepath = "";

############ JSON ##########
# p = Person
note("Load Well Formatted JSON (and Dump)");
my $p1 = jsonfile_load("./examples/sample.json");
print(Dumper($p1));
note("Load bad JSON (With caught exception)");
my $p2;
eval {
  my $p2 = jsonfile_load("./examples/sample_bad.json");
};
if ($@) { print("Got an exception '$@' on bad JSON (which is okay)\n");}

note("Try Loading commented JSON with bad-comment fixing enabled");
my $opts = {"stripcomm" => qr/^\s*(#.*?|\/\/.*?)\n/m};
my $p3 = jsonfile_load("./examples/sample_bad.json", %$opts);
print(Dumper($p3));

sub note {print("# $_[0]\n");}

# Regular file
my $testfile = "/etc/resolv.conf";
my @s = stat($testfile);
my $size = $s[7];
my $cont = file_read($testfile);
if ($size == length($cont)) { print("Content for $testfile is correct size\n");}

my $badfn = substr($testfile, 0, 7);
note("Try reading file with bad name ($badfn)");
eval {
  my $cont2 = file_read($badfn);
  print("Content:".$cont2);
};
if ($@) { print("Non-exiting file throws error '$@' (okay)\n"); }

# Write
# 
my $time = time();
my $tmpfn = "/tmp/$time.$$.json";
my $ok = file_write("$tmpfn", JSON::to_json($p3));
if ($ok) { print("Wrote Ugly JSON nicely to '$tmpfn'\n");}
my $tmpfn2 = "/tmp/$time.$$.pretty.json";
my $ok = file_write("$tmpfn2", JSON::to_json($p3, {pretty => 1}));
if ($ok) { print("Wrote Pretty JSON nicely to '$tmpfn2'\n");}
