#!/usr/bin/perl
use strict;
use warnings;
use lib (".");
use lib ("..");
use Data::Dumper;
#use JSON;
use DPUT;
use Digest::MD5;
my $samplepath = "";

############ JSON ##########
# p = Person
note("Load Well Formatted JSON (and Dump)");
my $p1 = jsonfile_load("./examples/sample.json");
print(Dumper($p1));
note("Load bad JSON (With caught exception)");
my $p2;
eval {
  $p2 = jsonfile_load("./examples/sample_bad.json");
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
 $ok = file_write("$tmpfn2", JSON::to_json($p3, {pretty => 1}));
if ($ok) { print("Wrote Pretty JSON nicely to '$tmpfn2'\n");}

my $md5sum = file_checksum($tmpfn2);
if (!$md5sum) { die("Cound not generate MD5 for $tmpfn2\n"); }
print("$md5sum $tmpfn2\n");

# Self Test for @EXPORT
my $text = file_read("DPUT.pm");
print("Content: ".length($text)." B\n");
my @allsyms = ($text =~ /^sub\s+(\w+)/gm);
my @exported = @DPUT::EXPORT;
#print(Dumper(\@allsyms));
#print(Dumper(\@DPUT::EXPORT));
my %exported = map({ ($_, 1); } @exported); # Index exported
#print(Dumper(\%exported));
#if (exists($exported{'jsonfile_load'})) { print("jsonfile_load - It's there\n");}
map({ if (!$exported{$_}) { print("'$_' not exported !\n");}} @allsyms);
print("# To export all, add:\n");
print("our \@EXPORT = (".join(', ', map({"'$_'"} @allsyms)).");\n");

# Dir listings
print("# Dir listings ($DPUT::VERSION)");
my $files = dir_list(".");
print("F1:".Dumper($files));
my $files2 = dir_list(".", 'tree' => 1);
print("F2:".Dumper($files2));

# Time
my $now = isotime();
my $date = `date -I`; chomp($date);
if ($date eq substr($now, 0, 10)) { print("Date portion of $now matches $date\n");}
else {print("isotime() error !\n");}
print("Time: $now / $date\n");
