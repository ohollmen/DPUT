#!/usr/bin/perl
# Retrier Examples
use lib (".");
use lib ("..");
use DPUT::Retrier;
use Data::Dumper;

my $i = 0;
# Return Perl-style ok-values
sub tryme {
  my ($sleeptime) = @_;
  $i++;
  print("Try # $i (Args: @_)\n");
  if ($sleeptime) { sleep($sleeptime); }
  if (@_) { print("Hello @_ ! (i=$i)\n"); }
  if ($i > 4) { print("Good enough\n"); return 1; }
  return 0;
}

my $ok = DPUT::Retrier->new('cnt' => 2, 'delay' => 3, 'debug' => 1, tout => 5)->run(sub { tryme(3); });
print("ok=$ok\n");
exit(1);

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

my $retry_cfg = {'cnt' => 5, 'delay' => 1, 'debug' => 1,
  'badret' => \&DPUT::Retrier::badret_cli, # Use CLI/shell good/bad return value convention
  'delays' => [1,2,3,4,5]
};
# print("CB: " . \&DPUT::Retrier::badret_cli . "\n");
my $retrier = new DPUT::Retrier($retry_cfg);
sub badret_custom {
  print("Custom badret CB\n");
  if ($_[0]) { return 1; }
  return 0;
}
sub doit {
  print("Doit\n");
  return 1; # Always bad
}
my $ok = $retrier->run(\&doit);
print("outcome(ok?): ".$ok."\n\n");
