# # DPUT::RSyncer - perform one or more copy tasks with rsync
# 
# Allow sync tasks to run in series or parallell.
## TODO: Allow templating on src and dest by auto-detecting template delimiters (e.g. '{{' and '}}')
#
# ## Example API use
# 
# Load config, run sync and inspect results
# 
#     my $tasks = jsonfile_load($opts{'config'}, "stripcomm" => qr/^\s+#.+$/);
#     my $rsyncer = DPUT::RSyncer->new($tasks, %opts)
#     $rsyncer->run();
#     # Inspect results
#     my $cnt = grep({ $_->{'rv'} != 0; } @{$rsyncer->{'tasks'}});
#     if ($cnt) { die("Some of the rsync ops failed !"); }
#     
# ## Notes on SSH
# As any modern rsync setting uses SSH as transport, it is important to know the basics of SSH before
# starting to use this. Both rsync and 'onhost' feature rely on SSH. In any kind of non-interactive
# automation setting you likely need your SSH public key copied to remote host to allow passwordless
# SSH.
package DPUT::RSyncer;
use DPUT;
use DPUT::DataRun;
## use Text::Template;
## use Storable;
use strict;
use warnings;
our $VERSION = "0.01";

## Rsync default options
our $defopts = "-av";
our $sshopts = "";

sub TO_JSON {
  my ($h) = @_;
  my %h2 = %$h;
  return \%h2;
}

# ## RSyncer->new($tasksconf, %opts);
#
# Rsync Task items in $tasksconf (AoH) should have following properties:
# - src - Rsync source (mandatory, per rsync CL conventions)
# - dest - Rsync destination (mandatory, per rsync CL conventions)
# - title - Descriptive name for the Rsync Task (optional)
# - opts - Explicit rsync CL options starting with "-" (Implicit Default "-av")
# - excludes - An Array of Exclude patterns to serialize to command line (Optional, No defaults)
# - onhost - Run the rsync operation completely on a remote host (by SSH)
# 
# Options in %opts:
# - title - The title/name for the whole set of rsync tasks
# - debug - Debug level (currently true/false flag) for rsync message verbosity.
# - runtype - 'series' (default) or 'parallel'
# - preitemcb - A callback to execute just before running Rsync task item.
#   - Callback receives objects for 1) single Rsync task item, 2) Rsyncer Object (and may choose to tweak / use these)
# 
# Notice that currently the policy to run is "all in series" or "all in parallel" with no further
# granularity by nesting tasks into sets of parallel / in series runnable sets.
# However this limitation can be (for now) worked around on the application level for example by a
# bit of filtering (Perl: grep()) or using multiple Rsyncer configs and tuning your application logic
# to handle sequencing of series and parallel runs.
# 
sub new {
  my ($class, $conf, %opts) = @_;
  my $rsyncer = {"title" => "Another Rsync", "runtype" => "series", "tasks" => []};
  my $attrs = ["title","runtype","debug", "seq"]; # Attrs to inherit / override from top level config
  map({ $rsyncer->{$_} = $opts{$_}; } @$attrs);
  my $ref = ref($conf);
  if ($ref ne 'ARRAY') { die("Need Config as ARRAY"); }
  my $tasks = $conf;
  $rsyncer->{'tasks'} = $tasks;
  # Validate All task nodes
  map({if (ref($_) ne 'HASH') { die("Task node is not an HASH/Object"); } } @$tasks);
  map({ bless($_, 'RSTask'); } @$tasks);
  # Early validation of src, dest
  map({ $_->isvalid(); } @$tasks);
  #if ($rsyncer->{'seq'}) {
    my $i = 0; map({ $_->{'seq'} = $i; $i++; } @$tasks);
  #}
  bless($rsyncer, $class);
  return $rsyncer;
}

# ## $rsyncer->run()
#
# Currently no options are supported, but the operation is completely driven by the config
# data given at construction.
# Run RSyncer tasks in series or parallel manner (as dictated by $rsyncer options at construction).
# After the run the rsync task nodes will have rsync result info written on them:
# - time - Time used for the single rsync
# - pid - Process id of the process that run the sync in 'parallel' run (series run pid will be set to 0)
# - rv  - rsync return value (man rsync to to interpret error values)
# - cmd - Underlying command that was generated to run rsync.
sub run {
  my ($rsyncer) = @_;
  my $res;
  my $debug = $rsyncer->{'debug'};
  my %oktypes = (
    'series' => 1,
    'parallel' => 1
  );
  my $rt = $rsyncer->{'runtype'} || 'series';
  if (!$oktypes{$rt}) { die("RSyncer runtype '$rt' not supported - must be one of: ", join("\n", keys(%oktypes))); }
  my $tasks = $rsyncer->{'tasks'};
  
  my $cnt = scalar(@$tasks);
  if (!$cnt) { die("No RSync Tasks for RSyncer"); }
  # DONOT: Local optimization for single (run and return): if ($cnt == 1) { $tasks->[0]->rsync(); }
  # Callback for running single task.
  my $cb = sub { my ($rst) = @_; $rst->rsync($rsyncer); };
  # Parallel run single task completion callback
  my $ccb = sub {
    my ($it, $res, $pid) = @_;
    $debug && print(STDERR "Completed(proc:$pid): ".Data::Dumper::Dumper($it)."\n");
    if (!$pid) { return; } # Index by seq, not ID ?
    # Load info from PID named file and copy to original node OR $res ?
    my $rsinfo = jsonfile_load("/tmp/rsync.$pid.json");
    #TEST: $res->{$pid} = $pid;
    $res->{$pid} = $rsinfo;
  };
  my $dropts = {
    'autowait' => 0,
    'ccb' => $ccb,
    'debug' => 1,
  };
  my $drun = DPUT::DataRun->new($cb, $dropts);
  
  $debug && print(STDERR "Created drun: $drun.\nStarting run $cnt tasks in '$rt'\n");
  my $t1 = time();
  if ($rt eq 'parallel') {
    $drun->run_parallel($tasks);
    $debug && print(STDERR "Start wait for $cnt tasks ...\n");
    $res = $drun->runwait(); # Only on parallel
    # Map child result info back to items
    mapresults($tasks, $res);
  }
  else {
    $drun->run_series($tasks); # Already calls $ccb
    $res = $drun->{'res'}; # Assigns empty: {}
  }
  OLD:my $dt0 = time() - $t1;
  my $dt = $rsyncer->{'dt'} = $drun->time();
  $debug && print(STDERR "All $cnt tasks Ran in parent(PID:$$) in $dt (OLD:$dt0) secs\n");
  # Access $drun->{''}; ???
  $debug && print(STDERR "Run Res: ".Data::Dumper::Dumper($res)."\n\n");
  return $res;
}
## ## mapresults($tasks, $res);
## Internal utility method to map results back to Rsync task nodes.
## Mreges result attributes to task nodes by correlating them by 'seq' (sequence order number).
sub mapresults {
  my ($tasks, $res) = @_;
  my %byseq = ();
  for $_ (keys(%$res)) {
    my $o = $res->{$_};
    $byseq{$o->{'seq'}} = $o; # map({ $o->{'seq'}, $o; } keys(%$res));
  }
  map({ my $o = $byseq{$_->{'seq'}}; @$_{'rv','time','pid','cmd',} = @$o{'rv','time','pid','cmd',}} @$tasks);
    
}

## ## RSTask - Package for single Rsync task
## This is a low-level module not meant to be accessed by developer.
## It takes care of single rsync operation by generating the command line and running rsync.
## Additionally rudimentary validations are done on mandatory attributes.
package RSTask;
use DPUT;
sub TO_JSON {
  my ($h) = @_;
  my %h2 = %$h;
  return \%h2;
}
## Perform superficial validation
sub isvalid {
  my ($rst) = @_;
  if (!$rst->{'src'})  { die("No Sync Source (src)"); }
  if (!$rst->{'dest'}) { die("No Sync Destination (dest)"); }
  return 1;
}
## Detect if Rsync Task has hostname to consider it remote.
sub isremote {
  my ($str) = @_;
  if ($str =~ /\:/) { return 1; }
  return(0);
}
## ## $rst->command($rsyncer)
## Formulate the rsync command, complete with options, excludes, src and dest.
## src and dest will be single quoted to be safe for shell (currently no excaping is done).
## TODO: Allow templating of src, dest (OR all members)
sub command {
  my ($rst, $rsyncer) = @_;
  my @exc = map({ "--exclude '$_'"; } @{$rst->{'excludes'} || []});
  my $opts = $rst->{'opts'} || '-av'; # $DPUT::RSyncer::defopts
  # my $rst2 = Storable::dclone($rst);
  # if ($rst2->{'src'} =~ /\{\{/ && $rst2->{'src'} =~ /\}\}/ ) {} # Use templating
  my $cmd = "rsync $opts ".join(' ', @exc)." '$rst->{'src'}' '$rst->{'dest'}'";
  if (isremote($rst->{'src'}) && isremote($rst->{'dest'})) { die("Both 'src' and 'dest' are remote - can't do that !"); }
  # Run whole rsync on a remote host ?
  if ($rst->{'onhost'}) {
    $rsyncer->{'debug'} && print(STDERR "Special: Running on SSH remote host: $rst->{'onhost'}\n");
    # TODO: ssh options
    my $sshopts = $DPUT::RSyncer::sshopts || "";
    $cmd = "ssh $rst->{'onhost'} $sshopts ".$cmd;
  }
  return $cmd;
}


# ## $rst->rsync($syncer)
# 
# Perform single rsync on the low level.
# Will return results of a sync in a JSON results file with:
# - PID of child process
# - Return value (pre-shifted to a sane man-page kinda easily interpretable value)
# - time spent (s.)
# - TODO: list or number of files
#
# These results are available to application as data structure, no poking of JSON file is necessary.
# Return always 1 here and let (top level) caller detect actual rsync (or ssh, for 'ohhost') return value
# from task node 'rv' (return value).
sub rsync {
  my ($rst, $rsyncer) = @_;
  my $debug = $rsyncer->{'debug'};
  ######  ##################
  my $cmd = $rst->command($rsyncer);
  #$debug && print(STDERR "Running $rst->{'title'}: $cmd\n");
  my $cb = $rsyncer->{'preitemcb'};
  if (ref($cb) eq 'CODE') { $cb->($rst, $rsyncer); }
  ###### Run ######
  my $t1 = time();
  # TODO: Provide multiple execution styles: system, backticks, pipe ?
  my $out = `$cmd`;
  #system($cmd);
  my $dt = time() - $t1;
  #print(STDERR "DEBUG1: Time=$dt\n");
  my $rv = $? >> 8;
  my $ret = {'rv' => $rv, 'time' => $dt, 'pid' => $$, 'cmd' => $cmd};
  if ($rsyncer->{'runtype'} eq 'series') { $ret->{'pid'} = 0; fillinfo($rst, $ret); return 1; } # Series run - no intercomm file
  ####### Store Rsync Processing Results for parallel run (for the completion callback called in parent) #####
  
  # fillinfo($rst, $ret); # $$=PID
  sub fillinfo {
    my ($rst, $ret) = @_;
    my @copyattrs = ('rv','time','pid', 'cmd');
    #$rst->{'rv'} = $rv;
    #$rst->{'pid'} = $pid;
    #print("DEBUG2: Time=$dt\n");
    #$rst->{'time'} = $dt;
    #if (!$pid) { return; }
    for my $k (@copyattrs) { $rst->{$k} = $ret->{$k}; }
  }
  $ret->{'title'} = $rst->{'title'}; # mostly for DEBUG:ing
  $ret->{'seq'}   = $rst->{'seq'}; # For correlating result and original node
  # Store Process inter-communication JSON file (to be picked up by the parent process)
  my $fn = "/tmp/rsync.$$.json";
  jsonfile_write($fn, $ret); # , %opts);
  $debug && print(STDERR "Rsync returned: $ret ($dt s.), Wrote res to '$fn'\n");
  return 1;
}
1;
