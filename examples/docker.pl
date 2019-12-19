#!/usr/bin/perl
# Run Docker container image
# List docker images: docker image ls -a
# Example image names: ubuntu, hello-world
use lib("..", ".");
use DPUT;
use DPUT::DockerRunner;
use User::pwent; # See also: POSIX::cuserid()  Win32::LoginName().
use Data::Dumper;

use strict;
use warnings;
if (! DPUT::DockerRunner::userhasdocker("docker")) {die("User has no docker");}
my $dcfg = {
  "img" => "ubuntu",
  #"cmd" => "ls /usr",
  "cmd" => "grep Johnny /etc/passwd",
  "vols" => ["/tmp", "/usr"],
  "asuser" => "ohollmen",
  "mergeuser" => "oddball:x:1004:1004:Johnny Oddball,,,:/home/oddball:/bin/bash",
  #
  "debug" => 1,
};
#my $pw = getpwnam($ENV{'USER'}); # 13 elems !
#print(Dumper($pw)); exit(0);
#my @acct = DPUT::DockerRunner::getaccount($ENV{'USER'});
#print(Dumper(\@acct)); exit(0);
# Create Docker runner
#my $docker = DPUT::DockerRunner->new(%$dcfg);
#my $cmd = $docker->run('cmdstring' => 0);
#print("Generated command:\n$cmd\n");
#exit(0);
$dcfg->{"mergeuser"} = $ENV{'USER'};
$dcfg->{"cmd"} = "grep $ENV{'USER'} /etc/passwd";
my $docker = DPUT::DockerRunner->new(%$dcfg);
my $cmd = $docker->run('cmdstring' => 0);

