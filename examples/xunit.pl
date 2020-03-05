#!/usr/bin/perl
# Produce a xUnit (jUnit) Test report based on xUnit *.xml files in a directory.
# Se Also: http://www.template-toolkit.org/docs/manual/Directives.html
use lib ("..", ".");

use DPUT;
use JSON;
use Data::Dumper;
use Template;
use strict; use warnings;
use Getopt::Long;
$Data::Dumper::Sortkeys;
my $ops = {dumpjson => 1, report => 1};
my $op = shift(@ARGV);
if (!$op) { usage("Missing subcommand\n"); }
if (!$ops->{$op}) { }
my %opts = ('path' => '.', 'title' => 'All Test Results');
GetOptions (\%opts, 'path=s', 'title=s');
# Common pre-ops
my $testpath = $ENV{'XUNIT_TEST_PATH'} || $opts{'path'};
my $tmpl = DPUT::file_read("./xunit.htreport.template");
my $allsuites = DPUT::testsuites_parse($testpath, 'debug' => 0);
# $ENV{'XUNIT_DEBUG'} ||
if ( ($op eq 'dumpjson')) {
  print(to_json($allsuites, {pretty => 1}));
  exit(1);
}
# Else ...
my $config = {}; # None needed to carry out basic templating
my $p = {'all' => $allsuites, "title" => $opts{'title'}};
my $tm = Template->new($config);
my $out;
my $rc = $tm->process(\$tmpl, $p, \$out);
# "1" at the end of output (!?)
print($out);

sub usage {
  my ($msg) = @_;
  if ($msg) { print(STDERR "$msg\n"); }
  my $usage = <<EOT;
Usage (w. subcommands): $0 dumpsjon|report ...
(Use one of subcommands: dumpjson, report)
Examples:
  # Produce a JSON dump of all xUnit files parsed from path ../tests to STDOUT
  $0 dumpjson --path ../tests
  # Same but store to file
  $0 dumpjson --path ../tests > ../tests/alltests.json
  # Produce HTML report from current path (.) to STDOUT
  $0 report
  # Explicit path, Store to file, title the report
  $0 report --path ../tests --title "test Results for Gadget-101" > ../tests/tests.report.json
Defaults:
- --path - Optional, Defaults to "." (current dir). Can be overriden by env. XUNIT_TEST_PATH.
- --title - Title for whole test suites run (w. multiple *.xml files)
EOT
  print(STDERR $usage);
  exit(1);
}
