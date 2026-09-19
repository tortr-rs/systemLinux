# Texinfo.pm: output a Texinfo tree as Texinfo.
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

# ALTIMP perl/XSTexinfo/convert/ConvertToTexinfoXS.xs
# ALTIMP C/main/convert_to_texinfo.c

package Texinfo::Convert::Texinfo;

# Contains code loading the XS module, Perl code common to XS and NonXS
# and the Perl implementation of the conversion to Texinfo, as it may be
# used both with and without XS.

use 5.006;
use strict;

# stop \s from matching non-ASCII spaces, etc.  \p{...} can still be
# used to match Unicode character classes.
use if $] >= 5.014, re => '/a';

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Carp qw(cluck confess);

use Texinfo::XSLoader;

# commands definitions
use Texinfo::Commands;

use Texinfo::TreeElement;

# get_label_element
use Texinfo::Common;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
  convert_to_texinfo
  link_element_to_texi
  target_element_to_texi_label
);

our $VERSION = '7.3';


BEGIN {
  my $shared_library_name = "ConvertToTexinfoXS";
  if (!Texinfo::XSLoader::XS_convert_enabled()) {
    undef $shared_library_name;
  }

  my $loaded_package = Texinfo::XSLoader::init (
      "Texinfo::Convert::Texinfo",
      "Texinfo::Convert::TexinfoNonXS",
      $shared_library_name,
      "Texinfo::Convert::TexinfoXS",
      ['texinfo', 'texinfoxs'],
  );
}

# used in root_heading_command_to_texinfo
my %sectioning_heading_commands = %Texinfo::Commands::sectioning_heading_commands;

# TODO document?
sub link_element_to_texi($) {
  my $element = shift;

  my $result = '';
  return $result if (!exists($element->{'extra'}));
  if (exists($element->{'extra'}->{'manual_content'})) {
    $result = '('.convert_to_texinfo($element->{'extra'}->{'manual_content'})
                    .')';
  }
  if (exists($element->{'extra'}->{'node_content'})) {
    $result .= convert_to_texinfo($element->{'extra'}->{'node_content'});
  }
  return $result
}

# TODO document?
sub target_element_to_texi_label($) {
  my $element = shift;

  my $label_element = Texinfo::Common::get_label_element($element);
  # get_label_element does not handle links to external manuals in menus
  if (!defined($label_element)) {
    return link_element_to_texi($element);
  }
  return convert_to_texinfo(
   Texinfo::TreeElement::new({'contents' => $label_element->{'contents'}}));
}

# only used in Texinfo::Structuring.  Here and not in Texinfo::Structuring
# to use re => '/a'.
# $REFERENCE_NODE should always be a target element associated to
# a label.
sub check_node_same_texinfo_code($$) {
  my ($reference_node, $node_content) = @_;

  my $reference_node_texi;
  if (defined($reference_node->{'extra'}->{'normalized'})) {
    my $label_element = Texinfo::Common::get_label_element($reference_node);
    $reference_node_texi = convert_to_texinfo(
     Texinfo::TreeElement::new({'contents' => $label_element->{'contents'}}));
    $reference_node_texi =~ s/\s+/ /g;
  } else {
    $reference_node_texi = '';
  }

  my $node_texi;
  if (defined($node_content)) {
    my $contents_node = $node_content;
    if ($node_content->{'contents'}->[-1]->{'type'}
        and $node_content->{'contents'}->[-1]->{'type'}
                                      eq 'space_at_end_menu_node') {
      my $contents = [@{$node_content->{'contents'}}];
      pop @$contents;
      $contents_node
        = Texinfo::TreeElement::new({'contents' => $contents});
    }
    $node_texi = convert_to_texinfo($contents_node);
    $node_texi =~ s/\s+/ /g;
  } else {
    $node_texi = '';
  }
  return ($reference_node_texi eq $node_texi);
}

# for debugging.
sub root_heading_command_to_texinfo($) {
  my $element = shift;

  my $tree;
  if (exists($element->{'cmdname'})) {
    if (($element->{'cmdname'} eq 'node'
         or exists($sectioning_heading_commands{$element->{'cmdname'}}))
        and exists($element->{'contents'}->[0]->{'type'})
        and $element->{'contents'}->[0]->{'type'} eq 'arguments_line'
        and exists($element->{'contents'}->[0]->{'contents'}->[0]->{'type'})
        # Should always be true
        and $element->{'contents'}->[0]->{'contents'}->[0]->{'type'}
                                                           eq 'line_arg'
        and exists(
              $element->{'contents'}->[0]->{'contents'}->[0]->{'contents'})) {
      $tree = $element->{'contents'}->[0]->{'contents'}->[0];
    }
  } else {
    return "Not a command";
  }
  if (defined($tree)) {
    return '@'.$element->{'cmdname'}.' '
                .convert_to_texinfo(
               Texinfo::TreeElement::new({'contents' => $tree->{'contents'}}));
  } else {
    return '@'.$element->{'cmdname'};
  }
}

# The NonXS implementation is here, as it may be called by the Perl
# code associated with the XS module when there is no C data
# associated to the element.

my %brace_commands           = %Texinfo::Commands::brace_commands;
my %root_commands            = %Texinfo::Commands::root_commands;
my %block_commands           = %Texinfo::Commands::block_commands;
my %def_commands             = %Texinfo::Commands::def_commands;
my %nobrace_commands         = %Texinfo::Commands::nobrace_commands;
my %line_commands            = %Texinfo::Commands::line_commands;

sub convert_to_texinfoNonXS($);

# convert ELEMENT contents as comma separated arguments
sub _convert_args($) {
  my $element = shift;

  my $result = '';
  my $arg_nr = 0;
  foreach my $arg (@{$element->{'contents'}}) {
    next if ($arg->{'info'} and $arg->{'info'}->{'inserted'});
    $result .= ',' if ($arg_nr);
    $arg_nr++;
    $result .= convert_to_texinfoNonXS($arg);
  }
  return $result;
}

# Following subroutines deal with transforming a texinfo tree into texinfo
# text.  Should give the text that was used parsed, except for a few cases.
sub convert_to_texinfoNonXS($) {
  my $element = shift;

  confess "convert_to_texinfoNonXS: element undef" if (!defined($element));

  my $result = '';
  if (ref($element) ne 'Texinfo::TreeElement') {
    if (ref($element) eq 'HASH') {
      $result = 'CTTXI:HASH['
                  .Texinfo::Common::debug_print_element($element)."]";
    } else {
      confess "convert_to_texinfo: bad element type (".
                    ref($element).") $element";
    }
  }

  return '' if ((exists($element->{'info'})
                 and $element->{'info'}->{'inserted'})
                or (exists($element->{'type'})
                    and $element->{'type'} eq 'arguments_line'));

  if (exists($element->{'text'})) {
    if (exists($element->{'type'})
        and $element->{'type'} eq 'bracketed_linemacro_arg') {
      $result .= '{';
    }
    $result .= $element->{'text'};
    if (exists($element->{'type'})
        and $element->{'type'} eq 'bracketed_linemacro_arg') {
      $result .= '}';
    }
  } else {
    if (exists($element->{'cmdname'})) {
      my $cmdname = $element->{'cmdname'};
      my $data_cmdname;
      if ($cmdname eq 'item' and $element->{'contents'}
          and exists($element->{'contents'}->[0]->{'type'})
          and $element->{'contents'}->[0]->{'type'} eq 'line_arg') {
        $data_cmdname = 'item_LINE';
      } else {
        $data_cmdname = $cmdname;
      }

      $result .= '@'.$cmdname;

      if (exists($element->{'info'})
          and exists($element->{'info'}->{'spaces_after_cmd_before_arg'})) {
          $result
           .= $element->{'info'}->{'spaces_after_cmd_before_arg'}->{'text'};
      }

      my $spc_before_arg = '';
      if (exists($element->{'info'})
          and exists($element->{'info'}->{'spaces_before_argument'})) {
        $spc_before_arg
          = $element->{'info'}->{'spaces_before_argument'}->{'text'};
      }

      if (exists($nobrace_commands{$data_cmdname})) {
        # the spaces following a command are put in a text element in the
        # tree, not associated to the command element.
        # item, tab and headitem are nobrace commands with contents
        return $result if (!exists($element->{'contents'}));
      } elsif (exists($element->{'contents'})
          and (exists($element->{'contents'}->[0]->{'type'})
               and $element->{'contents'}->[0]->{'type'} eq 'arguments_line')) {
        # root commands and block commands that are not def commands
        $result .= $spc_before_arg;
        $result .= _convert_args($element->{'contents'}->[0]);
      } elsif (exists($brace_commands{$cmdname})
               or (exists($element->{'type'})
                   and ($element->{'type'} eq 'definfoenclose_command'
                        or $element->{'type'} eq 'macro_call'
                        or $element->{'type'} eq 'rmacro_call'))) {
        # contents may not be set for a command without braces.  In that
        # case it is better if the command is considered as a command without
        # argument.
        return $result if (!exists($element->{'contents'}));
        my $braces = 1;
        $braces = 0 if ($element->{'contents'}->[0]->{'type'} eq 'following_arg');
        $result .= '{' if ($braces);
        if ($cmdname eq 'verb') {
          $result .= $element->{'info'}->{'delimiter'};
        }
        $result .= $spc_before_arg;
        $result .= _convert_args($element);
        if ($cmdname eq 'verb') {
          $result .= $element->{'info'}->{'delimiter'};
        }
        $result .= '}' if ($braces);
        return $result;
      } elsif (exists($line_commands{$data_cmdname})
               or (exists($element->{'type'})
                   and ($element->{'type'} eq 'index_entry_command'
                        or $element->{'type'} eq 'macro_call_line'
                        or $element->{'type'} eq 'rmacro_call_line'))) {
        # line commands that are not root commands
        $result .= $spc_before_arg;
        $result .= _convert_args($element);
        return $result;
      } elsif (exists($def_commands{$data_cmdname})
               or (exists($element->{'type'})
                   and ($element->{'type'} eq 'linemacro_call'))) {
        # @def* commands (that are also block commands)
        $result .= $spc_before_arg;
      } else {
        warn "BUG: Unknown command type to convert to texinfo: $cmdname\n";
      }
    } else {
      if (exists($element->{'type'})
          and $element->{'type'} eq 'bracketed_arg') {
        $result .= '{';
      }
      if (exists($element->{'info'})
          and exists($element->{'info'}->{'spaces_before_argument'})) {
        $result .= $element->{'info'}->{'spaces_before_argument'}->{'text'};
      }
    }

    if (exists($element->{'contents'})) {
      foreach my $child (@{$element->{'contents'}}) {
        $result .= convert_to_texinfoNonXS($child);
      }
    }

    if (exists($element->{'info'})
        and exists($element->{'info'}->{'spaces_after_argument'})) {
      $result .= $element->{'info'}->{'spaces_after_argument'}->{'text'};
    }
    if (exists($element->{'info'})
        and exists($element->{'info'}->{'comment_at_end'})) {
      $result .= convert_to_texinfoNonXS($element->{'info'}->{'comment_at_end'})
    }
    $result .= '}' if (exists($element->{'type'})
                       and $element->{'type'} eq 'bracketed_arg');
  }
  return $result;
}

1;
__END__

=head1 NAME

Texinfo::Convert::Texinfo - Convert a Texinfo tree to Texinfo code

=head1 SYNOPSIS

  use Texinfo::Convert::Texinfo qw(convert_to_texinfo);

  my $texinfo_text = convert_to_texinfo($tree);

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

C<Texinfo::Convert::Texinfo> converts a Texinfo tree (described in
L<Texinfo::Parser>) to Texinfo code.  If the Texinfo tree results from
parsing some Texinfo document, The converted Texinfo code should be
exactly the same as the initial document, except that user defined @-macros
and C<@value> are expanded, and some invalid code is discarded.

=head1 METHODS

=over

=item $texinfo_text = convert_to_texinfo($tree)
X<C<convert_to_texinfo>>

Converts the Texinfo tree I<$tree> to Texinfo code.

=back

=head1 AUTHOR

Patrice Dumas, E<lt>bug-texinfo@gnu.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2010- Free Software Foundation, Inc.  See the source file for
all copyright years.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or (at
your option) any later version.

=cut
