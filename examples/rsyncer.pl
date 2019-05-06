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
use File::Path qw(make_path remove_tree);
use Getopt::Long;
use Data::Dumper;

# Prepare local rsync test files
preptestfiles();
my @optsmeta = ('runtype=s','debug','prof=s', 'config=s');
# print("loaded DPUT::RSyncer $DPUT::RSyncer::VERSION\n\n");


# Note: We are not locked onto JSON (config) files, but we could load
# config from a file with perl array-ref by:
# my $tasks = require("./copies.pl");
my %opts = ('runtype' => 'parallel', 'debug' => 1, 'config' => './copies.json'); # 'seq' => 1, 'runtype' => 'series' / 'parallel'
GetOptions(\%opts, @optsmeta);
# Load Rsync config
#OLD: my $copyconfig = $ARGV[0] || "./copies.json";
if (!-f $opts{'config'}) { die("Rsync Config file '$opts{'config'}' does not exist"); }
my $tasks = jsonfile_load($opts{'config'}, "stripcomm" => qr/^\s+#.+$/); # %opts '^\\s+#'
# Example of getting a set of rsync task nodes as a group.
if ($opts{'prof'}) { @$tasks = grep({ $_->{'lbl'} eq $opts{'prof'}; } @$tasks); } # filter correct task nodes
# Construct and run
my $rsyncer = DPUT::RSyncer->new($tasks, %opts);
my $res = $rsyncer->run();
#print("rsyncer.pl: ".Dumper($res));
jsonfile_write('-', $res);
jsonfile_write('-', $rsyncer->{'tasks'});
#print(Dumper($rsyncer->{'tasks'}));

sub preptestfiles {
  my @created = make_path('/tmp/junk1', '/tmp/junk2');
  map({`touch /tmp/junk1/$_`} ('a','b','c'));
}
