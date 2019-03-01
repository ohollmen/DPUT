# # Retrier - Try operation multiple times in failsafe manner
# Most typical use case for retrying would likely be an operation over the network
# (e.g. HTTP, SSH, Git, FTP, ...).
# Even reliable and well-maintained environment occasionally have brief glitches that
# prevent interaction with a single try.
#
# ## Signaling results from single try callback
#
# The return value from the callback of `...->run($cb)` is - for most
# flexibility - tested with a callback. While this initially seems inconvenient,
# the module provides 2 internal functions to handle 90%-95% of cases:

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
#     local $Retrier::badret = $Retrier::badret_cli;
#     # You can also do this for your completely custom badret - interpreter:
#     local $Retrier::badret = $Retrier::badret_myown;
# 
# Demonstration of a custom badret -interpretation callback (and why callback
# style interpretation may become handy):
# 
#     sub badret_myown {
#       my ($ret) = @_;
#       # Up to value 3 return values are warnings and okay
#       if ($ret > 3) { return 1; } # Bad
#       return 0; # Good (<= 3)
#     }
# 
# This flexibility on iterpreting return values will hopefully allow running *any* existing
# sub / function in a retried manner.
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
## 
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
# - cnt - Number of times to retry (default: 3)
# - delay - delay between the tries (seconds, default: 10)
# - args - Arguments (in array-ref) to pass to function to be run (Optional, no default).
# - debug - A debug flag / level for enabling module internal messages
#   (currently treated as flag with now distinct levels, default: 0)
# 
# Return instance reference.
# The retry options can be passed either with keyword -style convention
# or as a perl hash(ref) as argument:
# 
#     new Retrier('cnt' => 5);
#     new Retrier({'cnt' => 5});
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
    'badret' => $opts{'badret'} || \&badret_perl,
    #TODO: 'throw'
  };
  # Test the tester cb is *really* CODE
  if (ref($rt->{'badret'}) ne 'CODE') { die("Not 'Bad return value' -tester given"); }
  if ($rt->{'args'} && (ref($rt->{'args'}) ne 'ARRAY')) {die("'args' must be passed in ARRAY (ref)");}
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
#     my $ok = Retrier->new('cnt' => 2, 'delay' => 3)->run(\&get_news);
#     # Same parametrized (with 'args'):
#     sub get_news {
#       my ($jsonurl) = @_;
#       my $cont = get($jsonurl);
#       ...
#     my $url = "http://news.flaky.com/api/v3/news?today=1";
#     my $ok = Retrier->new('cnt' => 2, 'delay' => 3, 'args' => [$url])->run(\&get_news);
#     # Or you can just do
#     my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3)->run(sub { return get_news($url); });
# 
# Store good app-wide defaults in Retrier class vars to make construction super brief.
# 
#     $DPUT::Retrier::trycnt = 3;
#     $DPUT::Retrier::delay = 10;
#     my $ok = DPUT::Retrier->new()->run(sub { get($url); });
# TODO: Allow passing max time to try.
sub run {
  my ($rt, $cb) = @_;
  my $cnt   = $rt->{'cnt'} || $trycnt;
  my $br    = $rt->{'badret'} || $badret;
  my $delay = $rt->{'delay'} || $delay;
  my $args  = (ref($rt->{'args'}) eq 'ARRAY') ? $rt->{'args'} : [];
  my $i;
  my $ret;
  for ($i = 0;$i < $cnt; $i++) {
    eval { $ret = $cb->(@$args); };
    if ($@) { print(STDERR "run(): Retrier Exception "); return 0; }
    $rt->{'debug'} && print("run(): Scored ret=$ret\n");
    if ($br->($ret)) {
      $rt->{'debug'} && print("run(): $ret Deemed Bad by $br\n");
      sleep($delay); next; } # Bad
    #print("$ret Deemed good by $br\n");
    else {  return 1; }
    
  }
  # Test last $ret
  # Here: Test Bad in terms of perl ($ok) print("Bad return($ret)");
  if ($br->($ret)) {  return 0; }
  return 1;
}
