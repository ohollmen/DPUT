#!/usr/bin/perl
use strict;
use warnings;
use lib("..");
use Data::Dumper;
use DPUT::DataRun;
use DPUT;
use File::Path ('make_path');
use Digest::MD5 qw(md5 md5_hex md5_base64);
use Test::More;

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





# Data Chunking for run_serpar()

my $aoa = [
  [1],
  [1, 2],
  [1, 2, 3],
  [1, 2, 3, 4],
  [1, 2, 3, 4, 5],
];

#$aoa = makedataset(123); # 123
# print(Dumper($aoa)); exit(1);
note("run_serpar() chunking\n");
my $testcnt = 0;
# Try combos of array and group size
for my $arr (@$aoa) {
  # my $grpcnt = 2;
  for my $grpcnt (1..3) {
    my $cnt_o = scalar(@$arr);
    my $chunked = DPUT::DataRun::arr_chunk($arr, $grpcnt);
    note("Chunked(".scalar(@$arr)." items, grpcnt: $grpcnt)\n");
    local $Data::Dumper::Indent = 0;
    print(Dumper($arr)."\n");
    print(Dumper($chunked)."\n");
    # Chunked
    my $cnt_c = aoa_count($chunked); # TODO:  DPUT::DataRun::aoa_count()
    # if ($cnt_o != $cnt_c) { print("ERROR: Counts not matching org($cnt_o) vs chunked($cnt_c) grpsize: $grpcnt\n"); }
    # assert !
    ok($cnt_o == $cnt_c, "Chunked to original number of items ($cnt_o)");
    $testcnt++;
  }
}
done_testing( $testcnt );

# Could total items 
sub aoa_count {
  my ($aoa) = @_;
  my $tot = 0;
  for my $arr (@$aoa) {
    if (ref($arr) ne 'ARRAY') { die("Inner item is not an array !\n"); }
    $tot += scalar(@$arr);
  }
  return $tot;
}

# Make array datasets in varying lengths
sub makedataset {
  my ($numarr) = @_;
  my $aoa = [];
  for my $i (1..$numarr) {
    push(@$aoa, [(1..$i)]);
  }
  return $aoa;
}

