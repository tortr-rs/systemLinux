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

# This module has an implementation as XS extension:
# ALTIMP TreeElement.pm
# ALTIMP XSTexinfo/reader_element/TreeElement.xs
# In C, the tree element structure fields are accessed directly, there are
# no equivalent functions.

# The new() method of this module should be used for each creation
# of a Texinfo tree element.

# Except for the new() method, nothing in texi2any uses this module, because
# calling accessors instead of accessing hash keys is much slower in Perl, and
# also because using the XS interface requires careful code and many
# functions replacements.  The SWIG interface should be used instead.

package Texinfo::TreeElement;

use strict;
use warnings;

# Texinfo::Common depends on this module in code outside of functions,
# so it will be good not to depend on Texinfo::Common here.

# check that autovivification do not happen incorrectly.
#no autovivification qw(fetch delete exists store strict);

sub new($) {
  my $element = shift;

  bless $element;
  return $element;
}

# next 3 accessors are not actually used because using an accessor is much
# slower than accessing hash values
sub type($) {
  my $element = shift;

  return $element->{'type'};
}

sub cmdname($) {
  my $element = shift;

  return $element->{'cmdname'};
}

sub text($) {
  my $element = shift;

  return $element->{'text'};
}

sub children_number($) {
  my $element = shift;

  if (exists($element->{'contents'})) {
    return scalar(@{$element->{'contents'}});
  }
  return 0;
}

sub get_child($$) {
  my ($element, $index) = @_;

  if (exists($element->{'contents'})) {
    return $element->{'contents'}->[$index];
  }
  return undef;
}

# NOTE it is a complex type and not an element, so it complexify the
# API, but is simplifies code and could be more efficient
sub get_children($) {
  my $element = shift;

  return $element->{'contents'};
}

sub parent($) {
  my $element = shift;

  return $element->{'parent'};
}

sub source_info($) {
  my $element = shift;

  return $element->{'source_info'};
}

sub get_attribute($$) {
  my ($element, $attribute) = @_;

  if (exists($element->{'extra'})
      and exists($element->{'extra'}->{$attribute})) {
    return $element->{'extra'}->{$attribute};
  } elsif (exists($element->{'info'})
           and exists($element->{'info'}->{$attribute})) {
    return $element->{'info'}->{$attribute};
  }
  return undef;
}

sub source_marks_number($) {
  my $element = shift;

  if (exists($element->{'source_marks'})) {
    return scalar(@{$element->{'source_marks'}});
  }
  return 0;
}

sub add_to_element_contents($$) {
  my ($parent_element, $element) = @_;

  $element->{'parent'} = $parent_element;
  push @{$parent_element->{'contents'}}, $element;
}

# NOTE debug functions in Texinfo::Common cannot be used when the TreeElement
# interface only is used, they should be reimplemented with use of accessors.
# Could have been a good place for those functions (debug_print_element,
# debug_print_element_details and similar functions).

1;
__END__
=head1 NAME

Texinfo::TreeElement - Texinfo tree element interface

=head1 SYNOPSIS

  my $element = Texinfo::TreeElement::new({});

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

Note that this module is not used in C<texi2any> (except for the C<new> method,
which is trivial and could be moved to another module).

Note that this module could be removed at any time.

=head1 DESCRIPTION

C<Texinfo::TreeElement::new> should be called on every Perl tree
elements created.

C<Texinfo::TreeElement> defines accessors and methods for Texinfo tree elements
obtained from parsing Texinfo code.  There is no specific advantage of using
the accessors, but they may be needed when some Texinfo modules XS interfaces
are used.

These accessors are not used in C<texi2any>.

=head1 METHODS

=over

=item $element = new($element_hash)
X<C<new>>

Turns the I<$element_hash> element hash into a C<Texinfo::TreeElement> object.

This function is called on all the tree elements created in Texinfo modules
codes.  Since no accessors are used in C<texi2any> Texinfo modules,
the call to C<new> is mainly cosmetic.  It also allows to distinguish a
Texinfo tree element from a hash.

=item $type = $element->type()
X<C<type>>

Return the I<$element> type, or C<undef>.

=item $cmdname = $element->cmdname()
X<C<cmdname>>

Return the I<$element> command name, if defined, or C<undef>.

=item $text = $element->text()
X<C<text>>

Return the I<$element> text if the element is a text element, or C<undef>.

=item $number = $element->children_number()
X<C<children_number>>

Return the number of children elements contained in I<$element>.

=item $child = $element->get_child($index)
X<C<get_child>>

Return the I<$element> child element at index I<$index>.

=item $children_list = $element->get_children()
X<C<get_children>>

Return an array reference holding the elements contained in I<$element>.

=item $parent = $element->parent()
X<C<parent>>

Return the parent element of I<$element>.

=item $source_info = $element->source_info()
X<C<source_info>>

Return the I<$element> source info, or C<undef> if there is none.

=item $value = $element->get_attribute($attribute_name)
X<C<get_attribute>>

Return the I<$element> I<$attribute_name> attribute value.  If the
I<$attribute_name> does not exist or is not set at all, return C<undef>.

=item $element->add_to_element_contents($added_element)
X<C<add_to_element_contents>>

Insert I<$added_element> at the end of the I<$element> contents
(ie the element children array).

=back

=head2 C<Texinfo::TreeElement> and XS extensions

The Texinfo Perl modules can be setup to use Perl XS module extensions in
native code (written in C) that replace Perl package or methods by native code
for faster execution.  It may be important to use the C<Texinfo::TreeElement>
accessors that return elements instead of using hash keys described in
L<Texinfo::Parser/TEXINFO TREE> when some Texinfo modules XS interfaces are
used.

The Texinfo modules XS interface is designed such that the Texinfo tree
actually processed is not the Perl elements tree, but a tree stored in
native code in XS extensions, corresponding to compiled C data structures.  For
some Texinfo modules XS extensions, Perl tree elements need to have a link from
Perl to native code C data registered in the Perl element to find the C tree
data corresponding to a Perl element.

Using the C<Texinfo::TreeElement> methods may help setting up this link.
Indeed, if an element has already a link to C data,
the elements returned by C<Texinfo::TreeElement> methods will also have
this link setup.

For example, if I<$element> has already a link to C data, I<$element_child> will
also have a link to C data setup:

  my $element_child = $element->get_child(0)

Note that, even if XS extensions are used, calling
L<< C<new>|/$element = new($element_hash) >> does not set up a link to C,
L<< Texinfo::Example::TreeElementConverter C<new_tree_element>|Texinfo::Example::TreeElementConverter/$converter->new_tree_element($element, $use_sv) >> should be used for that.

For other ways to setup this link, see L<Texinfo::Example::TreeElementConverter>
and L<< Texinfo::Reader/C<Texinfo::Reader> and XS extensions >>.

=head1 SEE ALSO

L<Texinfo::Parser/TEXINFO TREE>.

=head1 AUTHOR

Patrice Dumas.

=head1 COPYRIGHT AND LICENSE

Copyright 2025- Free Software Foundation, Inc.  See the source file for
all copyright years.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or (at
your option) any later version.

=cut
