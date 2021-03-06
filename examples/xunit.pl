#!/usr/bin/perl
# # XUnit Parser/Loader
# 
# Produce a xUnit (jUnit) Test report based on xUnit *.xml testresult files in a directory.
# DPUT toolkit Reference implementation for parsing and loading test results.
# Supports ops (via subcommands):
# 
# - dumpsjon - Dump all parsed xUnit results as JSON
# - report - Generate a HTML report output using templating (example template provided to be customized)
# - help - Output Usage help
# 
# # See Also:
# 
# - Template Toolkit: http://www.template-toolkit.org/docs/manual/Directives.html

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
my $ops = {dumpjson => \&dumpjson, report => \&report, help => \&usage, passfail => \&pf_counts};
my $op = shift(@ARGV);
if (!$op) { usage("Missing subcommand\n"); }
if (!$ops->{$op}) { usage("'".$op ."' - No such subcommand !\n"); }
my @optmeta = ('path=s', 'title=s', 'tmplfname=s', 'tree', 'debug', 'tcdata');
my %opts = (
  'path' => '.', 'title' => 'All Test Results',
  'ttkit' => 'Template', 'tmplfname' => './xunit.htreport.template', 'tree' => 0, 'debug' => 0, 'tcdata' => undef);
GetOptions (\%opts, @optmeta); # 'ttkit=s'
# Common pre-ops
my $testpath = $ENV{'XUNIT_TEST_PATH'} || $opts{'path'};
my $tmpl = DPUT::file_read($opts{'tmplfname'});
# 
my $allsuites = DPUT::testsuites_parse($testpath, 'debug' => $opts{'debug'}, 'tree' => $opts{'tree'});
if (!$allsuites) { die("Could not parse xUnit test files !"); }
my $cnt_tot = DPUT::testsuites_test_cnt($allsuites);
my $rc = $ops->{$op}->();
exit(0);
# $ENV{'XUNIT_DEBUG'} ||
sub dumpjson {
  print(to_json($allsuites, {pretty => 1}));
  exit(1);
}
sub report {
  my $config = {}; # Template toolkit config Params - None needed to carry out basic templating
  my $p = {'all' => $allsuites, "title" => $opts{'title'}, 'cnt_tot' => $cnt_tot}; # Template params
  my $testdata = {
    "labels" => [1,2,3,4,5], datasets => [
      {label => "Pass", data => [0, 2, 0, 5, 4], borderColor => "#008000"},
      {label => "Fail", data => [5, 3, 5, 0, 1], borderColor => "#ED3417"},
    ]
  };
  if ($opts{'tcdata'}) { $p->{'cdata'} = to_json($testdata, {pretty => 1}); }
  # Dispatch templating based on config ?
  my $out;
  my $tm = Template->new($config);
  my $ok = $tm->process(\$tmpl, $p, \$out);
  if (!$ok) { die("failed to run templating !"); }
  # Had "1" at the end of output because by Template toolkit by default
  # Produces output to stdout, NOT return the content (like other toolkits)
  print($out);
}
# Compute pass/fail counts
sub pf_counts {
  my $cnt = DPUT::testsuites_test_cnt($allsuites);
  print("$cnt tests\n");
  my $pfstat = DPUT::testsuites_pass_fail_cnt($allsuites);
  print(to_json($pfstat, {pretty => 1}));
}
sub usage {
  my ($msg) = @_;
  if ($msg) { print(STDERR "$msg\n"); }
  my @ops = keys(%$ops);
  my $opsstr = join("|", @ops);
  my $usage = <<EOT;
Usage (w. subcommands): $0 $opsstr ...
(Use one of subcommands: $opsstr)
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
