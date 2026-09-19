# Copyright 2014-2026 Free Software Foundation, Inc.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

package Texinfo::XSLoader;

use 5.006;
use strict;
use warnings;

use DynaLoader;

#use version;

# disable_XS is set in CheckXS TestXS.pm to override the
# Texinfo::ModulePath::enable_xs based on the previous configure+make
our $disable_XS;

# Currently not set elsewhere, but could be if needed.
our $disable_C_libraries;

BEGIN {
  eval 'require Texinfo::ModulePath';
  if ($@ ne '') {
    # For configure test in CheckXS where Texinfo/ModulePath.pm is
    # not loaded.
    $Texinfo::ModulePath::texinfo_uninstalled = 1;
    $Texinfo::ModulePath::t2a_builddir = '';
  } else {
    if ($Texinfo::ModulePath::enable_xs eq 'no') {
      $disable_XS = 1;
    }
    if ($Texinfo::ModulePath::use_shared_txi_libraries eq 'no') {
      $disable_C_libraries = 1;
    }
  }
}

our $TEXINFO_XS;

our $VERSION = '7.3';

# used for comparison with XS_VERSION passed through configure and make.
# The github CI adds the date after a hyphen, turn the hyphen to a dot.
my $xs_version = $VERSION;
$xs_version =~ s/-/./g;
$xs_version =~ s/dev$//; # XS bootstrap functions choke on non-numeric version
#my $xs_version = version->declare($VERSION)->numify;

# Set from code to notify that Perl is embedded in C, and that XS needs to
# be used.  When Perl is embedded in C, many computations are done in C and
# are not directly passed to Perl.  These C data should be accessed/modified
# through XS interfaces.  The situation is similar to setting only handlers
# when calling XS methods from Perl, such that the data is not built to Perl,
# the changes are done in C only, at least until Perl structures are explicitly
# required through an XS interface.
our $embedded_xs;

sub set_XS_embedded {
  $embedded_xs = 1;
}

sub XS_parser_enabled {
  return ($embedded_xs or
          ((not defined($ENV{TEXINFO_XS})
                or $ENV{TEXINFO_XS} ne 'omit')
           and (not defined($ENV{TEXINFO_XS_PARSER})
                or $ENV{TEXINFO_XS_PARSER} ne '0')));
}

sub XS_structuring_enabled {
  return ($embedded_xs or
          (XS_parser_enabled()
           and (not defined($ENV{TEXINFO_XS_STRUCTURE})
                or $ENV{TEXINFO_XS_STRUCTURE} ne '0')));
}

sub XS_convert_enabled {
  return ($embedded_xs or
          (XS_structuring_enabled()
            and (not defined $ENV{TEXINFO_XS_CONVERT}
                 or $ENV{TEXINFO_XS_CONVERT} ne '0')));
}

# set from Texinfo/Parser.pm
my $xs_parser_loaded;
sub XS_parser_loaded {
  return $xs_parser_loaded;
}

sub set_XS_parser_loaded($) {
  my $parser_loaded = shift;

  $xs_parser_loaded = $parser_loaded;
}

# For verbose information about what's being done
sub _debug($) {
  my $msg = shift;

  if ($TEXINFO_XS eq 'debug') {
    warn $msg . "\n";
  }
}

# For messages to say that XS module couldn't be loaded
sub _message($) {
  my $msg = shift;

  if ($TEXINFO_XS eq 'debug'
      or $TEXINFO_XS eq 'required'
      or $TEXINFO_XS eq 'warn'
      or $embedded_xs) {
    warn $msg . "\n";
  }
}

# We look for the .la and .so files in @INC because this allows us to override
# which modules are used using -I flags to "perl".
sub _find_file_in_inc($) {
  my $file = shift;

  foreach my $dir (@INC) {
    next if (ref($dir) ne '');
    _debug("checking $dir/$file");
    if (-f "$dir/$file") {
      _debug("found $dir/$file");
      return ($dir, "$dir/$file");
    }
  }
  return undef;
}

my $added_xsdir;
my %dl_path_prepended_dirs;

# If $TRY_DIRECT_LOAD is set and no .la file is found in @INC, add
# the XS extensions directory to the DynaLoader path and let DynaLoader
# find the XS module file using the usual file names.
# This allows to have XS modules found even if packagers remove .la files
# installed in the default case on platforms where modules have usual names
# and are found by DynaLoader.
sub load_libtool_library {
  my ($module_name, $libtool_dir, $libtool_archive, $try_direct_load) = @_;

  my $dlname;

  if (!defined($libtool_archive)) {
    if (!$try_direct_load) {
      _message("$module_name: couldn't find Libtool archive file");
      return 0;
    } else {
      # this case can only happen for XS modules, for libraries direct load
      # is never attempted.
      $dlname = $module_name;
      if (!defined($added_xsdir)
          and defined($Texinfo::ModulePath::converter_libdir)) {
        $added_xsdir
         = join('/', ($Texinfo::ModulePath::converter_libdir, 'XS_extension'));
        unshift @DynaLoader::dl_library_path, $added_xsdir;
      }
      _debug("try direct load $module_name: $added_xsdir");
    }
  } else {
    my $fh;
    open $fh, $libtool_archive;
    if (!$fh) {
      _message("$module_name: couldn't open Libtool archive file");
      return 0;
    }

    # Look for the line in *.la giving the name of the loadable object.
    while (my $line = <$fh>) {
      if ($line =~ /^\s*dlname\s*=\s*'([^']+)'\s$/) {
        $dlname = $1;
        last;
      }
    }
    if (!defined($dlname) or $dlname eq '') {
      _message("$module_name: couldn't find name of shared object");
      return 0;
    }

    # Use unshift to place directories at start of search path.  This
    # way we avoid accidentally loading the wrong library, e.g. if someone
    # has some random /usr/lib/libtexinfo.so file.
    # The *.so file is under .libs in the build directory.
    # Consider that we are in the build directory if texinfo_uninstalled
    # is set, or if Texinfo::ModulePath has not been called, as is the
    # case when TestXS is called, as it is not called from a Perl script.
    if (not defined($Texinfo::ModulePath::texinfo_uninstalled)
        or $Texinfo::ModulePath::texinfo_uninstalled) {
      if (!$dl_path_prepended_dirs{"$libtool_dir/.libs"}) {
        unshift @DynaLoader::dl_library_path, "$libtool_dir/.libs";
      }
    }
    if (!$dl_path_prepended_dirs{$libtool_dir}) {
      unshift @DynaLoader::dl_library_path, $libtool_dir;
    }
  }

  my @found_files = DynaLoader::dl_findfile($dlname);
  if (scalar(@found_files) == 0) {
    _message("$module_name: couldn't find $dlname");
    return 0;
  }
  my $dlpath = $found_files[0];

  #my $flags = dl_load_flags $module; # This is 0 in DynaLoader
  my $flags = 0;
  my $libref = DynaLoader::dl_load_file($dlpath, $flags);
  if (!defined($libref)) {
    my $message = DynaLoader::dl_error();
    _message("$module_name: couldn't load file $dlpath: $message");
    return 0;
  }
  _debug("$dlpath loaded");
  push @DynaLoader::dl_shared_objects, $dlpath; # record files loaded

  my @undefined_symbols = DynaLoader::dl_undef_symbols();
  if (scalar(@undefined_symbols) != 0) {
    _message("$module_name: still have undefined symbols after dl_load_file");
  }
  return $libref;
}

my $loaded_additional_libraries = {};

# Load module $MODULE, either from XS implementation in
# Libtool file $MODULE_NAME and Perl file $PERL_EXTRA_FILE,
# or non-XS implementation $FALLBACK_MODULE.
# The package loaded is returned or undef if there is no fallback and the
# XS package was not loaded.
sub init {
  my ($module,
     $fallback_module,
     $module_name,
     $perl_extra_file,
     $additional_libraries,
   ) = @_;

  # Possible values for TEXINFO_XS environment variable:
  #
  # TEXINFO_XS=omit         # don't try loading xs at all
  # TEXINFO_XS=default      # try xs, silent fallback
  # TEXINFO_XS=warn         # try xs, warn on failure
  # TEXINFO_XS=required     # try xs, abort if not loadable, no fallback
  # TEXINFO_XS=requiredifenabled  # try xs, abort if enabled by TEXINFO_XS_*
  #                         # and not loadable
  # TEXINFO_XS=debug        # try xs, voluminuous debugging, fallback
  #
  # Other values are treated at the moment as 'default'.

  $TEXINFO_XS = $ENV{'TEXINFO_XS'};
  if (!defined($TEXINFO_XS)) {
    $TEXINFO_XS = '';
  }

  if ($embedded_xs and $TEXINFO_XS eq 'omit') {
    warn "ignoring TEXINFO_XS environment variable set to 'omit' ".
         "for embedded Perl\n";
    $ENV{'TEXINFO_XS'} = '';
    $TEXINFO_XS = '';
  }

  if ($TEXINFO_XS eq 'requiredifenabled' and $disable_XS) {
    $TEXINFO_XS = 'omit';
  }

  if ($TEXINFO_XS eq 'omit') {
    # Don't try to use the XS module
    goto FALLBACK;
  }

  if ($disable_XS) {
    _message("use of XS modules was disabled when Texinfo was built");
    goto FALLBACK;
  }

  if (!defined($module_name)) {
    goto FALLBACK;
  }

  # Consider that we are in the build directory if texinfo_uninstalled
  # is set, or if Texinfo::ModulePath has not been called, as is the
  # case when TestXS is called, as it is not called from a Perl script.
  my $uninstalled = (not defined($Texinfo::ModulePath::texinfo_uninstalled)
                     or $Texinfo::ModulePath::texinfo_uninstalled);

  if (defined($additional_libraries)) {
    # TODO if $disable_C_libraries is true, this is unlikely to succeed,
    # we could shortcut this code.
    foreach my $additional_library_name (@{$additional_libraries}) {
      my $additional_library = 'lib' . $additional_library_name;
      # Note that we do not try to load again a library that didn't load
      # before.
      if (!exists($loaded_additional_libraries->{$additional_library})) {
        my $libdir = $Texinfo::ModulePath::libraries_dir;
        my $ref;
        if (defined($libdir)) {
          my $libtool_lib_archive = "$libdir/$additional_library.la";
          if (-f $libtool_lib_archive) {
            _debug("found dependency $additional_library.la in $libdir");
            $ref = load_libtool_library($additional_library, $libdir,
                                        $libtool_lib_archive);
          } else {
            _debug("dependency $additional_library.la not found in $libdir");
          }
        } else {
          _debug("no directory for dependency $additional_library");
        }
        # If library is installed but .la file cannot be found, maybe because
        # .la files were removed, it may still be possible for the library to
        # be found through dynamic linking when the XS module is loaded if
        # there are RUNPATH or similar pointing to the installation directory
        # in the XS modules objects themselves.
        # Therefore, we only fallback if the library is not found and we
        # are in-source.
        if (!$ref and $uninstalled) {
          goto FALLBACK;
        } else {
          $loaded_additional_libraries->{$additional_library} = $ref;
        }
      }
    }
  }

  my ($libtool_dir, $libtool_archive) = _find_file_in_inc("$module_name.la");
  # If installed, try direct load of modules if .la file is not found, as
  # it should work in that case on platforms where libtool has installed
  # the module in the specified directory.
  my $libref = load_libtool_library($module_name, $libtool_dir,
                                    $libtool_archive, !$uninstalled);
  if (!$libref) {
    goto FALLBACK;
  }

  my $bootname = "boot_$module";
  $bootname =~ s/:/_/g;
  _debug("looking for $bootname");
  my $symref = DynaLoader::dl_find_symbol($libref, $bootname);
  if (!defined($symref)) {
    _message("$module_name: couldn't find $bootname symbol");
    goto FALLBACK;
  }
  _debug("trying to call $bootname...");
  my $boot_fn = DynaLoader::dl_install_xsub("${module}::bootstrap",
                                                  $symref); #, $dlname);

  if (!defined($boot_fn)) {
    _message("$module_name: couldn't bootstrap");
    goto FALLBACK;
  }
  _debug("  ...succeeded");

  # This is the module bootstrap function, which causes all the other
  # functions (XSUB's) provided by the module to become available to
  # be called from Perl code, after a check that the version argument
  # matches the XS object XS_VERSION value.  In our case, XS_VERSION
  # is set based on tta/configure.ac AC_INIT version passed
  # through Makefile.am.  The tta/configure.ac AC_INIT version
  # and the Perl modules VERSION should be synchronized with the top-level
  # configure.ac version.  The check therefore ensures that the XS objects
  # and the Perl module come from the same GNU Texinfo distribution.
  #print STDERR "REMARK: XS version: $xs_version\n";
  &$boot_fn($module, $xs_version);

  # This makes it easier to refer to packages and symbols by name.
  no strict 'refs';

  if (defined &{"${module}::init"}
      and !&{"${module}::init"} ($Texinfo::ModulePath::texinfo_uninstalled,
                                 $Texinfo::ModulePath::datadir,
                                 $Texinfo::ModulePath::t2a_builddir,
                                 $Texinfo::ModulePath::t2a_srcdir)) {
    _message("$module_name: error initializing");
    goto FALLBACK;
  }

  if (defined($perl_extra_file)) {
    eval "require $perl_extra_file";
    if ($@) {
      warn();
      die "Error loading $perl_extra_file\n";
    }
  }

  return $module;

 FALLBACK:
  if ($TEXINFO_XS eq 'required') {
    die "set the TEXINFO_XS environment variable to 'omit' to use the "
       ."pure Perl modules\n";
  } elsif ($embedded_xs) {
    die "Perl is embedded, unexpected failure loading $module XS, aborting\n";
  } elsif ($TEXINFO_XS eq 'warn' or $TEXINFO_XS eq 'debug') {
    if (defined($fallback_module)) {
      warn "falling back to pure Perl module $fallback_module\n";
    }
  } elsif ($TEXINFO_XS eq 'requiredifenabled') {
    if (defined($additional_libraries) and $disable_C_libraries) {
      # This happens if iconv is not found or not usable.
      # in that case, the loading of the module is expected to fail.
      # FIXME expected failure when overriding a specific function
      # if (!defined($fallback_module)) for modules without fallback.
      # Cannot use _debug here...
      #warn("No C libraries expected failure of loading $module_name\n");
    } elsif (!defined($module_name)) {
      # An undefined module name should only happen based on the TEXINFO_XS_*
      # environment variables values.
      if (!defined($fallback_module)) {
        die "extension disabled, no required fallback module for $module\n";
      }
    } else {
      die "extension $module_name enabled required for $module\n";
    }
  }

  # undef is returned only if there is no fallback and loading the module
  # failed.
  if (!defined($fallback_module)) {
    if ($TEXINFO_XS eq 'warn' or $TEXINFO_XS eq 'debug') {
      warn "no fallback module for $module\n";
    }
    return undef;
  }

  # Fall back to using the Perl code.
  # Note that if no import method can be found, then the call is skipped (this
  # special case is described in perldoc use), therefore the fallback module
  # does not need to implement import().
  # Use eval here to interpret :: properly in module name.
  eval "require $fallback_module; $module->import();";
  if ($@) {
    warn();
    die "Error loading $fallback_module\n";
  }

  return $fallback_module;
} # end init

my $XS_disable_for_override_error_output;

# Override subroutine $TARGET with $SOURCE.
sub override($$) {
  my ($target, $source) = @_;

  if ($disable_XS) {
    if (!$XS_disable_for_override_error_output) {
      _debug("use of XS for override was disabled when Texinfo was built");
      $XS_disable_for_override_error_output = 1;
    }
    return;
  }

  _debug("attempting to override $target with $source...");

  no strict 'refs'; # access modules and symbols by name.
  no warnings 'redefine'; # do not warn about redefining a function.

  if (defined &{"${source}"}) {
    *{"${target}"} = \&{"${source}"};
    _debug("  ...succeeded");
  } else {
    if ($TEXINFO_XS eq 'requiredifenabled') {
      die "extension loaded but overriding $target with $source failed\n";
    } else {
      _debug("  ...failed");
    }
  }
}


1;
__END__
