# # DPUT - Data Processing Utility Toolkit
#
# This is the top-level, "umbrella" module of "Data Processing Utility Toolkit" that has lot of bread and
# butter functionality for modern SW development and devops tasks:
# 
# - Reading/Parsing and Writing/Serializing into files (esp. JSON)
# - Running tasks in parallel as a processing speedup optimization (supporting data driven parallel running)
# - Retrying operations under unreliable conditions, trying to create a reliable app on top of unreliable
#   infrastructure or environment (e.g. glitchy network conditions)
# - Sync/Copy large quantities of files across network or in local filesystems (using **rsync**)
# - Create Command line applications easily with minimum boilerplate (Supporting subcommands and reuse of CLI parsing specs)
# - Extracting **Markdown documentation** within code files to an aggregated "publishable" documentation
# - Auditing toolchains by recording which tools and their versions were used by data processing (e.g. python, git, make, gcc)
# - Loading, interpreting and reporting **xUnit** (**jUnit**) test results (from xUnit XML files)
# - Running **Docker** workloads in an easy and structured way.
# 
# This top-level module is not Object oriented in any way. It contains the most elementary operations like file reading/writing,
# listing directories (also recursively) on a very high level.
# 
# ## Reading and writing files
# 
# - *write - write content or append content to a (existing or new) file.
# - *read - Read file content into a variable (scalar or data structure for JSON, YAML, ...)
# 
package DPUT;
use strict;
use warnings;

use Exporter 'import';
use JSON;
use Data::Dumper;
## Make thes also runtime wide global
$Data::Dumper::Indent = 1;
$Data::Dumper::Terse = 1;
use File::Find;
use File::Spec;

use Scalar::Util ('reftype');
our @EXPORT = ('jsonfile_load', 'jsonfile_write', 'file_write', 'file_read', 'dir_list', 'domainname', 'require_fastjson', 'file_checksum', 'isotime');
our $VERSION = "0.0.2";

##### Reading and wring files
my $okref = {'HASH' => 1, 'ARRAY' => 1,};
# ## jsonfile_load($fname, %opts)
# Load a JSON data from a file ($fname).
# There is no constraint of what type (array, object) the "data root" is.
# Allow options:
# - 'stripcomm' - Strip comments by RegExp pattern given. The regular expression substitution
#   is run across the whole JSON string content before parsing is called.
# 
sub jsonfile_load {
  my ($fname, %opts) = @_; # $fname_or_cont, 
  #my $cont = '';
  # TODO: Additional checks
  #if ($fname_or_cont !~ /\n/) {
  #  #my $fname = $fname_or_cont;
  #  $cont = file_read($fname_or_cont); # Treat as filename
  #  # TODO: Pass also raw lines to caller (via scalar ref) - BUT LATER
  #}
  #else {$cont = $fname_or_cont; }
  my $cont = file_read($fname);
  if ($opts{'contref'}) {} # TODO: !
  if ($opts{'stripcomm'}) {
    
    my $re = qr/$opts{'stripcomm'}/;
    #print(STDERR "Stripping comments by string re: '$opts{'stripcomm'}', Compiled: $re\n");
    $cont =~ s/$re//gm;
  }
  my $j;
  eval { $j = from_json($cont); };
  if ($@) { die("jsonfile_load: from_json: Problems parsing JSON: $@\n"); }
  return $j;
}
# ## jsonfile_write($fname, $ref, %opts);
# Write JSON file.
# By default the formatting is done "pretty" way (not single-line whitespace stripped).
# This is basically a shorthand form of: `file_write($fname, $datatree, 'fmt' => 'json');`
# However this mandates $datatree parameter in above to be a reference to either
# HASH or ARRAY (as writing a scalar number or string as JSON is niche thing to do).
sub jsonfile_write {
  my ($fname, $ref, %opts) = @_;
  # Check reference
  my $rt = reftype($ref); # reftype() ?
  if (!$okref->{$rt}) { die("data must be either HASH or ARRAY");}
  return file_write($fname, $ref, 'fmt' => 'json');
}

# ## file_write($fname, $cont, %opts)
# Write content (or data structure) to a file.
# By default writing happens in non-appending / overwriting mode.
# If content is a reference it is stored in one of the data structure based formats (json,perl,yaml) - see 'fmt' below.
# Options in %opts:
# - append - append to existing file content (opens file in append-mode)
# - fmt - Format to serialize content to when the $cont parameter is actually a (data structure) reference
#   Formats supported are: 'json', 'yaml' and 'perl' (Default: 'json')
# - lines - Lines in array(ref) passed in $cont should be written to file. Each of lines will be terminated with "\n".
# 
# Perl format is written with small indent and no perl variable name (e.g. $VAR1)
# JSON is written in "pretty" format assuming it benefits out of human readability.
# Return $ok (actually number of bytes written)
sub file_write {
  my ($fname, $cont, %opts) = @_;
  if ($fname =~ /\n/) { die("Filename corrupt (name is multi-line - do you filename, content params swapped) !"); }
  if (!defined($cont)) { die("Content is not defined (even empty content is okay)\n"); }
  my $mode = $opts{'append'} ? '>>' : '>';
  my $fh;
  if ($fname eq '-') { $fh = *STDOUT; } # Allow write to STDOUT
  else {
    my $ok = open($fh, $mode, $fname);
    if (!$ok) { die("Failed to open '$fname': $!\n"); }
  }
  #FILEOPENED:
  # Got data structure
  my $fmt = $opts{'fmt'} || 'json';
  my $ref = ref($cont);
  if ($ref && ($ref eq 'ARRAY') && $opts{'lines'}) {
    $cont = join("\n", @$cont)."\n";
  }
  elsif ($ref && ($fmt eq 'json')) {
    $cont = to_json($cont, {canonical => 1, pretty => 1, convert_blessed => 1});
  }
  elsif ($ref && ($fmt eq 'yaml')) {
    require("YAML.pm"); # Lazy-load YAML;
    $cont = YAML::Dump($cont);
  }
  elsif ($ref && ($fmt eq 'perl')) {
    $cont = Data::Dumper::Dumper($cont);
  }
  elsif ($ref) { die("Format '$fmt' not supported !"); }
  my $cnt;
  $cnt = print($fh $cont);
  #DONEWRITE:
  #if ($cnt != length($cont)) {}
  if ($fname ne '-') { close($fh); }
  return $cnt;
}

# ## DPUT::file_read($fname, %opts)
# Read file content from a file by $fname.
# Options in opts:
# - 'lines' - Pre-split to lines and return array(ref) instead of scalar content
# - 'rtrim' - Get rid of trailing newline
# Return file content as scalar string (default) or array(ref) (with option 'lines')
sub file_read {
  my ($fname, %opts) = @_;
  if ($fname =~ /\n/) { die("Filename corrupt !");}
  if (!-f $fname) { die("file_read: File by name '$fname' does not exist for reading."); }
  
  my $fh;
  my $ok = open($fh, "<", $fname);
  if (!$ok) { die("file_read: File by name '$fname' not opened !"); }
  my $cont;
  if ($opts{'lines'}) {
    my @lines = <$fh>;
    if ($opts{'rtrim'}) { chomp(@lines); } # Chomp / trim
    $cont = \@lines;
  } 
  else { local $/ = undef(); $cont = <$fh>; }
  close($fh);
  return $cont;
}
# ## DPUT::dir_list($path, %opts)
# List a single directory or subdirectory tree.
# $path can be any resolvable path (relative or absolute).
# Options:
# - 'tree' - Create recursive listing
# - 'preprocess' - File::Find preprocess for tree traversal (triggered by 'tree' option)
# - 'abs' - Return absolute paths
# Return the files as array(ref)
sub dir_list {
  my ($path, %opts) = @_;
  #my @files;
  if ($opts{'tree'}) {
    my $follow = $opts{'follow'} || 1;
    my @files;
    # Option 'no_chdir' makes $_ be == $File::Find::name
    sub wanted {
      no warnings 'all'; # local $SIG{__WARN__} = sub { };
      my $fn = $File::Find::name; # Originally Absolute
      if (!$opts{'abs'}) { $fn = File::Spec->abs2rel($fn , $path ); } # Normalize (strip) to relative
      $opts{'debug'} && print(STDERR "Found: $fn\n");
      push(@files, $fn);
    }
    
    my $ffopts = { "wanted" => \&wanted, "follow" => $follow, 'no_chdir' => 1};
    find($ffopts, $path);
    return \@files;
  }
  my $ok = opendir(my $dir, "$path");
  if (!$ok) { die("Failed to open dir '$path' !"); }
  my @files = readdir($dir); # Actually files AND dirs
  closedir($dir);
  # Possible filtering ...
  @files = grep({!/^\.\.?$/} @files);
  if ($opts{'abs'}) { map({"$path/$_"} @files); } # Map to abs names
  return \@files;
}
## Do flexible path prefixing
sub dir_list_path_prefix {
  my ($list, $prefix) = @_;
  # Check that we do not place extra slashes (mostly for cosmetics)
  if ($prefix =~ /\/+$/) { $prefix =~ s/\/+$//; }
  @$list = map({"$prefix/$_"} @$list);
}

# ## domainname()
# Probe current DNS domainname (*not* NIS domainname) for the host app is running on.
# Return full domain part of current host (e.g. passing host.example.com => example.com).
sub domainname {
  my $domn = Net::Domain::hostdomain();
  # Need to strip something in case of Windows ?
  return $domn;
}

# ## DPUT::require_fastjson(%opts)
# Mandate a fast and size-scalable JSON parser/serializer in current runtime.
# Our biased favorite for this kind of parser is JSON::XS.
# Option 'probe' does not load (and possibly fail with exception)
# Return true value with version of JSON::XS on success, or fail with exception.
# If option 'probe' was passed, only detection of JSON::XS presence from current runtime is done
# and no exceptions are ever thrown.
sub require_fastjson {
  my (%opts) = @_;
  my $ver = $JSON::XS::VERSION;
  # Success for probe or just having the module already loaded.
  if ($opts{'probe'} || $ver) { return $ver; }
  eval { require("JSON/XS.pm"); };
  if ($@) { die("JSON::XS Could not be loaded"); }
  $ver = $JSON::XS::VERSION;
  return $ver;
}
# ## DPUT::file_checksum($fname, %opts)
# Extract MD5 checksum (default) from a file.
# Doing this inline in code is slightly tedious. This works well as a shortcut.
# Checksumming is still done efficiently by bot loading the whole content into memory.
# Return MD5 Checksum.
sub file_checksum {
  my ($fname, %opts) = @_;
  #NOT:$digest = md5_hex($data);
  # TODO:
  # - Support sha1, sha256. See respective modules
  # - Load modules lazily on demand or just check presence in RT.
  #if ($opts{'type'}) {}
  my $ctx = Digest::MD5->new();
  # Keep this done via filehandle and *not* by loading full content - all in hopes
  # of filehandle method being MUCH more memory efficient.
  my $ok = open(my $fh, "<", $fname);
  if (!$ok) { die("Could not open '$fname' for checksumming\n"); }
  $ctx->addfile($fh);
  my $digest = $ctx->hexdigest();
  close($fh);
  return $digest;
}
# ## DPUT::isotime($time)
# Generate local ISO timestamp for current moment in time or for another point in time - with optional $time parameter.
sub isotime {
   my @t = localtime($_[0] ? $_[0] : time());
   return sprintf("%.4d-%.2d-%.2d %.2d:%.2d:%.2d",
     $t[5]+1900, $t[4]+1, $t[3], $t[2], $t[1], $t[0],
    );
}
#################################### TABULAR FILES: CSV, XLSX ################################################
## # Tabular files processing (CSV, XLSX)
## 
## Create easily/natively processable AoH Objects out of popular data formats.
## DPUT couples you to neither of the modules Test::CSV or Spreadsheet::XLSX but they must be loaded by app
## (see examples below).
## Only their *methods* will be called in here (with late binding).
## For the column headers for these tabular files (first valid line of the table) there are typically 3 scenarios:
## - The first line contains headers and headers are usable as-is - no need to use 'cols' parameter
## - File content has NO headers and columns must be named by API caller - use `'cols' => [...]` to name columns
## - The first line contains headers, but they are NOT usable as-is (e.g. they have spaces, are too long or
##   there's some other annoyance about them) - use `'cols' => [...]` to name columns *AND* use `'striphdr' => 1` to
##   eliminate headers from data.

# ## DPUT::csv_to_data($csv, $fh, %opts);
# Extract data from CSV file by passing Text::CSV processor instance and filehandle (or filename) to load data from.
# Options:
# - cols - Pass explicit column names, do not extract column names from sheet (or map to new names)
# - striphdr - Strip first entity extracted when explicit column names ('cols') are passed
# Example CSV extraction scenario:
# 
#     use Text::CSV; 
#     my $csv = Text::CSV->new({binary => 1});
#     if (!$csv) { die("No Text::CSV processor instance"); }
#     my $ok = open(my $fh, "<", "animals.csv");
#     my $arr = DPUT::csv_to_data($csv, $fh, 'cols' => undef);
#     print(Dumper($arr));
sub csv_to_data {
  my ($csv, $fh, %opts) = @_;
  if (!$csv) { die("No Text::CSV instance passed !"); }
  if (!$fh) { die("No open file handle (or name) passed !"); }
  # $fh seems to be a filename ...
  my $fh2;
  if (!ref($fh)) { open($fh2, '<', $fh) || die("File '$fh' not opened"); $fh = $fh2; }
  my $cols = $opts{'cols'};
  my $i=0;
  if (!$cols) {
    $cols = $csv->getline($fh);
    $i++;
    # Validate as cols ?
  }
  if (!$cols) { die("No columns to transform to AoH"); }
  if (ref($cols) ne 'ARRAY') { die("Columns not in ARRAY !"); }
  my @arr = ();
  my $vcb = $opts{'validcb'};
  while (my $row = $csv->getline($fh)) {
    my %h = ();
    my ($hc,$vc)= (scalar(@$cols), scalar(@$row));
    if ($hc != $vc) {
      #print(Dumper($row)); # Usually ['']
      # The check below has shown to be excessively strict.
      #die("Mismatch in col counts (hdr:$hc, row vals:$vc)- on row $i check your CSV content!"); # Strict col count matching !
      last; # Quit at first non-matching row. Usually this is the correct thing to do and safe in any case.
    }
    @h{@$cols} = @$row;
    if ($vcb && !$vcb->(\%h) ) { next; }
    push(@arr, \%h);
    $i++;
  }
  if ($fh2) { close($fh2); }
  if ($opts{'striphdr'}) { shift(@arr); }
  if (!$opts{'fullinfo'}) { return(\@arr); }
  return {'data' => \@arr, 'cols' => $cols};
}
# ## DPUT::sheet_to_data($xlsx_sheet, %opts);
# Extract data from XLSX to Array of Hashes for processing
# The data is passed as single Spreadsheet::ParseExcel::Worksheet sheet object.
# Options:
# - debug - Turn on verbose messages
# - cols - Pass explicit column names, do not extract column names from sheet (see also: striphdr)
# - striphdr - Strip first entity extracted when explicit column names ('cols') are passed
# Example CSV extraction scenario:
#
#     my $converter = Text::Iconv->new ("utf-8", "windows-1251");
#     my $excel = Spreadsheet::XLSX->new("animals.xlsx", $converter);
#     my $sheet = $excel->{Worksheet}->[0]; # Choose first sheet
#     my %xopts = ('debug' => 1, 'fullinfo' => 1);
#     $aoh = DPUT::sheet_to_data($sheet, %xopts);
#     print(Dumper($aoh));
#
# Return Array of Objects contained in the sheet processed.
sub sheet_to_data {
  my ($sheet, %opts) = @_;
  my @aoo = ();
  if (!$sheet) { die("No XLSX Sheet passed"); }
  $opts{'debug'} && print("Got sheet: $sheet\n");
  # my @cols = ();
  my ($minc, $maxc) = ($sheet->{MinCol}, $sheet->{MaxCol});
  my $cols = $opts{'cols'};
  my $startrow = $sheet->{MinRow};
  # Header cols not given - extract them
  if (!$cols) {
    @$cols = map({ $sheet->{Cells}->[$startrow]->[$_]->{'Val'}; } ($minc .. $maxc));
    $startrow++;
  }
  foreach my $row ($startrow .. $sheet->{MaxRow}) {    
    $sheet->{MaxCol} ||= $sheet->{MinCol};
    my %e = ();
    foreach my $col ($sheet->{MinCol} ..  $sheet->{MaxCol}) {
      my $cell = $sheet->{Cells}->[$row]->[$col];
      my $colname = $cols->[$col];
      $e{$colname} = $cell->{'Val'};
    }
    push(@aoo, \%e);
  }
  if ($opts{'striphdr'}) { shift(@aoo); }
  if (!$opts{'fullinfo'}) { return \@aoo; }
  return {'data' => \@aoo, 'cols' => $cols};
}
# ## $creds = netrc_creds($hostname, %opts);
# Extract credentials (username and password) for a hostname.
# The triplet of hostname, username and password will be returned as an object with:
#      {
#        "host" => "the-server-host.com:8080",
#        "user" => "jsmith",
#        "pass" => "J0hNN7b07"
#       }
# Options in %opts:
# - debug - Create dumps for dev time debugging (Note: this will potentially show secure data in logs)
# Return a complete host + credentials object (as seen above) - that is hopefully usable
# for establishing connection to the remote sever (e.g. HTTP+REST, MySQL, MongoDB, LDAP, ...)
sub netrc_creds {
  my ($hostname, %opts) = @_;
  my @locs = ("$ENV{HOME}/.netrc", "$ENV{HOMEDRIVE}$ENV{HOMEPATH}.netrc");
  my @locs2 = grep({ -f $_; } @locs);
  if (!@locs2) { die("netrc_creds(): No .netrc found (from @locs)"); }
  # my $lines; my @$lines = DPUT::file_read($locs2[0], 'lines' => 1, rtrim => 1);
  my $ok = open(my $fh, "<", $locs2[0]);
  if (!$ok) { die("Could not open file"); }
  my @lines = <$fh>;
  close($fh);
  chomp(@lines);
  if ($opts{'debug'}) { print(Dumper(\@lines)); }
  my $re = qr/^machine\s+$hostname\b/;
  @lines = grep({ /$re/; } @lines);
  my $cnt = scalar(@lines);
  if (!$cnt)    { die("No credentials found for '$hostname'"); }
  if ($cnt > 1) { die("Multiple Credentials ($cnt) found for '$hostname'"); }
  my $creds = {'host' => $hostname, "user" => '', "pass" => ''};
  if ($lines[0] =~ /\blogin\s+(\S+)/)    { $creds->{'user'} = $1; }
  if ($lines[0] =~ /\bpassword\s+(\S+)/) { $creds->{'pass'} = $1; }
  return $creds;
}

#################################################################################################
# ## DPUT::filetree_filter_by_stat($dirpath, $filtercb, %opts);
# Collect a list of ("filtered-in") files from a directory tree based on stat results.
# Creates a list of filenames that filter callback indicates as "matching".
# Caller should pass:
# - $dirpath - Path to look for files
# - $filtercb - Callback returning true (to include) / false (to exclude) values like a normal filter function fashion.
#    Filter callback receives stat array (as reference) and absolute filename of current file as parameters.
# - %opts Processing options
#   - useret - Place return value of callback to file list generated (instead of default, which is filename)
# Using 'useret' means that filtercb function is written so that it returns a custom values that will be placed in results.
# Return list of filenames or custom callback generated objects / items.
sub filetree_filter_by_stat {
  if (!$File::Find::VERSION) { eval("use File::Find;"); }
  my ($path, $filtercb, %opts) = @_;
  if (!-d $path) { die("path param must be an existing directory !"); }
  if (ref($filtercb) ne 'CODE') { die("No callback as CODE (ref)"); }
  my @files = ();
  my $localcb = sub {
    my $an = $File::Find::name;
    my @s = stat($an);
    # TODO: Check if dir and not accessible. Otherwise File::Find
    # Permission denied warning in STDOUT. Processing here does not seem to help.
    # if ((-d $an) && (!-r $an) && (!-x $an)) { return 0; }
    my $rv = $filtercb->(\@s, $an);
    if ($rv) {
      if ($opts{'useret'}) { push(@files, $rv); }
      else { push(@files, $an); }
    }
  };
  File::Find::find({ 'wanted' => $localcb, 'follow' => 0, 'no_chdir' => 1}, $path);
  return \@files;
}

## Plan for extracting a "processing context" with
## - hostname - Fully qualified hostname (by Net::Domain)
## - dnsdomain - DNS domain
## - exe - Executable name (or basename ?)
## - pid - Process id - Process id of the current process
## - time Time when processing context was extracted - usually at the start of execution
##    usable for reflecting the start of processing (e.g. for later calculating how long processing has run)
## Options:
## - env - Inclusion of env - copy => make a copy of environment, none => No 'env' variable map at all
## - nis - Include nis domain info (Must have Net::NIS)
## The runtime of interpreter has already info most of these things, 
## TODO:Provide also a blessed version with methods.
## TODO: Move to DPUT::ProcCtx
## TODO: Create is_win() wrapper for detecting windows run
## TODO: Provide sub TO_JSON {} to serialize blessed to JSON
## TODO: Possibly env=none, env=copy
## See also: Net::Domain, Sys::Hostname, Net::NIS, https://perldoc.perl.org/perlvar.html
sub procctx {
  my (%opts) = @_;
  #if (!%opts) { $opts = (); }
  eval "use Net::Domain;use Storable;";
  my $pc = {
    'pid' => $$, # Process ID
    'exe' => $0, # Optionally basename or relative to ... ?
    #'hostname' => Sys::Hostname::hostname(),
    'hostname' => Net::Domain::hostfqdn(), # Full
    'dnsdomain' => Net::Domain::hostdomain(),
    'uid' => $<,
    'gid' => $(,
    'env' => (($opts{'env'} eq 'copy') ? Storable::dclone(\%ENV) : \%ENV),
    'osname' => $^O,
    # 'ver' => $^V, ## Non-portable - 5.10.0 changes string to object
  };
  if ($opts{'env'} eq 'none') { delete($pc->{'env'}); }
  if ($opts{'nis'}) { $pc->{'nisdomain'} = Net::NIS::yp_get_default_domain(); }
  return $pc;
}

## DPUT::named_parse($re, $str, $names);
## 
## Parse captures in regexp into an hash / object key-value pairs by:
## - $re - Regexp with capturing parenthesis - number of which should match number of names
## - $str - String to parse from
## - $names - array(ref) of names to use as keys of object
##
## Example:
##     my $re = qr/v?(\d+)\.(\d+)\.(\d+).*/;
##     my $verstr = "v2.6.7-patch87";
##     my $v = DPUT::named_parse($re, $verstr, ['major','minor','patch']);
##     if (!$v) { die("Could not extract version"); }
##     print(Dumper($v)); # 
## 
## TODO: Config option for starting at $0
## TODO: Allow multiline ?
sub named_parse {
  my ($re, $str, $names) = @_;
  if (!$re) { die("No regexp"); }
  if (!$names) { die("Missing names (to use as keys)!"); }
  if (ref($names) ne 'ARRAY') { die("names (to use as keys) not in Array"); }
  if ($str =~ /$re/mg) {
    my $vals = [$1, $2, $3, $4, $5, $6, $7, $8, $9];
    #if ($opts{'capall'}) { push(@$vals, $0); }
    my $o = {};
    my $cnt = scalar(@$names);
    for (my $i = 0;$i < $cnt;$i++) { $o->{$names->[$i]} = $vals->[$i]; }
    return $o;
  }
  return undef;
}

## Experimental to allow easy conversion of time + unit spec to seconds.
## Converts a human-friendly time specification with quantity and unit notation (e.g. "2d" for 2 days)
## to seconds for computer-friendly processing.
## Options:
## - ms - Convert to milliseconds instead of usual seconds (basically dur_s *= 1000)
my $tupatt = qr/^\s*(\d+)\s*([wdhms]){1}$/; # Note: m != month
sub timestr2secs {
  my ($tustr, %opts) = @_;
  if ($tustr !~ /$tupatt/) { return undef; }
  my %tus = (
    "s" => 1,
    "m" => 60,
    "h" => 3600,
    "d" => 86400,
    "w" => 604800,
  );
  if (!$tus{$2}) { return undef; }
  my $secs = $1 * ($tus{$2});
  return $secs;
}
# ## DPUT::testsuites_parse($path, %opts)
# 
# Parse xUnit XML test result files by name pattern (default '\w\.xml$').
# Return files as data structure (for generating report or other kind of presentation).
# Options in %opts
# - debug - Output verbose info on processing
# - patt - RegExp pattern for filenames to include as xUnit test results (default: '\w+\.xml$)
# - tree - Do recursive directory scan for test result files
# 
# ### Example
# 
# Full Blown template based tests results processing (on API level, with error checks):
# 
#     use DPUT;
#     use Template; # An example templating engine
#     my $testpath_top  = "./tests"; # Dirtree to scan from (See below: 'tree' => 1)
#     my $test_out_html = "./tests/all_results.html";
#     my $test_out_json = "./tests/all_results.json";
#     my $test_tmpl     = "/place/for/tmpl/xunit.htreport.template";
#     if (! -f $test_tmpl) { print("No Test Report Template !\n"); }
#     # Process ! 'tree' => 1 - recursive
#     my $suites = DPUT::testsuites_parse($testpath_top, 'tree' => 1);
#     if (!$suites) { print(STDERR "Test File search / parsing failed"); }
#     my $cnt_tot = DPUT::testsuites_test_cnt($suites);
#     my $out = ''; # Template toolkit output var
#     # Template parameters and template
#     my $p = {'all' => $suites, "title" => "Build ... test results", "cnt_tot" => $cnt_tot};
#     my $tmpl = DPUT::file_read($test_tmpl);
#     if (!$tmpl) { print(STDERR "Test HTML template loading failed"); }
#     # Run templating (using params and loaded template)
#     my $tm = Template->new({}); # Empty config (seems to work)
#     my $ok = $tm->process(\$tmpl, $p, \$out);
#     if (!$ok) { print(STDERR "Test HTML Report generation failed"); }
#     # Write both HTML and JSON
#     DPUT::file_write($test_out_html, $out); # HTML report
#     DPUT::file_write($test_out_json, $suites, 'fmt' => 'json'); # JSON (serializes json automatically)
#     
# ## Info on xUnit/jUnit format:
# 
# - https://llg.cubic.org/docs/junit/
# - https://www.ibm.com/support/knowledgecenter/SSQ2R2_9.1.1/com.ibm.rsar.analysis.codereview.cobol.doc/topics/cac_useresults_junit.html
# 
# 
sub testsuites_parse {
  my ($path, %opts) = @_;
  my $patt = $opts{'patt'} || '\w+\.xml$';
  my $re = qr/$patt/;
  my $debug = $opts{'debug'};
  my %diropts = ('tree' => ($opts{'tree'} || 0));
  my $list = DPUT::dir_list($path, %diropts);
  #print("$re\n");
  $opts{'debug'} && print(Dumper($list));
  my @props = ("tests", "time", "name", "disabled", "errors", "failures", "timestamp");
  # Map and filter result files into final list of result files
  my @list2 = map({ ($_ =~ /$re/g) ? {'absfn' => "$path/$_", 'fn' => $_ }: (); } @$list);
  $opts{'debug'} && print(Dumper(@list2));
  eval("use XML::Simple;"); # Lazy-load
  my %xopts = ( 'ForceArray' => ['testsuite', 'testcase'], 'KeyAttr' => undef );
  my @suites = (); # Suites to collect
  foreach my $f (@list2) {
    my $x = XMLin($f->{'absfn'}, %xopts);
    if (!$x) { next; }
    # Others: name, time, errors, failures
    # NOTE: Both testsuites and testsuite should have "tests"
    if (!$x->{'tests'}) { print(STDERR "Warning: does not look like xUnit results file\n"); next; }
    # Autodetect missing **testsuites** (optional) top-level element (Need keepRoot ?). Was originally required.
    # Generate/Nest (wrapping) **testsuites** element  if not present in XML. Detect by "testcase" located directly under top.
    my $tcs = $x->{'testcase'};
    if ($tcs) {
      
      #DEBUG: map({ delete($_->{'system-out'}); delete($_->{'system-err'}); delete($_->{'failure'}); } @$tcs);
      #DEBUG: print("Got testcase on top !\n"); print(Dumper($x->{'testcase'})); # exit();
      my $x2 = {}; # New top
      map({ $x2->{$_} = $x->{$_}; } @props); # print("Copy $_\n");
      $x2->{'testsuite'} = [$x]; # MUST be array
      $x = $x2;
    }
    # NOTE: Innermost "testcase" element may have a nested "error", "failure" or "skipped" element, how to deal with these ?
    $x->{'resfname'} = $f->{'fn'};
    # TODO: Iterate cases and if "skipped" property is found, set status = skipped
    # NOT: $tcs = $x->{"testsuite"}->{""}
    foreach my $s (@{$x->{"testsuite"}}) {
      foreach my $c (@{$s->{'testcase'}}) {
        if ($c->{'skipped'}) { $c->{'status'} = "skipped"; }
        #if ($c->{'failure'}) { $c->{'status'} = "snafu"; }
      }
    }
    $debug && print(STDERR Dumper($x));
    
    push(@suites, $x);
  }
  return(\@suites);
}
# ## DPUT::testsuites_test_cnt(\@suites)
# 
# Find out the total number of individual tests in results as parsed by DPUT::testsuites_parse(...)
# Return total number of tests.
sub testsuites_test_cnt {
  my ($suites) = @_;
  my $cnt = 0;
  if (ref($suites) ne 'ARRAY') { die("Suites not in array for test counting !"); }
  map({ $cnt += $_->{'tests'}; } @$suites);
  return $cnt;
}
# ## DPUT::testsuites_pass_fail_cnt(\@suites, %opts)
# 
# Find out the numers of passed and failed tests in results as parsed by DPUT::testsuites_parse(...).
# With $opts{'incerrs'} errors are also included to statistics.
# Return and hash object(ref) with members pass, total and fail (and optionally 'errs').
sub testsuites_pass_fail_cnt {
  my ($suites, %opts) = @_;
  my $r = {'pass' => 0, 'fail' => 0};
  if (ref($suites) ne 'ARRAY') { die("Suites not in array for test counting !"); }
  my $cnt = 0;
  map({
    $cnt += $_->{'tests'};
    #print("Suite: $_->{'resfname'}\n");
    #print(Dumper($_)); # suite
    $r->{'fail'} += int($_->{failures});
    $r->{'errs'} += int($_->{errors});
    # NOTHERE: $r->{'pass'} += (int($_->{tests}) - int($_->{'failures'}));
  } @$suites);
  $r->{'pass'} = $cnt - $r->{'fail'};
  $r->{'total'} = $cnt;
  if (!$opts{'incerrs'}) { delete($r->{'errs'});}
  return $r;
}

# ## DPUT::path_resolve($path, $fname, %opts)
# 
# Look for file (by name $fname) in path by name $path.
# $path can be passed as array(ref) of paths or as a colon delimited path string.
# Resolution stops normally at the first matching path location, even if later
# paths would match. Option $opts{'all'} forces matching to return all candidates
# and coerces return value to array(ref).
# 
# $fname can also directory name as 
# 
# Examples:
#     # Find finding / resolving "my.cnf" from 2 alternative dirs
#     my $fname_to_use = DPUT::path_resolve(["/etc/", "/etc/mysql"], "my.cnf");
#     # ... is same as (whichever is more convenient)
#     my $fname_to_use = DPUT::path_resolve("/etc/:/etc/mysql", "my.cnf");
#     # which ls ?
#     my $fname_to_use = DPUT::path_resolve($ENV{'PATH'}, "ls");
#     # filename can be relative (with path component) too
#     my $fname_to_use = DPUT::path_resolve(["/etc/","/home/mrsmith"], "myapp/main.conf");
#   
sub path_resolve {
  my ($path, $fname, %opts) = @_;
  $path = (ref($path) eq 'ARRAY') ? $path : [split(":", $path)];
  if (ref($path) ne 'ARRAY') { die("Could not turn path to array"); }
  my @m = grep({-e "$_/$fname" ? 1 : 0; } @$path);
  
  if (!@m) { return undef; }
  elsif ($opts{'all'}) { return \@m; }
  return $m[0];
}

1;
