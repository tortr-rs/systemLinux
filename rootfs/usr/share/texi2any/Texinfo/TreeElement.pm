# TreeElement.pm: interface to Texinfo tree element.
#
# Copyright 2025-2026 Free Software Foundation, Inc.
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
# ALTIMP TreeElementNonXS.pm

package Texinfo::TreeElement;

use 5.006;
use strict;
use warnings;

our $VERSION = '7.3';

use Texinfo::XSLoader;

BEGIN {
  my $shared_library_name = "TreeElementXS";
  if (!Texinfo::XSLoader::XS_structuring_enabled()) {
    undef $shared_library_name;
  }

  Texinfo::XSLoader::init (
      "Texinfo::TreeElement",
      "Texinfo::TreeElementNonXS",
      $shared_library_name,
      undef,
      ['texinfo', 'texinfoxs', 'texinfo-convert', 'texinfo-convertxs'],
  );
}

1;
