# # Retrier - Try operation multiple times in failsafe manner
#
# Most typical use case for retrying would likely be an operation over the network
# (e.g. HTTP, SSH, Git, FTP, ...).
# Even reliable and well-maintained environment occasionally have brief glitches that
# prevent interaction with a single try.
#
# ## Signaling results from single try callback
#
# The return value from the callback of `...->run($cb)` is - for most
# flexibility - tested with a callback. The callback name 'badret' refers to
# "bad return value", encountering of which triggers a retry.
# While this initially seems inconvenient,the module provides 2 internal functions
# to handle 90%-95% of cases:

# - badret_perl - Interprets "Perl style" $ok return value as success
# - badret_cli - Interprets success with a shell command line convention of
#   zero value indicating success and non-zero return value indicating error.
#   This allows
# 
# the default return value interpretation is "Perl style" and you do not have
# to specify a 'badret' callback in your constructor.
# In case you have mixed convention cases in your app, the choices of coping
# with this are:
# 
#     # Use local to set temporary value for the duration of current curly-scope
#     # (sub, if- or else block, ...) which will be "undone" and reverted
#     # back to default after exiting curly-scope.
#     local $DPUT::Retrier::badret = \&Retrier::badret_cli;
#     # You can also do this for your completely custom badret - interpreter:
#     local $DPUT::Retrier::badret = \&badret_myown;
# 
# Passing badret value in construction in 'badret' option
#
#     my $retrier = new DPUT::Retrier('cnt' => 5, 'badret' => \&DPUT::Retrier::badret_cli);
#
# Demonstration of a custom badret -interpretation callback (and why callback
# style interpretation may become handy):
# 
#     sub badret_myown {
#       my ($ret) = @_;
#       # Up to value 3 return values are warnings and okay
#       if ($ret > 3) { return 1; } # Bad (>3)
#       return 0; # Good/Okay (<= 3)
#     }
# 
# This flexibility on iterpreting return values will hopefully allow running *any* existing
# sub / function in a retried manner. With custom function you can also test undef values,
# array,hash and code references, etc.
#
# ## Signaling results from run() (all tries)
#
# When `$rt->run()` returns with a value, it indicates the overall success
# of operation independent of whether operation needed to be tried many times
# or the first try succeeded.
# The chosen return value is Perl style $ok - true for success indication (in
# contrast to C-style $err error indication).
#
# ## Notes on systems you interact with
#
# To use this module effectively, you have to be somewhat familiar with
# the error patterns of the (many times remote, over-the-network) systems
# that you interact with. E.g 3 retries with a 3s delay on one relatively
# reliable, but occasionally glitchy system (with a very small glitch
# timewindow) might be relevant, where as with a system where "bastard operator
# from hell" reboots the system a few times a day to entertain himself may
# require 6 minute (360s.) delay to allow the OS and services to come up.
# Retrier provides no silver bullet or substitute for this knowledge.
#
# ## TODO
#
# Consider millisecond resolution on delay. This would require pulling in
# a CORE module dependency Time::HiRes. Would need to introduce 'unit'
# and separation between constructor config params vs. internal value
# held (e.g. always in 'ms'). At this point ms resolution is deemed overkill
# and not worth the dependency.
# DPUT::Retrier
package DPUT::Retrier;
use strict;
use warnings;
#use Time::HiRes ('usleep');
our $VERSION = '0.0.1';
## sub trythis {
##    # ...
##    return 1;
## }
## new Retrier('cnt' => 2)->run(sub { trythis() } );
## Change glocal settings by $Retrier::trycnt = ...
## ... to avoid explicit settings with a re-trier instance.
## 
our $trycnt = 3;
our $delay = 10;
our $debug = 0;
our $badret = \&badret_perl;
sub badret_cli {  return $_[0] ? 1 : 0;}
sub badret_perl {  return $_[0] ? 0 : 1; }
# ## DPUT::Retrier->new(%opts)
# Construct a Retrier.
# Settings:
# 
# - cnt - Number of times to retry (default: 3)
# - delay - delay between the tries (seconds, default: 10)
# - delays - an array of arbitrary (non-evenly spaced) delays to waits instead of constat interval time 'delay'.
#           This is mutaually exclusive with delay ('delays' overrides 'delay')
# - delaycb - Function to generate delay value for the Nth wait time (N=0..N-1). Function must accept a 0-based
#           N-value for the next wait (i.e. for first delay N=0). Mutually exclusive with 'delay' and 'delays' (This
#           overrides either of earlier)
# - args - Arguments (in array-ref) to pass to function to be run (Optional, no default).
# - debug - A debug flag / level for enabling module internal messages
#   (currently treated as flag with now distinct levels, default: 0)
# - badret - A custom callback defining whether return value of main retry callback is a bad return value.
# - raw - A low level power-user flag to return the actual "raw" value of the retry callback (e.g. http result handle,
#   DB connection handle, FTP connection or some other reference, which are all "true" / valid $ok values).
#   NOTE: This is only safe when internally used badret callback does not "invert" the value and both retry callback and badret
#   callback are geared around "$ok" (perl-style, not shell style) return convention.
# 
# Return instance reference.
# The retry options can be passed either with keyword -style convention
# or as a perl hash(ref) as argument:
# 
#     new DPUT::Retrier('cnt' => 5);
#     new DPUT::Retrier({'cnt' => 5});
#
sub new {
  #my ($class, %opts) = @_;
  my ($class, %opts);
  # Allow $opts also as HASH ref (2nd param)
  if ((scalar(@_) == 2) && (ref($_[1]) eq 'HASH')) {
    %opts = %{$_[1]}; $class = $_[0];
  }
  else { ($class, %opts) = @_; }
  my $rt = {
    'cnt'    => int($opts{'cnt'}) || $trycnt,
    'delay'  => $opts{'delay'}  || $delay,
    'debug'  => $opts{'debug'}  || $debug,
    'args'   => $opts{'args'},
    'badret' => $opts{'badret'} || \&badret_perl, # TODO: $badret, to remove order sensitiveness
    'raw'    => $opts{'raw'},
    'tout'   => $opts{'tout'},
    #TODO: 'throw'
  };
  # Allow varying delays for more dynamic setting.
  # NOTE: Setting "delays" should cancel / override "delay"
  if (ref($opts{'delays'}) eq 'ARRAY') {
    my $delays = $opts{'delays'};
    # Test that number of delays give is sufficient
    # Excess number of items does not matter
    if (scalar(@$delays) < ($rt->{'cnt'})) { die("Not enough dynamic delay values (Make sure num-delays == try-cnt)"); }
    # Discard 'delay' from causing ambiguity (is this wise?)
    delete($rt->{'delay'});
    $rt->{'delays'} = $delays;
  }
  # Test the tester cb is *really* CODE
  if (ref($rt->{'badret'}) ne 'CODE') { die("Not 'Bad return value' -tester given"); }
  if ($rt->{'args'} && (ref($rt->{'args'}) ne 'ARRAY')) {die("'args' must be passed in ARRAY (ref)");}
  if ($rt->{'debug'} > 1) {
    print(STDERR "Bad return CB:s: perl: ".\&DPUT::Retrier::badret_perl.
      ", cli: ".\&DPUT::Retrier::badret_cli.", Curr: ".$rt->{'badret'}."\n");
  }
  bless($rt, $class);
  return($rt);
}

# ## $retrier->run($callback)
# Run the operational callback ('cnt') number of times to successfully execute it.
# Callback is passed as first argument.
# See Retrier constructor for retry params ('cnt','delay',...)
# Return (perl style) true value for success, false for failure.
# Example:
# 
#     # Store news from flaky news site.
#     use LWP::Simple;
#     use JSON;
#     my $news; # Store news here.
#     # Use the perl-style $ok return value
#     sub get_news {
#       my $cont = get("http://news.flaky.com/api/v3/news?today=1");
#       if ($cont !~ /^\{/) { return 0; } # JSON curly not found !
#       eval { $news = from_json($cont); }
#       if ($@) { return 0; } # Still not good, JSON error
#       return 1; # Success, Perl style $ok value
#     }
#     my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3)->run(\&get_news);
#     # Same parametrized (with 'args'):
#     sub get_news {
#       my ($jsonurl) = @_;
#       my $cont = get($jsonurl);
#       ...
#     my $url = "http://news.flaky.com/api/v3/news?today=1";
#     my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3, 'args' => [$url])->run(\&get_news);
#     # Or you can just do (no 'args' needed).
#     my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3)->run(sub { return get_news($url); });
# 
# Store good app-wide defaults in DPUT::Retrier class vars to make construction super brief.
# 
#     $DPUT::Retrier::trycnt = 3;
#     $DPUT::Retrier::delay = 10;
#     # Rely on module-global defaults, instead of passing 'cnt' and 'delay'.
#     my $ok = DPUT::Retrier->new()->run(sub { get($url); });
#
# This is a valid approach when settings are universal to whole app (no variance between the calls).
#
# ### Using non-linear delay times
# If you are not happy using evenly spaced intervals when trying, DPUT::Retrier allows passing the delay
# time as array in parameter 'delays" (note trailing 's'). The values can be e.g. generated by caller:
# 
#     my @delays = map({ return $_ ^ 2; } 1..5);
#     my $ok = DPUT::Retrier->new('delays' => \@delays)->run(sub { get($url); });
# 
# TODO: Allow passing max time to try.
# TODO: Allow args for **this** function (as an alternative to passing args to construction (a mild design flaw)
sub run {
  my ($rt, $cb) = @_; # $args ?
  my $cnt   = $rt->{'cnt'} || $trycnt;
  my $br    = $rt->{'badret'} || $badret;
  my $delay = $rt->{'delay'} || $delay;
  my $delays= $rt->{'delays'} || undef; # NEW: Dynamic delay
  my $raw   = $rt->{'raw'}; # Return "raw" $ret value instead of plain 1;
  my $tout   = $rt->{'tout'}; # Timeout. Should we set default ?
  # TODO: Allow args to run !
  my $args  = (ref($rt->{'args'}) eq 'ARRAY') ? $rt->{'args'} : [];
  my $i;
  my $ret; # "raw" return value
  
  # NOTE: Theoretically $br could be a string dispatchable / runnable as function symbol.
  # However we require it to be a hard code reference for now.
  if (ref($br) ne 'CODE') { die("badret callback not set to code-ref !\n"); }
  if ($tout) { setalarm($tout); }
  for ($i = 0;$i < $cnt; $i++) {
    eval {
      #setalarm($tout);
      $ret = $cb->(@$args);
    };
    if ($@) { print(STDERR "run(): Retrier Exception: $@\n"); alarm(0); return 0; }
    $rt->{'debug'} && print(STDERR "run(): Scored ret=$ret\n");
    if ($br->($ret)) {
      $rt->{'debug'} && print(STDERR "run(): $ret Deemed Bad by $br\n");
      my $usedelay = $delays ? $delays->[$i]: $delay;
      if ($rt->{'delaycb'} && (ref($rt->{'delaycb'}) eq 'CODE')) { $usedelay = $rt->{'delaycb'}->($i); }
      $rt->{'debug'} && print(STDERR "run(): Wait $usedelay s.\n");
      sleep($usedelay);
      next;
    } # Bad
    #print("$ret Deemed good by $br\n");
    # TODO: Allow returning / forwarding "raw" value from callback, but only 
    else { alarm(0); return $raw ? $ret : 1; } # $ret (OLD: 1)
    
  }
  # Test last $ret
  # Here: Test Bad in terms of perl ($ok) print("Bad return($ret)");
  alarm(0);
  if ($br->($ret)) {  return 0; }
  return $raw ? $ret : 1; # $ret (OLD: 1)
  sub setalarm {
    my ($tout) = @_;
    print(STDERR "Setting Retrier timeout ALRM\n");
    #local
    $SIG{'ALRM'} = sub { print(STDERR "ALRM Problems ... !"); alarm(0); die("Retry Timed Out ($tout s.)!\n"); };
    alarm($tout);
  }
  
}

