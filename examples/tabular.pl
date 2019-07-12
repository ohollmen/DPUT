#!/usr/bin/perl
# Example of extracting info out of CSV or XLSX
use lib (".");
use lib ("..");
use strict;
use warnings;
use DPUT;
use Text::CSV; # libtext-csv-perl
use Spreadsheet::XLSX; # libspreadsheet-xlsx-perl
use Text::Iconv;
use Data::Dumper;
use Net::Netrc;

my $csv = Text::CSV->new({binary => 1});
if (!$csv) { die("No Text::CSV processor instance created !"); }
################################################
note("Extract from animals.csv, use headers from file");
my $ok = open(my $fh, "<", "animals.csv");
my $aoh = DPUT::csv_to_data($csv, $fh, 'cols' => undef);
print(Dumper($aoh));
close($fh);
#################################################
# Filter (validation) callback
my $vcb = sub {my ($e) = @_; if ($e->{'Expected-age'} < 4) {
  print("Filtering: Animal $e->{'Kind'} is short lived ($e->{'Expected-age'})\n");return(0);
}
  return 1;
};
note("Extract from animals.csv, use headers from file, Validate by callback");
my %opts = ('cols' => undef, 'validcb' => $vcb);
$aoh = DPUT::csv_to_data($csv, "animals.csv", %opts);
print(Dumper($aoh));
###########################
note("Extract from animals.csv, use explicit headers, strip header line, Validate by callback");
my %opts = ('cols' => ['spec', 'legcnt', 'expage'], 'striphdr' => 1);
$aoh = DPUT::csv_to_data($csv, "animals.csv", %opts);
print(Dumper($aoh));
###################################################
my $converter = Text::Iconv->new ("utf-8", "windows-1251");
my $excel = Spreadsheet::XLSX->new("animals.xlsx", $converter);
my $sheet = $excel->{Worksheet}->[0];
note("Extract from animals.xlsx, use headers from file");
my %xopts = ('debug' => 1, 'fullinfo' => 1);
$aoh = DPUT::sheet_to_data($sheet, %xopts);
print(Dumper($aoh));
###################################################
note("Extract from animals.xlsx, use explicit headers, strip header line");
$xopts{'cols'} = ['spec', 'legcnt', 'expage'];
$xopts{'striphdr'} = 1;
$aoh = DPUT::sheet_to_data($sheet, %xopts);
print(Dumper($aoh));
#################### NETRC ##########################
note("lookup host credentials from .netrc");
my $creds = DPUT::netrc_creds('me');
print("netrc_creds:".Dumper($creds));
# Compare to Net::Netrc
my $mach = Net::Netrc->lookup('me');
@$creds{'host','user','pass'} = @$mach{'machine','login','password'};
print("Parsed-by-Net::Netrc:".Dumper($mach));
print("Parsed-by-Net::Netrc-remapped-keys:".Dumper($creds));
sub note {
  my ($msg) = @_;
  print("# $msg\n");
}
