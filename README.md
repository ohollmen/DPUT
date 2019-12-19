# DPUT - Data Processing Utility Toolkit

This is the top-level, "umbrella" module of "Data Processing Utility Toolkit" that has lot of bread and
butter functionality for modern SW development and devops tasks:

- Reading/Parsing and Writing/Serializing into files (esp. JSON)
- Running tasks in parallel as an optimization (supporting data driven parallell running)
- Retrying operations under unreliable conditions, trying to create a reliable app on top of unreliable
  infrastructure or environment (e.g. glitchy network conditions)
- Sync/Copy large quantities of files across network or in local filesystems
- Create Command line applications easily with minimum boilerplate
- Extracting Markdown documentation within code files to an aggregated "publishable" documentation
- Auditing toolchains by recording which tools and their versions were used by data processing

This top-level module is not Object oriented in any way. It contains the most elementary operations like file reading/writing,
listing directories (also recursively) on a very high level.

## Reading and writing files
- *write - write content or append content to a (existing or new) file.
- *read - Read file content into a variable (scalar or data structure for JSON, YAML, ...)


## jsonfile_load($fname, %opts)
Load a JSON data from a file ($fname).
There is no constraint of what type (array, object) the "data root" is.
Allow options:
- 'stripcomm' - Strip comments by RegExp pattern given. The regular expression substitution
  is run across the whole JSON string content before parsing is called.


## jsonfile_write($fname, $ref, %opts);
Write JSON file.
By default the formatting is done "pretty" way (not single-line whitespace stripped).
This is basically a shorthand form of: `file_write($fname, $datatree, 'fmt' => 'json');`
However this mandates $datatree parameter in above to be a reference to either
HASH or ARRAY (as writing a scalar number or string as JSON is niche thing to do).

## file_write($fname, $cont, %opts)
Write content (or data structure) to a file.
By default writing happens in non-appending / overwriting mode.
If content is a reference it is stored in one of the data structure based formats (json,perl,yaml) - see 'fmt' below.
Options in %opts:
- append - append to existing file content (opens file in append-mode)
- fmt - Format to serialize content to when the $cont parameter is actually a (data structure) reference
  Formats supported are: 'json', 'yaml' and 'perl' (Default: 'json')
- lines - Lines in array(ref) passed in $cont should be written to file. Each of lines will be terminated with "\n".

Perl format is written with small indent and no perl variable name (e.g. $VAR1)
JSON is written in "pretty" format assuming it benefits out of human readability.
Return $ok (actually number of bytes written)

## file_read($fname, %opts)
Read file content from a file by $fname.
Options in opts:
- 'lines' - Pre-split to lines and return array(ref) instead of scalar content
- 'rtrim' - Get rid of trailing newline
Return file content as scalar string (default) or array(ref) (with option 'lines')

## dir_list($path, %opts)
List a single directory or subdirectory tree.
$path can be any resolvable path (relative or absolute).
Options:
- 'tree' - Create recursive listing
- 'preprocess' - File::Find preprocess for tree traversal (triggered by 'tree' option)
Return the files as array(ref)

## domainname()
Probe current DNS domainname (*not* NIS domainname) for the host app is running on.
Return full domain part of current host (e.g. passing host.example.com => example.com).

## require_fastjson(%opts)
Mandate a fast and size-scalable JSON parser/serializer in current runtime.
Our biased favorite for this kind of parser is JSON::XS.
Option 'probe' does not load (and possibly fail with exception)
Return true value with version of JSON::XS on success, or fail with exception.
If option 'probe' was passed, only detection of JSON::XS presence from current runtime is done
and no exceptions are ever thrown.

## file_checksum($fname, %opts)
Extract MD5 checksum (default) from a file.
Doing this inline in code is slightly tedious. This works well as a shortcut.
Checksumming is still done efficiently by bot loading the whole content into memory.
Return MD5 Checksum.

## isotime($time)
Generate local ISO timestamp for current moment in time or for another point in time - with optional $time parameter.

## DPUT::csv_to_data($csv, $fh, %opts);
Extract data from CSV file by passing Text::CSV processor instance and filehandle (or filename) to load data from.
Options:
- cols - Pass explicit column names, do not extract column names from sheet (or map to new names)
- striphdr - Strip first entity extracted when explicit column names ('cols') are passed
Example CSV extraction scenario:

    use Text::CSV; 
    my $csv = Text::CSV->new({binary => 1});
    if (!$csv) { die("No Text::CSV processor instance"); }
    my $ok = open(my $fh, "<", "animals.csv");
    my $arr = DPUT::csv_to_data($csv, $fh, 'cols' => undef);
    print(Dumper($arr));

## DPUT::sheet_to_data($xlsx_sheet, %opts);
Extract data from XLSX to Array of Hashes for processing
The data is passed as single Spreadsheet::ParseExcel::Worksheet sheet object.
Options:
- debug - Turn on verbose messages
- cols - Pass explicit column names, do not extract column names from sheet (see also: striphdr)
- striphdr - Strip first entity extracted when explicit column names ('cols') are passed
Example CSV extraction scenario:

    my $converter = Text::Iconv->new ("utf-8", "windows-1251");
    my $excel = Spreadsheet::XLSX->new("animals.xlsx", $converter);
    my $sheet = $excel->{Worksheet}->[0]; # Choose first sheet
    my %xopts = ('debug' => 1, 'fullinfo' => 1);
    $aoh = DPUT::sheet_to_data($sheet, %xopts);
    print(Dumper($aoh));

Return Array of Objects contained in the sheet processed.

## $creds = netrc_creds($hostname, %opts);
Extract credentials (username and password) for a hostname.
The triplet of hostname, username and password will be returned as an object with:
     {
       "host" => "the-server-host.com:8080",
       "user" => "jsmith",
       "pass" => "J0hNN7b07"
      }
Options in %opts:
- debug - Create dumps for dev time debugging (Note: this will potentially show secure data in logs)
Return a complete host + credentials object (as seen above) - that is hopefully usable
for establishing connection to the remote sever (e.g. HTTP+REST, MySQL, MongoDB, LDAP, ...)

DPUT::filetree_filter_by_stat($dirpath, $filtercb, %opts);
Collect a list of ("filtered-in") files from a directory tree based on stat results.
Creates a list of filenames that filter callback indicates as "matching".
Caller should pass:
- $dirpath - Path to look for files
- $filtercb - Callback returning true (to include) / false (to exclude) values like a normal filter function fashion.
   Filter callback receives stat array (as reference) and absolute filename of current file as parameters.
- %opts Processing options
  - useret - Place return value of callback to file list generated (instead of default, which is filename)
Using 'useret' means that filtercb function is written so that it returns a custom values that will be placed in results.
Return list of filenames or custom callback generated objects / items.

# DPUT::CLRunner - Design command line apps and interfaces with ease.

CLRunner bases all its functionality on Getopt::Long, but makes the usage declarative.
It also strongly supports the modern convention of using sub-commands for cl commands
(E.g. git clone, git checkout or apt-get install, apt-get purge).

## Usage
my $optmeta = ["",""];
my $runneropts = {};
sub greet {}
sub delegate {}
$clrunner = DPUT::CLRunner->new($optmeta, $runneropts);
$clrunner->ops({'greet' => \&greet, '' => \&delegate});


## $clrunner = DPUT::CLRunner->new($optmeta, $runneropts)
Missing 'ops' means that subcommands are not supported by this utility and this instance.
Options in %$runneropts
- ops - Ops dispatch (callback) table
- op- Single op callback (Mutually exclusive with ops, only one must be passed)
- debug - Produce verbose output

## $clrunner->ops($ops)
Explicit method to set operations (sub command dispatch table). Operations dispatch table is passed in $ops (hash ref),
where each operation keyword / label (usually a impertaive / verb form word e.g. "search") maps to a function with call signature:

    $cb->($opts); # Options passed to run() method. %$opts should be a hash object that callback can handle.
Options:
- 'merge' - When set to true value, the new $ops will be merged with possible existing values (in overriding manner)

## isuniop($ops)
Internal detector to see if there is only single unambiguous operation in dispatch table.
Return the op name (key in dispatch table for the uique op, undef otherwise.
Only for module internal use (Do not use from outside app).

## $clrunner->run($opts)
Run application in ops mode (supporting CL sub-commands) or single-op mode (no subcommands).
This mode will be auto-detected.
Options:
- 'exit' - Auto exit after dispatching operation.

Return instance for method chaining.

## $cl_params_string = $clrunner->args($clioptions)
Turn opts (back) to CL argumnents, either an Array or string-serialized (quoted, escaped) form.
Uses CLRunner 'optmeta' as guide for the serialization.
Return array (default) or command line ready arguments string if 'str' option is passed.

# DataRun - Process datasets in series or in parallell (in a child process)

## $drun = DPUT::DataRun->new($callback, $opts)
Construct a DataRun Data processor object.
Pass a mandatory callback $cb to run on each item passed later to one of:
- run_series($dataset)
- run_parallel($dataset)
- run_forked_single($data_item)
Options in $opts:
- 'ccb' - Completion callback (for single item of $dataset array)
- 'autowait' - Flag to wait for children to complete automatically inside the run_* function

### Notes on 'autowait'

If 'autowait' is set, The call to one of the processing launching functions above
causes the call to it to block, and you may be wasting time idling (i.e. just waiting) in the main
process. If you have a pretty good idea of the processing time of children and what you could do
in the main process during that time, make an explict call to runwait() instead of using 'autpowait'.
Same wastage happens when you call `run_parallel($dataset)->runwait()` in a method-chained manner.
Examples higlighting this situation -
Blocking wait (with main process idling):

    my $dropts = {}; # NO 'autowait'
    DPUT::DataRun->new($cb, $dropts)->run_parallel($dataset)->runwait()
    # ... is effectively same as ...
    my $dropts = {'autowait' => 1};
    DPUT::DataRun->new($cb, $dropts)->run_parallel($dataset);

Both of these block while waiting for children to process.
To really perform maximum multitasking while waiting and utilize the time in main process, do:

    my $dropts = {}; # NO 'autowait'
    $drun = DPUT::DataRun->new($cb, $dropts)->run_parallel($dataset);
    # Optimally this should take approx same time as parallel processing by children
    do_someting_else_while_waiting_children($somedata); # Utilize the waiting time !
    $drun->runwait();

## $drun->run_series($dataset);
Run processing in series within main process.
This is a trivial (internally simple) method and **not** the reason to use DPUT::DataRun.
It merely exists to **compare** the savings caused by running data processing in parallel in
child processes. To do this rather easy comparison, do:

    $drun = DPUT::DataRun->new(\&my_data_proc_sub, $dropts);
    # Time this
    my $res = $drun->run_series($dataset);
    # and time this
    my $res = $drun->run_parallel($dataset)->runwait();
    # ... Compare the 2 and see if running in parallell is worth it

There is always a small overhead of launching child processes, so for a small number of items **and** short processing
time there may be no time benefit spawning the child processes in parallel.

## $results = $drun->res();
Return result of run which is stored in instance.
Delete current result from instance (to reduce "state ambiguity" and for for next run via same instance).

## $drun->reset();
Reset state information related to particular run via instance.
Reset internap properties are: 'res', 'numproc', 'pididx'.

## $drun->run_parallel($dataset);
Process Data items passed in in a parallel manner (by fork()).
Typical run setting:

    my $dropts = {'ccb' => sub {}}; # Data run constructor options
    my $res = new DataRun(sub { return myop($p1, $p2, $p3); }, $dropts)->run_parallel($dataset)->runwait();

Return normally an object itself for method chaining (e.g. calling runwait()).
In case of 'autowait' setting in instance, the runwait() is automatically called and
return value is the result from runwait() (See runwait()).

## Notes on internals

run_parallel() internally keeps track of processes vs. the data item processed.
On the high level this enables producing collective results by completion callback 'ccb'
and retrieveing the collective results by res() method.

## $drun->runwait();
Wait for the child processes spawned earlier to complete.
Allows a completion callback (configured as 'ccb' in constructor options) to be run on each data item.
Completion callback has signature ($item, $res, $pid) with follwing meanings

- $item - Original (single) data item (from array passed to run_parallel())
- $res - Result object to which callback may fill in data (See: "filling of result")
- $pid - Child Process PID that processed item - in case original $cb used PID (e.g. create files,
  whose name contains PID)

### Filling of result $res

The $res starts out as an empty hash/object (refrence, i.e. $res = {}) and completion callback needs to
establish its own application (or "run case") specific organization within $res object. Completion callback
will basically "fill in" this object the way it wants to allow main application to have access to results.
$res is returned by runwait() or retrievable by res() method.

## $drun->run_forked_single()
Process single item as a subprocess.
This allows for example re-using the existing instance of DataRun to be used for
running single item in sub-process.

## TODO
Create a simple event mechanism with onstart/onend events where processing can be done or things can be recorded
(e.g. init / cleanup, calcing duration ...)

# MDRipper - Rip Markdown documentation out of (any) files

Markdown ripper uses a simple methodology for ripping MD content
out of files.
- Any lines starting with RegExp patter "^# " will be ripped
- TODO: allow "minlines" config var to eliminate blocks ofd less
  contiguous lines than number in "minlines"
- Return MD document content
- process one file at the time (mutiple files may be processed via same instance)

## DPUT::MDRipper->new(%opts);
Construct new Markdown ripper.

## $mdripper->rip($fname, %opts)
Rip Markdown content from a single file, whose name is passed as parameter.
Current settings of instance are used for this op.
Return Mardown content.

# OpRun - Run Set of different operations with (single) shared data context.

## $oprunner = DPUT::OpRun->new($ctx, $opsarr, %opts);
Create new Op Runner
- $ctx - Data Context
- $opsarr - Opration callbacks in an array

Return instance.

## $oprunner->run_series(%opts)
Run operations in series (within current process).
Return instance for method chaining.

## $oprunner->run_parallel(%opts)
Run operations in parallel (using child processes).
Return instance for method chaining.

$oprunner->runwait()
Wait for the child processes to complete (Similar to DPUT::DataRun::runwait() method).

# Retrier - Try operation multiple times in failsafe manner

Most typical use case for retrying would likely be an operation over the network
(e.g. HTTP, SSH, Git, FTP, ...).
Even reliable and well-maintained environment occasionally have brief glitches that
prevent interaction with a single try.

## Signaling results from single try callback

The return value from the callback of `...->run($cb)` is - for most
flexibility - tested with a callback. The callback name 'badret' refers to
"bad return value", encountering of which triggers a retry.
While this initially seems inconvenient,the module provides 2 internal functions
to handle 90%-95% of cases:

- badret_perl - Interprets "Perl style" $ok return value as success
- badret_cli - Interprets success with a shell command line convention of
  zero value indicating success and non-zero return value indicating error.
  This allows

the default return value interpretation is "Perl style" and you do not have
to specify a 'badret' callback in your constructor.
In case you have mixed convention cases in your app, the choices of coping
with this are:

    # Use local to set temporary value for the duration of current curly-scope
    # (sub, if- or else block, ...) which will be "undone" and reverted
    # back to default after exiting curly-scope.
    local $DPUT::Retrier::badret = \&Retrier::badret_cli;
    # You can also do this for your completely custom badret - interpreter:
    local $DPUT::Retrier::badret = \&badret_myown;

Passing badret value in construction in 'badret' option

    my $retrier = new DPUT::Retrier('cnt' => 5, 'badret' => \&DPUT::Retrier::badret_cli);

Demonstration of a custom badret -interpretation callback (and why callback
style interpretation may become handy):

    sub badret_myown {
      my ($ret) = @_;
      # Up to value 3 return values are warnings and okay
      if ($ret > 3) { return 1; } # Bad (>3)
      return 0; # Good/Okay (<= 3)
    }

This flexibility on iterpreting return values will hopefully allow running *any* existing
sub / function in a retried manner. With custom function you can also test undef values,
array,hash and code references, etc.

## Signaling results from run() (all tries)

When `$rt->run()` returns with a value, it indicates the overall success
of operation independent of whether operation needed to be tried many times
or the first try succeeded.
The chosen return value is Perl style $ok - true for success indication (in
contrast to C-style $err error indication).

## Notes on systems you interact with

To use this module effectively, you have to be somewhat familiar with
the error patterns of the (many times remote, over-the-network) systems
that you interact with. E.g 3 retries with a 3s delay on one relatively
reliable, but occasionally glitchy system (with a very small glitch
timewindow) might be relevant, where as with a system where "bastard operator
from hell" reboots the system a few times a day to entertain himself may
require 6 minute (360s.) delay to allow the OS and services to come up.
Retrier provides no silver bullet or substitute for this knowledge.

## TODO

Consider millisecond resolution on delay. This would require pulling in
a CORE module dependency Time::HiRes. Would need to introduce 'unit'
and separation between constructor config params vs. internal value
held (e.g. always in 'ms'). At this point ms resolution is deemed overkill
and not worth the dependency.
DPUT::Retrier

## DPUT::Retrier->new(%opts)
Construct a Retrier.
Settings:
- cnt - Number of times to retry (default: 3)
- delay - delay between the tries (seconds, default: 10)
- args - Arguments (in array-ref) to pass to function to be run (Optional, no default).
- debug - A debug flag / level for enabling module internal messages
  (currently treated as flag with now distinct levels, default: 0)

Return instance reference.
The retry options can be passed either with keyword -style convention
or as a perl hash(ref) as argument:

    new DPUT::Retrier('cnt' => 5);
    new DPUT::Retrier({'cnt' => 5});

## $retrier->run($callback)
Run the operational callback ('cnt') number of times to successfully execute it.
Callback is passed as first argument.
See Retrier constructor for retry params ('cnt','delay',...)
Return (perl style) true value for success, false for failure.
Example:

    # Store news from flaky news site.
    use LWP::Simple;
    use JSON;
    my $news; # Store news here.
    # Use the perl-style $ok return value
    sub get_news {
      my $cont = get("http://news.flaky.com/api/v3/news?today=1");
      if ($cont !~ /^\{/) { return 0; } # JSON curly not found !
      eval { $news = from_json($cont); }
      if ($@) { return 0; } # Still not good, JSON error
      return 1; # Success, Perl style $ok value
    }
    my $ok = Retrier->new('cnt' => 2, 'delay' => 3)->run(\&get_news);
    # Same parametrized (with 'args'):
    sub get_news {
      my ($jsonurl) = @_;
      my $cont = get($jsonurl);
      ...
    my $url = "http://news.flaky.com/api/v3/news?today=1";
    my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3, 'args' => [$url])->run(\&get_news);
    # Or you can just do (no 'args' needed).
    my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3)->run(sub { return get_news($url); });

Store good app-wide defaults in DPUT::Retrier class vars to make construction super brief.

    $DPUT::Retrier::trycnt = 3;
    $DPUT::Retrier::delay = 10;
    # Rely on module-global defaults, instead of passing 'cnt' and 'delay'.
    my $ok = DPUT::Retrier->new()->run(sub { get($url); });

This is a valid approach when settings are universal to whole app (no variance between the calls).

TODO: Allow passing max time to try.

# DPUT::ToolProbe - Detect command-line tool versions

## Tool definitions

Tool definition consists of following members:
- cmd - The command (basename) for tool (e.g. 'perl', without path)
- patt - Regular expression for detecting and extracting version
- stderr - Flag for extracting version information from stderr (instead of default stdout)

## Adding new tool definitions
The module comes with a basic set of tool definitions
Note, this is kept module-global to allow simple
additions by (e.g.):
push(@{$SWBuilder::toolprobeinfo}, {"cmd" => "repo", "" => ""})

# Note on $PATH

This module is reliant on the `which` utility that uses `$PATH` to see which actual executable and from which path is
going to be run for the basename of particular command.
The reported results of ToolProbe are only valid for the $PATH that was used at the time of detection. If $PATH changes,
the results may change.

# TODO
Consider adding (or just documenting) semantic versioning functionality to compare extracted version
to some feature "threshold version" (i.e. version > 1.5.5 supports shortcut feature X and in versions below
that we have to multiple steps to accopmlish the same result).

Set by $DPUT::ToolProbe::debug =1;

Convenience method for adding a new tool definition.
Definition is added to the class -held defintion collection
variable ($toolprobeinfo) with validation. Same as

    push(@$DPUT::ToolProbe::toolprobeinfo, $newtool);

Except the latter low level way does not validate %$$newtool.

Create RegExp for tool definition based on Regexp options ('reopt').

## DPUT::ToolProbe::detect()
Probe tool command version and path from which it was found.
This happens for all the tools registered (See doc on how to add more tools).
Assume tools to support conventional --version option.
Return an hash of hashes containing:
- outer keys rflecting the tool name (from tool probe info $tool->{'cmd'})
- inner object containing members:
  - path - Full path to tool
  - version - Version of the tool (extracted)

 

# DPUT::RSyncer - perform one or more copy tasks with rsync

Allow sync tasks to run in series or parallell.

## Example API use

Load config, run sync and inspect results

    my $tasks = jsonfile_load($opts{'config'}, "stripcomm" => qr/^\s+#.+$/);
    my $rsyncer = DPUT::RSyncer->new($tasks, %opts)
    $rsyncer->run();
    # Inspect results
    my $cnt = grep({ $_->{'rv'} != 0; } @{$rsyncer->{'tasks'}});
    if ($cnt) { die("Some of the rsync ops failed !"); }
    
## Notes on SSH
As any modern rsync setting uses SSH as transport, it is important to know the basics of SSH before
starting to use this. Both rsync and 'onhost' feature rely on SSH. In any kind of non-interactive
automation setting you likely need your SSH public key copied to remote host to allow passwordless
SSH.

## DPUT::RSyncer->new($tasksconf, %opts);

Rsync Task items in $tasksconf (AoH) should have following properties:
- src - Rsync source (mandatory, per rsync CL conventions)
- dest - Rsync destination (mandatory, per rsync CL conventions)
- title - Descriptive name for the Rsync Task (optional)
- opts - Explicit rsync CL options starting with "-" (Implicit Default "-av")
- excludes - An Array of Exclude patterns to serialize to command line (Optional, No defaults)
- onhost - Run the rsync operation completely on a remote host (by SSH)

Options in %opts:
- title - The title/name for the whole set of rsync tasks
- debug - Debug level (currently true/false flag) for rsync message verbosity.
- runtype - 'series' (default) or 'parallel'
- preitemcb - A callback to execute just before running Rsync task item.
  - Callback receives objects for 1) single Rsync task item, 2) Rsyncer Object (and may choose to tweak / use these)

Notice that currently the policy to run is "all in series" or "all in parallel" with no further
granularity by nesting tasks into sets of parallel / in series runnable sets.
However this limitation can be (for now) worked around on the application level for example by a
bit of filtering (Perl: grep()) or using multiple Rsyncer configs and tuning your application logic
to handle sequencing of series and parallel runs.


## $rsyncer->run()

Currently no options are supported, but the operation is completely driven by the config
data given at construction.
Run RSyncer tasks in series or parallel manner (as dictated by $rsyncer options at construction).
After the run the rsync task nodes will have rsync result info written on them:
- time - Time used for the single rsync
- pid - Process id of the process that run the sync in 'parallel' run (series run pid will be set to 0)
- rv  - rsync return value (man rsync to to interpret error values)
- cmd - Underlying command that was generated to run rsync.
Return 

Run templating on string $tstr with parameters from $p.
Return expanded content.

## $rst->rsync($syncer)

Perform single rsync on the low level.
Will return results of a sync in a JSON results file with:
- PID of child process
- Return value (pre-shifted to a sane man-page kinda easily interpretable value)
- time spent (s.)
- TODO: list or number of files

These results are available to application as data structure, no poking of JSON file is necessary.
Return always 1 here and let (top level) caller detect actual rsync (or ssh, for 'ohhost') return value
from task node 'rv' (return value).

# DPUT::DockerRunner - Run docker in automated context with preconfigured options

## DPUT::DockerRunner->new('img' => 'myimage', 'cmd' => 'compute.sh');

Create new docker runner with options to run docker.

Keyword Options in %opts:
- img - Image name to use for running "docker run $IMAGE $CMD"
- cmd - Command to run in docker (with possible whitespace separated arguments)
- cwd - Current working directory inside container (docker -w param)
  - Passing a explicit path sets working dir to that value
  - passing the kw param, but with false value does not set any explicit working dir. Docker sets the cwd for you.
  - When kw param is completely left out, container cwd is set to current host cwd
- mergeuser - User to add as resolvable user in container /etc/passwd using volume mapping (e.g. "compute").
- asuser - Run as user (resolvable on local system **and** docker.
- vols - an array of volume mappings. Simple 1:1 mappings with form:to the same can be given without delimiting ":".

Todo:
- Allow checking/validating volume source locations presence. For now caller has to make sure
they are valid.
- Could do duplicate volume check before launch (Error response from daemon: Duplicate mount point: ...)
 
### Merging a user

"mergeuser" parameter can take 3 forms:

- bare username resolvable on host (e.g. "mrsmith")
- a valid passwd file line (with 7 ":" delimited fields)
- an array(ref) with 7 elements describing valid user

### Volumes

Volume mappings are passed (simply in array, not hash object) in a docker-familiar notation
"/path/on/host:/path/inside/docker. They are formulated into docker -v options.

### Example of running
Terse use case with params set and run executed on-the-fly:

     my $rc = DPUT::DockerRunner->new('img' => 'myimage', 'cmd' => 'compute.sh')->run();
More granular config passed and (only) command is generated:

     my $dcfg = {
       "img" => "ubuntu",
       "cmd" => "ls /usr",
       "vols" => ["/tmp","/usr", "/placeone:/anotherplace"],
       "asuser" => "mrsmith",
       #"mergeuser" => "oddball:x:1004:1004:Johnny Oddball,,,:/home/oddball:/bin/bash",
     };
     # Create Docker runner
     my $docker = DPUT::DockerRunner->new(%$dcfg);
     my $cmd = $docker->run('cmdstring' => 1);
     print("Generated command: '$cmd'\n");


Wrapper for Getting an account

Detect if the currect user of the system has docker executable.
User may additionally need to belong UNIX groups (like "docker") to actually run docker.
This check is not done here.
Return docker absoute path (a true value) or false if docker is not detected.

## $docker->setup_accts()
Add (merge) an account to a generated temporary passwd file on the host and map it into use (as a volume)
inside the docker container.

## $docker->run(%opts); 
Run Docker with preconfigured params or *only* return docker run command (string) for more "manual" run.
Options in opts:

- cmdstring - Trigger return of command string only *without* actually running container

Return either docker command string (w. option cmdstring) or return code of actual docker run.

