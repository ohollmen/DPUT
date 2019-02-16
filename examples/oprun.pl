#!/usr/bin/perl
use strict;
use warnings;
use lib(".");
use lib("..");

use DPUT::OpRun;
use Benchmark qw(:all) ;

my $ctx = {'n' => 'Ellie'}; # Common Context (for all ops)
my $ops = [
  sub {print("Good Morning $_[0]->{'n'}\n"); sleep(4); },
  sub {print("Good Day $_[0]->{'n'}\n"); sleep(8); },
  sub {print("Good Night $_[0]->{'n'}\n"); sleep(6); },
];
my $opts = {'debug' => 1, 'ccb' => sub { print("CCB:Done: $_[0] ($_[2])\n\n"); }};
my $orun = DPUT::OpRun->new($ctx, $ops, %$opts);

timethese(1, { 'SERIES' => sub {
  $orun->run_series();
}, 'PARALLEL' => sub {
  $orun->run_parallel()->runwait();
}});
# Context passed "late", not at construction
#$orun = DPUT::OpRun->new($ctx, undef, %$opts);
#$orun->run_series('ctx' => $ctx);
#$orun->run_parallel()->runwait('ctx' => $ctx);
