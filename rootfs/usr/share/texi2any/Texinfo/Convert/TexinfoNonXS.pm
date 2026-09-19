# TexinfoNonXS.pm: output a Texinfo tree as Texinfo.  Non XS entry point.
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

# ALTIMP Texinfo/Convert/TexinfoXS.pm

package Texinfo::Convert::Texinfo;

use 5.006;
use strict;

use Carp qw(confess);

# entry point for convert_to_texinfo when no XS is used
sub convert_to_texinfo($) {
  my $element = shift;

  confess "convert_to_texinfo: element undef" if (!defined($element));

  return convert_to_texinfoNonXS($element);
}

1;
