# # DPUT - The most elementary Data processing utilities
#
# This module is not Object oriented in any way. It contains the most elementary operations like file reading/writing,
# listing directories (also recursively) on a very high level.
# 
# ## Reading and writing files
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
    if (!$ok) { die("Failed to open $fname"); }
  }
  #FILEOPENED:
  # Got data structure
  my $fmt = $opts{'fmt'} || 'json';
  my $ref = ref($cont);
  if ($ref && ($fmt eq 'json')) {
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
  my $cnt = print($fh $cont);
  #if ($cnt != length($cont)) {}
  if ($fname ne '-') { close($fh); }
  return $cnt;
}

# ## file_read($fname, %opts)
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
# ## dir_list($path, %opts)
# List a single directory or subdirectory tree.
# $path can be any resolvable path (relative or absolute).
# Options:
# - 'tree' - Create recursive listing
# - 'preprocess' - File::Find preprocess for tree traversal (triggered by 'tree' option)
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
      my $an = $File::Find::name;
      $opts{'debug'} || print("Found: $an\n");
      push(@files, $an);
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
  return \@files;
}
## Do flexible path prefixing
sub dir_list_path_prefix {
  my ($list, $prefix) = @_;
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

# ## require_fastjson(%opts)
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
# ## file_checksum($fname, %opts)
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
# ## isotime($time)
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
  my $ok = open(my $fh, "<", $locs2[0]);
  if (!$ok) { die("Could not open file"); }
  my @lines = <$fh>;
  close($fh);
  chomp(@lines);
  if ($opts{'debug'}) { print(Dumper(\@lines)); }
  # my $re = qr/^machine\s+$hostname\s+login\s+(\S*)\s+password\s+(\S*)$/;
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
# DPUT::filetree_filter_by_stat($dirpath, $filtercb, %opts);
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
  if (!$File::Find::VERSION) { eval("use File::Find"); }
  my ($path, $filtercb, %opts) = @_;
  if (!-d $path) { die("path param must be an existing directory !"); }
  if (ref($filtercb) ne 'CODE') { die("No callback as CODE (ref)"); }
  my @files = ();
  my $localcb = sub {
    my $an = $File::Find::name;
    my @s = stat($an);
    # TODO: Check if dir and not accessible. Otherwise File::Find
    # Permission denied warning in STDOUT. Processing here does not seen to help.
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
1;
