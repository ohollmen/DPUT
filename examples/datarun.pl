#!/usr/bin/perl
use strict;
use warnings;
use lib("..");
use Data::Dumper;
use DPUT::DataRun;
use DPUT;
use File::Path ('make_path');
use Digest::MD5 qw(md5 md5_hex md5_base64);


my $waits = [5, 8, 3, 9, 12];
sub waitfor_me {
  my ($waittime) = @_;
  print("Hi ! I'm waiting for $waittime s.\n");
  sleep($waittime);
  print("Done sleeping $waittime s.\n");
  return(1);
}
if (0) {
my $dropts = {'ccb' => sub { print("Seeing completion of $_[0]\n"); },
  'debug' => 1};
#my $drun = new DPUT::DataRun(sub { waitfor_me($_[0]); }, $dropts);
my $drun = new DPUT::DataRun(\&waitfor_me, $dropts);
#if ($opts->{'parallel'}) {
$drun->run_parallel($waits);
print("Do something in between, for example nap/sleep\n");
sleep(20);
print("Start waiting for children !!!\n");
$drun->runwait();
#}
#else { $drun->run_series($tars); }
print("Done !\n");
}
################### PATH EXAMPLE ####################
my $commonstore_path = "/tmp/tree_$$";

my $pathitems = [
  {'path' => '/usr/bin'},
  {'path' => '/bin/'},
  {'path' => $ENV{'HOME'}.'/.cache/mozilla/firefox/u8huzzhc.default/cache2/entries/'}
  
];
sub path_flatten {
  my ($path) = @_;
  $path =~ s/\//__/g;
  #$path = md5_hex($path);
  return $path;
}
sub get_path_files {
  my ($pathnode) = @_; # We only have $_[0];
  my $files = dir_list($pathnode->{'path'});
  print("Got ".scalar(@$files)." files\n");
  my $path = path_flatten($pathnode->{'path'});
  
  # OLD: Use $$
  my $itemresfn = "$commonstore_path/$path.json";
  file_write($itemresfn, $files); # 'fmt' => 'json',
  #symlink("$commonstore_path/$$.json", "$commonstore_path/$path.json");
}

sub path_listing_complete {
  my ($item, $res, $pid) = @_;
  #local $Data::Dumper::Indent = 0;
  print("main: Completed: ".Dumper($item)."\n");
  my $path = path_flatten($item->{'path'});
  my $itemresfn = "$commonstore_path/$path.json";
  if (!-f $itemresfn) { print("Hmm - no file from worker child (?)\n");}
  my $j = eval { jsonfile_load($itemresfn); };
  if ($@) { print("Bad JSON: $itemresfn: $@\n"); return; }
  #print("Loaded JSON $j\n");
  $res->{$item->{'path'}} = $j;
  
}

make_path($commonstore_path, {'verbose' => 1, 'mode' => 0777,});
print("Created common store in: $commonstore_path\n");
{
my $dropts = {
  #'ccb' => sub { print("Seeing completion of $_[0], pid: $_[2]\n"); },
  'ccb' => \&path_listing_complete,
  'debug' => 1};
#my $drun = new DPUT::DataRun(sub { waitfor_me($_[0]); }, $dropts);
my $drun = new DPUT::DataRun(\&get_path_files, $dropts);
$drun->run_parallel($pathitems);
#my $res = $drun->run_series($pathitems)->res(); report($res, 1); exit(1);
print("main: Start waiting for children\n");
my $res = $drun->runwait();
report($res, 1);
sub report {
  my ($res, $short) = @_;
  print("Possibly long result (from child processes, ".keys(%$res)." keys):\n");
  if ($short) { return; }
  #print(Dumper($drun->{'res'})."\n");
  print(Dumper($res)."\n");
}
############################# SINGLE ITEM ##############
if (0)
{
my $drun = new DPUT::DataRun(\&get_path_files, $dropts);
my $singleitem = {'path' => $ENV{'HOME'}};
#print("Run single item:\n");
#$drun->run_forked_single($singleitem);
#$drun->runwait();
}

}
