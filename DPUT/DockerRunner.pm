package DPUT::DockerRunner;
use Data::Dumper;
use User::pwent;
use Cwd;

# # DPUT::DockerRunner - Run docker in automated context with preconfigured options

## Allow changing docker binary, e.g. $DPUT::DockerRunner::dockerbin = 'docker-b22';
our $dockerbin = 'docker';
# ## DPUT::DockerRunner->new('img' => 'myimage', 'cmd' => 'compute.sh');
# 
# Create new docker runner with options to run docker.
# 
# Keyword Options in %opts:
# - img - Image name to use for running "docker run $IMAGE $CMD"
# - cmd - Command to run in docker (with possible whitespace separated arguments)
# - cwd - Current working directory inside container (docker -w param)
#   - Passing a explicit path sets working dir to that value
#   - passing the kw param, but with false value does not set any explicit working dir. Docker sets the cwd for you.
#   - When kw param is completely left out, container cwd is set to current host cwd
# - mergeuser - User to add as resolvable user in container /etc/passwd using volume mapping (e.g. "compute").
# - asuser - Run as user (resolvable on local system **and** docker.
# - vols - an array of volume mappings. Simple 1:1 mappings with form:to the same can be given without delimiting ":".
#
# Todo:
# - Allow checking/validating volume source locations presence. For now caller has to make sure
# they are valid.
# - Could do duplicate volume check before launch (Error response from daemon: Duplicate mount point: ...)
#  
# ### Merging a user
#
# "mergeuser" parameter can take 3 forms:
#
# - bare username resolvable on host (e.g. "mrsmith")
# - a valid passwd file line (with 7 ":" delimited fields)
# - an array(ref) with 7 elements describing valid user
# 
# ### Volumes
# 
# Volume mappings are passed (simply in array, not hash object) in a docker-familiar notation
# "/path/on/host:/path/inside/docker. They are formulated into docker -v options.
#
# ### Example of running
# Terse use case with params set and run executed on-the-fly:
# 
#      my $rc = DPUT::DockerRunner->new('img' => 'myimage', 'cmd' => 'compute.sh')->run();
# More granular config passed and (only) command is generated:
# 
#      my $dcfg = {
#        "img" => "ubuntu",
#        "cmd" => "ls /usr",
#        "vols" => ["/tmp","/usr", "/placeone:/anotherplace"],
#        "asuser" => "mrsmith",
#        #"mergeuser" => "oddball:x:1004:1004:Johnny Oddball,,,:/home/oddball:/bin/bash",
#      };
#      # Create Docker runner
#      my $docker = DPUT::DockerRunner->new(%$dcfg);
#      my $cmd = $docker->run('cmdstring' => 1);
#      print("Generated command: '$cmd'\n");
# 

sub new {
  my ($class, %opts) = @_;
  if (!keys(%opts)) { die("No Options !\n"); }
  #my $cfg = $opts{'config'} || {};
  print(Dumper(\%opts));
  if (!$opts{'img'}) { die("No Docker Image\n"); }
  if (!$opts{'cmd'}) { die("No Docker Command to execute\n"); }
  #if (!$opts{'img'}) { die("Does not look like docker build\n"); }
  
  my $self = {'img' => $opts{'img'}, 'vols' => ($opts{'vols'} || []), 'cmd' => $opts{'cmd'},
     'mergeuser' => $opts{'mergeuser'}, asuser => $opts{'asuser'},
     'debug' => $opts{'debug'}};
  my $vols = $self->{'vols'};
  @$vols = map({/:/ ? $_ : "$_:$_"; } @$vols); # Ensure "srcvol:destvol" notation
  bless($self, $class);
  if ($self->{'mergeuser'}) {
    if (!ref($self->{'mergeuser'})) {
      my $mu = $self->{'mergeuser'};
      if ($mu =~ /^\w+$/) { $self->{'mergeuser'} = getaccount($mu); }
      else { $self->{'mergeuser'} = [split(/:/, $mu)]; }
    }
    my $mulen = scalar(@{$self->{'mergeuser'}});
    if ($mulen != 7) { die("User not passed correctly (arry or string) - must contain 7 fields (Got: $mulen).".Dumper($self)); }
    $self->{'mergeuname'} = $self->{'mergeuser'}->[0];
    $self->setup_accts();
  }
  if ($self->{'asuser'}) {
    #  use User::pwent; ????
    my $uid   = CORE::getpwnam($self->{'asuser'}); # getpwent();
    if (!$uid) { print("No user resolved for '$self->{'asuser'}'\n"); }
    $self->{'debug'} && print(STDERR "Resolved $self->{'asuser'} to uid='$uid'\n");
    $self->{'uid'} = $uid;
  }
  $self->{debug} && print(STDERR Dumper($self));
  return $self; 
}
# Wrapper for Getting an account
sub getaccount {
  my ($uname) = @_;
  if (!$uname) { die("No username passed"); }
  if ($uname =~ /^\d+$/) { die("username passed as numeric"); }
  my $pw = getpwnam($uname);
  if (!$pw) { die("No passwd entry gotten for $uname"); }
  my @acct = ( splice(@$pw, 0, 4), splice(@$pw, 5, 3));
  return wantarray ? @acct : \@acct;
}

# Detect if the currect user of the system has docker executable.
# User may additionally need to belong UNIX groups (like "docker") to actually run docker.
# This check is not done here.
# Return docker absoute path (a true value) or false if docker is not detected.
sub userhasdocker {
  my $dname = $_[0] || "docker";
  my $out = `which $dname`;
  chomp($out);
  #print("Got: '$out'\n");
  return $out;
}
# ## $docker->setup_accts()
# Add (merge) an account to a generated temporary passwd file on the host and map it into use (as a volume)
# inside the docker container.
sub setup_accts {
  my ($self) = @_;
  if (!$self->{'mergeuser'}) { return 0; }
  if (!$self->{'mergeuname'}) { print(STDERR "Warning: Merge user passed, but no 'mergeuname' resolved\n");return 0; }
  # Run dump from docker
  my @passout = `docker run --rm '$self->{'img'}' cat /etc/passwd`;
  chomp(@passout);
  #$self->{'debug'} && print(STDERR "PASSDUMP:".Dumper(\@passout));
  my $mun = $self->{'mergeuname'};
  my @m = grep({$_ =~ /^$mun:/} @passout);
  if (@m) { print(STDERR "Warning: Username to merge ('$mun') seems to already exist in Docker passwd file\n");return 0; }
  push(@passout, join(":", @{ $self->{'mergeuser'} }));
  $self->{'debug'} && print(STDERR "PASSDUMP-POSTADD:\n".Dumper(\@passout));
  my $fname = "/tmp/passwd_".$$."_".time();
  DPUT::file_write($fname, \@passout, 'lines' => 1);
  $self->{'etcpasswd'} = $fname; # Record
  # Add new mapping for temp passwd file
  push(@{$self->{'vols'}}, "$self->{'etcpasswd'}:/etc/passwd");
  print(STDERR "Added user '$mun' to '$fname' and will use that as container /etc/passwd\n");
}
# ## $docker->run(%opts); 
# Run Docker with preconfigured params or *only* return docker run command (string) for more "manual" run.
# Options in opts:
# 
# - cmdstring - Trigger return of command string only *without* actually running container
# 
# Return either docker command string (w. option cmdstring) or return code of actual docker run.
sub run {
  my ($self, %opts) = @_;
  my @args = ();
  push(@args, "--rm",);
  push(@args, map({("-v", "'$_'");} @{$self->{'vols'}}) ); # Volume args
  my $cwd = getcwd(); # Default: Auto-probe
  if ($self->{'cwd'}) { $cwd = $self->{'cwd'}; }
  if (exists($self->{'cwd'}) && !$self->{'cwd'}) { $cwd = undef; }
  if ($cwd) { push(@args, "-w", $cwd); }
  if ($self->{'uid'}) { push(@args, "-u", $self->{'uid'}); }
  push(@args, $self->{'img'});
  push(@args, $self->{'cmd'}); # Unquoted to avoid nested quotes OR escape inner ?
  my $cmd = "docker run ".join(' ', @args);
  if ($opts{'cmdstring'}) { return $cmd; }
  $self->{debug} && print(STDERR "Running:\n$cmd\n");
  my $rc = system($cmd); # `$cmd`
  return $rc;
}
