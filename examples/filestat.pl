#!/usr/bin/perl
use File::Find;
use File::stat;
use Data::Dumper;
use lib("..");
use DPUT;
$Data::Dumper::Terse = 1;
$Data::Dumper::Indent = 1;
# no warnings "File::stat";
# 
my $fn = "/etc/passwd";

my $st = stat($fn);
print(Dumper($st));

sub is_small_conf {
  my ($s, $fn) =@_;
  my $dt = time() - $s->[9];
  my $halfyear = 15552000;
  #print("$dt\n");
  
  if ($fn =~ /\.conf$/ && ($s->[7] < 4000) && ($dt > ($halfyear*2) )) {
    my $m = `file -b $fn`;chomp($m);
    return {'fn' => $fn, 'size' => $s->[7], 'mtime' => DPUT::isotime($s->[9]), 'mtype' => $m};
  }
  return undef;
};
# sub is_small_conf { return 1; }
# sub is_small_conf { return -d $_[1] ? [@{$_[0]}, $_[1]] : 0; }
my $files = DPUT::filetree_filter_by_stat('/etc/', \&is_small_conf, 'useret' => 1);
my $cnt = scalar(@$files);
print(Dumper($files));
print("# $cnt Small (<4K) .conf files.\n");
# Example of removal
#forXX my $fnode (@$files) { unlink(fnode->{'fn'}); } # fnode['fn'] fnode.fn
