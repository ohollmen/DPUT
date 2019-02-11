use ExtUtils::MakeMaker; # 6.64 - allows:
# CONFIGURE_REQUIRES BUILD_REQUIRES TEST_REQUIRES
# Test: perl -MExtUtils::MakeMaker -e "print $ExtUtils::MakeMaker::VERSION;";
# Does not work ?
# http://blogs.perl.org/users/neilb/2017/05/specifying-dependencies-for-your-cpan-distribution.html
WriteMakefile(
  'NAME'         => 'DPUT',  #  module name (Mod::Pack)
  'DISTNAME'         => 'DPUT',  #  Dist name (Mod-Pack)
  #'DISTNAME' => '', # Explicit dist filename
  'VERSION_FROM' => 'DPUT.pm', # finds $VERSION from a file
  'ABSTRACT'     => 'Data Processing Utility Toolkit',
  #ABSTRACT_FROM
  'AUTHOR'       => 'Olli Hollmen <olli.hollmen@gmail.com>',
  # Class name => ver
  'PREREQ_PM'    => {
    'Data::Dumper' => 0, # CORE
    'JSON' => 0,
    'Digest::MD5' => 0, # Examples (CORE)
  },
  #"test" => {"TESTS" => "t/*.t"}
  
  # Ref to executables to be copied to INST_SCRIPT directory
  # 'EXE_FILES' => [],
  # Mapping of XS to C files
  #'XS' => {'DPUT.xs' => 'DPUT.c'},
  #'XSOPT' => '-extern',
  #'TYPEMAPS' => ['','']
);
