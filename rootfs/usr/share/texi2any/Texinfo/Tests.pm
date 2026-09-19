# common code for code test in t/*
#
# Copyright 2010-2026 Free Software Foundation, Inc.
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

package Texinfo::Tests;

use 5.006;

use strict;

use Test::More;

use File::Compare qw(compare); # standard since 5.004
use File::Spec;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
compare_dirs_files
configure_document_locales
find_dirs_t2a
is_diff
prepare_format_directories
unlink_dir_files
);

#eval {
# require Test::Differences; Test::Differences->import(('eq_or_diff_text', 'unified_diff')); unified_diff();
#};

#my $test_differences_loading_error = $@;

eval { require Text::Diff; Text::Diff->import('diff'); };

my $text_diff_loading_error = $@;

sub is_diff($$$) {
  my ($result, $reference, $test_name) = @_;

  #if (!$test_differences_loading_error) {
  #  eq_or_diff_text($result, $reference, $test_name);
  #} elsif ($text_diff_loading_error) {
  if ($text_diff_loading_error or !defined($reference)
      or ref($reference) ne '' or !defined($result)) {
    is($result, $reference, $test_name);
  } else {
    ok($result eq $reference, $test_name)
       or note((diff(\$reference, \$result)));
    #is($result, $reference, $test_name) or note(diff(\$reference, \$result));
  }
}

sub find_dirs_t2a(;$$) {
  my ($t2a_srcdir, $t2a_builddir) = @_;

  my $updir = File::Spec->updir();

  # Find $t2a_srcdir for input files and $srcdir for test results
  my $srcdir = $ENV{'srcdir'};

  if (!defined($srcdir) and defined($t2a_srcdir)) {
    $srcdir = join('/', ($t2a_srcdir, 'perl'));
  } elsif (defined($srcdir) and !defined($t2a_srcdir)) {
    $t2a_srcdir = join('/', ($srcdir, $updir));
  }

  $srcdir = '.' if (!defined($srcdir) or $srcdir eq '');
  if (!defined($t2a_srcdir)) {
    $t2a_srcdir = '..';
  }

  if (!defined($t2a_builddir)) {
    $t2a_builddir = $updir;
  }
  return $t2a_srcdir, $t2a_builddir, $srcdir;
}

# Find locales in builddir
sub configure_document_locales($) {
  my $t2a_builddir = shift;

  # NOTE if the LocaleData directory is not found, the test could still succeed
  # if the translations for the strings textdomain are found elsewhere in the
  # system.  If the translations found elsewhere are too old, some tests could
  # still fail.
  my $locales_dir;
  foreach my $dir ('LocaleData', join('/', ($t2a_builddir, 'LocaleData'))) {
    if (-d $dir) {
      $locales_dir = $dir;
    }
  }

  if (! defined($locales_dir)) {
    warn "No locales directory found, some tests could fail\n";
  }

  Texinfo::Translations::configure($locales_dir);
}

# not that subdirectories are not compared, so subdirectories generated
# by INFO_JS_DIR, if different, will not trigger an error in test, but
# will lead to different directories and files in diffs.
sub compare_dirs_files($$;$) {
  my ($dir1, $dir2, $ignore_files) = @_;

  my %dir1_files;
  my %dir2_files;
  my @errors;
  my %ignored_files_hash;
  foreach my $ignored_file (@$ignore_files) {
    $ignored_files_hash{$ignored_file} = 1;
  }
  if (opendir(DIR1, $dir1)) {
    my @files = readdir (DIR1);
    foreach my $file (@files) {
      next if (! -r "$dir1/$file" or ! -f "$dir1/$file"
               or exists($ignored_files_hash{$file}));
      $dir1_files{$file} = 1;
    }
    closedir (DIR1);
  } else {
    push @errors, "readdir $dir1: $!";
  }
  if (opendir(DIR2, $dir2)) {
    my @files = readdir (DIR2);
    foreach my $file (@files) {
      next if (! -r "$dir2/$file" or ! -f "$dir2/$file"
               or exists($ignored_files_hash{$file}));
      $dir2_files{$file} = 1;
    }
    closedir (DIR2);
  } else {
    push @errors, "readdir $dir2: $!";
  }
  if (scalar(@errors)) {
    return \@errors;
  }
  foreach my $file (sort(keys(%dir1_files))) {
    if (exists($dir2_files{$file})) {
      my $status = compare("$dir1/$file", "$dir2/$file");
      if ($status) {
        push @errors, "$dir1/$file and $dir2/$file differ: $status";
      }
      delete $dir2_files{$file};
    } else {
      push @errors, "No $file in $dir2";
    }
  }
  foreach my $file (sort(keys(%dir2_files))) {
    push @errors, "No $file in $dir1"
  }
  if (scalar(@errors)) {
    return \@errors;
  } else {
    return undef;
  }
}

#my $errors = compare_dirs_files('a', 'b',['nnn']);
#if ($errors) {
#  foreach my $error (@$errors) {
#    warn $error."\n";
#  }
#}

sub unlink_dir_files($;$) {
  my ($dir, $ignore_files) = @_;

  my %ignored_files_hash;
  foreach my $ignored_file (@$ignore_files) {
    $ignored_files_hash{$ignored_file} = 1;
  }
  if (opendir(DIR, $dir)) {
    my @files = readdir (DIR);
    foreach my $file (@files) {
      next if (! -f "$dir/$file"
               or exists($ignored_files_hash{$file}));
      unlink "$dir/$file" or warn "Could not unlink $dir/$file: $!\n";
    }
    closedir (DIR);
  } else {
    warn "readdir $dir: $!";
  }
}

my $default_result_base = 't/results/';

sub create_group_directory($;$) {
  my ($test_group, $result_base) = @_;

  $result_base = $default_result_base if (!defined($result_base));

  foreach my $dir ('t', $result_base,
                   join('/', ($result_base, $test_group))) {
    my $error;
    # to avoid a race conditon, first create the dir then test that it
    # exists
    mkdir $dir or $error = $!;
    if (! -d $dir) {
      die "mkdir $dir: $error\n";
    }
  }
}

sub prepare_format_directories($$$$;$) {
  my ($srcdir, $test_group, $test_name, $format_type, $result_base) = @_;

  $result_base = $default_result_base if (!defined($result_base));

  my $base = join('/', ($result_base, $test_group, $test_name));

  my $test_out_dir = join('/', ($base, 'out_'.$format_type));
  my $reference_dir = join('/', ($srcdir, $base, 'res_'.$format_type));

  mkdir ($base)
    if (! -d $base);
  if (! -d $test_out_dir) {
    mkdir ($test_out_dir);
  } else {
    # remove any files from previous runs
    unlink glob ("$test_out_dir/*");
  }
  return ($test_out_dir, $reference_dir);
}

1;
