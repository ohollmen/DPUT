package DPUT::ToolProbe;
use strict;
use warnings;
use Storable;

# # DPUT::ToolProbe - Detect command-line tool versions
# 
# Probes version of a CL tool based on the universally accepted **--version** command line flag
# supported by about every open source tool.
#
# ## Tool definitions
# 
# Tool definition consists of following members:
# - cmd - The command (basename) for tool (e.g. 'perl', without path)
# - patt - Regular expression for detecting and extracting version from version info output
# - stderr - Flag for extracting version information from stderr (instead of default stdout)
#
# ## Adding new tool definitions
# 
# The module comes with a basic set of tool definitions
# Note, this is kept module-global to allow simple
# additions by (e.g.):
# 
#     push(@{$SWBuilder::toolprobeinfo}, {"cmd" => "repo", "" => ""})
# 
# # Note on $PATH
# 
# This module is reliant on the `which` utility that uses `$PATH` to see which actual executable and from which path is
# going to be run for the basename of particular command.
# The reported results of ToolProbe are only valid for the $PATH that was used at the time of detection. If $PATH changes,
# the results may change.
# 
# # TODO
# 
# - Consider adding (or just documenting) semantic versioning functionality to compare extracted version
# to some feature "threshold version" (i.e. version > 1.5.5 supports shortcut feature X and in versions below
# that we have to multiple steps to accopmlish the same result).
# - Consider turning toolinfo report to new (more comprehensive) format recording also the $PATH based on
#   which tool detection was done.
our $toolprobeinfo = [
  {"cmd" => "python", "patt" => "^Python\\s+(.*?)\$", "reopt" => "s", 'stderr' => 1},
  {"cmd" => "perl",   "patt" => "\\(v([\\d\.]+)\\)", "reopt" => "s"},
  {"cmd" => "git",    "patt" => "git version\\s+([\\d\.]+)", "reopt" => "s"},
  {"cmd" => "make",   "patt" => "GNU Make\\s+([\\d\.]+)", "reopt" => "s"},
  {"cmd" => "gcc",    "patt" => "gcc.+?([\\d.]+)\$", "reopt" => "m"}, # Important to have non-greedy !
  {"cmd" => "docker", "patt" => "\\bversion\\s+([\\d\\.]+)", "reopt" => "m"},
  # 
  #{"cmd" => "nmake",    "patt" => "Version (.*?)\$", "reopt" => "s"}, # 'vopt' => '',
];

# Set by $DPUT::ToolProbe::debug =1;
our $debug = 0;
our $VERSION = "0.01";

# ## DPUT::ToolProbe::add($newtool)
# 
# Convenience method for adding a new tool definition.
# Definition is added to the class -held defintion collection
# variable ($toolprobeinfo) with validation. Same as
# 
#     push(@$DPUT::ToolProbe::toolprobeinfo, $newtool);
# 
# Except the latter low level way does not validate %$$newtool.
# Example of use:
# 
#     my $newtool = {"cmd" => "ls", "patt" => "(\d+)\.(\d+)"};
#     DPUT::ToolProbe::add($newtool)
#
sub add {
  my ($newtool) = @_;
  if (!$newtool->{'cmd'})   { die("No tool command");}
  if (!$newtool->{'patt'})  { die("No Version Extraction pattern !");}
  if (!$newtool->{'reopt'}) { $newtool->{'reopt'} = 's'; } # Default to 's'
  push(@$toolprobeinfo, $newtool);
}
# Create RegExp for tool definition based on Regexp options ('reopt').
sub make_re {
  my ($p) = @_;
  my $reopt = $p->{'reopt'};
  if (!$p->{'patt'}) { die("No pattern - cannot make RegExp !");}
  if ($reopt eq 's') { return qr/$p->{'patt'}/s; }
  if ($reopt eq 'm') { return qr/$p->{'patt'}/m; }
  return qr/$p->{'patt'}/;
}
# ## DPUT::ToolProbe::detect(%opts)
# 
# Probe tool command version and path from which it was found.
# This happens for all the tools registered (See doc on how to add more tools).
# Assume tools to support conventional --version option.
# 
# Options:
# - dieonmissing - Trigger an exception on *any* missing tool
# - hoh - produce report in pre-indexed "hash of hashes" format (indexed by 'cmd' for fast lookup by command name)
# 
# Return an hash of hashes containing:
# - outer keys reflecting the tool name (from tool probe info $tool->{'cmd'})
# - inner object containing members:
#   - path - Full path to tool
#   - version - Version of the tool (extracted)
# 
# If tool is missing 'path' and 'version' it could not be found in the system.
# 
sub detect {
  my (%opts) = @_;
  #my ($addlitems) = @_; # Additional items ?
  #OLD:my $info = {};
  #OLD:my $infos = $toolprobeinfo; # Deep copy ?
  my $infos = Storable::dclone($toolprobeinfo);
  # TODO: Allow passing the executable basename:s for ONLY the tools that we want to detect.
  # Override @$infos above by transforming original array
  #my $tools = $opts{'tools'};
  #if ($tools && (ref($tools) eq 'ARRAY')) {
  #  %toolidx = map({ ($_, 1); } @$tools);
  #  @$infos = map({$toolidx{ $_->{'cmd'} } ? 1 : 0; } @$infos);
  #}
  my @nrattrs = ('patt','reopt','stderr',); # Non-reportable attributes
  foreach my $p (@$infos) {
    my $re = make_re($p); # qr/$p->{'patt'}/;
    my $cmd = $p->{'cmd'};
    # Find out absolute path
    my $fullpath = `which $p->{'cmd'}`;
    chomp($fullpath);
    if ($? || !$fullpath) {
      if ($opts{'dieonmissing'}) { die("Your system does not have tool '$p->{'cmd'}' (Check \$PATH)\n"); }
      next;
    }
    # Probe version
    my $toolvercmd ="$p->{'cmd'} --version";
    if ($p->{'stderr'}) { $toolvercmd .= " 2>&1"; }
    my $infostr = `$toolvercmd`; # 2> /dev/null
    if (!$infostr) { die("No tool info (for '$p->{'cmd'}') by '$toolvercmd' !"); }
    if ($debug) { print(STDERR "Complete output of '$toolvercmd': $infostr\n"); }
    if ($infostr =~ /$re/) { $infostr = $1; }
    else {die("'$p->{'cmd'}' - No version available by pattern '$p->{'patt'}'!");}
    #OLD: $info->{$cmd} = {'cmd' => $p->{'cmd'}, 'path' => $fullpath, 'version' => $infostr};
    $p->{'path'} = $fullpath; $p->{'version'} = $infostr;
    if ($opts{'terse'}) { map( { delete($p->{$_}); } @nrattrs); }
  }
  # Map into hoh format if requested ...
  # if ($opts{'hoh'}) { my %idx = map({($_->{'cmd'}, $_); } @$infos); return \%idx; }
  #OLD:return($info);
  return($infos);
}
1;
