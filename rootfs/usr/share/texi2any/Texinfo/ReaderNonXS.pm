# Reader.pm: interface to Texinfo tree.
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
# The interface to the Texinfo tree provided in this file is similar to
# Pod::Simple::PullParser or XML::LibXML::Reader

# This module is not used in texi2any converters.  Using the Reader
# interface is slow in Perl and using the XS interface requires careful code
# and many functions replacements.  The SWIG interface should be used instead.

# ALTIMP Reader.pm
# ALTIMP XSTexinfo/reader_element/ReaderXS.xs
# ALTIMP C/main/reader.c

package Texinfo::Reader;

use strict;
use warnings;

use Carp qw(cluck confess);

# check that autovivification do not happen incorrectly.
#no autovivification qw(fetch delete exists store strict);

my %ignorable_text_types;
foreach my $text_type (
            'ignorable_spaces_after_command',
            'ignorable_spaces_before_command',
            'spaces_after_close_brace',
            'spaces_at_end',
            #'text_after_end',
            #'text_before_beginning',
            'spaces_after_argument',
            'spaces_after_cmd_before_arg',
            'spaces_before_argument',
  ) {
  $ignorable_text_types{$text_type} = 1;
}

# The stack holds pair of the children array and the index in this array.
# The index is the index of the previous element, starting at -1 when
# pushing on the stack.  When popping the stack, the parent element is
# at the current index.

sub new($) {
  my $tree = shift;

  if (!defined($tree)) {
    confess("Texinfo::Reader new undefined tree");
  }

  my $reader = {};

  bless $reader;

  $reader->{'stack'} = [[-1, [$tree]]];

  return $reader;
}

# For XS
# As can be seen, only the XS override returns something useful.
# A trick can be used to call this function only if with XS, by calling
# that function only if $token->{'element'} is undef as it may only happen
# with XS.  This is only relevant if the return value is needed, if the
# return value is ignored, it may not be an issue if the non-overriden
# function is called when there is no XS.
sub register_token_element($) {
  my $reader = shift;

  return undef;
}

# For XS
sub register_token_element_child($;$) {
}

sub _end_element($) {
  my $reader = shift;

  pop @{$reader->{'stack'}};
  if (!scalar(@{$reader->{'stack'}})) {
    return undef;
  }

  my $context = $reader->{'stack'}->[-1];
  my ($index, $contents_array) = @{$context};

  my $token = {'element' => $contents_array->[$index],
               'category' => Texinfo::Reader->TXI_READ_ELEMENT_END};

  return $token;
}

sub read($) {
  my $reader = shift;

  my $context = $reader->{'stack'}->[-1];
  my ($index, $contents_array) = @{$context};
  #print STDERR "EREAD @{$reader->{'stack'}}| $index ".scalar(@$contents_array)
  #  ." $contents_array\n";

  $context->[0]++;

  if ($context->[0] +1 > scalar(@$contents_array)) {
    return _end_element($reader);
  }

  my $element = $contents_array->[$context->[0]];

  my $token = {'element' => $element};

  if (ref($element) eq 'HASH') {
    print STDERR "ERROR:read:HASH "
       .Texinfo::Common::debug_print_element($element)."\n";
    cluck();
  }

  if (exists($element->{'text'})) {
    my $type = $element->{'type'};
    if (defined($type) and $ignorable_text_types{$type}) {
      $token->{'category'} = Texinfo::Reader->TXI_READ_IGNORABLE_TEXT;
    } else {
      $token->{'category'} = Texinfo::Reader->TXI_READ_TEXT;
    }
  } else {
    my $contents = $element->{'contents'};
    if (defined($contents)) {
      push @{$reader->{'stack'}}, [-1, $contents];
      $token->{'category'} = Texinfo::Reader->TXI_READ_ELEMENT_START;
    } else {
      $token->{'category'} = Texinfo::Reader->TXI_READ_EMPTY;
    }
  }

  return $token;
}

# The $ELEMENT argument is solely used to check that the end element
# matches.
sub skip_children($;$) {
  my ($reader, $element) = @_;

  my $token = _end_element($reader);

  if ($element) {
    my $end_element = $token->{'element'};
    if ($end_element ne $element) {
      confess("skip_children $end_element ne $element; "
        .Texinfo::Common::debug_print_element($end_element)."; "
        .Texinfo::Common::debug_print_element($element));
    }
  }

  return $token;
}

sub reader_collect_commands_list($$) {
  my ($root, $commands_list) = @_;

  my $collected_commands_list = [];
  my $commands_hash = {};
  foreach my $command_name (@$commands_list) {
    $commands_hash->{$command_name} = 1;
  }
  my $reader = Texinfo::Reader::new($root);
  my $next;

  while ($next = $reader->read()) {
    my $category = $next->{'category'};
    if ($category == Texinfo::Reader->TXI_READ_ELEMENT_START
        or $category == Texinfo::Reader->TXI_READ_EMPTY) {
      my $element = $next->{'element'};
      my $cmdname = $element->{'cmdname'};
      if (defined($cmdname) and exists($commands_hash->{$cmdname})) {
        push @{$collected_commands_list}, $element;
      }
    }
  }
  return $collected_commands_list;
}

1;
__END__
=head1 NAME

Texinfo::Reader - Texinfo tree reader

=head1 SYNOPSIS

  use Texinfo::Parser;
  use Texinfo::Reader;

  my $parser = Texinfo::Parser::parser();
  my $document = $parser->parse_texi_file("somefile.texi");

  my $start_element = $document->tree();

  my $reader = Texinfo::Reader::new($start_element);

  while (1) {
    my $next = $reader->read();
    last if (!defined($next));

    my $category = $next->{'category'};

    my $element = $next->{'element'};

    if ($category == Texinfo::Reader->TXI_READ_TEXT) {
      my $text = $element->{'text'};
      ....
    } elsif ($category == Texinfo::Reader->TXI_READ_ELEMENT_START) {
      my $cmdname = $element->{'cmdname'};
      ...
    ....
    }
  }

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

Note that this module is not used in C<texi2any>.

Note that this module could be removed at any time.

=head1 DESCRIPTION

C<Texinfo::Reader> offers an interface to a Texinfo tree obtained from
parsing Texinfo code.  This interface is based on a stream of tokens associated
to tree elements.  This interface is conceptually similar to the interface of
L<XML::LibXML::Reader> or L<Pod::Simple::PullParser>.

The Reader acts as a cursor going forward on the Texinfo tree and stopping
at each element on the way, providing with a new token.  The user's code keeps
control of the progress and simply calls the C<read()> function repeatedly to
progress to the next token in the Texinfo document order.  The other
function provides means for skipping sub-trees.

=head1 METHODS

=over

=item $reader = Texinfo::Reader::new ($element)
X<C<Texinfo::Reader::new>>

Initialize a reader starting at the I<$element> Texinfo tree element.

=item $token = $reader->read()
X<C<read>>

Returns the next token or undef at the end of the tree.

A token is an hash reference with string keys:

=over

=item element

The current tree element.

=item category

Information on the tree element and on the position read.  The possible token
category values are declared as constants and are accessed through
the C<Texinfo::Reader> package, like
C<< Texinfo::Reader->TXI_READ_ELEMENT_START >>.

The token category can take the following C<Texinfo::Reader> constant values:

=over

=item TXI_READ_ELEMENT_START

Start of the tree element, before getting the element contents.

=item TXI_READ_ELEMENT_END

End of the tree element after having read the contents (after a closing
brace, an @end, at the end of a container).

=item TXI_READ_TEXT

Text element.

=item TXI_READ_IGNORABLE_TEXT

Text element supposed to be ignored, such as spaces appearing after
an opening brace or around a comma delimiting arguments.

=item TXI_READ_EMPTY

A tree element which is not a text tree element and does not hold content.  For
Texinfo @-commands without braces nor line argument such as C<@@> and for empty
arguments.  For example the C<brace_container> argument container of C<@TeX{}>
is empty.  Also for invalid constructs such as brace @-commands without braces.

=back

=back

The Texinfo tree element is described in L<Texinfo::Parser/TEXINFO TREE>.

=item $token = $reader->skip_children($element)
X<C<skip_children>>

Skip the remaining of the contents currently being processed.
Return a token with the I<TXI_READ_ELEMENT_END> category, or undef at the end
of the tree.

If the I<$element> optional argument is specified, a fatal error is emitted if
it does not match with the parent element of the skipped contents.

=item $elements = reader_collect_commands_list($element, $command_names)

Collect all the tree elements corresponding to @-command names in the
I<$command_names> array reference, starting at I<$element>.  The
return value is an array reference of the collected elements, in the order of
their appearence in the Texinfo tree.

=back

=head2 C<Texinfo::Reader> and XS extensions

The Texinfo Perl modules can be setup to use Perl XS module extensions
in native code (written in C) that replace Perl package or methods
by native code for faster execution.  In general, using pure Perl or XS
extensions is transparent.  This is not fully the case for C<Texinfo::Reader>.
The XS interface is designed such that the Texinfo tree actually processed is
not the Perl elements tree, but a tree stored in native code in XS
extensions, corresponding to compiled C data structures.

If the C<Texinfo::Reader> XS extension is used, the element used to
initialize the reader through
L<< new|/$reader = Texinfo::Reader::new ($element) >>
need to have a link from Perl to native code C data registered in the
Perl element to find the C tree data corresponding to the Perl element.
This is done automatically if the element is the Texinfo tree root element.
For other elements, this link may need to be setup especially.

To setup this link explicitly for the element associated to the
current Reader token or the child elements of the current Reader token
the following methods may be called:

=over

=item $reader->register_token_element()

Add a link from the current token Perl element to the associated C
data.

=item $reader->register_token_element_child($index)

Add a link from the Perl element to the associated C data for the child of the
current token Perl element at index I<$index>.  If the first child of the
current token Perl element is of type C<arguments_line>, the child
of the C<arguments_line> tree element is selected instead of the child
of the current token Perl element.

=back

For example, to register all the elements upon reading them:

  while (1) {

    my $next = $reader->read();
    last if (!defined($next));

    my $element = $next->{'element'};

    my $registerd_element = $reader->register_token_element();

    if (!defined($element)) {
      $element = $registerd_element;
    }

    ...
  }

Calling these two functions is not the only possibility to create
a link from Perl to C data.  Another possibility is to use the
L<Texinfo::TreeElement> interface to access other elements from elements with
the link to C data already setup, or to use the
L<Texinfo::Example::TreeElementConverter> module methods.

=head1 SEE ALSO

L<Texinfo::Parser>. L<Texinfo::Document>.
L<Texinfo::Example::TreeElementConverter>.

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
