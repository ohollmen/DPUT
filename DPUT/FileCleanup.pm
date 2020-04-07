package DPUT::FileCleanup;
use File::Path;
use File::Basename;
use DPUT;
use Data::Dumper;
use strict;
use warnings;

# # DPUT::FileCleanup - Delete Files based on time and naming criteria
# 
# ## DPUT::FileCleanup->new($cfg)
# Instantiate file cleaner by a config profile with following config.
# 
# members in $cfg object:
# - path - Path to find files from
# - tspec - Time specifier with value and unit s,m,h,d,w (e.g. 20d for 20 days) to express file age boundary
# - npatt - Name pattern for files or dirs to include
# - type - Set to 'subdirs' to only look for dirs immediately under path (See find() method for more info)
# - debug - Turn on debugging during processing with various methods
# 
# Return File cleaner instance
sub new {
  my ($class, $cfg) = @_;
  
  if (!$cfg->{'path'}) { die("No path given !"); }
  # -d or -e (Consider symlinks)
  if (!-d $cfg->{'path'}) { die("path '$cfg->{'path'}' does not exist !"); }
  if (!$cfg->{'tspec'}) {die("No timespec (E.g. '7d' in 'tspec')"); }
  $cfg->{'files'} = []; # Init to empty
  # eval ?
  my %tsopts = ('debug' => ($cfg->{'debug'}), 'fcinst' => $cfg);
  $cfg->{'tfilter'} = gentimefilt($cfg->{'tspec'}, %tsopts);
  if (!$cfg->{'tfilter'} || (ref($cfg->{'tfilter'}) ne 'CODE')) {
    die("Time spec filter (callback) could not be generated (spec: $cfg->{'tspec'}).");
  }
  # NOT mandatory
  # if (!$cfg->{'npatt'}) { die("No name pattern available for cleanup"); }
  if (!$cfg->{'type'}) {$cfg->{'type'} = 'tree'; } # 'tree'
  bless($cfg, $class);
  
  return($cfg);
}

sub find_dirs {
  my ($prof) = @_;
  my $path = $prof->{'path'};
  # Do not use -d, could be a dir symlink 
  if (!-e $path) { die("Path '$path' does not exist"); }
  $prof->{'debug'} &&  print(STDERR "Find 'subdirs': $path\n");
  my $npatt = $prof->{'npatt'};
  my $files = DPUT::dir_list($path, ); # NOT: 'abs' => 1
  $prof->{'debug'} &&  print(STDERR scalar(@$files)." Files (pre-patt-filter)\n");
  # Do this early
  if ($npatt) { @$files = grep({/$npatt/} @$files); }
  #MUST: Add full path - ( 'abs' => 1 does not work as we filter on basename)
  @$files = map({"$path/$_"} @$files);
  $prof->{'debug'} &&  print(STDERR scalar(@$files)." Files (post-patt-filter by '$prof->{'npatt'}')\n");
  # Dumper($files)
  my @files = ();
  my $fcb = $prof->{'tfilter'};
  for my $fn (@$files) {

    my @s = stat($fn);
    # DEBUG:print("subdirs-FILE: $fn: ".Dumper($s)."\n");
    if (!-d $fn) { next; }
    my $ret = $fcb->(\@s, $fn);
    # DEBUG: my $ls = `ls -ald $fn`;
    # 'size' returned for files NOT applicable here.
    if ($ret) { push(@files, {"fn" => "$fn", "isdir" => 1, 'mtime' => DPUT::isotime($s[9]) }); } # 'ls' => $ls
  }
  return \@files;
}

# ## $fc->find()
# 
# Find files to cleanup.
# Finding files / dirs can be based on following approaches:
# 
# - Default: files (not dirs) recursively from configured 'path'
# - When cleanup config 'type' is set to 'subdirs', consider only subdires immediately under path
#   (where later deletion by rm() method will delete them recursively)
# 
# Return files found (and also store them internally to $fc instance).
sub find {
  my ($fc) = @_;
  my $files = [];
  if ($fc->{'type'} eq 'subdirs') { $files = $fc->find_dirs(); }
  # NOTE: tfilter must be written to return Object
  else {
    $files = DPUT::filetree_filter_by_stat($fc->{'path'}, $fc->{'tfilter'}, 'useret' => 1) || [];
    if ($fc->{'npatt'}) {
      @$files = grep({
        if (-d $_->{'fn'}) { 0; }
        else {
          my $bn = File::Basename::basename($_->{'fn'});
          if ($bn =~ /$fc->{'npatt'}/) { 1; }
          else { 0; }
        }
        
      } @$files);
      
    }
  }
  $fc->{'files'} = $files; # Also store
  return $files;
}

sub dump {
  my ($fc) = @_;
  print(Data::Dumper::Dumper($fc->{'files'}));
}
# ## $fc->rm(%opts)
# 
# Remove files or directories in the set passed as:
# - $opts{'files'} explicitly
# - Stored in $fc object internally by earlier call to find() method
# 
# Allow CB to be run just before delete
sub rm {
  my ($fc, %opts) = @_;
  my $files = $opts{'files'} || $fc->{'files'};
  if (!$files) { print(STDERR "No files (or dirs) to remove / delete !"); return; }
  my $safe = $fc->{'force'} ? 0 : 1;
  for my $fnode (@$files) {
    my $ok = 0;
    # File
    my $fn = $fnode->{'fn'};
    # Pre-del CB ?
    my $cb = ($fc->{'predel'} && (ref($fc->{'predel'}) eq 'CODE')) ? $fc->{'predel'} : undef;
    if ($cb) { $cb->($fnode); } # TODO: Define meaningful ret values ?
    my $type;
    if (-f $fnode->{'fn'}) {
      # print("DEL-FILE: $fn\n");
      $type = 'file';
      $ok = unlink($fnode->{'fn'});
    }
    elsif (-d $fnode->{'fn'}) {
      # print("DEL-DIR: $fn\n");
      $type = 'dir';
      $ok = File::Path::remove_tree($fnode->{'fn'}, {'safe' => $safe});
    }
    if (!$ok) { die("Error deleting $type '$fnode->{'fn'}' - $!  (quitting for perm. checks)\n"); }
  }
}
# ## gentimefilt($timestr, %opts)
# 
# Generate filter function for time based file list filtering.
# 
sub gentimefilt {
  my ($timestr, %opts) = @_;
  my $unit2s = {
    "s" => 1, "m" => 60, "h" => 3600, "d" => 86400, "w" => 604800,
  };
  if ($timestr =~ /^(\d+)([smhdw])$/) {
    # E.g. 2d => 2 * 86400
    my $tss = int($1) * $unit2s->{$2};  # Time spec in seconds
    # Keep track of tspec boundary
    my $ts = time() - $tss;
    my $iso = DPUT::isotime($ts);
    if ($opts{'debug'})  { print("Tspec: '$timestr', Older than: $iso\n"); }
    if ($opts{'fcinst'}) { $opts{'fcinst'}->{'iso'} = $iso; }
    # my $timesecs = 15552000; # Approx half year (in secs)
    return sub {
      my ($s, $fn) = @_;
      my $dt = time() - $s->[9]; # Age For file !
      my $sizelim = 10000000000;
      # print("$dt\n");
      #OLD: if ($fn =~ /\.backup$/ && ($s->[7] > $sizelim) && ($dt > ($halfyear) )) {
      if ($dt > $tss ) {
         return {'fn' => $fn, 'size' => $s->[7], 'mtime' => DPUT::isotime($s->[9])};
      }
      return undef;
    };
  }
  return undef; # None, undefined
}

# Test. TODO: Convert to actual utility
if ($0 =~ /FileCleanup.pm/) {
  print("Running the module ('$0')\n");
  $| = 1;
  my @optmeta = ("path=s", "tspec=s", "npatt=s", "debug");
  # GetOptions(\%opts, @optmeta); # 
  #my $cfg = {"path" => "/usr/lib/", "tspec" => "900d", 'npatt' => qr/\.so\b.*/, 'debug' => 1};
  #my $cfg = {"path" => "/usr/lib/", "tspec" => "900d", 'npatt' => "\.so\b.*", 'debug' => 1}; # String RE
  my $cfg = {"path" => "/usr/lib/", "tspec" => "300d", 'npatt' => ".*", 'type' => 'subdirs', 'debug' => 1}; # String RE + 'subdirs'
  my $fc = DPUT::FileCleanup->new($cfg);
  DEBUG: print(Dumper($fc));
  #exit(1);
  my $files = $fc->find() || [];
  #exit(1);
  print(scalar(@$files)." Files from '$cfg->{'path'}', type=$cfg->{'type'}\n");
  print(Dumper($files));
}

# ## TODO
# Allow alternative to time and pattern spec and let a callback handle selection for deletion.
1;
