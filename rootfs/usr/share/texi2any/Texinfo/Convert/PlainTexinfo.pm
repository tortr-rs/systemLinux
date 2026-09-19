# PlainTexinfo.pm: convert the Texinfo tree as Texinfo
#
# Copyright 2012-2026 Free Software Foundation, Inc.
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
#
# Original author: Patrice Dumas <pertusus@free.fr>

# This calls Texinfo::Convert::Texinfo::convert_to_texinfo while
# inheriting standard functions from Texinfo::Convert::Converter.

# ALTIMP C/convert/plaintexinfo_converter_api.c

package Texinfo::Convert::PlainTexinfo;

use 5.006;
use strict;

use Texinfo::Options;

use Texinfo::Convert::Texinfo;
use Texinfo::Convert::Converter;

our @ISA = qw(Texinfo::Convert::Converter);

our $VERSION = '7.3';

my $regular_defaults
  = Texinfo::Options::get_regular_options('plaintexinfo_converter');
my %defaults = %{$regular_defaults};

sub converter_defaults($;$) {
  return \%defaults;
}

sub convert_tree($$) {
  my ($self, $root) = @_;

  return Texinfo::Convert::Texinfo::convert_to_texinfo($root);
}

sub output($$) {
  my ($self, $document) = @_;

  return $self->output_tree($document);
}

sub convert($$) {
  my ($self, $document) = @_;

  my $root = $document->tree();

  return $self->convert_tree($root);
}

1;
