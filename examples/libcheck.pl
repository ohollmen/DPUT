#!/usr/bin/perl
$ENV{'PERL5LIB'} = "$ENV{'PERL5LIB'}:/home/odroid-32_odroid_backup/src/libbie";
use lib("/home/odroid-32_odroid_backup/src/libbie");
use strict;
use warnings;
use libinfo;
use linkinfo;
use Data::Dumper;
use File::Basename;
$Data::Dumper::Indent = 1;
$Data::Dumper::Terse = 1;
use JSON;

my $elfname = $ARGV[0] || "/usr/bin/curl";

my $li = linkinfo->new($elfname);
print("Got: $li\n");
my $libs = $li->{'LIBS'};
addlinfo($li);
# print(Dumper($libs));
print("JSON:".to_json($li, { pretty => 1, allow_blessed => 1, convert_blessed => 1}));
exit(0);
# Gather additional info on linked libraries.
# - If static library is in the system
# - What OS package library comes from
# - 
sub addlinfo {
  my ($li) = @_;
  my $libs = $li->{'LIBS'};
  # Resolve to basename (to make *.a)
  # Try to find respective *.a files (possibly many)
  # 
  for my $l (@$libs) {
    #print("DYN: $l->{'libres'}\n");
    $l->{'bn'} = File::Basename::basename($l->{'libres'});
    $l->{'bn'} =~ s/\.so\.?[\d\.]*$//;
    $l->{static} = findlib("$l->{'bn'}.a");
    # Pkg manager related
    $l->{libpkg} = findownerpkg($l);
    if (!$l->{'static'} || !scalar(@{ $l->{'static'} })) {
      $l->{addlpkgs} = findaddlpkgs($l->{libpkg});
    }
    # Find owner pkg of static
    else {
      $l->{libpkg_static} = findownerpkg($l->{'static'}->[0]);
    }
  }
  return;
}


# print(to_json($li, {pretty => 1}));
sub findlib {
  my ($libn) = @_;
  my $cmd = "find /usr/lib/ -nowarn -name $libn";
  my @rows = `$cmd`;
  chomp(@rows);
  #print(Dumper(\@rows));
  # @rows = grep({$_ =~ /\/usr\/lib\/x86_64-linux-gnu/} @rows);
  return \@rows;
}
sub findownerpkg {
  my ($l) = @_;
  my $abslib = (ref($l) ) ? $l->{'libres'} : $l; # eq "HASH" - NOTE is blessed !
  #print("Find owner of: $abslib\n");
  my $cmd = "dpkg-query -S $abslib";
  my @pkgs = `$cmd`;
  if (!@pkgs) { return undef; }
  chomp(@pkgs);
  if (@pkgs > 1) { die("Error: Multiple owning pkgs for $abslib!\n"); }
  #print("PKGLINE: $pkgs[0]\n");
  my ($pkg) = split(/:\s+/, $pkgs[0], 2);
     ($pkg) = split(/:/, $pkg, 2); # Strip arch-indicator
  return $pkg;
}
# Find additional packages heuristically by base package name (for dynamic library).
# NOTE / Samples examples
# - libnghttp2-14 => libnghttp2-dev
# - librtmp1 => librtmp-dev
# - libpsl5 => libpsl-dev
# - libgssapi-krb5-2 => Possibly libkrb5-dev or krb5-multidev or libkdb5-9 NONE ?
# - libldap-2.4-2 => libldap2-dev
# - libkrb5-3 => libkrb5-dev
# - libk5crypto3 => 
# - libcom-err2 => comerr-dev
# - libkrb5support0 =>
# - libsasl2-2 => libsasl2-dev
# - libgssapi3-heimdal => NONE ? libgss-dev ?
# - libkeyutils1 => libkeyutils-dev
# - libheimntlm0-heimdal => NONE ? heimdal-dev ?
# - libkrb5-26-heimdal => 
# - libasn1-8-heimdal => heimdal-dev ?
# - libhcrypto4-heimdal => ???
# - libffi6 => libffi-dev
# - libwind0-heimdal => 
sub findaddlpkgs {
  my ($pkgbn) = @_;
  if (!$pkgbn) { return []; }
  if ($pkgbn eq 'libc6') { return []; } # ld-linux-* (dynamic linker)
  # TODO: drop 1) /\d+$/ 2) [\d\-]$
  my @pkgs = `apt-cache search $pkgbn`;
  chomp(@pkgs);
  return \@pkgs;
}
