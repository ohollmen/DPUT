#!/usr/bin/perl
# Produce a xUnit (jUnit) Test report based on xUnit *.xml files in a directory.
# Se Also: http://www.template-toolkit.org/docs/manual/Directives.html
use lib ("..", ".");

use DPUT;
use JSON;
use Data::Dumper;
use Template;
use strict; use warnings;
$Data::Dumper::Sortkeys;

my $testpath = $ENV{'XUNIT_TEST_PATH'} || '.';
my $tmpl = DPUT::file_read("./xunit.htreport.template");
my $allsuites = DPUT::testsuites_parse($testpath, 'debug' => 0);
$ENV{'XUNIT_DEBUG'} && print(to_json($allsuites, {pretty => 1})) && exit(1);
my $config = {}; # None needed to carry out basic templating
my $p = {'all' => $allsuites, "title" => "Results"};
my $tm = Template->new($config);
my $out = $tm->process(\$tmpl, $p);
# "1" at the end of output (!?)
print($out);
