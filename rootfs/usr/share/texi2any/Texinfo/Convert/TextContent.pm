# TextContent.pm: return the text contents stripped of commands
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

package Texinfo::Convert::TextContent;

use 5.006;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Texinfo::Commands;
use Texinfo::CommandsValues;
use Texinfo::Convert::Utils;
use Texinfo::Convert::Text;
use Texinfo::Convert::Converter;

our @ISA = qw(Texinfo::Convert::Converter);

our $VERSION = '7.3';


my %ignored_brace_commands;
# Handle better @errormsg?
foreach my $ignored_brace_command ('hyphenation', 'errormsg') {
  $ignored_brace_commands{$ignored_brace_command} = 1;
}
my %ignored_block_commands;
foreach my $ignored_command (
  'html', 'tex', 'xml', 'docbook', 'latex', 'ignore', 'macro', 'rmacro',
  'linemacro') {
  $ignored_block_commands{$ignored_command} = 1;
}

my %ignored_types;

foreach my $type (
            'ignorable_spaces_after_command',
            'ignorable_spaces_before_command',
            'spaces_at_end',
            'space_at_end_menu_node',
            'spaces_before_paragraph',
            'spaces_after_close_brace') {
  $ignored_types{$type} = 1;
}

foreach my $type (
            'postamble_after_end',
            'preamble_before_beginning',
            'preamble_before_setfilename') {
  $ignored_types{$type} = 1;
}

my %defaults = (
  # Customization option variables
  'FORMAT_MENU'          => 'menu',
  # different from the default, which is undef
  'OUTFILE'              => '-',
);

sub converter_defaults($;$) {
  return \%defaults;
}

my %formatted_line_commands = %Texinfo::Commands::formatted_line_commands;
foreach my $def_command (keys(%Texinfo::Commands::def_commands)) {
  if ($Texinfo::Commands::line_commands{$def_command}) {
    $formatted_line_commands{$def_command} = 1;
  }
}

sub converter_initialize($) {
  my $self = shift;

  %{$self->{'formatted_line_commands'}}
    = %formatted_line_commands;
  if ($self->get_conf('TEXTCONTENT_COMMENT')) {
    $self->{'formatted_line_commands'}->{'c'} = 1;
    $self->{'formatted_line_commands'}->{'comment'} = 1;
  }
}

sub output($$) {
  my ($self, $document) = @_;

  return $self->output_tree($document);
}

sub convert_tree($$) {
  my ($self, $root) = @_;

  return $self->_convert($root);
}

sub convert($$) {
  my ($self, $document) = @_;

  my $root = $document->tree();

  return $self->_convert($root);
}

sub _convert($$);

sub _convert($$) {
  my ($self, $element) = @_;

  # determine name used to check command properties
  my $data_cmdname;
  if (exists($element->{'cmdname'})) {
    if ($element->{'cmdname'} eq 'item'
        and exists($element->{'contents'})
        and exists($element->{'contents'}->[0]->{'type'})
        and $element->{'contents'}->[0]->{'type'} eq 'line_arg') {
      $data_cmdname = 'item_LINE';
    } else {
      $data_cmdname = $element->{'cmdname'};
    }
  }

  return ''
  if (!(exists($element->{'type'})
        and $element->{'type'} eq 'def_line')
     and ((exists($element->{'type'})
           and exists($ignored_types{$element->{'type'}}))
          or (exists($element->{'type'})
              and $element->{'type'} eq 'arguments_line'
              and exists($Texinfo::Commands::blockitem_commands{
                                $element->{'parent'}->{'cmdname'}}))
          or (exists($element->{'cmdname'})
             and (exists($ignored_brace_commands{$element->{'cmdname'}})
                 or (exists($ignored_block_commands{$element->{'cmdname'}})
                     and !(exists($self->{'expanded_formats'})
                           and $self->{'expanded_formats'}->{$element->{'cmdname'}}))
                 or (exists(
             $Texinfo::Commands::inline_format_commands{$element->{'cmdname'}})
                     and (!exists($element->{'extra'}->{'format'})
                          or !$self->{'expanded_formats'}
                                        ->{$element->{'extra'}->{'format'}}))
                 or ($element->{'cmdname'} eq 'menu'
                     and $self->get_conf('FORMAT_MENU') eq 'nomenu')
             # here ignore most of the line commands
                 or (exists($element->{'contents'})
                     and exists($element->{'contents'}->[0]->{'type'})
                     and ($element->{'contents'}->[0]->{'type'} eq 'line_arg'
                          or $element->{'contents'}->[0]->{'type'} eq 'rawline_arg')
                     and !exists(
                      $self->{'formatted_line_commands'}->{$data_cmdname}))))));
  if (exists($element->{'text'})) {
    return $element->{'text'};
  }

  if (exists($element->{'cmdname'})) {
    if (exists($Texinfo::CommandsValues::nobrace_symbol_text{
                                                    $element->{'cmdname'}})) {
      return $Texinfo::CommandsValues::nobrace_symbol_text{
                                                        $element->{'cmdname'}};
    } elsif ($element->{'cmdname'} eq 'today') {
      if ($self->get_conf('TEST')) {
        return 'a sunny day';
      }
      my($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)
        = localtime(time);
      $year += ($year < 70) ? 2000 : 1900;
      return "$Texinfo::Convert::Utils::month_name[$mon] $mday, $year";
    } elsif (defined($Texinfo::CommandsValues::text_brace_no_arg_commands{
                                                      $element->{'cmdname'}})) {
      return Texinfo::Convert::Text::brace_no_arg_command($element, undef);
    } elsif (exists($Texinfo::Commands::accent_commands{$element->{'cmdname'}})) {
      my $result = Texinfo::Convert::Text::text_accents($element,
                  $self->{'convert_text_options'}->{'enabled_encoding'});
      return $result;
    }
  }
  my $result = '';
  if (exists($element->{'contents'})) {
    my $contents_nr = scalar(@{$element->{'contents'}});

    my $start = 0;
    if (exists($element->{'cmdname'})
        and exists(
          $Texinfo::Commands::inline_format_commands{$element->{'cmdname'}})) {
      # TODO there is no test for that code
      $start = 1;
    }
    for (my $i = $start; $i < $contents_nr; $i++) {
      my $content = $element->{'contents'}->[$i];
      $result .= _convert($self, $content);
      if (exists($content->{'type'})
          and $content->{'type'} eq 'block_line_arg'
          and exists($content->{'info'})
          and exists($content->{'info'}->{'spaces_after_argument'})
          and $result =~ /\S/) {
        $result .= $content->{'info'}->{'spaces_after_argument'}->{'text'};
      }
    }
  }

  if (exists($element->{'type'}) and $element->{'type'} eq 'line_arg') {
    $result .= "\n";
  }

  return $result;
}

1;
