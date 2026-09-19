# TexinfoMarkup.pm: output tree keeping Texinfo code information
#
# Copyright 2011-2026 Free Software Foundation, Inc.
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
#
#
# This is an abstract class, that calls markup language formatting
# functions, but does not implement them.  The type of markup corresponds
# to nested elements with attributes, similar to XML.  Initially setup
# for XML, but more generic.
#
# Markup language formatting functions should be implemented in modules that
# inherit from this module.  The functions to implement are documented in
# the POD section.

package Texinfo::Convert::TexinfoMarkup;

use 5.006;
use strict;

# have :alpha: match only ASCII
use if $] >= 5.014, re => '/a';

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Texinfo::Commands;

use Texinfo::TreeElement;

use Texinfo::Common;

# for section_level_adjusted_command_name
use Texinfo::Structuring;
use Texinfo::Convert::Converter;
use Texinfo::Convert::Unicode;
# for debugging and adding the original line for some commands
use Texinfo::Convert::Texinfo;
#use Data::Dumper;
use Carp qw(cluck);

our @ISA = qw(Texinfo::Convert::Converter);

our $VERSION = '7.3';


# our because it is used in the xml to texi translator and subclasses.
our %no_arg_commands_formatting = (
           '*' => 'linebreak',
           ' ' => ['spacecmd', ['type', 'spc']],
           "\t" => ['spacecmd', ['type', 'tab']],
           "\n" => ['spacecmd', ['type', 'nl']],
           '-' => 'hyphenbreak',  # hyphenation hint
           '|' => ['divideheading'],  # used in formatting commands
                                      # @evenfooting and friends
           '/' => 'slashbreak',
           ':' => 'noeos',
           '!' => 'eosexcl',
           '?' => 'eosquest',
           '.' => 'eosperiod',
           '@' => 'arobase',
           '{' => 'lbrace',
           '}' => 'rbrace',
           '&' => 'ampsymbol',  # avoid amp as it is already the entity for
                                # & in text in XML
           '\\' => 'backslash',  # should only appear in math

           'TeX' => 'tex',
           'LaTeX' => 'latex',
           'bullet' => 'bullet',
           'copyright'    => 'copyright',
           'registeredsymbol'   => 'registered',
           'dots'    => 'dots',
           'enddots'    => 'enddots',
           'error'        => 'errorglyph',
           'expansion'     => 'expansion',
           'arrow'        => 'rarr',
           'click'        => 'click',
           'minus'        => 'minus',
           'point'        => 'point',
           'print'        => 'printglyph',
           'result'       => 'result',
           'l'            => 'lslash',
           'L'            => 'Lslash',
           'today'        => ['today'],
           'comma'        => 'comma',
           'atchar'       => 'atchar',
           'ampchar'      => 'ampchar',
           'lbracechar'   => 'lbracechar',
           'rbracechar'   => 'rbracechar',
           'backslashchar' => 'backslashchar',
           'hashchar'      => 'hashchar',
           # in Texinfo::Convert::Converter::default_xml_no_arg_commands_formatting,
           # guillemotleft and guillemotright are mapped to laquo and raquo,
           # but guillemetleft and guillemetright are also mapped to those
           # entities.  To make sure that it is possible to go back to the
           # @-command from the entity, we use specific entities here
           'guillemotleft'   => 'guillemotleft',
           'guillemotright'  => 'guillemotright',
);

my %brace_commands = %Texinfo::Commands::brace_commands;

# use default XML formatting to complete the hash, removing XML
# specific formatting.  This avoids some code duplication.
my %default_xml_no_arg_commands_formatting =
    %Texinfo::Convert::Converter::xml_text_entity_no_arg_commands_formatting;

foreach my $command (keys(%default_xml_no_arg_commands_formatting)) {
  if (!exists($no_arg_commands_formatting{$command})) {
    if ($default_xml_no_arg_commands_formatting{$command} ne '') {
      if ($default_xml_no_arg_commands_formatting{$command} =~ /^&(.*);$/) {
        $no_arg_commands_formatting{$command} = $1;
      } else {
        die "BUG: Strange xml_no_arg_commands_formatting: $default_xml_no_arg_commands_formatting{$command}\n";
      }
    } else {
      $no_arg_commands_formatting{$command} = '';
    }
  }
}

# following is not format specific.  Some infos are taken from generic
# XML, but XML specific formatting is stripped.

# our because it is used in the xml to texi translator
our %accent_types = %Texinfo::Convert::Converter::xml_accent_entities;

# do not treat @dotless as an accent command but
# together with brace commands.
delete $accent_types{'dotless'};

# no entity
my @other_accents = ('tieaccent', 'ubaraccent', 'udotaccent');
foreach my $accent (@other_accents) {
  $accent_types{$accent} = $accent;
}

my %line_command_line_attributes = (
  'setfilename' => 'file',
  'documentencoding' => 'encoding',
  'verbatiminclude' => 'file',
  'documentlanguage' => 'lang',
);

my %line_command_numbered_arguments_attributes = (
  'definfoenclose' => [ 'command', 'open', 'close' ],
  'alias' => [ 'new', 'existing' ],
  'syncodeindex' => [ 'from', 'to' ],
  'synindex' => [ 'from', 'to' ],
);

my %nobrace_commands = %Texinfo::Commands::nobrace_commands;
my %line_commands = %Texinfo::Commands::line_commands;

foreach my $command ('item', 'headitem', 'tab') {
  delete $nobrace_commands{$command};
}

foreach my $command ('item', 'itemx') {
  delete $line_commands{$command};
}

my %default_args_code_style
  = %Texinfo::Convert::Converter::default_args_code_style;

# our because it is used in the xml to texi translator
our %commands_args_elements = (
  'namedanchor' => ['anchoridentifier', 'anchorname'],
  'email' => ['emailaddress', 'emailname'],
  'uref' => ['urefurl', 'urefdesc', 'urefreplacement'],
  'url' => ['urefurl', 'urefdesc', 'urefreplacement'],
  'link' => ['linknodename', 'linkrefname', 'linkinfofile'],
  'inforef' => ['inforefnodename', 'inforefrefname', 'inforefinfoname'],
  'image' => ['imagefile', 'imagewidth', 'imageheight',
              'alttext', 'imageextension'],
  # * means that the previous element is variadic, ie can appear indefinitely
  'example' => ['examplelanguage', 'examplearg', '*'],
  'quotation' => ['quotationtype'],
  'cartouche' => ['cartouchetitle'],
  'float' => ['floattype', 'floatname'],
  'itemize' => ['itemprepend'],
  'enumerate' => ['enumeratefirst'],
);

foreach my $ref_cmd ('pxref', 'xref', 'ref') {
  $commands_args_elements{$ref_cmd}
    = ['xrefnodename', 'xrefinfoname', 'xrefprinteddesc', 'xrefinfofile',
       'xrefprintedname'];
}

foreach my $explained_command (keys(%Texinfo::Commands::explained_commands)) {
  $commands_args_elements{$explained_command} = ["${explained_command}word",
                                                 "${explained_command}desc"];
}

foreach my $brace_command (keys(%Texinfo::Commands::brace_commands)) {
  if ($Texinfo::Commands::brace_commands{$brace_command} eq 'inline') {
    if ($brace_command eq 'inlinefmtifelse') {
      $commands_args_elements{$brace_command} = ["${brace_command}format",
             "${brace_command}contentif", "${brace_command}contentelse"];

    } else {
      $commands_args_elements{$brace_command} = ["${brace_command}format",
                                                 "${brace_command}content"];
    }
  }
}

my %defcommand_name_type = (
 'defline'   => 'symbol',
 'deftypeline' => 'symbol',
 'deffn'     => 'function',
 'defvr'     => 'variable',
 'deftypefn' => 'function',
 'deftypeop' => 'operation',
 'deftypevr' => 'variable',
 'defcv'     => 'classvar',
 'deftypecv' => 'classvar',
 'defop'     => 'operation',
 'deftp'     => 'datatype',
);

my %type_elements = (
  'paragraph' => 'para',
  'preformatted' => 'pre',
  'menu_entry' => 'menuentry',
  'menu_entry_leading_text' => 'menuleadingtext',
  'menu_entry_node' => 'menunode',
  'menu_entry_separator' => 'menuseparator',
  'menu_comment' => 'menucomment',
  'menu_entry_description' => 'menudescription',
  'menu_entry_name' => 'menutitle',
  'postamble_after_end' => 'postambleafterend',
  'preamble_before_beginning' => 'preamblebeforebeginning',
  'table_definition' => 'tableitem',
  'table_entry' => 'tableentry',
  'table_term' => 'tableterm',
  'row' => 'row',
  'multitable_head' => 'thead',
  'multitable_body' => 'tbody',
  'def_item' => 'definitionitem',
  'before_item' => 'beforefirstitem',
  'before_defline' => 'beforefirstdefline',
);

# Empty containers do not happen often, mainly when a source mark
# needs to be kept.  However, it is more robust to remove explictely
# empty containers that we want to remove instead of relying on a
# specific tree.
my %container_ignored_if_empty = (
  'preformatted' => 1,
  'menu_comment' => 1,
);

my %default_context_block_commands = (
  'float' => 1,
);

# converter_defaults() should be implemented by subclasses.
sub converter_defaults($;$) {
  return undef;
}

sub converter_initialize($) {
  my $self = shift;

  $self->{'context_block_commands'} = {%default_context_block_commands};
  foreach my $raw (grep {$Texinfo::Commands::block_commands{$_} eq 'format_raw'}
                        keys(%Texinfo::Commands::block_commands)) {
    $self->{'context_block_commands'}->{$raw} = 1
         if $self->{'expanded_formats'}->{$raw};
  }
}

sub conversion_initialization($;$) {
  my ($self, $document) = @_;

  if ($document) {
    $self->set_document($document);
  }

  $self->{'document_context'} = [{'monospace' => [0]}];
}

sub conversion_output_begin($;$$) {
  my ($self, $output_file, $output_filename) = @_;

  my $result = $self->txi_markup_header();
  $result .= $self->txi_markup_open_element('texinfo')."\n";
  if ($output_file ne '') {
    my $filename_element = $self->txi_markup_open_element('filename',
                                                  [['file', $output_filename]])
             .$self->txi_markup_close_element('filename')."\n";
    $result .= $filename_element;
  }
  return $result;
}

sub conversion_output_end($) {
  my $self = shift;

  return $self->txi_markup_close_element('texinfo')."\n";
}

# Main output function for the Texinfo language markup output files.
sub output($$) {
  my ($self, $document) = @_;

  return $self->output_tree($document);
}

# API for markup formatting subclasses
sub in_monospace($) {
  my $self = shift;

  return $self->{'document_context'}->[-1]->{'monospace'}->[-1];
}
# end of API

sub _format_command($$) {
  my ($self, $command) = @_;

  if (ref($no_arg_commands_formatting{$command}) eq '') {
    return $self->txi_markup_atom($command);
  } else {
    my @spec = @{$no_arg_commands_formatting{$command}};
    my $format_element = shift @spec;
    return $self->txi_markup_element($format_element, \@spec);
  }
}

sub _index_entry($$) {
  my ($self, $element) = @_;

  if ($element->{'extra'} and $element->{'extra'}->{'index_entry'}) {
    my $indices_information;
    if ($self->{'document'}) {
      $indices_information = $self->{'document'}->indices_information();
    }

    my ($index_entry, $index_info)
     = Texinfo::Common::lookup_index_entry($element->{'extra'}->{'index_entry'},
                                           $indices_information);
    my $attribute = [['index', $index_entry->{'index_name'}]];
    push @$attribute, ['number', $index_entry->{'entry_number'}]
        if (defined($index_entry->{'entry_number'}));
    # in case the index is not a default index, or the style of the
    # entry (in code or not) is not the default for this index
    my $entry_index_name = $index_entry->{'index_name'};
    my $in_code = $index_info->{'in_code'};
    if (!$Texinfo::Commands::index_names{$entry_index_name}
        or $in_code != $Texinfo::Commands::index_names{$entry_index_name}->{'in_code'}) {
      push @$attribute, ['incode', $in_code];
    }
    if ($index_info->{'merged_in'}) {
      push @$attribute, ['mergedindex', $index_info->{'merged_in'}];
    }
    my $result = $self->txi_markup_open_element('indexterm', $attribute);
    push @{$self->{'document_context'}}, {'monospace' => [0]};
    $self->{'document_context'}->[-1]->{'monospace'}->[-1] = 1
      if ($in_code);
    $result .= $self->_convert(Texinfo::Common::index_content_element($element));
    pop @{$self->{'document_context'}};
    $result .= $self->txi_markup_close_element('indexterm');
    return $result;
  }
  return '';
}

sub _infoenclose_attribute($$) {
  my ($self, $element) = @_;

  my @attribute = ();
  return @attribute if (!$element->{'extra'});
  push @attribute, ['begin', $element->{'extra'}->{'begin'}]
    if (defined($element->{'extra'}->{'begin'}));
  push @attribute, ['end', $element->{'extra'}->{'end'}]
    if (defined($element->{'extra'}->{'end'}));
  return @attribute;
}

sub _accent($$$;$$$$) {
  my ($self, $text, $element, $index_in_stack, $accents_stack,
      $in_upper_case, $attributes) = @_;

  $attributes = [] if (!defined($attributes));

  unshift @$attributes, ['type', $accent_types{$element->{'cmdname'}}];
  my $result = $self->txi_markup_open_element('accent', $attributes);
  $result .= $text;
  $result .= $self->txi_markup_close_element('accent');
  return $result;
}

sub convert($$) {
  my ($self, $document) = @_;

  $self->conversion_initialization($document);

  my $root = $document->tree();

  return $self->convert_tree($root);
}

sub convert_tree($$) {
  my ($self, $root) = @_;

  return $self->_convert($root);
}

sub _leading_spaces_arg($) {
  my $element = shift;

  if ($element->{'info'} and $element->{'info'}->{'spaces_before_argument'}
      and $element->{'info'}->{'spaces_before_argument'}->{'text'} ne '') {
    return ['spaces', $element->{'info'}->{'spaces_before_argument'}->{'text'}];
  } else {
    return ();
  }
}

# return spaces only, end of line is gathered by calling
# _format_comment_or_end_line
sub _end_line_spaces($$) {
  my ($self, $element) = @_;

  my $last_arg = $element->{'contents'}->[-1];

  if ($last_arg and $last_arg->{'info'}
      and $last_arg->{'info'}->{'spaces_after_argument'}) {
    # spaces and form feeds only, protection is needed for form feeds
    my $spaces
      = $last_arg->{'info'}->{'spaces_after_argument'}->{'text'};
    chomp $spaces;
    my $end_spaces = $self->txi_markup_protect_text($spaces);
    return $end_spaces;
  }
  return '';
}

sub _format_comment($$) {
  my ($self, $element) = @_;

  my $command_text = '';
  if (defined($element->{'info'})
      and defined($element->{'info'}->{'spaces_before_argument'})) {
    $command_text .= $element->{'info'}->{'spaces_before_argument'}->{'text'};
  }
  if ($element->{'contents'}) {
    my $line_arg = $element->{'contents'}->[0];
    if ($line_arg->{'contents'}) {
      $command_text .= $line_arg->{'contents'}->[0]->{'text'};
    }
    if (defined($line_arg->{'info'})
        and defined($line_arg->{'info'}->{'spaces_after_argument'})) {
      $command_text
        .= $line_arg->{'info'}->{'spaces_after_argument'}->{'text'};
    }
  }
  return $self->txi_markup_comment(" $element->{'cmdname'}" .$command_text);
}

sub _format_comment_or_end_line($$) {
  my ($self, $element) = @_;

  my ($comment, $end_line)
   = $self->comment_or_end_line($element);

  if ($comment) {
    return _format_comment($self, $comment);
  } else {
    return $end_line;
  }
}


# without the end of line.  The end of line is usually returned by
# _format_comment_or_end_line
sub _trailing_spaces_arg($) {
  my $element = shift;

  if ($element->{'info'} and
      $element->{'info'}->{'spaces_after_argument'}) {
    my $spaces = $element->{'info'}->{'spaces_after_argument'}->{'text'};
    chomp($spaces);
    if ($spaces ne '') {
      return ['trailingspaces', $spaces];
    }
  }
  return ();
}

sub _leading_trailing_spaces_arg($) {
  my $element = shift;

  my @result;
  push @result, _leading_spaces_arg($element);
  push @result, _trailing_spaces_arg($element);
  return @result;
}

sub _texinfo_line($$) {
  my ($self, $element) = @_;

  my $line
   = Texinfo::Convert::Texinfo::convert_to_texinfo(
                                         $element->{'contents'}->[-1]);
  chomp($line);
  if ($line ne '') {
    return ['line', $line];
  }
  return ();
}

sub _format_columnfractions($$) {
  my ($self, $element) = @_;

  my $attribute = [_leading_spaces_arg($element),
                   $self->_texinfo_line($element)];
  my $result = '';
  $result .= $self->txi_markup_open_element('columnfractions', $attribute);
  if ($element
      and $element->{'extra'}
      and $element->{'extra'}->{'misc_args'}) {
    foreach my $fraction (@{$element->{'extra'}->{'misc_args'}}) {
      $result .= $self->txi_markup_open_element('columnfraction',
                                    [['value', $fraction]])
                 .$self->txi_markup_close_element('columnfraction');
    }
  }
  $result .= $self->txi_markup_close_element('columnfractions');
  $result .= _format_comment_or_end_line($self, $element);
  return $result;
}

# used in brace commands
# NOTE not really needed now that comment_at_end are not generated
# for brace commands.
sub _convert_comment_at_end {
  my ($self, $element) = @_;

  my $comment = $element->{'info'}->{'comment_at_end'}
    if $element->{'info'};

  if ($comment) {
    return $self->convert_tree($comment);
  }
  return '';
}

sub _convert_def_line($$) {
  my ($self, $element) = @_;

  my $result = '';

  if ($element->{'cmdname'}) {
    # @def*x command has the command associated with def_line.
    my $attribute = [];
    push @$attribute, _leading_spaces_arg($element);
    $result .= $self->txi_markup_open_element($element->{'cmdname'},
                                              $attribute);
  }
  $result .= $self->txi_markup_open_element('definitionterm');
  $result .= $self->_index_entry($element);
  push @{$self->{'document_context'}->[-1]->{'monospace'}}, 1;
  my $def_command = $element->{'extra'}->{'def_command'};
  if ($element->{'contents'}
      and $element->{'contents'}->[0]->{'contents'}) {
    my $main_command;
    my $alias;
    if ($Texinfo::Common::def_aliases{$def_command}) {
      $main_command
        = $Texinfo::Common::def_aliases{$def_command};
      $alias = 1;
    } else {
      $main_command = $def_command;
      $alias = 0;
    }
    foreach my $arg (@{$element->{'contents'}->[0]->{'contents'}}) {
      my $type = $arg->{'type'};
      # should only happen for dubious trees in which the def line
      # was not split in def roles
      next if (!defined($type));
      my $content = $self->_convert($arg);
      if ($type eq 'spaces') {
        $content =~ s/\n$//;
        $result .= $content;
      } else {
        my $attribute = [];
        if ($type eq 'def_category' and $alias) {
          push @$attribute, ['automatic', 'on'];
        }
        my $format_element;
        if ($type eq 'def_name') {
          $format_element = $defcommand_name_type{$main_command};
        } elsif ($type eq 'def_arg') {
          $format_element = 'param';
        } elsif ($type eq 'def_typearg') {
          $format_element = 'paramtype';
        } else {
          $format_element = $type;
          $format_element =~ s/^def_//;
        }
        if ($arg->{'contents'} and scalar($arg->{'contents'})
            and $arg->{'contents'}->[0]->{'type'}
            and $arg->{'contents'}->[0]->{'type'} eq 'bracketed_arg') {
          push @$attribute, ['bracketed', 'on'];
          push @$attribute,
             _leading_trailing_spaces_arg($arg->{'contents'}->[0]);
        }
        $result
          .= $self->txi_markup_open_element("def$format_element", $attribute)
                  .$content
                  .$self->txi_markup_close_element("def$format_element");
      }
    }
  }
  pop @{$self->{'document_context'}->[-1]->{'monospace'}};
  $result .= _end_line_spaces($self, $element);
  $result .= $self->txi_markup_close_element('definitionterm');
  if ($element->{'cmdname'}) {
    $result .= $self->txi_markup_close_element($element->{'cmdname'});
  }
  chomp ($result);
  $result .= "\n";

  return $result;
}

my @node_directions = ('Next', 'Prev', 'Up');

# not used here, but it is consistent with other %commands_args_elements
# entries and may be used by XML to Texinfo converters
$commands_args_elements{'node'} = ['nodename'];
foreach my $direction (@node_directions) {
  push @{$commands_args_elements{'node'}}, 'node'.lc($direction);
}

sub _convert($$;$);

sub _convert($$;$) {
  my ($self, $element, $unused) = @_;

  if (0) {
  #if (1) { #}
    print STDERR "element\n";
    print STDERR "  Command: $element->{'cmdname'}\n" if ($element->{'cmdname'});
    print STDERR "  Type: $element->{'type'}\n" if ($element->{'type'});
    print STDERR "  Text: $element->{'text'}\n" if (defined($element->{'text'}));
    #print STDERR "  Special def_command: $element->{'extra'}->{'def_command'}\n"
    #  if (defined($element->{'extra'}) and $element->{'extra'}->{'def_command'});
  }

  if (defined($element->{'text'})) {
    if ($self->{'document_context'}->[-1]->{'raw'}) {
      return $element->{'text'};
    }
    my $result = '';
    my $text_element;
    if ($element->{'type'} and defined($type_elements{$element->{'type'}})) {
      $text_element = $type_elements{$element->{'type'}};
      $result .= $self->txi_markup_open_element($text_element);
    }
    $result .= $self->txi_markup_convert_text($element);
    if ($text_element) {
      $result .= $self->txi_markup_close_element($text_element);
    }
    return $result;
  }

  my @close_format_elements;
  # for @-commands with contents, to accumulate conversion results
  my $result = '';
  if ($element->{'cmdname'}) {
    my $cmdname = $element->{'cmdname'};
    if (defined($no_arg_commands_formatting{$cmdname})) {
      if ($self->{'itemize_command_as_argument'}
          and $element eq $self->{'itemize_command_as_argument'}) {
        # the element was determined to be an element without braces
        # when going through @itemize, reuse this information to output
        # a specific element.
        my $arguments = [['command', $cmdname]];
        return $self->txi_markup_element('formattingcommand', $arguments);
      }

      return $self->_format_command($cmdname);
    } elsif ($accent_types{$cmdname}) {
      if ($self->get_conf('OUTPUT_CHARACTERS')) {
        return $self->convert_accents($element, \&_accent, 1);
      } else {
        my $attributes = [];
        my $arg;
        if (!exists($element->{'contents'})) {
          $arg = '';
        } else {
          $arg = $self->_convert($element->{'contents'}->[0]);
          if (exists($element->{'info'})
              and exists($element->{'info'}->{'spaces_after_cmd_before_arg'})) {
            push @$attributes, ['spacesaftercmd',
               $element->{'info'}->{'spaces_after_cmd_before_arg'}->{'text'}];
          }
          if ($element->{'contents'}->[0]->{'type'} ne 'brace_container'
              and $element->{'contents'}->[0]->{'type'} ne 'brace_arg') {
            push @$attributes, ['bracketed', 'off'];
          }
        }
        return $self->_accent($arg, $element, undef, undef, undef,
                              $attributes);
      }
    } elsif ($cmdname eq 'item'
             or $cmdname eq 'itemx'
             or $cmdname eq 'headitem'
             or $cmdname eq 'tab') {
      if ($cmdname eq 'item'
          and $element->{'parent'}->{'cmdname'}
          and ($element->{'parent'}->{'cmdname'} eq 'itemize'
               or $element->{'parent'}->{'cmdname'} eq 'enumerate')) {
        $result .= $self->txi_markup_open_element('listitem',
                                [_leading_spaces_arg($element)]);
        if ($element->{'parent'}->{'cmdname'} eq 'itemize') {
          my $prepended_element
           = Texinfo::Common::item_itemize_prepended($element);
          $result .= $self->txi_markup_open_element('prepend')
            .$self->_convert($prepended_element)
            .$self->txi_markup_close_element('prepend');
        }
        unshift @close_format_elements, 'listitem';
      } elsif (($cmdname eq 'item'
                or $cmdname eq 'itemx')
               and $element->{'contents'}
               and $element->{'contents'}->[0]->{'type'}
               and $element->{'contents'}->[0]->{'type'} eq 'line_arg') {
        my $table_command = $element->{'parent'}->{'parent'}->{'parent'};
        my $format_item_command;
        my $attribute = [];
        if ($table_command->{'cmdname'}
            and $Texinfo::Commands::block_commands{$table_command->{'cmdname'}}
                                                              eq 'item_line') {
          # arguments_line type element
          my $arguments_line = $table_command->{'contents'}->[0];
          my $block_line_arg = $arguments_line->{'contents'}->[0];

          my $prepended_element
            = Texinfo::Common::block_item_line_command($block_line_arg);

          if ($prepended_element) {
            $format_item_command = $prepended_element->{'cmdname'};
            $attribute = [$self->_infoenclose_attribute($prepended_element)];
          }
        }
        my $line_item_result
          = $self->txi_markup_open_element($cmdname,
                                            [_leading_spaces_arg($element)]);
        if ($format_item_command) {
          $line_item_result .= $self->txi_markup_open_element('itemformat',
                              [['command', $format_item_command], @$attribute]);
        }
        $line_item_result .= $self->_index_entry($element);
        my $in_code;
        $in_code = 1
          if ($format_item_command
              and defined($default_args_code_style{$format_item_command})
              and $default_args_code_style{$format_item_command}->[0]);
        my $in_monospace_not_normal;
        if ($format_item_command) {
          if (defined($default_args_code_style{$format_item_command})
              and $default_args_code_style{$format_item_command}->[0]) {
            $in_monospace_not_normal = 1;
          } elsif ($brace_commands{$format_item_command}
                   and $brace_commands{$format_item_command} eq 'style_no_code') {
            $in_monospace_not_normal = 0;
          }
        }
        push @{$self->{'document_context'}->[-1]->{'monospace'}},
          $in_monospace_not_normal
            if (defined($in_monospace_not_normal));

        my $arg = $self->convert_tree($element->{'contents'}->[0]);
        my $end_space = _end_line_spaces($self, $element);

        pop @{$self->{'document_context'}->[-1]->{'monospace'}}
          if (defined($in_monospace_not_normal));

        $line_item_result .= $arg . $end_space;
        if ($format_item_command) {
          $line_item_result .= $self->txi_markup_close_element('itemformat');
        }
        my $end_line = _format_comment_or_end_line($self, $element);
        $line_item_result
           .= $self->txi_markup_close_element($cmdname).$end_line;
        return $line_item_result;
      } elsif (($cmdname eq 'item'
                or $cmdname eq 'headitem'
                or $cmdname eq 'tab')
               and $element->{'parent'}->{'type'}
               and $element->{'parent'}->{'type'} eq 'row') {
        $result .= $self->txi_markup_open_element('entry',
                                          [['command', $cmdname],
                                                _leading_spaces_arg($element)]);
        unshift @close_format_elements, 'entry';
      } # otherwise we have an incorrect construct, for instance
        # out of block commands @item, @itemx in enumerate or multitable...
    } elsif ($element->{'type'} and $element->{'type'} eq 'index_entry_command'
             and $element->{'extra'} and $element->{'extra'}->{'index_entry'}) {
      my $indices_information;
      if ($self->{'document'}) {
        $indices_information = $self->{'document'}->indices_information();
      }

      my ($index_entry, $index_info)
        = Texinfo::Common::lookup_index_entry($element->{'extra'}->{'index_entry'},
                                              $indices_information);
      my $format_element;
      my $attribute = [];
      if (exists $line_commands{$cmdname}) {
        $format_element = $cmdname;
      } else {
        $format_element = 'indexcommand';
        $attribute = [['command', $cmdname]];
      }
      push @$attribute, ['index',
                         $index_entry->{'index_name'}];
      push @$attribute, _leading_spaces_arg($element);

      # this is important to get the spaces before a @subentry
      my $end_line_spaces = _end_line_spaces($self, $element);
      my $end_line = _format_comment_or_end_line($self, $element);

      return $self->txi_markup_open_element($format_element, $attribute)
          .$self->_index_entry($element)
          .$self->txi_markup_close_element($format_element).$end_line_spaces
          .${end_line};
    } elsif (exists($line_commands{$cmdname})) {
      my $type = $line_commands{$cmdname};
      if ($type eq 'text') {
        return '' if ($cmdname eq 'end');
        my $attribute;
        if ($line_command_line_attributes{$cmdname}) {
          if ($element->{'extra'}
              and defined($element->{'extra'}->{'text_arg'})) {
            push @$attribute, [$line_command_line_attributes{$cmdname},
                  $element->{'extra'}->{'text_arg'}];
          }
        }
        my $arg = $self->convert_tree($element->{'contents'}->[0]);
        my $end_space = _end_line_spaces($self, $element);
        my $end_line = _format_comment_or_end_line($self, $element);
        push @$attribute, _leading_spaces_arg($element);
        return $self->txi_markup_open_element($cmdname, $attribute)
                .$arg.$end_space
                .$self->txi_markup_close_element($cmdname).${end_line};
      } elsif ($type eq 'line') {
        if ($cmdname eq 'node') {
          my $nodename;
          my $node_relations;
          if ($element->{'extra'} and $element->{'extra'}->{'is_target'}) {
            $nodename = $element->{'extra'}->{'normalized'};
            my $nodes_list = $self->{'document'}->nodes_list();
            $node_relations
              = $nodes_list->[$element->{'extra'}->{'node_number'} -1];
          } else {
            $nodename = '';
          }
          $result .= $self->txi_markup_open_element('node',
                    [['identifier', $nodename], _leading_spaces_arg($element)]);
          push @{$self->{'document_context'}->[-1]->{'monospace'}}, 1;
          # arguments_line type element
          my $arguments_line = $element->{'contents'}->[0];
          my $line_arg = $arguments_line->{'contents'}->[0];
          $result .= $self->txi_markup_open_element('nodename',
                               [_trailing_spaces_arg($line_arg)]);
          $result .= $self->_convert({'contents'
                                  => $line_arg->{'contents'}})
            if ($nodename ne '');
          $result .= $self->txi_markup_close_element('nodename');
          # first arg is the node name, directions start at 1.
          my $direction_index = 1;
          my $pending_empty_directions = '';
          foreach my $direction (@node_directions) {
            my $format_element = 'node'.lc($direction);
            if ($node_relations and $node_relations->{'node_directions'}
                and $node_relations->{'node_directions'}->{lc($direction)}) {
              my $node_direction
                  = $node_relations->{'node_directions'}->{lc($direction)};
              my $node_name = '';
              my $attributes = [];
              if ($arguments_line->{'contents'}->[$direction_index]) {
                push @$attributes, _leading_trailing_spaces_arg(
                          $arguments_line->{'contents'}->[$direction_index]);
              }
              if (scalar(@{$arguments_line->{'contents'}}) < $direction_index +1
                  or !defined($arguments_line->{'contents'}->[$direction_index]->{'extra'})
                  or !(defined($arguments_line->{'contents'}->[$direction_index]
                                                    ->{'extra'}->{'manual_node'}
                       or defined($arguments_line->{'contents'}->[$direction_index]
                                                     ->{'extra'}->{'normalized'})))) {
                push @$attributes, ['automatic', 'on'];

                # TODO since we call get_label_element, we only use internal
                # nodes for directions, external nodes could be used too.
                if (defined($node_direction->{'extra'}->{'normalized'})) {
                  my $label_element
                    = Texinfo::Common::get_label_element($node_direction);
                  if (defined($label_element)) {
                    $node_name .= Texinfo::Common::normalize_top_node_name(
                      $self->_convert({'contents'
                               => $label_element->{'contents'}}));
                  }
                }
              } else {
                $node_name
                  = $self->_convert(
                          $arguments_line->{'contents'}->[$direction_index]);
              }
              $result .= "$pending_empty_directions".
                $self->txi_markup_open_element($format_element, $attributes)
                .$node_name.
                $self->txi_markup_close_element($format_element);
              $pending_empty_directions = '';
            } else {
              if ($arguments_line->{'contents'}->[$direction_index]) {
                $pending_empty_directions .=
                  $self->txi_markup_open_element($format_element,
                    [_leading_trailing_spaces_arg(
                          $arguments_line->{'contents'}->[$direction_index])])
                            .$self->txi_markup_close_element($format_element);
              }
            }
            $direction_index++;
          }
          if (! $self->get_conf('TXI_MARKUP_NO_SECTION_EXTENT')) {
            $result .= $self->txi_markup_close_element('node');
          }
          $result .= _format_comment_or_end_line($self, $arguments_line);
          pop @{$self->{'document_context'}->[-1]->{'monospace'}};
        } elsif ($Texinfo::Commands::root_commands{$cmdname}) {
          my $attribute = [_leading_spaces_arg($element)];
          my $level_adjusted_cmdname
            = Texinfo::Structuring::section_level_adjusted_command_name($element);
          if ($level_adjusted_cmdname ne $cmdname) {
            unshift @$attribute, ['originalcommand', $cmdname];
          }
          $result .= $self->txi_markup_open_element($level_adjusted_cmdname,
                                                    $attribute);
          my $closed_section_element;
          if ($self->get_conf('TXI_MARKUP_NO_SECTION_EXTENT')) {
            $closed_section_element
               = $self->txi_markup_close_element($level_adjusted_cmdname);
          } else {
            $closed_section_element = '';
          }

          # arguments_line type
          my $arguments_line = $element->{'contents'}->[0];
          my $arg = $self->convert_tree($arguments_line->{'contents'}->[0]);
          my $end_space = _end_line_spaces($self, $arguments_line);
          my $end_line
            = _format_comment_or_end_line($self, $arguments_line);

          $result .= $self->txi_markup_open_element('sectiontitle')
                    .$arg.$end_space
                    .$self->txi_markup_close_element('sectiontitle')
                    .$closed_section_element.$end_line;
        } elsif ($Texinfo::Commands::def_commands{$cmdname}) {
          $result .= _convert_def_line($self, $element);
          return $result;
        } else {
          my $attribute = [_leading_spaces_arg($element)];
          if ($cmdname eq 'listoffloats') {
            unshift @$attribute, ['type',
                                  $element->{'extra'}->{'float_type'}];
          }
          my $arg = $self->convert_tree($element->{'contents'}->[0]);
          my $end_space = _end_line_spaces($self, $element);
          my $end_line = _format_comment_or_end_line($self, $element);
          return $self->txi_markup_open_element($cmdname, $attribute)
               .$arg.$end_space
               .$self->txi_markup_close_element($cmdname).$end_line;
        }
      } elsif ($type eq 'lineraw') {
        if ($cmdname eq 'c' or $cmdname eq 'comment') {
          return _format_comment($self, $element);
        } elsif ($cmdname eq 'clear' or $cmdname eq 'set'
                 or $cmdname eq 'clickstyle' or $cmdname eq 'unmacro') {
          my $attribute = [_leading_spaces_arg($element)];
          my $misc_args;
          if (defined($element->{'extra'})
              and defined($element->{'extra'}->{'misc_args'})) {
            $misc_args = $element->{'extra'}->{'misc_args'};
          }
          if (defined($misc_args) and scalar(@$misc_args)) {
            if ($cmdname eq 'clear' or $cmdname eq 'set'
                or $cmdname eq 'unmacro') {
              unshift @$attribute, ['name', $misc_args->[0]];
            } elsif ($cmdname eq 'clickstyle') {
              my $click_command = $misc_args->[0];
              $click_command =~ s/^\@//;
              unshift @$attribute, ['command', $click_command];
            } elsif ($cmdname eq 'unmacro') {
            }
          }
          my $arg = $self->convert_tree($element->{'contents'}->[0]);
          my $end_space = _end_line_spaces($self, $element);
          my $end_line = _format_comment_or_end_line($self, $element);
          return $self->txi_markup_open_element($cmdname, $attribute)
               .$arg.$end_space
               .$self->txi_markup_close_element($cmdname).$end_line;
        } else {
          my $attribute = [_leading_spaces_arg($element)];
          my $arg;
          if ($element->{'contents'}->[0]->{'contents'}) {
            $arg = $self->txi_markup_protect_text(
              $element->{'contents'}->[0]->{'contents'}->[0]->{'text'})
          } else {
            $arg = '';
          }
          my $end_space = _end_line_spaces($self, $element);
          my $end_line = _format_comment_or_end_line($self, $element);
          return $self->txi_markup_open_element($cmdname, $attribute)
               .$arg.$end_space
               .$self->txi_markup_close_element($cmdname).$end_line;
        }
      } else {
        print STDERR "BUG: unknown line_command style $type\n"
           if ($type ne 'specific');
        my $args_attributes;
        if ($line_command_numbered_arguments_attributes{$cmdname}) {
          $args_attributes
             = $line_command_numbered_arguments_attributes{$cmdname};
        } elsif ($cmdname eq 'columnfractions') {
          return _format_columnfractions($self, $element);
        } else {
          $args_attributes = ['value'];
        }
        my $attribute = [_leading_spaces_arg($element)];
        my $arg_index = 0;
        if (defined($element->{'extra'})
            and defined($element->{'extra'}->{'misc_args'})) {
          foreach my $arg_attribute (@{$args_attributes}) {
            if (defined ($element->{'extra'}->{'misc_args'}->[$arg_index])) {
              push @$attribute, [$arg_attribute,
                        $element->{'extra'}->{'misc_args'}->[$arg_index]];
            }
            $arg_index++;
          }
        }
        my $end_line = _format_comment_or_end_line($self, $element);
        # not sure if it may happen
        $end_line = "\n" if ($end_line eq '');
        push @$attribute, $self->_texinfo_line($element);
        return $self->txi_markup_open_element($cmdname, $attribute)
                    .$self->txi_markup_close_element($cmdname).$end_line;
      }
    } elsif (exists($nobrace_commands{$cmdname})) {
      # other or skipspace, symbol commands should be selected above
      # as being in no_arg_commands_formatting
      my $spaces = '';
      $spaces = $element->{'extra'}->{'spaces_after_command'}
        if ($element->{'extra'} and $element->{'extra'}->{'spaces_after_command'}
            and $element->{'extra'}->{'spaces_after_command'} ne '');
      return $self->txi_markup_open_element($cmdname)
              .$self->txi_markup_close_element($cmdname).$spaces;
    } elsif ($element->{'type'}
             and $element->{'type'} eq 'definfoenclose_command') {
      my $in_monospace_not_normal;
      if (defined($default_args_code_style{$cmdname})
          and $default_args_code_style{$cmdname}->[0]) {
        $in_monospace_not_normal = 1;
      } elsif ($brace_commands{$cmdname}
               and $brace_commands{$cmdname} eq 'style_no_code') {
        $in_monospace_not_normal = 0;
      }
      push @{$self->{'document_context'}->[-1]->{'monospace'}},
        $in_monospace_not_normal
          if (defined($in_monospace_not_normal));
      my $arg = $self->_convert($element->{'contents'}->[0]);
      pop @{$self->{'document_context'}->[-1]->{'monospace'}}
        if (defined($in_monospace_not_normal));
      my $command_result = $self->txi_markup_open_element('infoenclose',
                                          [['command', $cmdname],
                                       $self->_infoenclose_attribute($element)])
             .$arg.$self->_convert_comment_at_end($element->{'contents'}->[0]).
                 $self->txi_markup_close_element('infoenclose');
      return $command_result;
    } elsif ($element->{'contents'}
             and exists($brace_commands{$cmdname})) {

      if ($Texinfo::Commands::inline_format_commands{$cmdname}
          and $element->{'extra'} and $element->{'extra'}->{'format'}
          and $self->{'expanded_formats'}->{$element->{'extra'}->{'format'}}) {
        if ($cmdname eq 'inlineraw') {
          push @{$self->{'document_context'}}, {'monospace' => [0]};
          $self->{'document_context'}->[-1]->{'raw'} = 1;
        }
        my $command_result = '';
        if (scalar(@{$element->{'contents'}}) >= 2
              and defined($element->{'contents'}->[1])
              and $element->{'contents'}->[1]->{'contents'}
              and scalar(@{$element->{'contents'}->[1]->{'contents'}})) {
          $command_result = $self->_convert({'contents'
                                         => [$element->{'contents'}->[1]]});
        }
        if ($cmdname eq 'inlineraw') {
          pop @{$self->{'document_context'}};
        }
        return $command_result;
      } elsif ($cmdname eq 'value') {
        # value in tree corresponds to an unknown flag, ignored here
        return '';
      }


      # this is used for commands without args, or associated to the
      # first argument
      my $attribute = [];
      if ($cmdname eq 'verb') {
        push @$attribute, ['delimiter', $element->{'info'}->{'delimiter'}];
      } elsif ($cmdname eq 'anchor'
               or $cmdname eq 'namedanchor') {
        my $anchor_name;
        if ($element->{'extra'} and $element->{'extra'}->{'is_target'}) {
          $anchor_name = $element->{'extra'}->{'normalized'};
        } else {
          $anchor_name = '';
        }
        push @$attribute, ['identifier', $anchor_name];
      }

      my $space_after_command_attribute;
      if ($element->{'info'}
          and $element->{'info'}->{'spaces_after_cmd_before_arg'}) {
        $space_after_command_attribute = ['spacesaftercmd',
                $element->{'info'}->{'spaces_after_cmd_before_arg'}->{'text'}];
      }

      my @format_elements;
      my $main_cmdname;
      if ($commands_args_elements{$cmdname}) {
        # command with arguments, format the arguments using their specific
        # elements
        @format_elements = @{$commands_args_elements{$cmdname}};
        $main_cmdname = $cmdname;
      } else {
        # command with only one argument, the command itself is used as
        # element for the first argument
        @format_elements = ($cmdname);
        # leading spaces are directly associated to the @-command for @-command
        # in context brace_commands
        push @$attribute, _leading_spaces_arg($element);
        push @$attribute, $space_after_command_attribute
           if (defined($space_after_command_attribute));
      }

      if ($Texinfo::Commands::brace_commands{$cmdname} eq 'context') {
        push @{$self->{'document_context'}}, {'monospace' => [0]};
      }
      my $last_empty_element;
      my $args_or_one_arg_cmd = '';
      my $arg_index = 0;
      foreach my $format_element (@format_elements) {
        if (defined($element->{'contents'}->[$arg_index])) {
          # Leading spaces are gathered here except for context brace_commands
          # (gathered just above).
          push @$attribute,
            _leading_spaces_arg($element->{'contents'}->[$arg_index]);
          my $in_monospace_not_normal;
          if (defined($default_args_code_style{$cmdname})
              and $default_args_code_style{$cmdname}->[$arg_index]) {
            $in_monospace_not_normal = 1;
          } elsif ($brace_commands{$cmdname}
                   and $brace_commands{$cmdname} eq 'style_no_code') {
            $in_monospace_not_normal = 0;
          }
          push @{$self->{'document_context'}->[-1]->{'monospace'}},
            $in_monospace_not_normal
              if (defined($in_monospace_not_normal));
          my $arg = $self->_convert($element->{'contents'}->[$arg_index]);
          my $comment_at_end
            = $self->_convert_comment_at_end($element->{'contents'}->[$arg_index]);
          pop @{$self->{'document_context'}->[-1]->{'monospace'}}
            if (defined($in_monospace_not_normal));

          if ($element->{'contents'}->[$arg_index]->{'info'}
              and $element->{'contents'}->[$arg_index]
                                      ->{'info'}->{'spaces_after_argument'}) {
            $arg .= $element->{'contents'}->[$arg_index]
                   ->{'info'}->{'spaces_after_argument'}->{'text'};
          }

          if (!defined($main_cmdname) or $arg ne '' or scalar(@$attribute) > 0
              or $comment_at_end ne '') {
            $args_or_one_arg_cmd .=
                 $self->txi_markup_open_element($format_element, $attribute)
                      .$arg.$comment_at_end
                      .$self->txi_markup_close_element($format_element);
            $last_empty_element = undef;
          # we keep the last empty argument to be able to prepend it to be able
          # to reconstitute trailing empty arguments in the original Texinfo
          # code.
          # For example, for @bracecmd{a,b,,c,,} we keep the last (6th argument)
          # empty element.
          } elsif (defined($main_cmdname)) {
            $last_empty_element
               = $self->txi_markup_open_element($format_element)
                           .$self->txi_markup_close_element($format_element);
          }
          $attribute = [];
        } else {
          last;
        }
        $arg_index++;
      }
      if ($last_empty_element) {
        $args_or_one_arg_cmd .= $last_empty_element;
      }
      if ($Texinfo::Commands::brace_commands{$cmdname} eq 'context') {
        pop @{$self->{'document_context'}};
      }
      if (not defined($main_cmdname)) {
        # one argument @-command
        return $args_or_one_arg_cmd;
      }
      # This is for the main command
      $attribute = [];
      push @$attribute, $space_after_command_attribute
           if (defined($space_after_command_attribute));
      if ($cmdname eq 'image') {
        if (Texinfo::Common::element_is_inline($element)) {
          push @$attribute, ['where', 'inline'];
        }
      } elsif ($Texinfo::Commands::ref_commands{$cmdname}) {
        if ($element->{'contents'}) {
          my $normalized;
          my $node_arg = $element->{'contents'}->[0];
          if ($node_arg and $node_arg->{'extra'}
              and $node_arg->{'extra'}->{'node_content'}) {
            my $normalized;
            if (defined($node_arg->{'extra'}->{'normalized'})) {
              $normalized = $node_arg->{'extra'}->{'normalized'};
            } else {
              $normalized
        = Texinfo::Convert::NodeNameNormalization::convert_to_node_identifier(
                  Texinfo::TreeElement::new(
                   $node_arg->{'extra'}->{'node_content'}));
            }
            if ($normalized) {
              push @$attribute, ['label', $normalized];
            }
          }
          my $manual;
          my $manual_arg_index = 3;
          if ($cmdname eq 'link' or $cmdname eq 'inforef') {
            $manual_arg_index = 2;
          }
          if (defined($element->{'contents'}->[$manual_arg_index])
              and $element->{'contents'}->[$manual_arg_index]->{'contents'}
              and @{$element->{'contents'}->[$manual_arg_index]->{'contents'}}) {

            Texinfo::Convert::Text::set_options_code(
                                 $self->{'convert_text_options'});
            Texinfo::Convert::Text::set_options_encoding_if_not_ascii($self,
                                  $self->{'convert_text_options'});
            $manual = Texinfo::Convert::Text::convert_to_text(
                               $element->{'contents'}->[$manual_arg_index],
                                   $self->{'convert_text_options'});
            Texinfo::Convert::Text::reset_options_encoding(
                                 $self->{'convert_text_options'});
            Texinfo::Convert::Text::reset_options_code(
                                 $self->{'convert_text_options'});
          }
          if (!defined($manual) and $node_arg
              and $node_arg->{'extra'}
              and $node_arg->{'extra'}->{'manual_content'}) {
            Texinfo::Convert::Text::set_options_code(
                                 $self->{'convert_text_options'});
            Texinfo::Convert::Text::set_options_encoding_if_not_ascii($self,
                                  $self->{'convert_text_options'});
            $manual = Texinfo::Convert::Text::convert_to_text(
                         $node_arg->{'extra'}->{'manual_content'},
                                   $self->{'convert_text_options'});
            Texinfo::Convert::Text::reset_options_encoding(
                                 $self->{'convert_text_options'});
            Texinfo::Convert::Text::reset_options_code(
                                 $self->{'convert_text_options'});
          }
          if (defined($manual)) {
            my $manual_base = $manual;
            $manual_base =~ s/\.[^\.]*$//;
            $manual_base =~ s/^.*\///;

            push @$attribute, ['manual', $manual_base]
                  if ($manual_base ne '');
          }
        }
      }
      # this never happens as there is no @-commands with more than one
      # argument that is also a context brace_commands.  Leading spaces
      # after the command brace opening are only associated with command
      # if a context brace_commands, therefore they are with the first argument.
      push @$attribute, _leading_spaces_arg($element);
      return $self->txi_markup_open_element($main_cmdname, $attribute)
                 .$args_or_one_arg_cmd
                 .$self->txi_markup_close_element($main_cmdname);
    } elsif (exists($Texinfo::Commands::block_commands{$cmdname})) {
      if ($self->{'context_block_commands'}->{$cmdname}) {
        push @{$self->{'document_context'}}, {'monospace' => [0]};
      }
      my $prepended_elements = '';
      my $attribute = [];
      if ($cmdname eq 'itemize'
          or $Texinfo::Commands::block_commands{$cmdname}
                                                        eq 'item_line') {
        # arguments_line type element
        my $arguments_line = $element->{'contents'}->[0];
        my $block_line_arg = $arguments_line->{'contents'}->[0];

        my $command_argument;
        if ($cmdname eq 'itemize') {
          $command_argument
            = Texinfo::Common::block_line_argument_command($block_line_arg);
        } else {
          $command_argument
            = Texinfo::Common::item_line_block_line_argument_command(
                                                         $block_line_arg);
        }

        if ($command_argument) {
          if ($element->{'cmdname'} eq 'itemize'
              and !$command_argument->{'contents'}) {
            # this is used to determine that a command appears on the @itemize
            # line without braces, for the command line arguments
            # conversion just below.
            # It could have been possible to use the tree in the command as
            # argument formatting, but this is simpler, and $command_argument
            # was already obtained by going through the tree.
            $self->{'itemize_command_as_argument'} = $command_argument;
          }
          push @$attribute,
           (['commandarg', $command_argument->{'cmdname'}],
             $self->_infoenclose_attribute($command_argument));
        }
      } elsif ($cmdname eq 'enumerate') {
        my $arguments_line = $element->{'contents'}->[0];
        my $block_line_arg = $arguments_line->{'contents'}->[0];
        my $specification = '1';
        if (exists($block_line_arg->{'contents'})
            and exists($block_line_arg->{'contents'}->[0]->{'text'})) {
          my $spec_text = $block_line_arg->{'contents'}->[0]->{'text'};
          $specification = $spec_text if ($spec_text =~ /^(\d+|[[:alpha:]])$/);
        }
        push @$attribute, ['first', $specification];
      } elsif ($cmdname eq 'float' and $element->{'extra'}) {
        if ($element->{'extra'}->{'is_target'}) {
          push @$attribute, ['identifier', $element->{'extra'}->{'normalized'}];
        }
        push @$attribute, ['type',
                           $element->{'extra'}->{'float_type'}];
        if ($element->{'extra'}
            and defined($element->{'extra'}->{'float_number'})) {
          push @$attribute, ['number',
                             $element->{'extra'}->{'float_number'}];
        }
      } elsif ($cmdname eq 'verbatim') {
        push @$attribute, ['space', 'preserve'];
      } elsif ($cmdname eq 'macro'
               or $cmdname eq 'rmacro'
               or $cmdname eq 'linemacro') {
        if (defined($element->{'extra'})
            and defined($element->{'extra'}->{'macro_name'})) {
          my $macro_name = $element->{'extra'}->{'macro_name'};
          push @$attribute, ['name', $macro_name];
          my $macro_args_nr = scalar(@{$element->{'extra'}->{'misc_args'}});
          if ($macro_args_nr) {
            for (my $i = 0; $i < $macro_args_nr; $i++) {
              my $formal_arg = $element->{'extra'}->{'misc_args'}->[$i];
              $prepended_elements .= $self->txi_markup_open_element('formalarg')
                .$self->txi_markup_protect_text($formal_arg)
                .$self->txi_markup_close_element('formalarg');
            }
          }
        }
        # through arguments_line type and macro_line type
        my $line = $element->{'contents'}->[0]->{'contents'}->[0]->{'text'};
        chomp($line);
        if ($line ne '') {
          push @$attribute, ['line', $line];
        }
      }
      if ($self->{'expanded_formats'}->{$cmdname}) {
        $self->{'document_context'}->[-1]->{'raw'} = 1;
      } else {
        my @end_command_spaces;
        my $end_command;
        if ($element->{'contents'} and scalar(@{$element->{'contents'}}) > 0
            and $element->{'contents'}->[-1]->{'cmdname'}
            and $element->{'contents'}->[-1]->{'cmdname'} eq 'end') {
          $end_command = $element->{'contents'}->[-1];
          push @end_command_spaces, _leading_spaces_arg($end_command);
        }
        if (scalar(@end_command_spaces)) {
          $end_command_spaces[0]->[0] = 'endspaces';
        }
        $result .= $self->txi_markup_open_element($cmdname,
                                   [@$attribute, _leading_spaces_arg($element),
                                    @end_command_spaces])
                   .${prepended_elements};
        my $arguments_list;
        my $arguments_line;
        if ($element->{'contents'}
            and $element->{'contents'}->[0]->{'type'}
            and $element->{'contents'}->[0]->{'type'} eq 'arguments_line') {
          $arguments_line = $element->{'contents'}->[0];
          $arguments_list = $arguments_line->{'contents'};
        }
        if ($arguments_list) {
          my $variadic_element = undef;
          my $last_empty_element;
          my $end_line = '';
          if ($commands_args_elements{$cmdname}) {
            my $arg_index = 0;
            foreach my $arg_element (@{$arguments_list}) {
              my $format_element;
              if (defined($variadic_element)) {
                $format_element = $variadic_element;
              } else {
                if ($commands_args_elements{$cmdname}->[$arg_index] eq '*') {
                  $variadic_element
                    = $commands_args_elements{$cmdname}->[$arg_index-1];
                  $format_element = $variadic_element;
                  # the last argument was empty, it is the same argument
                  # as the variadic argument, it needs to be output to have
                  # it count as the last non variadic argument.
                  if ($last_empty_element) {
                    $result .= $last_empty_element;
                    $last_empty_element = undef;
                  }
                } else {
                  $format_element
                    = $commands_args_elements{$cmdname}->[$arg_index];
                }
              }
              my $spaces = [];
              my $arg = '';
              my $end_space = '';
              if (defined($arg_element)) {
                my $in_code;
                 $in_code = 1
                  if (defined($default_args_code_style{$cmdname})
                    and $default_args_code_style{$cmdname}->[$arg_index]);
                push @{$self->{'document_context'}->[-1]->{'monospace'}}, 1
                  if ($in_code);
                if ($arg_index != 0) {
                  push @$spaces, _leading_spaces_arg($arg_element);
                }
                if ($arg_index+1 eq scalar(@{$arguments_list})) {
                  # last argument
                  $arg = $self->convert_tree($arg_element);
                  $end_space = _end_line_spaces($self, $arguments_line);
                  $end_line
                   = _format_comment_or_end_line($self, $arguments_line);

                  # happens for @-commands interrupted by other commands
                  # incorrectly present on the line
                  $end_line = "\n" if ($end_line eq '');
                } else {
                  $arg = $self->_convert($arg_element);
                  push @$spaces, _trailing_spaces_arg($arg_element);
                }
                pop @{$self->{'document_context'}->[-1]->{'monospace'}}
                  if ($in_code);
              }
              # must add every variadic argument even if empty to get the
              # correct count
              if ($arg ne '' or scalar(@$spaces) or $variadic_element) {
                $result .= $self->txi_markup_open_element($format_element,
                                                          $spaces)
                            .$arg.$end_space
                            .$self->txi_markup_close_element($format_element);
                $last_empty_element = undef;
              } else {
                if ($arg_index > 0) {
                  if ($end_space ne '') {
                    push @$spaces, ['spaces', $end_space];
                  }
                  # we keep the last empty argument to be able to prepend
                  # it to be able to reconstitute trailing empty arguments
                  # in the original Texinfo code.
                  $last_empty_element
                     = $self->txi_markup_open_element($format_element, $spaces)
                              .$self->txi_markup_close_element($format_element);
                } else {
                  $result .= $end_space;
                }
              }
              $arg_index++;
            }
            if ($last_empty_element) {
              $result .= $last_empty_element;
            }
            $result .= $end_line;
          } else {
            # in that case the end of line is in the columnfractions line
            # or in the columnprototypes.
            if ($cmdname eq 'multitable') {
              my $columnfractions_element
               = Texinfo::Common::multitable_columnfractions($element);

              if ($columnfractions_element) {
                $result
                 .= _format_columnfractions($self, $columnfractions_element);
              } else {
                # arguments_line type element
                my $arguments_line = $element->{'contents'}->[0];
                my $block_line_arg = $arguments_line->{'contents'}->[0];
                if ($block_line_arg->{'contents'}) {
                  $result .= $self->txi_markup_open_element('columnprototypes');
                  foreach my $arg (@{$block_line_arg->{'contents'}}) {
                    if ($arg->{'type'}
                        and $arg->{'type'} eq 'bracketed_arg') {
                      my $attributes = [];
                      push @$attributes, ['bracketed', 'on'];
                      push @$attributes,
                                  _leading_spaces_arg($arg);
                      $result .= $self->txi_markup_open_element('columnprototype',
                                                              $attributes)
                           .$self->_convert($arg)
                           .$self->txi_markup_close_element('columnprototype');
                    } else {
                      $result .= $self->_convert($arg);
                    }
                  }
                  $result .= $self->txi_markup_close_element('columnprototypes');
                }
                my $end_space = _end_line_spaces($self, $arguments_line);
                $result .= $end_space
                    ._format_comment_or_end_line($self, $arguments_line);
                # happens for multitable line with prototypes interrupted
                # by another @-command
                $result .= "\n" unless ($result =~ /\n/);
              }
            } else {
              # get end of lines from @*table and block @-commands that
              # usually have arguments but with missing or bogus arguments,
              # and from block @-commands without argument.
              $result .= _end_line_spaces($self, $arguments_line);
              $result
                .= _format_comment_or_end_line($self, $arguments_line);
              # happens for commands interrupted on the line
              $result .= "\n" unless ($result =~ /\n/);
            }
          }
        # @def* line args are in the first def contents, the def_line type
        # and processed below.
        } elsif (not
           exists($Texinfo::Commands::def_commands{$cmdname})) {
          # happens for bogus empty @macro immediately followed by
          # newline.
          #print STDERR "no args: $cmdname\n";
          $result .= "\n";
        }
        unshift @close_format_elements, $cmdname;
      }
      delete $self->{'itemize_command_as_argument'}
        if ($self->{'itemize_command_as_argument'});
    }
  }
  if ($element->{'type'}) {

    if ($element->{'type'} eq 'arguments_line'
        or ($container_ignored_if_empty{$element->{'type'}}
            and !$element->{'contents'})) {
      return $result;
    }

    if (defined($type_elements{$element->{'type'}})) {
      my $attribute = [];
      if ($element->{'type'} eq 'preformatted') {
        push @$attribute, ['space', 'preserve'];
      }
      $result
        .= $self->txi_markup_open_element($type_elements{$element->{'type'}},
                                          $attribute);
    } elsif ($element->{'type'} eq 'def_line') {
      $result .= _convert_def_line($self, $element);
      return $result;
    # case of bracketed in def line not corresponding to a def* argument
    # by itself, for example, in the following '{a b}{c d}' is the
    # argument, it is not a bracketed by itself, but contains two
    # bracketed_arg.  Similarly '{e f}' is a bracketed_arg but the arg is
    # 'h{e f}'.
    # @deffn {a b}{c d} h{e f} g h
    } elsif ($element->{'type'} eq 'bracketed_arg'
             and not ($element->{'parent'}->{'parent'}
                      and $element->{'parent'}->{'parent'}->{'parent'}
                 and $element->{'parent'}->{'parent'}->{'parent'}->{'cmdname'}
                 and $element->{'parent'}->{'parent'}->{'parent'}->{'cmdname'}
                                                           eq 'multitable')
             and (!$element->{'parent'}->{'type'}
                  or ($element->{'parent'}->{'type'} ne 'def_category'
                      and $element->{'parent'}->{'type'} ne 'def_type'
                      and $element->{'parent'}->{'type'} ne 'def_name'
                      and $element->{'parent'}->{'type'} ne 'def_typearg'
                      and $element->{'parent'}->{'type'} ne 'def_arg'
                      and $element->{'parent'}->{'type'} ne 'def_class'))) {
      my $attribute = [];
      push @$attribute, ['bracketed', 'on'];
      push @$attribute, _leading_trailing_spaces_arg($element);
      $result .= $self->txi_markup_open_element("defbracketed", $attribute);
      push @close_format_elements, 'defbracketed';
    }
  }
  if ($element->{'contents'}) {
    my $in_code;
    if (($element->{'cmdname'}
         and ($Texinfo::Commands::preformatted_code_commands{$element->{'cmdname'}}
              or $Texinfo::Commands::math_commands{$element->{'cmdname'}}))
         or $element->{'type'} and $element->{'type'} eq 'menu_entry_node') {
      $in_code = 1;
    }
    push @{$self->{'document_context'}->[-1]->{'monospace'}}, 1
      if ($in_code);
    if (ref($element->{'contents'}) ne 'ARRAY') {
      cluck "contents not an array($element->{'contents'}).";
    }
    foreach my $content (@{$element->{'contents'}}) {
      $result .= $self->_convert($content);
    }
    pop @{$self->{'document_context'}->[-1]->{'monospace'}}
      if ($in_code);
  }
  if ($element->{'type'}) {
    if (defined($type_elements{$element->{'type'}})) {
      $result
        .= $self->txi_markup_close_element($type_elements{$element->{'type'}});
    }
  }

  foreach my $format_element (@close_format_elements) {
    $result .= $self->txi_markup_close_element($format_element);
  }
  if ($element->{'cmdname'}
      and exists($Texinfo::Commands::block_commands{$element->{'cmdname'}})) {
    if ($self->{'expanded_formats'}->{$element->{'cmdname'}}) {
    } else {
      if ($element->{'contents'}
          and $element->{'contents'}->[-1]->{'cmdname'}
          and $element->{'contents'}->[-1]->{'cmdname'} eq 'end') {
        my $end_command = $element->{'contents'}->[-1];
        $result .= _end_line_spaces($self, $end_command);
        $result .= _format_comment_or_end_line($self, $end_command);
      } else {
        # missing @end, add an end of line after the closing markup element.
        $result .= "\n";
      }
    }
    if ($self->{'context_block_commands'}->{$element->{'cmdname'}}) {
      pop @{$self->{'document_context'}};
    }
  } elsif ($element->{'cmdname'}
           and $Texinfo::Commands::root_commands{$element->{'cmdname'}}
           and $element->{'cmdname'} ne 'node'
           and !$self->get_conf('TXI_MARKUP_NO_SECTION_EXTENT')) {
    my $level_adjusted_cmdname
       = Texinfo::Structuring::section_level_adjusted_command_name($element);
    my $sections_list = $self->{'document'}->sections_list();
    my $section_relations
      = $sections_list->[$element->{'extra'}->{'section_number'} -1];
    if (!($section_relations
          and $section_relations->{'section_children'}
          and scalar(@{$section_relations->{'section_children'}}))
        or $level_adjusted_cmdname eq 'top') {
      $result .= $self->txi_markup_close_element($level_adjusted_cmdname)."\n";
      my $current = $element;
      my $current_relations
          = $sections_list->[$current->{'extra'}->{'section_number'} -1];
      while ($current_relations->{'section_directions'}
             and $current_relations->{'section_directions'}->{'up'}
             and !$current_relations->{'section_directions'}->{'next'}
             and Texinfo::Structuring::section_level_adjusted_command_name(
   $current_relations->{'section_directions'}->{'up'}->{'element'}) ne 'top') {
        $current_relations
          = $current_relations->{'section_directions'}->{'up'};
        $current = $current_relations->{'element'};
        my $level_adjusted_current_cmdname
          = Texinfo::Structuring::section_level_adjusted_command_name($current);
        $result
          .= $self->txi_markup_close_element($level_adjusted_current_cmdname)
               ."\n";
      }
    }
  } elsif ($element->{'cmdname'}
           and $element->{'cmdname'} eq 'node'
           and $self->get_conf('TXI_MARKUP_NO_SECTION_EXTENT')) {
    $result .= $self->txi_markup_close_element('node');

  }
  return $result;
}

1;

__END__

=head1 NAME

Texinfo::Convert::TexinfoMarkup - Convert Texinfo tree to element and attribute markup

=head1 SYNOPSIS

  package Texinfo::Convert::TexinfoMyMarkup;

  use Texinfo::Convert::TexinfoMarkup;

  @ISA = qw(Texinfo::Convert::TexinfoMarkup);

  sub converter_defaults ($$) {
    return %myconverter_defaults;
  }

  sub txi_markup_protect_text($$)
  {
    my $self = shift;
    ....
  }

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

C<Texinfo::Convert::TexinfoMarkup> converts a Texinfo tree to the Texinfo
Markup Language which is based on nested elements with attributes, similar
to XML.  All the information present in the Texinfo tree, after
expansion of C<@macro>, C<@value> and inclusion of include files is
kept.  C<Texinfo::Convert::TexinfoMarkup> is an abstract class, to be used as a
super class for modules implementing specific markup formatting functions
called by C<Texinfo::Convert::TexinfoMarkup>.

The Texinfo Markup Language elements and attributes are not documented,
but the Texinfo XML output by the C<Texinfo::Convert::TexinfoXML> subclass
(L<Texinfo::Convert::TexinfoXML>) is a straightforward formatting as XML,
and is described by the Texinfo DTD.  Therefore the Texinfo DTD can be
used as a description of the structure of both Texinfo XML and of the
more abstract Texinfo Markup Language.

=head1 METHODS

=head2 Markup formatting methods defined by subclasses

The following methods should be implemented by the modules inheriting
from C<Texinfo::Convert::TexinfoMarkup>:

=over

=item $result = $converter->txi_markup_atom($atom)

Format the I<$atom> symbol string in a simpler way than with an element.  For
example in XML the formatting of the symbol is achieved with an entity.

=item $result = $converter->txi_markup_comment($comment_string)

Format I<$comment_string> as a comment.

=item $result = $converter->txi_markup_convert_text($element)

Called to format the Texinfo tree I<$element> text, which is a
reference on a hash.  The I<$element> text is in the C<text> key.
The C<type> key value may also be set to distinguish the type of text
(L<Texinfo::Parser/Types for text elements>).
Texinfo tree elements are described in details in L<Texinfo::Parser/TEXINFO TREE>.

=item $result = $converter->txi_markup_element($format_element, $attributes)

=item $result = $converter->txi_markup_open_element($format_element, $attributes)

=item $result = $converter->txi_markup_close_element($format_element, $attributes)

C<txi_markup_element> is called for the formatting of empty elements.  Otherwise,
C<txi_markup_open_element> is called when an element is opened, and
C<txi_markup_close_element> is called when an element is closed.
I<$format_element> is the element name, I<$attributes> is a reference on an
array containing references on arrays of pairs, one pair for each attribute, with
the attribute name as the first item of the pair and the attribute text as the
second item of the pair.

=item $result = $converter->txi_markup_header()

Called to format a header at the beginning of output files.

=item $result = $converter->txi_markup_protect_text($string)

Protect special character in text for text fragments out of text
Texinfo tree elements.  For example, for spaces at end of line that
are ignorable in most output formats, for C<@set> or C<@macro>
arguments.

=back

=head2 Formatting state information

A method is available for subclasses to gather information on the
formatting state:

=over

=item $converter->in_monospace()

Return 1 if in a context where spacing should be kept
and C<---> or C<''> left as is, for example in C<@code>, C<@example>.

=back

=head1 AUTHOR

Patrice Dumas, E<lt>bug-texinfo@gnu.orgE<gt>

=head1 SEE ALSO

L<Texinfo::Convert::Converter>. L<Texinfo::Convert::TexinfoXML>.  The
C<Texinfo::Convert::TexinfoSXML> is another subclass, which outputs
SXML.  It is not much documented.

=head1 COPYRIGHT AND LICENSE

Copyright 2010- Free Software Foundation, Inc.  See the source file for
all copyright years.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or (at
your option) any later version.

=cut
