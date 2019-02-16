package DPUT::CLRunner;
use strict;
use warnings;

use Getopt::Long;
use Data::Dumper;
our $VERSION = "0.0.1";

our $runneropts_g = {

};
# Missing 'ops' means that subcommands are not supported by this utility and this instance.
# NOT: Allow validate CB. "defop"
sub new {
  my ($class, $optmeta, $runneropts) = @_;
  # TODO: Allow leaving empty - meaning no subcommands or assigning later (by ops())
  if (!$optmeta || (ref($optmeta) ne 'ARRAY')) { die("Must get Getopt::Long option meta in Array-ref, e.g. [\"type=s\", \"debug=i\"]!"); }
  if ($runneropts->{'ops'}) {}
  my $clr = {'optmeta' => $optmeta};
  for ('ops','op', 'debug') { $clr->{$_} = $runneropts->{$_}; }
  if ($clr->{'op'} && $clr->{'ops'}) { die("Cannot have single op and multiple ops simultaneously (ambiguity error) !"); }
  # Analyze /convert single 'op'
  if ($clr->{'op'}) {
    if (ref($clr->{'op'}) ne 'CODE') { die("Single-Op is not given as CODE(ref)");}
    $clr->{'ops'}->{'op1'} = $clr->{'op'};
  }
  delete($clr->{'op'});
  bless($clr, $class);
  return($clr);
}
# Explicit method to set operations (sub command dispatch table).
# Options:
# - 'merge' - When set to true value, the new $ops will be merged with possible existing values (in overriding manner)
sub ops {
  my ($clr, $ops, %opts) = @_;
  if ($ops) {
    if (ref($ops) ne 'HASH') { die("ops must be as HASH(ref) (op label mapped to sub(ref))!");}
    # Makes sure
    $clr->{'ops'} = $clr->{'ops'} || {};
    if ($opts{'merge'}) { map({ $clr->{'ops'}->{$_} = $ops->{$_}; } keys(%$ops)); }
    else { $clr->{'ops'} = $ops; } # Override completely
  }
  #$clr->{'ops'};
  return $clr;
}
sub optmeta {
  my ($clr) = @_;
}

# Internal method to Extract operation from pre-validated ops (hashref)
sub operation {
  my ($clr, $ops) = @_; 
  # Is unique op ?
  
  my $op = isuniop($ops);
  if ($op) { return $op; }
  
}
# Internal detector if 
sub isuniop {
  my ($ops) = @_;
  if (!$ops) { return undef; }
  if (ref($ops) ne 'HASH') { return undef; } # Test HASH. Die !
  my @keys = keys(%$ops);
  if (scalar(@keys) == 1) { return $keys[0]; }
  return undef;
}
  
# Run application in ops mode or single-op mode.
# 
sub run {
  my ($clr, $opts) = @_; # , $runneropts
  
  #if (!$ops) { die("No operations callback map available (pass: \$ops)"); }
  my $optmeta = $clr->{'optmeta'};
  # $argmeta = ($argmeta && ref($argmeta) eq 'ARRAY') ? $argmeta : [];
  $opts = $opts || {};
  # TODO: Make subcommand optional (for legacy apps) by ... (?)
  my $ops = $clr->{'ops'};
  my $op = isuniop($ops); # Allow single op mode
  if (!$op) {$op = $ops ? shift(@ARGV) : undef; } # Extract subcommand
  if (!$op) { die("run(): Nothing to run() (No op resolved from $ops)");}
  my $opcb;
  if ($ops) {
    # Lookup operation from dispatch table
    $opcb = $ops->{$op};
    if ($clr->{'debug'}) { print(STDERR "Got op: $op ... mapping to $opcb\n"); }
    # Validate op. TODO: Allow custom error messaging.
    if (!$opcb) { die("No CL op '$op'\nTry one of:\n".join("\n", map({" - $_";} keys(%$ops))));}
  }
  ################ Run ################
  GetOptions($opts, @$optmeta);
  if ($ops) {
    $opts->{'op'} = $op;
    # TODO: eval {}
    my $ret = $opcb->($opts); # Dispatch !
    # Invert return value here ?
    if ($clr->{'exit'}) { exit($ret); }
  } # Add subcommand as op (should not overlap with other options)
  return $clr;
}

# Turn opts (back) to CL argumnents, either an Array or string-serialized (quoted, escaped) form.
# Uses CLRunner 'optmeta' as guide for the serialization.
# Return array (default) or command line ready arguments string if 'str' option is passed.
sub args {
  my ($clr, $opts, %o) = @_;
  my $optmeta = $clr->{'optmeta'};
  my @args = ();
  #my @args_str = ();
  #my %types = ();
  my @toescape = (); # Record escape locs.
  for my $om (@$optmeta) {
    my ($k, $t) = split(/=/, $om, 2);
    $t = $t || ''; # 'b' ?
    my $clopt = "--".$k;
    
    push(@args, $clopt); # push(@args_str, $clopt);
    if (!$t) { if (!$opts->{$k}) { pop(@args); } } # Boolean - nothing left to do, except cancel opt if false
    elsif ($t eq 'i') { push(@args, "$opts->{$k}"); }
    elsif ($t eq 's') { push(@args, "$opts->{$k}"); push(@toescape, $#args); }
    #$types{"--".$k} = $t;
  }
  if ($o{'str'}) {
    map({ $args[$_] = "'$args[$_]'"; } @toescape);
    print(Dumper(@args));
    return join(' ', @args);
  }
  return(@args);
}

## The (OLD) quick classmethod way of running an CL app
sub clrunner {
  my ($ops, $argmeta, $opts, $runneropts) = @_;
  if (!$ops) { die("No operations callback map available (pass: \$ops)"); }
  $argmeta = ($argmeta && ref($argmeta) eq 'ARRAY') ? $argmeta : [];
  $opts = $opts || {};
  my $op = shift(@ARGV);
  
  my $opcb = $ops->{$op};
  if ($runneropts->{'debug'}) { print(STDERR "Got op: $op ... mapping to $opcb\n"); }
  if (!$opcb) { die("No CL op '$op'\nTry one of:\n".join("\n", map({" - $_";} keys(%$ops))));}
  GetOptions($opts, @$argmeta);
  $opts->{'op'} = $op;
  # TODO: eval {}
  $opcb->($opts); # Dispatch !
}
