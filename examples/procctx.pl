#!/usr/bin/perl
# Example of extracting processing context and parsing version
use lib (".");
use lib ("..");
use strict;
use warnings;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use DPUT;

my $pc = DPUT::procctx('env' => 'none');
#print(Dumper($pc));

my $re = qr/v?(\d+)\.(\d+)\.(\d+).*/;
my $verstr = "v2.6.7-rc54";
my $names = ['major','minor','patch'];
print("Parse '$verstr' into keys: @$names\n");
my $v = DPUT::named_parse($re, $verstr, $names);
if (!$v) { die("Could not extract version"); }
print(Dumper($v)); # 

$verstr = "2.6.7-rc54";
print("Parse '$verstr' (w/o 'v...') into keys: @$names (same Regexp)\n");
my $v = DPUT::named_parse($re, $verstr, $names);
if (!$v) { die("Could not extract version"); }
print(Dumper($v)); # 

push(@$names, "rc");
my $re = qr/v?(\d+)\.(\d+)\.(\d+).*?(\d+)/;
print("Parse '$verstr' into keys: @$names (same Regexp)\n");
my $v = DPUT::named_parse($re, $verstr, $names);
if (!$v) { die("Could not extract version"); }
print(Dumper($v)); # 

sub lineofpatt {
  my ($fname) = @_;
  
}
