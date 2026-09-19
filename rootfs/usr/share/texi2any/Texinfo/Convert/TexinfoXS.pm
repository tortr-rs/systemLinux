# TexinfoXS.pm: output a Texinfo tree as Texinfo.
#               Entry point with XS module with Perl code associated to XS.
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
#
# Original author: Patrice Dumas <pertusus@free.fr>
# Parts (also from Patrice Dumas) come from texi2html.pl or texi2html.init.

# ALTIMP Texinfo/Convert/TexinfoNonXS.pm

package Texinfo::Convert::Texinfo;

use 5.006;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Carp qw(confess);

# We do not define convert_to_texinfo directly in the XS module interface
# to be able to easily call the NonXS implementation if there is no C
# data along with the tree detected at runtime.

# expand a tree to the corresponding texinfo.
sub convert_to_texinfo($) {
  my $element = shift;

  confess("convert_to_texinfo: undef element") if (!defined($element));

  if (defined($element->{'tree_document_descriptor'})) {
    return plain_texinfo_convert_tree($element);
  }
  return convert_to_texinfoNonXS($element);
}

1;
