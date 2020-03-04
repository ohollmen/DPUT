#!/usr/bin/perl
# 
use lib ("..", ".");

use DPUT;
use JSON;
use Data::Dumper;
use Template;
use strict; use warnings;
#my $tmpl = <<EOT;
#EOT
my $tmpl = DPUT::file_read("./xunit.report.template");
my $allsuites = DPUT::testsuites_parse(".", 'debug' => 1);
DEBUG: print(to_json($allsuites, {pretty => 1}));
my $config = {}; # None needed to carry out basic templating
my $p = {'all' => $allsuites, "title" => "Results"};
my $tm = Template->new($config);
my $out = $tm->process(\$tmpl, $p);
print($out);
