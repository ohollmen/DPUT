package DPUT::DockerRunner;
use Data::Dumper;
use User::pwent;
use Cwd;
use DPUT;

# # DPUT::DockerRunner - Run docker in automated context with preconfigured options
# 
# Allows
# - Running a command under docker or generating the (potentially conplex and long) full docker command
# - Mapping of volumes (the easy way, partially automated)
# - Adding users from host machine to container (not image) to share files with proper ownerships betwee
#   host and container


## Allow changing docker binary, e.g. $DPUT::DockerRunner::dockerbin = 'docker-b22';
our $dockerbin = 'docker';
# ## DPUT::DockerRunner->new(%opts);
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
# - mergeuser - User to add as resolvable user in container /etc/passwd using volume mapping (e.g. user "compute").
# - asuser - Run as user (resolvable on local system **and** docker) by username (Not uidnumber).
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
# - a valid passwd file line string (with 7 ":" delimited fields)
# - an array(ref) with 7 elements describing valid user (with passwd file order and conventions)
# 
# ### Volumes
# 
# Volume mappings (in "vols") are passed (simply in array, not hash object) in a docker-familiar notation
# "/path/on/host:/path/inside/docker. They are formulated into docker -v options.
#
# ### Example of running
# 
# Terse use case with params set and run executed on-the-fly:
# 
#      my $rc = DPUT::DockerRunner->new('img' => 'myimage', 'cmd' => 'compute.sh')->run();
# 
# More granular config passed and (only) command is generated (No actual docker run is done):
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
#      print("Generated docker command: '$cmd'\n");
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
     'debug' => $opts{'debug'}, 'env' => ($opts{'env'} || {})
  };
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
    if ($mulen != 7) { die("User not passed correctly (array or string) - must contain 7 fields (Got: $mulen).".Dumper($self)); }
    $self->{'mergeuname'} = $self->{'mergeuser'}->[0];
    my %aopts = ('host' => $opts{'host'} || undef );
    $self->setup_accts();
  }
  if ($self->{'asuser'}) {
    #  use User::pwent; ????
    my $uid = -1;
    # uidnumber form given - Validate uid by doing lookup on host ?
    # NOTE: What if user ONLY exists in docker and we want to run as that user ?
    #if ($self->{'asuser'} =~ /^\d+$/) {
    #  my $name  = getpwuid($self->{'asuser'});
    #  if ($name) { $uid = $self->{'asuser'}; }
    #}
    # else {
    $uid   = CORE::getpwnam($self->{'asuser'}); # getpwent();
    # }
    if (!$uid) { print("No user resolved for '$self->{'asuser'}'\n"); }
    $self->{'debug'} && print(STDERR "Run-as user (-u) '$self->{'asuser'}' resolved to uid='$uid'\n");
    # Docker seems to mandate uidnumber
    $self->{'uid'} = $uid;
  }
  
  $self->{debug} && print(STDERR Dumper($self));
  return $self; 
}
# ## DPUT::DockerRunner::getaccount($username);
# 
# Wrapper for Getting a local (or any resolvable, e.g. NIS/LDAP) user account.
# Returns an array of 7 elements, with fields of /etc/passwd
sub getaccount {
  my ($uname) = @_;
  if (!$uname) { die("No username passed"); }
  if ($uname =~ /^\d+$/) { die("username passed as numeric"); }
  my $pw = getpwnam($uname); # Returns 13 elems - reduce.
  if (!$pw) { die("No passwd entry gotten for $uname"); }
  my @acct = ( splice(@$pw, 0, 4), splice(@$pw, 5, 3));
  return wantarray ? @acct : \@acct;
}

# ## DPUT::DockerRunner::userhasdocker($optional_docker_executable_name);
# 
# Detect if the currect user of the system has docker executable.
# User may additionally need to belong UNIX groups (like "docker") to actually run docker.
# This check is not done here.
# Return docker absoute path (a true value) or false if docker is not detected.
sub userhasdocker {
  my $dname = $_[0] || $dockerbin || "docker"; # TODO: $dockerbin
  my $out = `which $dname`;
  chomp($out);
  #print("Got: '$out'\n");
  return $out;
}
# ## $docker->setup_accts()
# 
# Add (merge) an account to a generated temporary passwd file on the host and map it into use (as a volume)
# inside the docker container.
# Options:
# 
# - host - Optional remote host to prepare the file on (if it is known docker job will run there instead of current host).
# 
# Returns true (1) for success and false (0) for (various) errors (with Warning printed to STDERR, no exceptions are thrown).
sub setup_accts {
  my ($self, %opts) = @_;
  if (!$self->{'mergeuser'}) { return 0; }
  if (!$self->{'mergeuname'}) { print(STDERR "Warning: Merge user passed, but no 'mergeuname' resolved\n");return 0; }
  my $remhost = $opts{'host'} || $self->{'host'};
  # Run dump from docker
  my $dumpcmd = "docker run --rm '$self->{'img'}' cat /etc/passwd";
  if ($remhost) { $dumpcmd = "ssh $remhost \"$dumpcmd\""; }
  my @passout = `$dumpcmd`;
  # srw-rw---- /var/run/docker.sock
  if (!@passout) { print(STDERR "Warning: Could not extract passwd from docker ($dumpcmd, uid:$<)\n");return 0; }
  chomp(@passout);
  #$self->{'debug'} && print(STDERR "PASSDUMP:".Dumper(\@passout));
  $self->{'debug'} && print(STDERR "setup_accts: Got ".scalar(@passout)." passwd lines from docker.\n");
  my $mun = $self->{'mergeuname'};
  my @m = grep({$_ =~ /^$mun:/} @passout);
  if (@m) { print(STDERR "Warning: Username to merge ('$mun') seems to already exist in Docker passwd file\n");return 0; }
  push(@passout, join(":", @{ $self->{'mergeuser'} }));
  $self->{'debug'} && print(STDERR "PASSWD-DUMP-POSTADD:\n".Dumper(\@passout));
  my $fname = "/tmp/passwd_".$$."_".time();
  eval { DPUT::file_write($fname, \@passout, 'lines' => 1); };
  if ($@) { print(STDERR "Failed to write temporary pasword file\n"); }
  $self->{'etcpasswd'} = $fname; # Record
  # Add new mapping for temp passwd file
  my $mapping = "$self->{'etcpasswd'}:/etc/passwd";
  # If remote, must copy file, keep name
  if ($remhost) { my $cpc = "scp -p $fname $remhost:$fname"; `$cpc`; if ($?) {} }
  push(@{$self->{'vols'}}, $mapping);
  print(STDERR "Added user '$mun' to '$fname' and will use that via new volume mapping '$mapping'.\n");
  return 1;
}
# ## $docker->run(%opts);
# 
# Run Docker with preconfigured params or *only* return docker run command (string) for more "manual" run.
# Options in opts:
# 
# - cmdstring - Trigger return of command string only *without* actually running container
# 
# Note: The command to run inside docker will not be quoted.
# Return either docker command string (w. option 'cmdstring') or return code of actual docker run.
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
  my $env = $self->{'env'};
  if ($env && (ref($env) eq 'HASH')) {
    for my $k (keys(%$env)) { push(@args, "-e", "'$k=$env->{$k}'"); }
  }
  push(@args, $self->{'img'});
  push(@args, $self->{'cmd'}); # Unquoted to avoid nested quotes OR should we escape inner ?
  my $cmd = "docker run ".join(' ', @args);
  if ($opts{'cmdstring'}) { return $cmd; }
  $self->{debug} && print(STDERR "Running:\n$cmd\n");
  my $rc = system($cmd); # `$cmd`
  return $rc;
}
# ## $docker->cmd($new);
# 
# Force command to be set after construction. Especially useful if $cmd is not known at construction time and for example
# dummy command was used at that time. No validation on command is done
sub cmd {
  my ($self, $cmd) = @_;
  $self->{'cmd'} = $cmd;
}

# ## DPUT::DockerRunner::dockercat_load($fname)
# Load and validate Docker Catalog with mappings from a symbolic "friendly name" of image ("dockerlbl") to
# image url and other info regarding colume (e.g. "vols" to use, Image may depend on these).
# Return Array of Hash-Objects.
sub dockercat_load {
  my ($fname) = @_;
  my $dc = DPUT::jsonfile_load($fname);
  if (ref($dc) ne 'ARRAY') { die("Docker catalog is not in an ARRAY!\n"); }
  map({
    if (ref($_) ne 'HASH') { die("Docker catalog item is not an object!\n"); }
    if (!$_->{'dockerlbl'} || !$_->{'dockerimg'}) { die("dockerlbl or dockerurl missing from node!"); }
  } @$dc);
  return $dc;
}

# ## DPUT::DockerRunner::dockercat_find($arr, $lbl)
# Find a image definition with image properties by its label (passed as $lbl, "dockerlbl" member in node).
# Return Hash-Object for matching image definition or a false for "not found".
sub dockercat_find {
  my ($dc, $lbl) = @_;
  if (ref($dc) ne 'ARRAY') { die("Docker catalog is not in an ARRAY!\n"); }
  my @m = grep({ $_->{'dockerlbl'} eq $lbl; } @$dc);
  if (!@m) { return undef; }
  return $m[0];
}
