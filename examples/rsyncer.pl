#!/usr/bin/perl
# Example of creating an Rsyncer App with config in a JSON File.
# App is very much data driven by config.
# Example of running:
#     ./rsyncer.pl --config myrsyncproject.json --runtype series
use lib (".");
use lib ("..");
use strict;
use warnings;
use DPUT;
use DPUT::RSyncer;
use File::Path ('make_path', 'remove_tree');
use Getopt::Long;
use Data::Dumper;
use Sys::Hostname;

# Prepare local rsync test files
preptestfiles();
my @optsmeta = ('runtype=s','debug','nodebug','prof=s', 'config=s');
# print("loaded DPUT::RSyncer $DPUT::RSyncer::VERSION\n\n");


# Note: We are not locked onto JSON (config) files, but we could load
# config from a file with perl array-ref by:
# my $tasks = require("./copies.pl");
my %opts = ('runtype' => 'parallel', 'debug' => 1, 'config' => './rsync.conf.json',
  'preitemcb' => sub {my ($rst) = @_; print("Syncing: '$rst->{'title'}'\n"); }); # 'seq' => 1, 'runtype' => 'series' / 'parallel'
GetOptions(\%opts, @optsmeta);
if ($ENV{'RSYNCER_DEBUG'}) { $opts{'debug'} = 0; }
if ($opts{'nodebug'}) { $opts{'debug'} = 0; }
if ($opts{'debug'}) { print(STDERR "Starting to run on ".hostname()." as UID real: $< eff: $>\n"); }
# Load Rsync config
if (!-f $opts{'config'}) { die("Rsync JSON Config file '$opts{'config'}' does not exist"); }
my $tasks = jsonfile_load($opts{'config'}); # "stripcomm" => qr/^\s+#.+$/  '^\\s+#'
# Example of getting a set of rsync task nodes as a group.
# if ($opts{'prof'}) { @$tasks = grep({ $_->{'lbl'} eq $opts{'prof'}; } @$tasks); } # filter correct task nodes
# Construct and run
my $rsyncer = DPUT::RSyncer->new($tasks, %opts);
my $res = $rsyncer->run();

#print("rsyncer.pl: ".Dumper($res));
#jsonfile_write('-', $res);
jsonfile_write('-', $rsyncer); # ->{'tasks'}
# timesummary($rsyncer);
$rsyncer->timesummary();
#errorsummary($rsyncer);
$rsyncer->errorsummary();
#print(Dumper($rsyncer->{'tasks'}));
# Runtime stats, time savings
sub DPUT::RSyncer::timesummary {
  my ($rsyncer) = @_;
  my $tasks = $rsyncer->{'tasks'};
  my $sumtime = 0;
  # Method taskssummedtime() ?
  map({ $sumtime += $_->{'time'}; } @$tasks);
  if (!$sumtime) { die("Failed to gather times !\n"); }
  my $tottime = $rsyncer->{'dt'}; # time();
  my $timerat = $tottime / $sumtime;
  print("Total time: $tottime,  Summed Individual times: $sumtime, Ratio: ". sprintf("%.3f", $timerat)."\n");
}
# Check Errors
sub DPUT::RSyncer::errorsummary {
  my ($rsyncer) = @_;
  my $totcnt = scalar(@{$rsyncer->{'tasks'}});
  # TODO: Store rv values, e.g. Errors, 23, 14
  # my @errs = ();
  my @errs = map({ $_->{'rv'} ? $_->{'rv'} : (); } @{$rsyncer->{'tasks'}});
  my $errcnt = scalar(@errs);
  if ($errcnt) { die("Some ($errcnt/$totcnt, Errors: ".join(',', @errs).") of the rsync ops failed !"); }
}


sub preptestfiles {
  my @created = make_path('/tmp/junk1', '/tmp/junk2');
  map({`touch /tmp/junk1/$_`} ('a','b','c'));
}
