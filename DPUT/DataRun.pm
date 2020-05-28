
# # DataRun - Process datasets in series or in parallell (in a child process)
package DPUT::DataRun;
use strict;
use warnings;

our $VERSION = '0.0.1';
# ## $drun = DPUT::DataRun->new($callback, $opts)
# Construct a DataRun Data processor object.
# Pass a mandatory callback $cb to run on each item passed later to one of:
# - run_series($dataset)
# - run_parallel($dataset)
# - run_forked_single($data_item)
# Options in $opts:
# - 'ccb' - Completion callback (for single item of $dataset array)
# - 'autowait' - Flag to wait for children to complete automatically inside the run_* function
#
# ### Notes on 'autowait'
#
# If 'autowait' is set, The call to one of the processing launching functions above
# causes the call to it to block, and you may be wasting time idling (i.e. just waiting) in the main
# process. If you have a pretty good idea of the processing time of children and what you could do
# in the main process during that time, make an explict call to runwait() instead of using 'autpowait'.
# Same wastage happens when you call `run_parallel($dataset)->runwait()` in a method-chained manner.
# Examples higlighting this situation -
# Blocking wait (with main process idling):
#
#     my $dropts = {}; # NO 'autowait'
#     DPUT::DataRun->new($cb, $dropts)->run_parallel($dataset)->runwait()
#     # ... is effectively same as ...
#     my $dropts = {'autowait' => 1};
#     DPUT::DataRun->new($cb, $dropts)->run_parallel($dataset);
#
# Both of these block while waiting for children to process.
# To really perform maximum multitasking while waiting and utilize the time in main process, do:
#
#     my $dropts = {}; # NO 'autowait'
#     $drun = DPUT::DataRun->new($cb, $dropts)->run_parallel($dataset);
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

# ## $drun->run_series($dataset);
# Run processing in series within main process.
# This is a trivial (internally simple) method and **not** the reason to use DPUT::DataRun.
# It merely exists to **compare** the savings caused by running data processing in parallel in
# child processes. To do this rather easy comparison, do:
#
#     $drun = DPUT::DataRun->new(\&my_data_proc_sub, $dropts);
#     # Time this
#     my $res = $drun->run_series($dataset);
#     # and time this
#     my $res = $drun->run_parallel($dataset)->runwait();
#     # ... Compare the 2 and see if running in parallell is worth it
#
# There is always a small overhead of launching child processes, so for a small number of items **and** short processing
# time there may be no time benefit spawning the child processes in parallel.
sub run_series {
  my ($drun, $tars) = @_;
  my $cb = $drun->{'cb'};
  my $ccb = $drun->{'ccb'};
  my $res = {};
  $drun->{'st'} = time();
  # NOTE: If $ccb uses 
  for my $reltar (@$tars) {
    my $ret = $cb->($reltar);
    # NOTE: 3rd param $pid not available / relevant for series run.
    # NOTE: $res for parallell run is an index by PID, which does not make sense for series run.
    $ccb && $ccb->($reltar, $res, 0);
  }
  $drun->{'dt'} = time() - $drun->{'st'};
  $drun->{'res'} = $res;
  return $drun;
}
# ## $results = $drun->res();
# Return result of run which is stored in instance.
# Delete current result from instance (to reduce "state ambiguity" and for for next run via same instance).
sub res { my $res = $_[0]->{'res'};delete($_[0]->{'res'}); return $res; }

# ## $drun->reset();
# Reset state information related to particular run via instance.
# Reset internap properties are: 'res', 'numproc', 'pididx'.
sub reset {
  my ($drun) = @_;
  my $stprops = ['res', 'numproc', 'pididx'];
  map({delete($drun->{$_});} @$stprops);
}
# ## $drun->run_parallel($dataset);
# Process Data items passed in in a parallel manner (by fork()).
# Typical run setting:
#
#     my $dropts = {'ccb' => sub {}}; # Data run constructor options
#     my $res = new DataRun(sub { return myop($p1, $p2, $p3); }, $dropts)->run_parallel($dataset)->runwait();
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
  $drun->{'st'} = time();
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
## Helper to chunk original array to approximately $grpcnt (subject for rounding by non-even divisions).
## Takes care of not being destrictive to $arr_org (Makes a shallow copy before chunking).
## Return 2-dimensional array of chunks.
sub arr_chunk {
  my ($arr_org, $grpcnt) = @_;
  $grpcnt = $grpcnt || 3;
  my $itemcnt = int(scalar(@$arr_org) / $grpcnt);
  my @arr_copy = @$arr_org;
  #print("Items per batch: $itemcnt\n");

  my @arr2d = ();
  while (my @subarr = splice(@arr_copy, 0, $itemcnt) ) {
    #print(to_json(\@subarr)."\n");
    push(@arr2d, \@subarr);
  }
  return(\@arr2d);
}

# ## $drun->run_serpar($dataset, %opts);
# Run Task sub-parallel in grouped batches giving effectively a mix of series and parallel processing.
# Opts in %opts:
# - grpcnt - Number of sub-groups to chunk the $dataset array into
# Return results ($res) of individual chunks in an array of results (see runwait() for description).
sub run_serpar {
  my ($drun, $items, %opts) = @_;
  my $grpcnt = $opts{'grpcnt'} || 3;
  if ($grpcnt < 2) { die("run_serpar does not make sense with grpcnt < 2 ! Cancelling run."); }
  my $grpsize = scalar(@$items);
  # Common
  #my $cb = $drun->{'cb'};
  $drun->{'autowait'} = 1; # Force autowait
  # Chunk
  my $chunks = arr_chunk($items, $grpcnt);
  my $i = 0;
  my @ress = ();
  for my $itemchunk (@$chunks) {
    my $sicnt = scalar(@$itemchunk);
    $drun->{'debug'} && print(STDERR "Run Chunk($i) with $sicnt items/$grpsize (total)\n");
    # Run items in a chunk
    my $res = $drun->run_parallel($itemchunk);
    push(@ress, $res);
    $i++;
  }
  return \@ress;
}
# ## $drun->runwait();
# Wait for the child processes spawned earlier to complete.
# Allows a completion callback (configured as 'ccb' in constructor options) to be run on each data item.
# Completion callback has signature ($item, $res, $pid) with follwing meanings
#
# - $item - Original (single) data item (from array passed to run_parallel())
# - $res - Result object to which callback may fill in data (See: "filling of result")
# - $pid - Child Process PID that processed item - in case original $cb used PID (e.g. create files,
#   whose name contains PID)
#
# ### Filling of result $res
#
# The $res starts out as an empty hash/object (refrence, i.e. $res = {}) and completion callback needs to
# establish its own application (or "run case") specific organization within $res object. Completion callback
# will basically "fill in" this object the way it wants to allow main application to have access to results.
# $res is returned by runwait() or retrievable by res() method.
sub runwait {
  my ($drun) = @_;
  my $numproc = $drun->{'numproc'};
  my $res = {}; # Collective result. Allow to come from outside
  my $ccb = $drun->{'ccb'}; # Completion and Collection Callback
  for (1 .. $numproc) {
    my $pid = wait();
    if ($pid == -1) { print(STDERR "PID: -1\n"); last; }
    $drun->{'debug'} && print(STDERR "Parent: Child $pid just exited\n");
    # Resolve original data item
    my $item = $drun->{'pididx'}->{$pid}; # Lookup original data
    # Check for completion callback
    # - $item - original item from array
    # - $res - result object to fill out for collecting individual results
    if ($ccb) { $ccb->($item, $res, $pid); }
  }
  $drun->{'dt'} = time() - $drun->{'st'};
  $drun->{'res'} = $res;
  #return $numproc; # Still in object after this call
  #return $drun;
  return $res;
}
# ## $drun->run_forked_single()
# Process single item as a subprocess.
# This allows for example re-using the existing instance of DataRun to be used for
# running single item in sub-process.
sub run_forked_single {
  my ($drun, $data) = @_;
  # TODO: Should we repeat the fork() business here or reusing run_parallel() is good enough ?
  $drun->run_parallel([$data]);
  # TODO: return $drun->runwait();
  if ($drun->{'autowait'}) { return $drun->runwait(); }
  return $drun;
}

sub time {
  my ($drun) = @_;
  return $drun->{'dt'} || 0;
}

# ## TODO
# Create a simple event mechanism with onstart/onend events where processing can be done or things can be recorded
# (e.g. init / cleanup, calcing duration ...)
1;
