#!/usr/bin/perl
use strict;
use warnings;
use lib('.');
use lib('..');
use DPUT::ToolProbe;
use Data::Dumper;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;
my $toolinfo = DPUT::ToolProbe::detect();
print(Dumper($toolinfo));


