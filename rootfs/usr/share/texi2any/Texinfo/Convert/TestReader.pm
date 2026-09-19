# TestReader.pm: test Texinfo::Reader.
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

package Texinfo::Example::TestReader;

use strict;
use warnings;

use Texinfo::ManipulateTree;
use Texinfo::Reader;
use Texinfo::Convert::Converter;

our @ISA = qw(Texinfo::Convert::Converter);

our $VERSION = '7.3';

sub _convert($$;$$) {
  my ($self, $tree, $fname_encoding, $use_filename) = @_;

  my $reader = Texinfo::Reader::new($tree);

  while (1) {
    my $token = $reader->read();
    if (!defined($token)) {
      print STDERR "DONE\n";
      return;
    } else {
      my ($current_nr, $result);
      my $element = $token->{'element'};
      my $category = $token->{'category'};
      if ($category == Texinfo::Reader::TXI_READ_ELEMENT_END) {
        $result
          = Texinfo::ManipulateTree::print_element_base($element,
                          undef, $fname_encoding, $use_filename);
      } else {
        ($current_nr, $result)
          = Texinfo::ManipulateTree::print_element_details($element,
                          0, undef, 0, $fname_encoding, $use_filename);
      }
      print STDERR "".$Texinfo::Reader::token_category_name{$category}
                    .": $result";
    }
  }
}

sub convert_tree($$) {
  my ($self, $tree) = @_;

  $self->_convert($tree);

  return '';
}

sub output($$) {
  my ($self, $document) = @_;

  my $tree = $document->tree();

  $self->convert_tree($tree);
  return undef;
}

sub convert($$) {
  my ($self, $document) = @_;

  my $tree = $document->tree();

  $self->convert_tree($tree);
  return undef;
}

1;
