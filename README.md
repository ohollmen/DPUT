# DPUT - The most elementary Data processing utilities

This module is not Object oriented in any way. It contains the most elementary operations like file reading/writing,
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

# CLRunner - Design command line apps and interfaces with ease.

## $clrunner = DPUT::CLRunner->new($optmeta, $runneropts)
Missing 'ops' means that subcommands are not supported by this utility and this instance.

## $clrunner->ops($ops)
Explicit method to set operations (sub command dispatch table).
Options:
- 'merge' - When set to true value, the new $ops will be merged with possible existing values (in overriding manner)

## isuniop($ops)
Internal detector to see if there is only single unambiguous operation in dispatch table.
Return the op name (key in dispatch table for the uique op, undef otherwise.
Only for module internal use (Do not use from outside app).

## $clrunner->run($opts)
Run application in ops mode or single-op mode. This will be auto-detected.
Options:
'exit' - Auto exit after dispatching operation.
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
- 'autowait' - Flag to wait for children to complete automatically inside

### Notes on 'autowait'

If 'autowait' is set, The call to one of the processing launching functions above
causes the call to it to block, and you may be wasting time idling (i.e. just waiting) in the main
process. If you have a pretty good idea of the processing time of children and what you could do
in the main process during that time, make an explict call to runwait() instead of using 'autpowait'.
Same wastage happens when you call `run_parallel($dataset)->runwait()` in a method-chained manner.
Examples higlighting this situation -
Blocking wait (with main process idling):

    my $dropts = {}; # NO 'autowait'
    DPUT::DataRun->new($dropts)->run_parallel($dataset)->runwait()
    # ... is effectively same as ...
    my $dropts = {'autowait' => 1};
    DPUT::DataRun->new($dropts)->run_parallel($dataset);

Both of these block while waiting for children to process.
To really perform maximum multitasking while waiting and utilize the time in main process, do:

    my $dropts = {}; # NO 'autowait'
    $drun = DPUT::DataRun->new()->run_parallel($dataset);
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

## Signaling results from single try

The return value from the callback of `...->run($cb)` is - for most
flexibility - tested with a callback. While this initially seems inconvenient,
the module provides 2 internal functions to handle 90%-95% of cases:

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
    local $Retrier::badret = $Retrier::badret_cli;
    # You can also do this for your completely custom badret - interpreter:
    local $Retrier::badret = $Retrier::badret_myown;

Demontration of a custom badret -interpretation callback (and why callback
style interpretation may become handy):

    sub badret_myown {
      my ($ret) = @_;
      # Up to value 3 return values are warnings and okay
      if ($ret > 3) { return 1; } # Bad
      return 0; # Good (<= 3)
    }

## Signaling results from all tries

When `$rt->run()` returns with a value, it indicates the overall success
of operation independent of whether operation needed to be tried many times
or the first try succeeded.
The chosen return value is Perl style $ok - true for success indication (in
contrast to C-style $err error indication).

## Notes on systems

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
Construct a Retrier
Settings:
- cnt - Number of times to retry (default: 3)
- delay - delay between the tries (seconds, default: 10)
- args - Arguments (in array-ref) to pass to function to be run (Optional, no default).
- debug - A debug flag / level for enabling module internal messages
  (currently treated as flag with now distinct levels, default: 0)

Return instance reference.
The retry options can be passed either with keyword -style convention
or as a perl hash(ref) as argument

    new Retrier('cnt' => 5);
    new Retrier({'cnt' => 5});

## $retrier->run($callback)
Run the operational callback ('cnt') number of times
Callback is passed as first argument.
See Retrier constructor for retry params ('cnt','delay',...)
Return (perl style) true value for success, false for failure.
Example:

    # Store news from flaky news site.
    use LWP::Simple;
    my $news; # Store news here.
    # Use the perl-style $ok return value
    sub get_news {
      my $cont = get("http://news.flaky.com/api/v3/news?today=1");
      if ($cont !~ /^\{/) { return 0; } # JSON curly not found !
      eval { $news = from_json($cont); }
      if ($@) { return 0; } # Still not good, JSON error
      return 1;
    }
    my $ok = Retrier->new('cnt' => 2, 'delay' => 3)->run(\&get_news);
    # Same parametrized:
    sub get_news {
      my ($jsonurl) = @_;
      my $cont = get($jsonurl);
      ...
    my $url = "http://news.flaky.com/api/v3/news?today=1";
    my $ok = Retrier->new('cnt' => 2, 'delay' => 3, 'args' => [$url])->run(\&get_news);
    # Or you can just do
    my $ok = Retrier->new('cnt' => 2, 'delay' => 3)->run(sub { return get_news($url); });

TODO: Allow passing max time to try.

# Detect command-line tool versions
# Tool definitions
Tool definition consists of following members:
- cmd - The command (basename) for tool (e.g. 'perl', without path)
- patt - Regular expression for detecting and extracting version
- stderr - Flag for extracting version info from stderr (instead of default stdout)

# Adding new tool definitions
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

