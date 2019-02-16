# Run Set of operations
package DPUT::OpRun;
#use DPUT::DataRun; # Do NOT Borrow runwait
use strict;
use warnings;
our $VERSION = '0.0.1';
# Create new Op Runner
# $ctx - Data Context 
sub new {
  my ($class, $ctx, $ops, %opts) = @_;
  if (ref($ops) ne 'ARRAY') { die("Ops not in array(ref)"); }
  # TODO: Consider if context is mandatory at this point or if it can be passed at run()
  if (!$ctx ) { die("No context provided"); } # || (ref($ctx))
  my $orun = {'ctx' => $ctx, 'ops' => $ops};
  for (keys(%opts)) { $orun->{$_} = $opts{$_}; }
  bless($orun, $class);
  return $orun;
}

# Run operations
sub run_series {
  my ($orun, %opts) = @_;
  my $ctx = $orun->{'ctx'} || $opts{'ctx'};
  my $ops = $orun->{'ops'};
  my $ccb = $orun->{'ccb'};
  my $res = {};
  if (!$ctx) { die("run(): Context not found for run(). Pass any valid value as context."); }
  foreach my $op (@$ops) {
    my $ret = $op->($ctx);
    $orun->{'debug'} && print("run_series(): Got ret: $ret\n");
    if ($ccb) { $ccb->($ctx, $res);  }
  }
  $orun->{'res'} = $res;
  return $orun;
}

sub run_parallel {
  my ($orun, %opts) = @_;
  my $ctx = $orun->{'ctx'} || $opts{'ctx'};
  my $ops = $orun->{'ops'};
  my $pididx = {};
  my $procs = 0;
  for my $op (@$ops) {
    my $pid = fork();
    if ( ! defined($pid)) { warn("Could not fork\n"); next; }
    if ($pid) { # Parent
      $orun->{'debug'} && print(STDERR "run_parallel: Forked: $pid\n"); $procs++;
      $pididx->{$pid} = 1; # What else to register ?
    }
    else { # Child
      my $ret = $op->($ctx); # Generic
      $orun->{'debug'} && print(STDERR "Child($$) returning\n");
      exit(0); # Must exit to prevent code from progressing
    }
  }
  $orun->{'numproc'} = $procs;
  $orun->{'pididx'} = $pididx;
  if ($orun->{'autowait'}) { return $orun->runwait(); }
  return $orun;
}

# NOTE: Redirecting Does not fully work (e.g. because of my $item = $drun->{'pididx'}->{$pid}; data item lookup
# sub runwait { return DPUT::DataRun($_[0]); }
sub runwait {
  my ($drun) = @_;
  my $numproc = $drun->{'numproc'};
  
  my $ctx = $drun->{'ctx'}; # SPECIFIC
  
  my $res = {}; # Collective result. Allow to come from outside
  my $ccb = $drun->{'ccb'}; # Completion and Collection Callback
  for (1 .. $numproc) {
    my $pid = wait();
    if ($pid == -1) { print(STDERR "PID: -1\n"); last; }
    $drun->{'debug'} && print(STDERR "Parent: $pid exited\n");
    # Resolve original data item
    #my $item = $drun->{'pididx'}->{$pid}; # Lookup original data
    # Check for completion callback
    # - $item - original item from array
    # - $res - result object to fill out for collecting individual results
    if ($ccb) { $ccb->($ctx, $res, $pid); } # SPECIFIC ($ctx)
  }
  $drun->{'res'} = $res;
  #return $numproc; # Still in object after this call
  #return $drun;
  return $res;
}
