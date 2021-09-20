#!/usr/bin/perl
# DPUT Test app for selecting docker containers for a number of docker hosts.
# Pass hosts in comma separated list in env. var DOCKER_HOSTS
use DPUT;
use DPUT::DockerRunner;
use Data::Dumper;
use JSON;
use strict;
use warnings;

# use lib ($ENV{'HOME'}.'/src/DPUT');

my $hosts = [ split(/,/, $ENV{'DOCKER_HOSTS'}) ];
print("Query hosts: ".Dumper($hosts));
if (!$hosts || !@$hosts) { die("No hosts to query (Use DOCKER_HOSTS to set hosts)!\n"); }
# print("@INC: ".Dumper(\@INC));
# print("%INC: ".Dumper(\%INC));
my $time = time(); #
# my $delta = 604800; # 7d
my $delta = 12096000; # 7d * 20 (20w)
print("$0: The time is: $time, delta: $delta\n");
# Example callback for selecting containers.
my $cb = sub { return 1; };
my $cb2 = sub { my ($j) = @_; return ($time - $j->{'Created'}) > $delta ? 1 : 0 ; };
my %opts = ( 'apiver' => 'v1.24', 'port' => 4243, debug => 0, idonly => 1);
my $arr = DPUT::DockerRunner::containers_select($hosts, $cb2, %opts);
print("Query results (as JSON):\n".to_json($arr, { pretty => 1 }));
my $cbdel = sub { return 0; };
$opts{'debug'} = 1;
my $errcnt = DPUT::DockerRunner::containers_delete($arr, foo => $cbdel, %opts);
print("Delection errors: $errcnt\n");
