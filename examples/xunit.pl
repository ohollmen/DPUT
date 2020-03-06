#!/usr/bin/perl
# # XUnit Parser/Loader
# Produce a xUnit (jUnit) Test report based on xUnit *.xml testresult files in a directory.
# DPUT toolkit Reference implementation for parsing and loading test results.
# Supports ops (via subcommands):
# 
# - dumpsjon - Dump all parsed xUnit results as JSON
# - report - Generate a HTML report output using templating (example template provided to be customized)
# 
# # See Also:
# 
# - Template toolkit: http://www.template-toolkit.org/docs/manual/Directives.html

use FindBin qw($Bin $Script);

use Data::Dumper;
use Getopt::Long;
# In an applied codebase ...
#use lib ("$Bin/../NNN");
use lib ("..", ".");
use JSON;
use Template;
use DPUT;

use strict; use warnings;
$Data::Dumper::Sortkeys = 1;
my $ops = {dumpjson => \&dumpjson, report => \&report, help => \&usage,};
my $op = shift(@ARGV);
if (!$op) { usage("Missing subcommand\n"); }
if (!$ops->{$op}) { usage("'".$op ."' - No such subcommand !\n"); }
my %opts = ('path' => '.', 'title' => 'All Test Results',
  'ttkit' => 'Template', 'tmplfname' => './xunit.htreport.template');
GetOptions (\%opts, 'path=s', 'title=s', 'tmplfname=s', ); # 'ttkit=s'
# Common pre-ops
my $testpath = $ENV{'XUNIT_TEST_PATH'} || $opts{'path'};
my $tmpl = DPUT::file_read($opts{'tmplfname'});
my $allsuites = DPUT::testsuites_parse($testpath, 'debug' => 0);
my $rc = $ops->{$op}->();
exit(1);
# $ENV{'XUNIT_DEBUG'} ||
sub dumpjson {
  print(to_json($allsuites, {pretty => 1}));
  exit(1);
}
sub report {
  my $config = {}; # None needed to carry out basic templating
  my $p = {'all' => $allsuites, "title" => $opts{'title'}};
  my $out;
  # Dispatch templating based on config ?
  my $tm = Template->new($config);
  my $rc = $tm->process(\$tmpl, $p, \$out);
  # Had "1" at the end of output because by Template toolkit by default
  # Produces output to stdout, NOT return the content (like other toolkits)
  print($out);
}
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
- --tmplfname - Template filename (file must be compatible with current templating engine e.g. "Template")
EOT
  print(STDERR $usage);
  exit(1);
}
