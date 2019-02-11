#!/usr/bin/perl
# Retrier Examples
use lib (".");
use lib ("..");
use DPUT::Retrier;
use Data::Dumper;

my $i = 0;
sub tryme {
  $i++;
  print("Try # $i (Args: @_)\n");
  if (@_) { print("Hello @_ !\n"); }
  if ($i>4) { print("Good enough\n"); return 1; }
  return 0;
}

my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3, 'debug' => 1)->run(\&tryme);
print("outcome(ok?): ".$ok."\n\n");
#print(Dumper($rt));
my $rt = DPUT::Retrier->new('cnt' => 2, 'delay' => 2, 'debug' => 1, args => ["Mickey","Mouse"]);
$rt->run(\&tryme);
print("outcome(ok?): ".$ok."\n\n");
# Reset $i
$i = 0;
my $ok = DPUT::Retrier->new({'cnt' => 5, 'delay' => 1,
  'debug' => 1})->run(sub { tryme("Minnie", "Mouse"); });
print("outcome(ok?): ".$ok."\n\n");
