
# DataRun - Process datasets in series or in parallell (in a child process)
package DPUT::DataRun;

our $VERSION = '0.0.1';
# ## Construct a DataRun Data processor object.
# Pass a mandatory callback $cb to run on each item passed later to one of:
# - run_series($dataset)
# - run_parallel($dataset)
# - run_forked_single($data_item)
# Options in $opts:
# - 'ccb' - Completion callback (for single item of $dataset array)
# - 'autowait' - Flag to wait for children to complete automatically inside
#
# ### Notes on 'autowait'
#
# If 'autowait' is set, The call to one of the processing launching functions above
# causes the call to it to block, and you may be wasting time idling (i.e. just waiting) in the main
# process. If you have a pretty good idea of the processing time of children and what you could do
# in the main process during that time, make an explict call to runwait() instead of using 'autpowait'.
# Same wasteage happens when you call `run_parallel($dataset)->runwait()` in a method-chained manner.
# Examples higlighting this situation -
# Blocking wait (with main process idling):
#
#     my $dropts = {}; # NO 'autowait'
#     DPUT::DataRun->new($dropts)->run_parallel($dataset)->runwait()
#     # ... is effectively same as ...
#     my $dropts = {'autowait' => 1};
#     PUT::DataRun->new($dropts)->run_parallel($dataset);
#
# Both of these block while waiting for children to process.
# To really perform maximum multitasking and utilize the time in main process, do:
#
#     my $dropts = {}; # NO 'autowait'
#     $drun = DPUT::DataRun->new()->run_parallel($dataset);
#     # Optimally this should take approx same time as parallel processing by children
#     do_someting_else_while_waiting_children($somedata); # Utilize the waiting time !
#     $drun->runwait();
sub new {
  my ($class, $cb, $opts) = @_; # splice(@_, 0, 2);
  $opts = $opts || {};
  my $drun = {'cb' => $cb, 'ccp' => $opts->{'ccp'}, 'retok' => 0};
  map({ $drun->{$_} = $opts->{$_}} keys(%$opts));
  bless($drun, $class);
  return $drun;
}

# Run processing in series within main process.
# This is a trivial (internally simple) method and **not** the reason to use DPUT::DataRun.
# It merely exists to **compare** the savings caused by running data processing in parallel in
# child processes. To do this rather easy comparison, do:
#
#    $drun = DPUT::DataRun->new($dropts);
#    # Time this
#    my $res = $drun->run_series($dataset);
#    # and time this
#    my $res = $drun->run_parallel($dataset)->runwait();
#
# There is always a small overhead of launching child processes, so for a small number of items **and** short processing
# time there may be no time benefit spawning the child processes.
sub run_series {
  my ($drun, $tars) = @_;
  my $cb = $drun->{'cb'};
  my $ccb = $drun->{'ccb'};
  my $res = {};
  # NOTE: If $ccb uses 
  for my $reltar (@$tars) {
    #tarfile_process($reltar);
    my $ret = $cb->($reltar);
    $ccb && $ccb->($reltar, $res);
  }
  $drun->{'res'} = $res;
  return $drun;
}
# Return result of run which is stored in instance.
# Delete current result from instance (to reduce "state ambiguity" and for for next run via same instance).
sub res { my $res = $_[0]->{'res'};delete($_[0]->{'res'}); return $res; }

# Reset state information related to particular run via instance.
# Reset internap properties are: 'res', 'numproc', 'pididx'.
sub reset {
  my ($drun) = @_;
  my $stprops = ['res', 'numproc', 'pididx'];
  map({delete($drun->{$_});} @$stprops);
}
# Process Data items passed in with callback registered in the instance.
# Typical run setting:
#
#     my $dropts = {'ccb' => sub {}}; # Data run constructor options
#     my $res = new DataRun(sub {  }, $dropts)->run_parallel($dataset)->runwait();
#
# Return normally an object itself for method chaining (e.g. calling runwait()).
# In case of 'autowait' setting in instance, the runwait() is automatically called and
# return value is the result from runwait() (See runwait()).
#
# ## Notes on internals
#
# run_parallel() internally keeps track of processes vs. the data item processed.
# On the high level this enables producing collective results by completion callback 'ccb'
# and retrieveing the collective results by res() method.
sub run_parallel {
  my ($drun, $tars) = @_;
  my $cb = $drun->{'cb'};
  # Maintain a mapping from child PID to data
  my $pididx = {};
  my $procs = $drun->{'numproc'} = 0;
  for my $reltar (@$tars) {
    my $pid = fork();
    if ( ! defined($pid)) { warn("Could not fork\n"); next; }
    if ($pid) { # Parent
      $drun->{'debug'} && print(STDERR "Forked: $pid\n"); $procs++;
      $pididx->{$pid} = $reltar;
    }
    else { # Child
      my $ret = $cb->($reltar); # Generic
      $drun->{'debug'} && print(STDERR "Child($$) returning\n");
      exit(0); # Must exit to prevent code from progressing
    }
  }
  $drun->{'numproc'} = $procs;
  $drun->{'pididx'} = $pididx; # Mapping from PID to data
  if ($drun->{'autowait'}) { return $drun->runwait(); } # Returns $res
  return $drun;
  
}
# Wait for the child processes spawned earlier to complete.
# Allows a completion callback (configured as 'ccb' in constructor options) to be run on each data item.
# Completion callback has signature ($item, $res, $pid) with follwing meanings
#
# - $item - Original (single) data item (from array passed to run_parallel())
# - $res - Result object to which callback may fill in data (See: "filling of result")
# - $pid - Child Process PID that processed item - in case original $cb used PID (e.g. create files,
#   whose name contains PID)
#
# ## Filling or result $res
#
# The $res starts out as an empty hash/object (refrence, i.e. $res = {}) and completion callback need to
# establish its own application / "run case" specific organization within $res object.
# $res is returned by runwait() or retrievable by res() method.
#
sub runwait {
  my ($drun) = @_;
  my $numproc = $drun->{'numproc'};
  my $res = {}; # Collective result. Allow to come from outside
  my $ccb = $drun->{'ccb'}; # Completion and Collection Callback
  for (1 .. $numproc) {
    my $pid = wait();
    if ($pid == -1) { print(STDERR "PID: -1\n"); last; }
    $drun->{'debug'} && print(STDERR "Parent: $pid exited\n");
    # Resolve original data item
    my $item = $drun->{'pididx'}->{$pid}; # Lookup original data
    # Check for completion callback
    # - $item - original item from array
    # - $res - result object to fill out for collecting individual results
    if ($ccb) { $ccb->($item, $res, $pid); }
  }
  $drun->{'res'} = $res;
  #return $numproc; # Still in object after this call
  #return $drun;
  return $res;
}
# Process single item as a subprocess.
# This allows for example re-using the the existing instance of DataRun to be used for
# running single item in sub-process.
sub run_forked_single {
  my ($drun, $data) = @_;
  # TODO: Should we repeat the fork() business here or reusing run_parallel() is good enough ?
  $drun->run_parallel([$data]);
  # TODO: return $drun->runwait();
  if ($drun->{'autowait'}) { return $drun->runwait(); }
  return $drun;
}
1;
