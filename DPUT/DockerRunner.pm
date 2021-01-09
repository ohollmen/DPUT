package DPUT::DockerRunner;
use Data::Dumper;
use User::pwent;
use Cwd;
use DPUT;

# # DPUT::DockerRunner - Run docker in automated context with preconfigured options
# 
# Allows
# - Running a command under docker or generating the (potentially complex and long) full docker command
# - Setting user, group, current workdir
# - Mapping Docker bind volumes (the easy way, partially automated)
# - Adding users from host machine to container (not image) to share files with proper ownerships between
#   host and container
# - Pass env vars from host environment to container


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
# - asgroup - Run as group (either group name or gidnumber)
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
#        "mergeuser" => "oddball:x:1004:1004:Johnny Oddball,,,:/home/oddball:/bin/bash",
#      };
#      # Create Docker runner
#      my $docker = DPUT::DockerRunner->new(%$dcfg);
#      my $cmd = $docker->run('cmdstring' => 1);
#      print("Generated docker command: '$cmd'\n");
#      # ... later
#      my $rc = system($cmd);
#      # If you used "mergeuser" and ONLY generated docker command, clean up temp passwd file
#      if ($docker->{'etcpasswd'} && -f $docker->{'etcpasswd'}) { unlink($docker->{'etcpasswd'}); }

sub new {
  my ($class, %opts) = @_;
  if (!keys(%opts)) { die("No Options !\n"); }
  #my $cfg = $opts{'config'} || {};
  $opts{'debug'} && print(Dumper(\%opts));
  if (!$opts{'img'}) { die("No Docker Image\n"); }
  if (!$opts{'cmd'}) { die("No Docker Command to execute\n"); }
  #if (!$opts{'img'}) { die("Does not look like docker build\n"); }
  
  my $self = {'img' => $opts{'img'}, 'vols' => ($opts{'vols'} || []), 'cmd' => $opts{'cmd'},
     'mergeuser' => $opts{'mergeuser'}, asuser => $opts{'asuser'}, 'mergegroup' => $opts{'mergegroup'},
     'debug' => $opts{'debug'}, 'env' => ($opts{'env'} || {}),  'asgroup' => $opts{'asgroup'} # 'cwd' => $opts{'cwd'},
  };
  if (exists($opts{'cwd'})) { $self->{'cwd'} = $opts{'cwd'}; }
  my $vols = $self->{'vols'};
  @$vols = map({/:/ ? $_ : "$_:$_"; } @$vols); # Ensure "srcvol:destvol" notation
  bless($self, $class);
  # User ?
  if ($self->{'mergeuser'}) {
    if (!ref($self->{'mergeuser'})) {
      my $mu = $self->{'mergeuser'};
      if ($mu =~ /^\d+$/) { die("mergeuser id passed as numeric ($mu) - use name."); }
      # Updated to from plain ^\w+$ to "modern" NAME_REGEX (allow dash/hyphen)
      if ($mu =~ /^[a-z][-a-z0-9]*$/) { $self->{'mergeuser'} = getaccount($mu); }
      # Expect 7 field record passed as ':' delimited string
      else { $self->{'mergeuser'} = [split(/:/, $mu)]; }
    }
    # By now we should have a array based 7-field pw-record.
    my $mulen = scalar(@{$self->{'mergeuser'}});
    if ($mulen != 7) { die("User not passed correctly (array or string) - must contain 7 fields (Got: $mulen).".Dumper($self)); }
    $self->{'mergeuname'} = $self->{'mergeuser'}->[0];
  }
  # Group
  if ($self->{'mergegroup'}) {
    if (!ref($self->{'mergegroup'})) {
      my $mu = $self->{'mergegroup'};
      if ($mu =~ /^\d+$/) { die("mergegroup id passed as numeric ($mu) - use name."); }
      # Updated to from plain ^\w+$ to "modern" NAME_REGEX (allow dash/hyphen)
      if ($mu =~ /^[a-z][-a-z0-9]*$/) { $self->{'mergegroup'} = getaccount($mu, 1); } # GROUP
      # Expect 7 field record passed as ':' delimited string
      else { $self->{'mergegroup'} = [split(/:/, $mu, 4)]; }
      print(Dumper($self->{'mergegroup'}));
    }
    # By now we should have a array based 7-field pw-record.
    my $mulen = scalar(@{$self->{'mergegroup'}});
    if ($mulen != 4) { die("Group not passed correctly (array or string) - must contain 4 fields (Got: $mulen).".Dumper($self)); }
    $self->{'mergegname'} = $self->{'mergegroup'}->[0];
  }
  my %aopts = ('host' => $opts{'host'} || undef );
  $self->setup_accts(%aopts);
    
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
    if ($self->{'asgroup'}) {
      if ($self->{'asgroup'} =~ /^\d+/) { $self->{'gid'} = int($self->{'asgroup'}); }
      else { $self->{'gid'} = CORE::getgrnam($self->{'asgroup'}); }
    }
  }
  
  $self->{debug} && print(STDERR Dumper($self));
  return $self; 
}
# ## DPUT::DockerRunner::getaccount($username);
# 
# Wrapper for Getting a local (or any resolvable, e.g. NIS/LDAP) user account.
# Returns an array of 7 elements, with fields of /etc/passwd
sub getaccount {
  my ($uname, $isgrp) = @_;
  if (!$uname) { die("No username/groupname passed"); }
  if ($uname =~ /^\d+$/) { die("entry id passed as numeric - use name."); }
  my @acct;
  if ($isgrp) {
    #my $ge = getgrnam($uname); # Returns scalar gid !
    my @ge = getgrnam($uname);
    if (!@ge) { die("No group entry gotten for '$uname'"); }
    #print("GRENT:".Dumper(\@ge));
    @acct = @ge;
  }
  else {
    my $pw = getpwnam($uname); # Returns 13 elems - reduce.
    if (!$pw) { die("No passwd entry gotten for '$uname'"); }
    @acct = ( splice(@$pw, 0, 4), splice(@$pw, 5, 3));
  }
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
  my $remhost = $opts{'host'} || $self->{'host'};
  # ORIG:
  #if (!$self->{'mergeuser'}) { return 0; }
  #if (!$self->{'mergeuname'}) { print(STDERR "Warning: Merge user passed, but no 'mergeuname' resolved\n");return 0; }
  foreach my $ftype ('passwd', 'group') {
    my $idkey = $ftype eq 'passwd' ? "mergeuser"  : "mergegroup";
    if (!$self->{$idkey}) { print(STDERR "No ent for $ftype addition (key=$idkey)\n"); next; }
    my $id   = $ftype eq 'passwd' ? "mergeuname" : "mergegname"; # ID attr
    if (!$self->{$id}) { print(STDERR "Warning: Merge $ftype passed, but no '$id' resolved\n");return 0; }
    my $fname = $self->etc_file_dump($ftype, $self->{$id});
    if (!$fname) { print(STDERR "Error: $ftype Merge error (No filename gotten)\n");return 0; }
    # Add new mapping for temp passwd file
    my $mapping = $self->{"etc$ftype"}.":/etc/$ftype";
    # If remote, must copy file, keep name
    if ($remhost) { my $cpc = "scp -p $fname $remhost:$fname"; `$cpc`; if ($?) {} }
    push(@{$self->{'vols'}}, $mapping);
    $self->{'debug'} && print(STDERR "Added user/group '$mun' to '$fname' and will use that via new volume mapping '$mapping'.\n");
  }
  
  return 1;
}
# ## 
# Dump an /etc/ file from inside docker with supported file types being "passwd" or "group"
sub etc_file_dump {
  my ($self, $ftype, $mun, %opts) = @_;
  if (!$mun) { print(STDERR "Error: Missing '$ftype' entry id\n");return 0; }
  # Run dump from docker
  my $dumpcmd = "docker run --rm '$self->{'img'}' cat /etc/$ftype";
  if ($remhost) { $dumpcmd = "ssh $remhost \"$dumpcmd\""; }
  my @passout = `$dumpcmd`;
  # srw-rw---- /var/run/docker.sock
  if (!@passout) { print(STDERR "Warning: Could not extract '$ftype' from docker ($dumpcmd, uid:$<)\n");return 0; }
  chomp(@passout);
  #$self->{'debug'} && print(STDERR "PASSDUMP:".Dumper(\@passout));
  $self->{'debug'} && print(STDERR "setup_accts: Got ".scalar(@passout)." '$ftype' lines from docker.\n");
  # OLD: my $mun = $self->{'mergeuname'};
  my @m = grep({$_ =~ /^$mun:/} @passout);
  if (@m) { print(STDERR "Warning: User/Group to merge (id: '$mun') seems to already exist in Docker '$ftype' file\n");return 0; }
  my $entkey = $ftype eq 'passwd' ? 'mergeuser' : 'mergegroup'; # Key to array ent
  push(@passout, join(":", @{ $self->{$entkey} })); # OLD: 'mergeuser'
  $self->{'debug'} && print(STDERR "PASSWD-DUMP-POSTADD:\n".Dumper(\@passout));
  my $fname = "/tmp/$ftype\_".$$."_".time();
  eval { DPUT::file_write($fname, \@passout, 'lines' => 1); };
  if ($@) { print(STDERR "Failed to write temporary $ftype file\n"); }
  $self->{"etc$ftype"} = $fname; # Record into $self
  return $fname;
}

# ## $docker->run(%opts);
# 
# Run Docker with preconfigured params or *only* return docker run command (string) for more "manual" run.
# Options in opts:
# 
# - cmdstring - Trigger return of command string only *without* actually running container (running is done by other means at caller side)
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
  #  See constructor documentation for this behavior
  if (exists($self->{'cwd'}) && !$self->{'cwd'}) { $cwd = undef; }
  if ($cwd) { push(@args, "-w", $cwd); }
  if ($self->{'uid'}) {
    my $uid = $self->{'uid'};
    if ($self->{'gid'}) {  $uid .= ":$self->{'gid'}"; }
    push(@args, "-u", $uid);
  }
  my $env = $self->{'env'};
  if ($env && (ref($env) eq 'HASH')) {
    for my $k (sort keys(%$env)) { push(@args, "-e", "'$k=$env->{$k}'"); }
  }
  push(@args, $self->{'img'});
  push(@args, $self->{'cmd'}); # Unquoted to avoid nested quotes OR should we escape inner ?
  my $cmd = "docker run ".join(' ', @args);
  if ($opts{'cmdstring'}) { return $cmd; }
  $self->{debug} && print(STDERR "Running:\n$cmd\n");
  my $rc = system($cmd); # `$cmd`
  return $rc;
}
# ## $docker->cmd($cmd);
# 
# Force command to be run in docker to be set (overriden) after construction. Especially useful if $cmd is not known at construction time and for example
# dummy command was used at that time. No validation on command is done.
sub cmd {
  my ($self, $cmd) = @_;
  $self->{'cmd'} = $cmd;
}
# ## $docker->vols_add(\@vols)
# 
# Adds to volumes with relevant checks (just type checks, no overlap check is done).
# Any errors in parameters will only trigger warnings (not treated as errors).
sub vols_add {
  my ($self, $vols) = @_;
  if (ref($vols) ne 'ARRAY') { print(STDERR "Warn: vols not in Array"); return; }
  if (!$self->{'vols'}) { $self->{'vols'} = []; }
  push(@{$self->{'vols'}}, @$vols);
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

# ## DPUT::DockerRunner::dockercat_find($arr, $lbl, %opts)
# Find a image definition with image properties by its label (passed as $lbl, "dockerlbl" member in node).
# Options in %opts:
# 
# - by - perform search by attribute given (e.g. 'by' => 'dockerimg')
# 
# Search is performed by exact matching.
# Return Hash-Object for matching image definition or a false for "not found".
sub dockercat_find {
  my ($dc, $lbl, %opts) = @_;
  if (ref($dc) ne 'ARRAY') { die("Docker catalog is not in an ARRAY!\n"); }
  my $prop = $opts{'by'} || 'dockerlbl';
  my @m = grep({ $_->{$prop} eq $lbl; } @$dc);
  if (!@m) { return undef; }
  return $m[0];
}

# TODO: Run Docker in wrapped, pre-configured way.
# - Allow referring to image with high-level label-name
# - Allow defaulting to particular image in main config
# - Resolve config from one of possible path locations
# - Default to running as the $ENV{'USER'}, in current dir.
# - Default to using current dir (User should provide current dir to be mounted by config "vols")
# Params coming here:
# - int - Use Interactive Mode
# - dcat - Docker (Image) catalog
# - imglbl - Image (high-level, "nice-name") label (to translate to image url via docker catalog)
# TODO: Normalize these into methods to allow normal DockerRunner construction to use these.
sub runcli {
  my ($p) = @_;
  my $dcfg = {'int' => $p->{'int'}, 'dcat' => $p->{'dcat'}, 'imglbl' => $p->{'imglbl'}, 'cmd' => $p->{'cmd'}}; # defaults here ?
  if (!$dcfg->{'imglbl'}) { die("No Docker image label ('imglbl') passed !\n"); }
  
  # Resolve config names and paths for "docker.conf.json" and dockercat.conf.json
  my @paths = (".","$ENV{'HOME'}");
  my @confs = grep({-f $_."/docker.conf.json"; } @paths);
  if (!@confs) {} # Fall back to defaults
  if (scalar(@confs) > 1) { print(STDERR "Warning: Multiple docker.conf.json files found, using first found."); }
  my $dconf;
  if (scalar(@confs)) { $dconf = $confs[0]; }
  # Load config, allow overrides
  if ($dconf) {
    if (!-f $dconf) { die("Docker config '$dconf' does not exist !\n"); }
    $dcfg = jsonfile_load($dconf);
    if (!$dcfg) { die("Could not parse Docker config: $dconf\n"); }
    if (!$dcfg->{'dcat'}) { $dcfg->{'dcat'} = $p->{'dcat'}; }
    if (!defined($dcfg->{'int'})) { $dcfg->{'int'} = $p->{'int'}; }
    # TODO: Config var for "user-level docker catalog"
  }
  ############# Image Resolve and image specific options #################
  if (!$dcfg->{'dcat'}) { die("No docker catalog specified. Must be available for image label translation.\n"); }
  if (! -f $dcfg->{'dcat'}) { die("Configured docker catalog ('$dcfg->{'dcat'}') does not exist !\n"); }
  # TODO: Find docker catalog in path ?
  #my @cats  = grep({-f $_."/dockercat.conf.json"; } @paths);
  my $dcat = dockercat_load($dcfg->{'dcat'});
  
  # Roll full environment ?
  my $docker = DPUT::DockerRunner->new(%$dcfg);
  my $cmd = $docker->run('cmdstring' => 1);
  
}
