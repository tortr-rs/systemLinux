# @configure_input@
#
# Add directories to @INC, Perl's module search path, to find modules,
# in the source and build directories or in installation directories.
#
# 'use Texinfo::ModulePath' should only occur once per program so that
# the initialization is only done once.  This makes the way this module
# is used very unusual.
#
# Also used to pass other information from configure to modules.

package Texinfo::ModulePath;

use strict;

use vars qw($VERSION);

$VERSION = '7.3';

use File::Basename;
use File::Spec;

# Used as a flag to say whether to look for data files in uninstalled
# locations.
our $texinfo_uninstalled = undef;

# uninstalled locations paths, if $Texinfo::ModulePath::texinfo_uninstalled
# Pathname of the tta/ build and source directories.  Used to find the locale
# data and other files.
our $t2a_builddir = '';
our $t2a_srcdir;

# installed locations paths, if not $Texinfo::ModulePath::texinfo_uninstalled
our $converter_datadir;
our $converter_libdir;
# C libraries directory
our $libraries_dir;

# installed locations paths
our $datadir;

# Other information passed to modules from configure
our $conversion_from_euc_cn = 'yes';
our $default_test_level = '1';

# Passed to texi2any.pl, which is not configured, to t/test_utils.pl
# and to modules.
our $enable_xs = 'no';
our $use_shared_txi_libraries = 'no';

my $converter = 'texi2any';

# If $PERL_MODULES_DIR and $CONVERTER_LIBDIR are given,
# (likely the installation directories)
# use them to add directories
# to @INC.
#
# PERL_MODULES_DIR for Texinfo Perl modules and bundled Perl modules.
# CONVERTER_LIBDIR for XS modules and C libraries.
# CONVERTER_DATADIR for HTML extensions, javascript
#
# otherwise use 't2a_srcdir'
# and 't2a_builddir' environment variables.
sub init {
  my $perl_modules_dir = shift;
  $converter_libdir = shift;
  $datadir = shift;

  if (defined($datadir)) {
    $converter_datadir = join('/', ($datadir, $converter));
  } else {
    $converter_datadir = undef;
  }

  my %named_args = @_;

  if (!$named_args{'installed'}) {
    $texinfo_uninstalled = 1;

    if ($ENV{'t2a_srcdir'}) {
      $t2a_srcdir = $ENV{'t2a_srcdir'};
    } elsif (defined $named_args{'updirs'}) {
      # the command used is always in the source directory
      my $argv0 = (-l $0) ? readlink($0) : $0;
      my ($real_command_name, $command_directory, $command_suffix)
              = fileparse($argv0, '.pl');
      my $updir = File::Spec->updir();

      # e.g. tta/t -> tta/t/../.. for 'updirs' = 2.
      my $count = $named_args{'updirs'};
      $t2a_srcdir = $command_directory;
      while ($count-- > 0) {
        $t2a_srcdir = join('/', ($t2a_srcdir, $updir));
      }
    }

    if (defined($t2a_srcdir)) {
      # For Texinfo::Parser and the rest.
      unshift @INC, join('/', ($t2a_srcdir, 'perl'));
      $perl_modules_dir = join('/', ($t2a_srcdir, 'maintain'));
    }

    # Find XS modules and C libraries in the build directory
    if (defined($ENV{'t2a_builddir'})) {
      $t2a_builddir = $ENV{'t2a_builddir'};
    } else {
      # this is correct for in-source builds only.
      $t2a_builddir = $t2a_srcdir;
    }
    if (defined($t2a_builddir)) {
      # For XS Modules
      unshift @INC, join('/', ($t2a_builddir, 'perl', 'XSTexinfo'));
      # for C libraries
      $libraries_dir = join('/', ($t2a_builddir, 'C'));
    }

  } else {
    $texinfo_uninstalled = 0;

    # for the Texinfo modules
    if (defined($perl_modules_dir)) {
      unshift @INC, $perl_modules_dir;
    }
    # for the XS modules and the C libraries
    if (defined($converter_libdir)) {
      # For XS Modules
      unshift @INC, join('/', ($converter_libdir, 'XS_extension'));
      # For C libraries
      $libraries_dir = join('/', ($converter_libdir, 'lib'));
    }
  }

  if (defined($perl_modules_dir)) {
    # Bundled Perl modules
    # '@USE_EXTERNAL_LIBINTL @' and similar are substituted
    if ('' ne 'yes') {
      unshift @INC, join('/', ($perl_modules_dir, 'lib',
                               'libintl-perl', 'lib'));
    }
    if ('no' ne 'yes') {
      unshift @INC, join('/', ($perl_modules_dir, 'lib',
                               'Unicode-EastAsianWidth', 'lib'));
    }
    if ('no' ne 'yes') {
      unshift @INC, join('/', ($perl_modules_dir, 'lib',
                               'Text-Unidecode', 'lib'));
    }
  }
}

sub import {
  my $class = shift;
  goto &init;
}

1;
