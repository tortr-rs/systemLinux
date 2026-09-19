# Reader.pm: interface to Texinfo tree
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

# ALTIMP ReaderNonXS.pm

package Texinfo::Reader;

use 5.006;
use strict;
use warnings;

our $VERSION = '7.3';

use Texinfo::XSLoader;

BEGIN {
  my $shared_library_name = "ReaderXS";
  if (!Texinfo::XSLoader::XS_structuring_enabled()) {
    undef $shared_library_name;
  }

  Texinfo::XSLoader::init (
      "Texinfo::Reader",
      "Texinfo::ReaderNonXS",
      $shared_library_name,
      undef,
      ['texinfo', 'texinfoxs'],
  );
}

use constant {
  # for elements with contents, a start token is emitted when encountering
  # the element, and an end token after going through the element children.
  TXI_READ_ELEMENT_START => 0,
  TXI_READ_ELEMENT_END => 1,
  # text
  TXI_READ_TEXT => 2,
  # ignorable text
  TXI_READ_IGNORABLE_TEXT => 3,
  # no text but no content either.  Invalid constructs, such as brace
  # commands without braces may end up in this category.
  TXI_READ_EMPTY => 4,
};

our %token_category_name = (
  Texinfo::Reader::TXI_READ_ELEMENT_START => 'ELEMENT_START',
  Texinfo::Reader::TXI_READ_ELEMENT_END => 'ELEMENT_END',
  Texinfo::Reader::TXI_READ_TEXT => 'TEXT',
  Texinfo::Reader::TXI_READ_IGNORABLE_TEXT => 'IGNORABLE_TEXT',
  Texinfo::Reader::TXI_READ_EMPTY => 'EMPTY',
);

1;
