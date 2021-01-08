package DPUT::CLRunner;
use strict;
use warnings;

use Getopt::Long;
use Data::Dumper;
our $VERSION = "0.0.1";

our $runneropts_g = {

};
# # DPUT::CLRunner - Design command line apps and interfaces with ease.
# 
# CLRunner bases all its functionality on Getopt::Long, but makes the usage declarative.
# It also strongly supports the modern convention of using sub-commands for cl commands
# (E.g. git clone, git checkout or apt-get install, apt-get purge).
#
# ## Usage
# 
#     my $optmeta = ["",""];
#     my $runneropts = {};
#     sub greet {}
#     sub delegate {}
#     $clrunner = DPUT::CLRunner->new($optmeta, $runneropts);
#     $clrunner->ops({'greet' => \&greet, '' => \&delegate});
# 
# 
# ## $clrunner = DPUT::CLRunner->new($optmeta, $runneropts)
# 
# Missing 'ops' means that subcommands are not supported by this utility and this instance.
# Options in %$runneropts:
# 
# - ops - Ops dispatch (callback) table
# - op- Single op callback (Mutually exclusive with ops, only one must be passed)
# - debug - Produce verbose output
# 
## NOT: Allow validate CB. "defop"
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
  # 'op' has been converted to 'ops' by now (see above)
  delete($clr->{'op'});
  bless($clr, $class);
  return($clr);
}
# ## $clrunner->ops($ops)
# 
# Explicit method to set operations (sub command dispatch table). Operations dispatch table is passed in $ops (hash ref),
# where each operation keyword / label (usually a impertaive / verb form word e.g. "search") maps to a function with call signature:
# 
#     $cb->($opts); # Options passed to run() method. %$opts should be a hash object that callback can handle.
# 
# Options:
# 
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
## Pass  a hash object of CL parameter descriptions and generate Help text.
## 
sub genhelp {
  my ($clr, $descriptions) = @_;
  
}
## Internal method to Extract operation from pre-validated ops (hashref)
sub operation {
  my ($clr, $ops) = @_; 
  # Is unique op ?
  
  my $op = isuniop($ops);
  if ($op) { return $op; }
  
}
# ## isuniop($ops)
# 
# Internal detector to see if there is only single unambiguous operation in dispatch table.
# Return the op name (key in dispatch table for the uique op, undef otherwise.
# Only for module internal use (Do not use from outside app).
sub isuniop {
  my ($ops) = @_;
  if (!$ops) { return undef; }
  if (ref($ops) ne 'HASH') { return undef; } # Test HASH. SHould Die !
  my @keys = keys(%$ops);
  if (scalar(@keys) == 1) { return $keys[0]; }
  return undef;
}

# ## $clrunner->run($opts)
# 
# Run application in ops mode (supporting CL sub-commands) or single-op mode (no subcommands).
# This mode will be auto-detected.
# Options:
# - 'exit' - Auto exit after dispatching operation.
#
# Return instance for method chaining.
sub run {
  my ($clr, $opts) = @_; # , $runneropts
  
  #if (!$ops) { die("No operations callback map available (pass: \$ops)"); }
  my $optmeta = $clr->{'optmeta'};
  # $argmeta = ($argmeta && ref($argmeta) eq 'ARRAY') ? $argmeta : [];
  $opts = $opts || {};
  # TODO: Make subcommand optional (for legacy apps) by ... (?)
  my $ops = $clr->{'ops'};
  my $op = isuniop($ops); # Allow single op mode (No CL subcommand)
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
  # Will merge / override
  GetOptions($opts, @$optmeta);
  # Only exec if ops exist, Otherwise plainly have options parsed by Getopt::Long
  if ($ops) {
    $opts->{'op'} = $op;
    # TODO: eval {}
    my $ret = $opcb->($opts); # Dispatch !
    # Invert return value here ?
    if ($clr->{'exit'}) { exit($ret); }
  } # Add subcommand as op (should not overlap with other options)
  return $clr;
}
# ## $cl_params_string = $clrunner->args($clioptions)
# 
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
