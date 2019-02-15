package DPUT::ToolProbe;
use strict;
use warnings;

# # Detect command-line tool versions
# # Tool definitions
# Tool definition consists of following members:
# - cmd - The command (basename) for tool (e.g. 'perl', without path)
# - patt - Regular expression for detecting and extracting version
# - stderr - Flag for extracting version info from stderr (instead of default stdout)
#
# # Adding new tool definitions
# The module comes with a basic set of tool definitions
# Note, this is kept module-global to allow simple
# additions by (e.g.):
# push(@{$SWBuilder::toolprobeinfo}, {"cmd" => "repo", "" => ""})
# 
# # Note on $PATH
# 
# This module is reliant on the `which` utility that uses `$PATH` to see which actual executable and from which path is
# going to be run for the basename of particular command.
# The reported results of ToolProbe are only valid for the $PATH that was used at the time of detection. If $PATH changes,
# the results may change.
# 
# # TODO
# Consider adding (or just documenting) semantic versioning functionality to compare extracted version
# to some feature "threshold version" (i.e. version > 1.5.5 supports shortcut feature X and in versions below
# that we have to multiple steps to accopmlish the same result).
our $toolprobeinfo = [
  {"cmd" => "python", "patt" => "^Python\\s+(.*?)\$", "reopt" => "s", 'stderr' => 1},
  {"cmd" => "perl",   "patt" => "\\(v([\\d\.]+)\\)", "reopt" => "s"},
  {"cmd" => "git",    "patt" => "git version\\s+([\\d\.]+)", "reopt" => "s"},
  {"cmd" => "make",   "patt" => "GNU Make\\s+([\\d\.]+)", "reopt" => "s"},
  {"cmd" => "gcc",    "patt" => "gcc.+?([\\d.]+)\$", "reopt" => "m"}, # Important to have non-greedy !
  # 
  #{"cmd" => "nmake",    "patt" => "Version (.*?)\$", "reopt" => "s"},
];

# Set by $DPUT::ToolProbe::debug =1;
our $debug = 0;
our $VERSION = "0.01";

# Convenience method for adding a new tool definition.
# Definition is added to the class -held defintion collection
# variable ($toolprobeinfo) with validation. Same as
# 
#     push(@$DPUT::ToolProbe::toolprobeinfo, $newtool);
# 
# Except the latter low level way does not validate %$$newtool.
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
# Probe build tool command version and path from which it was found.
# Assume tools to support conventional --version option.
# Return an hash of hashes containing:
# - outer keys rflecting the tool name (from tool probe info $tool->{'cmd'})
# - inner object containing members:
#   - path - Full path to tool
#   - version - Version of the tool (extracted)
sub detect {
  my (%opts) = @_;
  #my ($addlitems) = @_; # Additional items ?
  my $info = {};
  my $infos = $toolprobeinfo; # Deep copy ?
  # TODO: Allow passing the executable basename:s for ONLY the tools that we want to detect.
  # Override @$infos above by transforming original array
  #my $tools = $opts{'tools'};
  #if ($tools && (ref($tools) eq 'ARRAY')) {
  #  %toolidx = map({ ($_, 1); } @$tools);
  #  @$infos = map({$toolidx{ $_->{'cmd'} } ? 1 : 0; } @$infos);
  #}
  foreach my $p (@$infos) {
    my $re = make_re($p); # qr/$p->{'patt'}/;
    my $cmd = $p->{'cmd'};
    # Find out absolute path
    my $fullpath = `which $p->{'cmd'}`;
    chomp($fullpath);
    if (!$fullpath) { die("Your system does not have tool '$p->{'cmd'}' (Check \$PATH)\n"); }
    # Probe version
    my $toolvercmd ="$p->{'cmd'} --version";
    if ($p->{'stderr'}) { $toolvercmd .= " 2>&1"; }
    my $infostr = `$toolvercmd`; # 2> /dev/null
    if (!$infostr) { die("No tool info (for '$p->{'cmd'}') by '$toolvercmd' !"); }
    if ($debug) { print(STDERR "Complete output of '$toolvercmd': $infostr\n"); }
    if ($infostr =~ /$re/) { $infostr = $1; }
    else {die("'$p->{'cmd'}' - No version available by pattern '$p->{'patt'}'!");}
    $info->{$cmd} = {'path' => $fullpath, 'version' => $infostr};
  }
  return($info);
}
1;
