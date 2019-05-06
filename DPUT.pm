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
