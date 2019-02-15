#!/usr/bin/perl
# Test for CLRunner
# Run (e.g.): ./clrun.pl ngreet --name "Mrs. Jones" --verbose
use lib (".");
use lib ("..");
use strict;
use warnings;
use Data::Dumper;
use DPUT; # Just for Data::Dumper settings
use DPUT::CLRunner;
my $debug = 0;
my $ops = {
  'mgreet' => \&greet_morning,
  'dgreet' => \&greet_day,
  'ngreet' => \&greet_night,
};
my $opts = {'name' => 'Mr. Smith'}; # opts defaults
my $optmeta = ['name=s', 'verbose']; # Getopt::Long options meta
sub greet_morning {my ($opts) = @_; print("Good Morging, $opts->{'name'}\n");}
sub greet_day    {my ($opts) = @_; print("Good Day, $opts->{'name'}\n");}
sub greet_night {my ($opts) = @_; print("Good Night, $opts->{'name'}\n");}
my $clropts = {};
# Test 1 - Basic Use (w. multi-ops)
{
my $clr = DPUT::CLRunner->new($optmeta, $clropts)->ops($ops);
$debug && print(Dumper($clr)); # DEBUG Object internals
$clr->run($opts);
# Test 1.1 - Calls to args()
unshift(@ARGV, $opts->{'op'});
push(@ARGV, $clr->args($opts));
$debug && print(Dumper(\@ARGV));
print("Args Sample: ".$clr->args($opts, 'str' => 1)."\n");
}
# Test 2 - ops passed at construction
{
$clropts = {'ops' => $ops}; # Pass at construction
my $clr2 = DPUT::CLRunner->new($optmeta, $clropts)->run();
$debug && print(Dumper($clr2));
}
# Test 3 - Single command, no external ops, but single 'op'
@ARGV = ('--name', 'Johnny B. Goode', '--verbose');
{
$clropts = {'op' => \&greet_morning}; # Single op
my $clr3 = DPUT::CLRunner->new($optmeta, $clropts)->run();
$debug && print(Dumper($clr3));
}
# test 4 Same as before (no external ops) but single op give in 'ops'
$ops = {'foo1' => \&greet_morning};
@ARGV = ('--name', 'Johnny B. Goode 2', '--verbose');
{
$clropts = {'ops' => $ops};
my $clr = DPUT::CLRunner->new($optmeta, $clropts)->run();
$debug && print(Dumper($clr));
}
