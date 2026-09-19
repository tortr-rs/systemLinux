# ReadDocBook.pm: output tree as DocBook using Texinfo::Reader.
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

# This file is an example of a converter using the Reader interface but
# not the TreeElement interface.  It is not used in texi2any.

# TODO Perl data refcount remains too high such that some data is never
# released.  There are warnings if TEST is set high enough as in the tests.
# It is possible to silence the refcount related warnings by setting the
# TEXINFO_SILENT_REFCOUNT environment variable to 1.

package Texinfo::Example::ReadDocBook;

use 5.006;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

#use Data::Dumper;
use Carp qw(cluck confess);

#use Devel::Refcount qw(refcount);
#use Devel::Peek qw(SvREFCNT);

# for XS_structuring_enabled
use Texinfo::XSLoader;

use Texinfo::Commands;

use Texinfo::TreeElement;

use Texinfo::Reader;

use Texinfo::Common;

# for debugging
use Texinfo::Convert::Texinfo;

use Texinfo::Document;

# for section_level_adjusted_command_name
use Texinfo::Structuring;

use Texinfo::Convert::Unicode;
use Texinfo::Convert::Utils;
use Texinfo::Convert::Text;
use Texinfo::Convert::Converter;
use Texinfo::Example::TreeElementConverter;

# inherits from Texinfo::Convert::Converter through
# Texinfo::Example::TreeElementConverter
our @ISA = qw(Texinfo::Example::TreeElementConverter);

our $VERSION = '7.3';

my %brace_commands = %Texinfo::Commands::brace_commands;

my $nbsp = '&#'.hex('00A0').';';

my %defaults = (
  # Customization option variables
  'FORMAT_MENU'          => 'nomenu',
  'EXTENSION'            => 'xml', # dbk?
  'OUTPUT_ENCODING_NAME' => 'utf-8',
  'SPLIT'                => '',
  'OPEN_QUOTE_SYMBOL'    => '&#'.hex('2018').';',
  'CLOSE_QUOTE_SYMBOL'   => '&#'.hex('2019').';',
  'USE_NUMERIC_ENTITY'   => 1,
  'NO_TOP_NODE_OUTPUT'   => 1,
);

my @docbook_image_extensions
  = ('eps', 'gif', 'jpg', 'jpeg', 'pdf', 'png', 'svg');

my %docbook_special_quotations;
foreach my $special_quotation (
    'caution', 'important', 'note', 'tip', 'warning') {
  $docbook_special_quotations{$special_quotation} = 1;
}

# For '*', there is no line break in DocBook, except in cmdsynopsis (in this
# case it is <sbr>).  But currently we don't use cmdsynopsis, and it is
# unlikely we ever will.
my %docbook_specific_formatting = (
  'TeX' => '&tex;',
  'LaTeX' => '&latex;',
  "\t" => $nbsp,
  "\n" => $nbsp,
  " " => $nbsp,
  'tie' => $nbsp,
);
my %docbook_no_arg_commands_formatting
  = %Texinfo::Convert::Converter::xml_text_entity_no_arg_commands_formatting;

foreach my $command (keys(%Texinfo::Convert::Unicode::unicode_entities)) {
  $docbook_no_arg_commands_formatting{$command}
   = $Texinfo::Convert::Unicode::unicode_entities{$command};
}

foreach my $command (keys(%docbook_specific_formatting)) {
  $docbook_no_arg_commands_formatting{$command}
    = $docbook_specific_formatting{$command};
}

my %quoted_style_commands = (
  'samp' => 1,
);

my %upper_case_style_commands = (
  'sc' => 1,
);

my @inline_elements = ('emphasis', 'abbrev', 'acronym', 'link',
  'inlinemediaobject', 'firstterm', 'footnote', 'replaceable',
  'subscript', 'superscript', 'wordasword');
my %inline_elements;
foreach my $inline_element (@inline_elements) {
  $inline_elements{$inline_element} = 1;
};

my %style_attribute_commands;
%style_attribute_commands = (
      'b'           => 'emphasis role="bold"',
      'cite'        => 'citetitle',
      'code'        => 'literal',
      'command'     => 'command',
      'dfn'         => 'firstterm',
      'emph'        => 'emphasis',
      'env'         => 'envar',
      'file'        => 'filename',
      'footnote'    => 'footnote',   # brace context command
      'headitemfont' => 'emphasis role="bold"', # actually <th> instead of <td>
      'i'           => 'emphasis',
      'indicateurl' => 'literal',
      'kbd'         => 'userinput',
      'key'         => 'keycap',
      'math'        => 'mathphrase', # brace context command
      'option'      => 'option',
      'r'           => '',
      'samp'        => 'literal',
      'sansserif'   => '',
      'strong'      => 'emphasis role="bold"',
      'sub'         => 'subscript',
      'sup'         => 'superscript',
      't'           => 'literal',
      'var'         => 'replaceable',
      'verb'        => 'literal',     # brace other command
);

my %style_brace_types = map {$_ => 1} ('style_other', 'style_code', 'style_no_code');
# @all_style_commands is the union of style brace commands, commands
# in %style_attribute_commands and a few other, some not style brace commands.
# Using keys of a map generated hash does like uniq, it avoids duplicates.
# The first grep selects style brace commands, ie commands with %brace_commands
# type in %style_brace_types.
my @all_style_commands = keys %{{ map { $_ => 1 }
    ((grep {$style_brace_types{$brace_commands{$_}}} keys(%brace_commands)),
      keys(%style_attribute_commands), 'w', 'dmn', 'titlefont') }};

# special string for 'w'.
my $w_command_mark = '<!-- /@w -->';

my %style_commands_formatting;
foreach my $command(@all_style_commands) {
  $style_commands_formatting{$command} = {};
  if ($style_attribute_commands{$command}) {
    $style_commands_formatting{$command}->{'attribute'}
      = $style_attribute_commands{$command};
  }
  if ($quoted_style_commands{$command}) {
    $style_commands_formatting{$command}->{'quote'} = 1;
  }
  if ($upper_case_style_commands{$command}) {
    $style_commands_formatting{$command}->{'upper_case'} = 1;
  }
}

my %docbook_line_elements_with_arg_map = (
  'exdent' => 'simpara role="exdent"',
  'center' => 'simpara role="center"',
);

my %docbook_ignored_nobrace_commands = %Texinfo::Commands::nobrace_commands;
foreach my $command ('item', 'headitem', 'tab',
   keys(%docbook_no_arg_commands_formatting)) {
  delete $docbook_ignored_nobrace_commands{$command};
}

my %docbook_no_warn_empty_commands = %docbook_ignored_nobrace_commands;
#foreach my $command () {
#  $docbook_no_warn_empty_commands{$command} = 1;
#}

my %docbook_no_warn_empty_types;
# do not warn for empty brace commands and bracketed arguments and
# for a few containers.
foreach my $type ('brace_container', 'bracketed_arg', 'brace_command_context',
                  'preformatted', 'before_item', 'line_arg', 'block_line_arg',
                  'preamble_before_content', 'before_node_section') {
  $docbook_no_warn_empty_types{$type} = 1;
}

my %docbook_line_commands = %Texinfo::Commands::line_commands;
foreach my $command ('itemx') {
  delete $docbook_line_commands{$command};
}

my %docbook_global_commands = (
  'documentlanguage' => 1,
);

my %default_args_code_style
  = %Texinfo::Convert::Converter::default_args_code_style;

my %defcommand_name_type = (
 'defline'   => 'varname',
 'deftypeline' => 'varname',
 'defcv'     => 'property',
 'deffn'     => 'function',
 'defop'     => 'methodname',
 'deftp'     => 'structname',
 'deftypecv' => 'property',
 'deftypefn' => 'function',
 'deftypeop' => 'methodname',
 'deftypevr' => 'varname',
 'defvr'     => 'varname',
);

foreach my $def_alias (keys(%Texinfo::Common::def_aliases))
{
  my $main_command = $Texinfo::Common::def_aliases{$def_alias};
  $defcommand_name_type{$def_alias} = $defcommand_name_type{$main_command};
}

my %def_argument_types_docbook = (
  'def_type' => ['returnvalue'],
  'def_class' => ['ooclass', 'classname'],
  # TODO or a simple emphasis?
  # replaceable is not used here, such that replaceable is only
  # used if there is an explicit @var{}
  'def_arg' => ['emphasis role="arg"'],
  'def_typearg' => ['type'],
);

my %ignored_block_commands;
foreach my $block_command ('copying', 'titlepage', 'documentdescription',
    'nodedescriptionblock', 'publication', 'documentinfo') {
  $ignored_block_commands{$block_command} = 1;
}

my %ignored_text_types;
foreach my $text_type (
            'ignorable_spaces_after_command',
            'ignorable_spaces_before_command',
            'spaces_after_close_brace',
            'spaces_before_paragraph',
            'spaces_at_end',
  ) {
  $ignored_text_types{$text_type} = 1;
}

my %ignored_types;
foreach my $type (
            'menu_entry_leading_text',
            'menu_entry_separator',
            'postamble_after_end',
            'preamble_before_beginning',
            'preamble_before_setfilename',
            #'arguments_line',
  ) {
  $ignored_types{$type} = 1;
}

my %type_elements = (
  'paragraph' => 'para',
  'table_definition' => 'listitem',
  'table_entry' => 'varlistentry',
  'row' => 'row',
  'multitable_head' => 'thead',
  'multitable_body' => 'tbody',
  # Unfortunatly there does not seem to be anything better in DocBook.
  'def_item' => 'blockquote',
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

my %docbook_preformatted_formats = (
# command
   'example' => 'screen',
   'smallexample' => 'screen',
   'display' => 'literallayout',
   'smalldisplay' => 'literallayout',
   'lisp' => 'programlisting',
   'smalllisp' => 'programlisting',
   'format' => 'literallayout',
   'smallformat' => 'literallayout',
);
my %docbook_preformatted_types = (
# type
# Note that menus are ignored, so these are unlikely to happen
   'menu_comment' => 'literallayout',
   'menu_description' => 'literallayout',
);

my %sectioning_commands_done;

sub converter_defaults($;$)
{
  return \%defaults;
}


sub converter_initialize($)
{
  my $self = shift;

  $self->{'context_block_commands'} = {%default_context_block_commands};
  foreach my $raw (grep {$Texinfo::Commands::block_commands{$_} eq 'format_raw'}
                        keys(%Texinfo::Commands::block_commands)) {
    $self->{'context_block_commands'}->{$raw} = 1
         if $self->{'expanded_formats'}->{$raw};
  }

  foreach my $conf ('OPEN_QUOTE_SYMBOL', 'CLOSE_QUOTE_SYMBOL') {
    if (not defined($self->get_conf($conf))) {
      # override undef set in init file/command line
      $self->force_conf($conf, '');
    }
  }
}

sub conversion_initialization($;$)
{
  my $self = shift;
  my $document = shift;

  if ($document) {
    $self->set_document($document);
  }

  $self->{'document_context'} = [];
  _new_document_context($self);
  $self->{'lang_stack'} = [];
  $self->{'in_skipped_node_top'} = 0;
  %sectioning_commands_done = ();
}

sub conversion_finalization($)
{
  my $self = shift;

  pop @{$self->{'document_context'}};
}

sub convert($$)
{
  my $self = shift;
  my $document = shift;

  $self->conversion_initialization($document);

  my $root = $document->tree();

  $self->register_document_relations_lists_elements($document);

  push @{$self->{'lang_stack'}}, '';

  my $result = $self->convert_tree($root);

  $self->conversion_finalization();

  return $result;
}

sub convert_tree($$)
{
  my $self = shift;
  my $root = shift;

  if (!defined($root)) {
    confess("ReadDocbook::convert_tree: undef root\n");
  }

  if (scalar(@{$self->{'lang_stack'}}) == 0) {
    push @{$self->{'lang_stack'}}, '';
  }

  my $reader = Texinfo::Reader::new($root);

  if (!defined($reader)) {
    confess("ReadDocbook::convert_tree: undef reader\n");
  }

  return _convert($self, $reader);
}

sub conversion_output_begin($;$$)
{
  my $self = shift;
  my $output_file = shift;
  my $output_filename = shift;

  if ($self->{'document'}) {
    $self->register_document_relations_lists_elements($self->{'document'});
  }

  my $encoding = '';
  if ($self->get_conf('OUTPUT_ENCODING_NAME')
      and $self->get_conf('OUTPUT_ENCODING_NAME') ne 'utf-8') {
    $encoding = " encoding=\"".$self->get_conf('OUTPUT_ENCODING_NAME')."\" ";
  }

  my $id;
  if ($output_file ne '') {
    # FIXME DocBook 5 id -> xml:id
    $id = " id=\"".$self->xml_protect_text($output_filename)."\"";
  } else {
    $id = '';
  }

  my $lang_attribute;
  $self->set_global_document_commands('preamble', ['documentlanguage']);
  my $documentlanguage = $self->get_conf('documentlanguage');
  if (defined($documentlanguage)) {
    $lang_attribute = " lang=\"$documentlanguage\"";
    Texinfo::Convert::Utils::switch_lang_translations($self,
                                   $documentlanguage,
                                   $self->get_conf('COMMAND_LINE_ENCODING'));
    push @{$self->{'lang_stack'}}, $documentlanguage;
  } else {
    $lang_attribute = '';
    # start with an empty string if there is no documentlanguage
    push @{$self->{'lang_stack'}}, '';
  }
  my $result =  "<?xml version=\"1.0\"${encoding}?>".'
<!DOCTYPE book PUBLIC "-//OASIS//DTD DocBook XML V4.5//EN" "http://www.oasis-open.org/docbook/xml/4.5/docbookx.dtd" [
  <!ENTITY tex "TeX">
  <!ENTITY latex "LaTeX">
]>
'. "<book${id}${lang_attribute}>\n";

  my $legalnotice;
  my $copying_element = $self->get_global_unique_tree_element('copying');
  if ($copying_element) {
    my $copying_result = $self->convert_tree($self->new_tree_element(
           {'contents' => $copying_element->get_children()}, 1));
    if ($copying_result ne '') {
      $legalnotice = "<legalnotice>$copying_result</legalnotice>";
    }
  }

  my $fulltitle_command;
  foreach my $title_cmdname ('title', 'shorttitlepage') {
    my $command = $self->get_global_unique_tree_element($title_cmdname);
    if ($command and $command->{'contents'}->[0]->{'contents'}) {
      $fulltitle_command = $command;
      last;
    }
  }
  if (!defined($fulltitle_command)) {
    my $command_list
      = Texinfo::Example::TreeElementConverter::global_commands_information_command_list(
          $self->{'document'}, 'titlefont');
    if ($command_list) {
      my $command = $command_list->[0];
      if ($command->{'contents'}
          and $command->{'contents'}->[0]->{'contents'}) {
        $fulltitle_command = $command;
      }
    }
  }

  # get informations from the @titlepage.  Since the fulltitle is gathered
  # independently, only author and subtitle are gathered here.
  my $subtitle_info = '';
  my $authors_info = '';
  foreach my $information_block_cmdname ('documentinfo', 'titlepage') {
    my $information_block
       = $self->get_global_unique_tree_element($information_block_cmdname);
    if (defined($information_block)) {
      my $collected_commands = Texinfo::Reader::reader_collect_commands_list(
                                  $information_block, ['author', 'subtitle']);

      my @authors_elements;
      my $subtitle_text = '';
      if (scalar(@{$collected_commands})) {
        foreach my $element (@{$collected_commands}) {
          my $cmdname = $element->{'cmdname'};
          if ($cmdname eq 'author') {
            push @authors_elements, $element;
          } elsif ($cmdname eq 'subtitle') {
            # concatenate the text of @subtitle as DocBook only allows one.
            my ($arg, $end_line)
              = _convert_argument_and_end_line($self, $element);
            $subtitle_text .= $arg . $end_line
          }
        }
      }
      if ($subtitle_text ne '') {
        chomp ($subtitle_text);
        $subtitle_info = "<subtitle>$subtitle_text</subtitle>\n";
      }

      if (scalar(@authors_elements)) {
        # using authorgroup and collab is the best, because it doesn't require
        # knowing people name decomposition.  Also it should work for group names.
        # FIXME dblatex ignores collab/collabname.
        $authors_info .= "<authorgroup>\n";
        foreach my $element (@authors_elements) {
          my ($arg, $end_line) = _convert_argument_and_end_line($self, $element);
          # FIXME DocBook 5 no more collabname, merged with other elements in
          # orgname, which is much more specific than collabname, it is for an
          # organisation and therefore not suitable here.
          # https://tdg.docbook.org/tdg/5.0/ch01#introduction-whats-new
          # person/personname is not suitable either, because in Texinfo @author
          # may correspond to more than one author, and also because we do not
          # have the information in Texinfo needed for <person>, which requires
          # a split of the name in honorific, firstname, surname...
          # https://tdg.docbook.org/tdg/5.0/personname
          my $result = "<collab><collabname>$arg</collabname></collab>$end_line";
          chomp ($result);
          $result .= "\n";
          $authors_info .= $result;
        }
        $authors_info .= "</authorgroup>\n";
      }
    }
  }

  my $settitle_command;
  my $settitle = $self->get_global_unique_tree_element('settitle');
  if ($settitle and $settitle->{'contents'}
      and $settitle->{'contents'}->[0]->{'contents'}) {
    $settitle_command = $settitle;
  }

  my $top_command = $self->get_global_unique_tree_element('top');

  my $titleabbrev_command;
  if ($fulltitle_command) {
    $titleabbrev_command = $settitle_command;
  } elsif ($settitle_command) {
    $fulltitle_command = $settitle_command;
  } elsif (defined($legalnotice) and $top_command) {
    # if there is a legalnotice, we really want to have a title
    # preceding it, so we also use @top
    # arguments_line type element
    my $arguments_line = $top_command->{'contents'}->[0];
    my $line_arg = $arguments_line->{'contents'}->[0];
    $fulltitle_command = $top_command
      if ($line_arg->{'contents'});
  }

  my $title_info = '';

  if ($fulltitle_command) {
    foreach my $element_command ([$fulltitle_command, 'title'],
                                 [$titleabbrev_command, 'titleabbrev']) {
      my ($element, $docbook_element) = @$element_command;
      if (defined($element)) {
        my ($arg, $end_line) = _convert_argument_and_end_line($self, $element);
        my $result = "<$docbook_element>$arg</$docbook_element>$end_line";
        chomp ($result);
        $result .= "\n";
        $title_info .= $result;
        if ($docbook_element eq 'title') {
          $title_info .= $subtitle_info;
        }
      }
    }
  }
  $self->set_global_document_commands('before', ['documentlanguage']);
  Texinfo::Convert::Utils::switch_lang_translations($self,
                                       $self->get_conf('documentlanguage'),
                                   $self->get_conf('COMMAND_LINE_ENCODING'));

  my $document_info = '';
  $document_info .= $title_info . $authors_info;
  $document_info .= $legalnotice if (defined($legalnotice));

  # we duplicate title info, as it is explicitly said in the DocBook manual
  # that it can be duplicated if exactly the same
  $result .= $title_info;

  if ($document_info ne '') {
    # FIXME DocBook 5 bookinfo->info
    $result .= "<bookinfo>$document_info</bookinfo>\n";
  }

  return $result;
}

sub conversion_output_end($)
{
  my $self = shift;
  return "</book>\n";
}

sub output($$)
{
  my $self = shift;
  my $document = shift;

  return $self->output_tree($document);
}

my %docbook_sections = (
  'top'  => 'chapter',
  'part' => 'part',
  'chapter'  => 'chapter',
  'unnumbered'  => 'chapter',
  'centerchap'  => 'chapter',
  'appendix' => 'appendix',
  # chapter would have been the best choice here, but it is not a possibility
  # for renderas in bridgehead (possibilities are sect1 to 5 and other).
  # other is rendered small, smaller than sect1.  So use sect1, even though
  # it matches better with the @heading level.
  'majorheading' => 'sect1',
  'chapheading' => 'sect1',
  'heading' => 'sect1',
  'subheading' => 'sect2',
  'subsubheading' => 'sect3',
  2 => 'sect1',
  3 => 'sect2',
  4 => 'sect3'
);

my %docbook_special_unnumbered;
foreach my $special_unnumbered ('acknowledgements', 'colophon',
                                'dedication', 'preface') {
  $docbook_special_unnumbered{$special_unnumbered} = 1;
}

# element is not texinfo tree element here, but xml element
sub _docbook_section_element($$)
{
  my $self = shift;
  my $element = shift;

  if ($element->{'extra'}
      and defined($element->{'extra'}->{'section_level'})) {
    my $heading_level = $element->{'extra'}->{'section_level'};
    if (exists $docbook_sections{$heading_level}) {
      return $docbook_sections{$heading_level};
    }
  }
  my $level_adjusted_cmdname
   = Texinfo::Structuring::section_level_adjusted_command_name($element);
  if ($level_adjusted_cmdname eq 'unnumbered'
      and $self->{'document'}) {
    # other functions could have been called but this one has an XS override
    my $sections_list = $self->tree_element_sections_list();
    my $section_relations
      = $sections_list->[$element->{'extra'}->{'section_number'} -1];
    if ($section_relations->{'associated_node'}) {
      my $associated_node = $section_relations->{'associated_node'}->{'element'};
      if ($docbook_special_unnumbered{
              lc($associated_node->{'extra'}->{'normalized'})}) {
        return lc($associated_node->{'extra'}->{'normalized'});
      }
    }
  }

  if (defined($docbook_sections{$level_adjusted_cmdname})) {
    return $docbook_sections{$level_adjusted_cmdname};
  } else {
    # special case of no structuring information available for a regular
    # sectioning command, like @section, @appendix, if Structuring
    # sectioning_structure was not called.
    my $heading_level = Texinfo::Common::section_level($element);
    return $docbook_sections{$heading_level};
  }
}

sub _begin_index_entry($$)
{
  my $self = shift;
  my $element = shift;

  my ($index_entry, $index_info)
   = $self->get_tree_element_index_entry($element);
  if ($index_entry) {

    # FIXME DocBook 5 role->type
    my $result = "<indexterm role=\"$index_entry->{'index_name'}\">";

    _new_document_context($self);
    $self->{'document_context'}->[-1]->{'monospace'}->[-1] = 1
      if ($index_info->{'in_code'});
    $result .= "<primary>";
    return ($result, $index_entry);
  }
  return (undef, undef);
}

sub _end_index_entry($$)
{
  my $self = shift;
  my $element = shift;

  pop @{$self->{'document_context'}};

  my $result = "</primary>";
  $result .= "</indexterm>";
  return $result;
}

sub _parse_attribute($)
{
  my $element = shift;
  return ('', '') if (!defined($element));
  my $attributes = '';
  if ($element =~ /^(\w+)(\s+.*)/) {
    $element = $1;
    $attributes = $2;
  }
  return ($element, $attributes);
}

sub _protect_text($$)
{
  my $self = shift;
  my $text = shift;
  my $result = $self->xml_protect_text($text);
  # form feed not allowed in XML
  $result =~ s/\f/ /g;
  return $result;
}

sub _format_comment($$) {
  my ($self, $element) = @_;

  # TODO simplify, use only the text, not the spaces
  my $command_text = '';
  if (exists($element->{'info'})
      and exists($element->{'info'}->{'spaces_before_argument'})) {
    $command_text .= $element->{'info'}->{'spaces_before_argument'}->{'text'};
  }
  if (exists($element->{'contents'})) {
    my $line_arg = $element->{'contents'}->[0];
    if (exists($line_arg->{'contents'})) {
      $command_text .= $line_arg->{'contents'}->[0]->{'text'};
    }
    if (exists($line_arg->{'info'})
        and exists($line_arg->{'info'}->{'spaces_after_argument'})) {
      $command_text
        .= $line_arg->{'info'}->{'spaces_after_argument'}->{'text'};
    }
  }
  return $self->xml_comment($command_text);
}

# this is similar to functions used in other converters, but not exactly
# the same as we want to start with an element that is already registered
# to C, and so we go through the arguments_line in the
# argument_comment_end_line function overriden for XS.
sub _convert_argument_and_end_line($$)
{
  my $self = shift;
  my $element = shift;

  my ($line_arg, $comment, $end_line)
    = $self->argument_comment_end_line($element);

  my $converted = $self->convert_tree($line_arg);
  if ($comment) {
    $end_line = $self->_format_comment($comment);
  }
  return ($converted, $end_line);
}

sub _output_anchor($)
{
  my $element = shift;

  if ($element->{'extra'} and $element->{'extra'}->{'is_target'}) {
    # FIXME DocBook 5 id -> xml:id
    return "<anchor id=\"$element->{'extra'}->{'normalized'}\"/>";
  } else {
    return '';
  }
}

sub _new_document_context($)
{
  my $self = shift;
  push (@{$self->{'document_context'}}, {
                            'monospace' => [0],
                            'upper_case' => [0],
                            'no_break' => [0],
                          });
}

sub _begin_def_line($$)
{
  my $self = shift;
  my $element = shift;

  my $result = '<synopsis>';
  my ($index_entry_text, $index_entry) = _begin_index_entry($self, $element);
  if ($index_entry) {
    $result .= $index_entry_text;
    $result .= $self->convert_tree(
      Texinfo::Example::TreeElementConverter::index_content_element($element));
    $result .= _end_index_entry($self, $element);
  }
  _new_document_context($self);
  $self->{'document_context'}->[-1]->{'monospace'}->[0] = 1;
  $self->{'document_context'}->[-1]->{'inline'}++;
  return $result;
}

my $debug_global_element_nr = 0;

my $TXI_READ_TEXT = Texinfo::Reader::TXI_READ_TEXT;
my $TXI_READ_IGNORABLE_TEXT = Texinfo::Reader::TXI_READ_IGNORABLE_TEXT;
my $TXI_READ_ELEMENT_START = Texinfo::Reader::TXI_READ_ELEMENT_START;
my $TXI_READ_ELEMENT_END = Texinfo::Reader::TXI_READ_ELEMENT_END;


sub _convert($$)
{
  my $self = shift;
  my $reader = shift;

  my $result = '';
  my $void = '';

  my $output_ref = \$result;
  my @format_elements_stack = ();

  #print STDERR " ---- C\n";

  while (1) {
    my $next = $reader->read();
    last if (!defined($next));

    my $category = $next->{'category'};

    my $element = $next->{'element'};

    if (!defined($element)) {
      confess("ReadDocBook _convert element undef");
    }

    my $e_type = $element->{'type'};

    #if (1) { #}
    if (0) { #}
      $debug_global_element_nr++;
      my $category_name = $Texinfo::Reader::token_category_name{$category};
      print STDERR "element $category_name $debug_global_element_nr";
      my $cmdname = $element->{'cmdname'};
      print STDERR " cmd: $cmdname," if (defined($cmdname));
      print STDERR " type: $e_type" if (defined($e_type));
      my $text = $element->{'text'};
      if (defined($text)) {
        my $protected_text = $text;
        $protected_text =~ s/\n/\\n/;
        print STDERR " text: $protected_text";
      }
      if (scalar(@format_elements_stack)) {
        my @strings;
        foreach my $close_format_elements (@format_elements_stack) {
          if (scalar(@$close_format_elements)) {
            push @strings, '['.join(';', @$close_format_elements).']';
          } else {
            push @strings, '';
          }
        }
        print STDERR ' s: '.join('|', @strings);
      }
      if (defined($self->{'pending_prepend'})) {
        print STDERR ' pp: '.$self->{'pending_prepend'};
      }
      print STDERR "\n";
    }

    if ($category == $TXI_READ_TEXT) {
      next if (defined($e_type) and $ignored_text_types{$e_type});

      my $text = $element->{'text'};
      if (defined($e_type) and $e_type eq '_converted') {
        $$output_ref .= $text;
      } elsif ($self->{'document_context'}->[-1]->{'raw'}) {
        $$output_ref .= $text;
      } else {
        my $result_text = $text;
        if ($self->{'document_context'}->[-1]->{'upper_case'}->[-1]) {
          $result_text = uc($result_text);
        }
        if ($self->{'document_context'}->[-1]->{'no_break'}->[-1]) {
          $result_text =~ s/\n/ /g;
          $result_text =~ s/ +/$nbsp/g;
        }
        $result_text = _protect_text($self, $result_text);
        if (!(defined($e_type) and $e_type eq 'raw')
            and !$self->{'document_context'}->[-1]->{'monospace'}->[-1]) {
          $result_text
            = $self->xml_format_text_with_numeric_entities($result_text);
        }
        #warn "had text `$text', returning $result_text\n";
        $$output_ref .= $result_text;
      }
    } elsif ($category == $TXI_READ_IGNORABLE_TEXT) {
      # nothing to do

    } elsif ($category == $TXI_READ_ELEMENT_START) {

      #warn " START element\n";
      my $cmdname = $element->{'cmdname'};
      if (defined($cmdname)) {
        #warn "  START got cmdname $cmdname\n";
        my $result_text;
        if (defined($docbook_no_arg_commands_formatting{$cmdname})) {
          #warn "  has no_arg_commands_formatting \n";
          my $command_name;
          if ($self->{'document_context'}->[-1]->{'upper_case'}->[-1]
              and $Texinfo::Commands::letter_no_arg_commands{$cmdname}
              and $Texinfo::Commands::letter_no_arg_commands{uc($cmdname)}) {
            $command_name = uc($cmdname)
          } else {
            $command_name = $cmdname;
          }

          my $translated_tree
            = $self->tree_element_translated_command_tree($command_name, 1);
          if ($translated_tree) {
            $result_text = $self->convert_tree($translated_tree);
          } else {
            $result_text = $docbook_no_arg_commands_formatting{$command_name};
          }
        } elsif ($cmdname eq 'today') {
          $result_text = $self->convert_tree(
                           $self->tree_element_expand_today(1));
        } elsif ($Texinfo::Commands::accent_commands{$cmdname}) {
          $reader->register_token_element();
          $result_text = $self->tree_element_xml_accents($element,
                 $self->{'document_context'}->[-1]->{'upper_case'}->[-1]);
        }
        if (defined($result_text)) {
          $$output_ref .= $result_text;
          $reader->skip_children($element);
          #warn "  did inline cmdname $cmdname ($result_text)\n";
          next;
        }

        if ($cmdname eq 'item' or $cmdname eq 'itemx'
             or $cmdname eq 'headitem' or $cmdname eq 'tab') {

          push @format_elements_stack, [];

          my $parent = $element->{'parent'};
          my $parent_cmdname = $parent->{'cmdname'};
          if ($cmdname eq 'item' and $parent_cmdname
              and ($parent_cmdname eq 'itemize'
                   or $parent_cmdname eq 'enumerate')) {
            $$output_ref .= "<listitem>";
            if ($parent_cmdname eq 'itemize') {
              my $command_as_argument_name;
              $reader->register_token_element();
              my $prepended_element
   = Texinfo::Example::TreeElementConverter::item_itemize_prepended(
                                                          $element);
              if ($prepended_element) {
                $command_as_argument_name = $prepended_element->{'cmdname'};
              }

              if (!($command_as_argument_name
                    and $command_as_argument_name eq 'bullet')) {
                $self->{'pending_prepend'}
                  = $self->convert_tree($prepended_element);
                $self->{'pending_prepend'} .= " ";
              }
            }
            push @{$format_elements_stack[-1]}, 'listitem';
          } elsif (($cmdname eq 'item' or $cmdname eq 'itemx')
                   and exists($element->{'contents'})
                   and exists($element->{'contents'}->[0]->{'type'})
                   and $element->{'contents'}->[0]->{'type'} eq 'line_arg') {
            my $result_text = '';
            $result_text .= "<term>" if ($cmdname eq 'itemx');
            $reader->register_token_element();
            my ($index_entry_text, $index_entry)
              = _begin_index_entry($self, $element);
            if ($index_entry) {
              $result_text .= $index_entry_text;
              $result_text .= $self->convert_tree(
    Texinfo::Example::TreeElementConverter::index_content_element($element));
              $result_text .= _end_index_entry($self, $element);
            }
            if (exists($element->{'contents'}->[0]->{'contents'})) {
              # FIXME in that case, there is a reference in $table_item_tree
              # to $element child, that is not destroyed when $table_item_tree
              # goes out of scope, an added element may need to be undef.
              my $table_item_tree
                = $self->table_item_content_tree($element, 1);
              $table_item_tree = $element->{'contents'}->[0]
                if (!defined($table_item_tree));

              $result_text .= $self->convert_tree($table_item_tree);
            }
            chomp ($result_text);
            $result_text .= "\n";
            $result_text .= "</term>";
            $$output_ref .= $result_text;
            $reader->skip_children($element);
            pop @format_elements_stack;
          } else {
            unless (($cmdname eq 'item'
                     or $cmdname eq 'headitem'
                    or $cmdname eq 'tab')
                    and $element->{'parent'}->{'type'}
                    and $element->{'parent'}->{'type'} eq 'row') {
              warn "BUG: multitable cell command not in a row "
                .Texinfo::Common::debug_print_element($element, 1);
            }
            $$output_ref .= "<entry>";
            push @{$format_elements_stack[-1]}, 'entry';
          }
          # end *item* tab
        } elsif ($e_type
                 and $e_type eq 'index_entry_command') {
          $reader->register_token_element();
          my ($result, $index_entry) = _begin_index_entry($self, $element);
          if ($index_entry) {
            $$output_ref .= $result;
          } else {
            $reader->skip_children($element);
          }
        } elsif ($cmdname eq 'subentry') {
          # keep the initial output_ref
          if (!$self->{'document_context'}->[-1]->{'subentry_level'}) {
            push @{$self->{'document_context'}->[-1]->{'subentry_output'}},
              $output_ref;
          }
          my $subentry_output = '';
          my $level;
          if (scalar(@{$self->{'document_context'}->[-1]
                ->{'subentry_output'}}) == 1) {
            $level = 'secondary';
          } else {
            $level = 'tertiary';
          }
          $subentry_output .= "<$level>";
          $self->{'document_context'}->[-1]->{'subentry_level'}++;
          # redirect output_ref to be able to output subentries without
          # nesting them.
          $output_ref = \$subentry_output;
          push @{$self->{'document_context'}->[-1]->{'subentry_output'}},
            $output_ref;
        } elsif (exists($docbook_line_commands{$cmdname})) {
          #warn "  is dbk line command\n";
          if ($docbook_global_commands{$cmdname}) {
            Texinfo::Common::set_informative_command_value($self, $element);
            if ($cmdname eq 'documentlanguage') {
              Texinfo::Convert::Utils::switch_lang_translations($self,
                                      $self->get_conf('documentlanguage'),
                                   $self->get_conf('COMMAND_LINE_ENCODING'));
            }
          } elsif ($Texinfo::Commands::root_commands{$cmdname}) {
            my $section_relations;
            if ($cmdname ne 'node') {
              my $sections_list;
              if ($self->{'document'}) {
      # other functions could have been called but this one has an XS override
                $sections_list = $self->tree_element_sections_list();
                $section_relations
                 = $sections_list->[$element->{'extra'}->{'section_number'} -1];
              }
            }
            if ($self->get_conf('NO_TOP_NODE_OUTPUT')) {
              my $node_element;
              if ($cmdname eq 'node') {
                $node_element = $element;
              } elsif ($section_relations
                       and $section_relations->{'part_following_node'}) {
                # the section is necessarily a part
                $node_element
                  = $section_relations->{'part_following_node'}->{'element'};
              }
              if ($node_element or $cmdname eq 'part') {
                # normalized not defined happens for empty nodes
                if ($node_element and $node_element->{'extra'}
                    and $node_element->{'extra'}->{'normalized'}
                    and $node_element->{'extra'}->{'normalized'} eq 'Top') {
                  $self->{'in_skipped_node_top'} = 1;
                  $output_ref = \$void;
                } elsif (defined($self->{'in_skipped_node_top'})
                         and $self->{'in_skipped_node_top'} == 1) {
                  $self->{'in_skipped_node_top'} = -1;
                  $output_ref = \$result;
                }
              }
            }
            my $anchor;
            my $node_relations;
            if ($cmdname eq 'node' and $self->{'document'}
                and $element->{'extra'}
                and $element->{'extra'}->{'node_number'}) {
     # other functions could have been called but this one has an XS override
              my $nodes_list = $self->tree_element_nodes_list();
              $node_relations
                = $nodes_list->[$element->{'extra'}->{'node_number'} -1];
              if (not $node_relations->{'associated_section'}) {
                $anchor = _output_anchor($element);
                $$output_ref .= $anchor . "\n" if ($anchor ne '');
              }
            }
            if (!defined($anchor)) {
              # start the section at the associated node or part, or at the
              # sectioning command if there is no associated node nor part
              my $opening_section_relations;
              my $part;
              if ($cmdname eq 'node') {
                if ($node_relations) {
                  $opening_section_relations
                    = $node_relations->{'associated_section'};
                }
              } elsif ($cmdname eq 'part') {
                $part = $element;
                if ($section_relations
                    and $section_relations->{'part_associated_section'}) {
                  $opening_section_relations
                    = $section_relations->{'part_associated_section'};
                }
              } else {
                $opening_section_relations = $section_relations;
              }
              # FIXME add !$part in condition?
              my $section_element;
              if ($opening_section_relations) {
                if ($opening_section_relations->{'associated_part'}) {
                  $part
                  = $opening_section_relations->{'associated_part'}->{'element'};
                }
                $section_element = $opening_section_relations->{'element'};
              }
              my @opened_elements;
            # we need to check if the section was already done in case there is
            # both a node and a part, we do not know in which order they appear.
              if (not ($section_element
                       and $sectioning_commands_done{$section_element})) {
                push @opened_elements, $part if $part;
                if ($section_element) {
                  push @opened_elements, $section_element;
                }
              }
              foreach my $opened_element (@opened_elements) {
                if ($section_element
                    and $opened_element eq $section_element) {
                  $sectioning_commands_done{$section_element} = 1;
                }
                my $section_attribute = '';
                # It is not clear if a label should be set for @appendix* and
                # @chapter/@*section or not, as the formatter should be
                # able to figure it out.  For @unnumbered or if ! NUMBER_SECTIONS
                # having a label (empty) is important.
                my $label = '';
                if ($opened_element->{'extra'}
                    and defined($opened_element->{'extra'}
                                            ->{'section_heading_number'})
                    and ($self->get_conf('NUMBER_SECTIONS')
                         or !defined($self->get_conf('NUMBER_SECTIONS')))) {
                  # Looking at docbook2html output, Appendix is appended in the
                  # section title, so only the letter is used.
                  $label
                    = $opened_element->{'extra'}->{'section_heading_number'};
                }
                my $docbook_sectioning_element
                   = _docbook_section_element($self, $opened_element);
                if (! $docbook_special_unnumbered{$docbook_sectioning_element}) {
                  $section_attribute .= " label=\"$label\"";
                }
                my $section_relations;
                if ($self->{'document'}) {
      # other functions could have been called but this one has an XS override
                  my $sections_list = $self->tree_element_sections_list();
                  $section_relations
          = $sections_list->[$opened_element->{'extra'}->{'section_number'} -1];
                  if ($section_relations->{'associated_node'}) {
                   # FIXME DocBook 5 id -> xml:id
                    $section_attribute
    .= " id=\"$section_relations->{'associated_node'}->{'element'}->{'extra'}->{'normalized'}\"";
                  }
                }
                my $language = '';
                my $documentlanguage = $self->get_conf('documentlanguage');
                if (defined($documentlanguage)) {
                  $language = $documentlanguage;
                  if ($self->{'lang_stack'}->[-1] ne $language) {
                    $section_attribute .= ' lang="'.$language.'"';
                  }
                }
                push @{$self->{'lang_stack'}}, $language;
                my $result_text = '';
                $result_text
                  .= "<$docbook_sectioning_element${section_attribute}>\n";
                my ($arg, $end_line)
                  = _convert_argument_and_end_line($self, $opened_element);
                $result_text .= "<title>$arg</title>$end_line";
                chomp ($result_text);
                $result_text .= "\n";
                $$output_ref .= $result_text;

                # if associated with a sectioning element, the part is opened
                # before the sectioning element, such that the part content
                # appears after the sectioning command opening, no need for
                # partintro.
                if ($docbook_sectioning_element eq 'part'
                    and not ($section_relations
                             and $section_relations->{'part_associated_section'})
                             and !Texinfo::Common::is_content_empty(
                                                         $opened_element)) {
                  $$output_ref .= "<partintro>\n";
                }
              }
            }
          } elsif ($cmdname eq 'c' or $cmdname eq 'comment') {
            $$output_ref .= $self->_format_comment($element);
          } elsif ($Texinfo::Commands::sectioning_heading_commands{$cmdname}) {
            if (!$Texinfo::Commands::root_commands{$cmdname}) {
              $reader->register_token_element();
              my ($arg, $end_line)
                = _convert_argument_and_end_line($self, $element);
              $result_text .=
                "<bridgehead renderas=\"$docbook_sections{$cmdname}\">"
                    ."$arg</bridgehead>$end_line";
              chomp ($result_text);
              $result_text .= "\n";
              $$output_ref .= $result_text;
            }
          } elsif ($Texinfo::Commands::def_commands{$cmdname}) {
            $reader->register_token_element();
            my $def_line_result = _begin_def_line($self, $element);
            $$output_ref .= $def_line_result if (defined($def_line_result));
          } elsif (exists($docbook_line_elements_with_arg_map{$cmdname})) {
            my ($docbook_element, $attribute_text)
              = _parse_attribute($docbook_line_elements_with_arg_map{$cmdname});
            $reader->register_token_element();
            my ($arg, $end_line)
              = _convert_argument_and_end_line($self, $element);
            if ($docbook_element eq '') {
              $result_text .= "$arg$end_line";
            } else {
              $result_text .= "<$docbook_element${attribute_text}>"
                                      ."$arg</$docbook_element>$end_line";
            }
            chomp ($result_text);
            $result_text .= "\n";
            $$output_ref .= $result_text;
          } elsif ($cmdname eq 'insertcopying') {
            if ($self->{'document'}) {
              my $global_commands
                = $self->{'document'}->global_commands_information();
              my $copying_element
                 = $self->get_global_unique_tree_element('copying');
              if ($copying_element) {
                $$output_ref .= $self->convert_tree($self->new_tree_element(
                      {'contents' => $copying_element->get_children()}, 1));
              }
            }
          } elsif ($cmdname eq 'verbatiminclude') {
            $reader->register_token_element();
            # this function is used because the overriden function is the
            # function called by this function
            my $expansion
              = $self->expand_verbatiminclude($element);
            if (defined($expansion)) {
              $$output_ref .= $self->convert_tree($expansion);
            }
          } elsif ($cmdname eq 'printindex') {
            if ($element->{'extra'}
                and $element->{'extra'}->{'misc_args'}) {
              # FIXME DocBook 5
              #"<index type=\"$element->{'extra'}->{'misc_args'}->[0]\"></index>\n";
              $$output_ref
           .= "<index role=\"$element->{'extra'}->{'misc_args'}->[0]\">"
                     ."</index>\n";
            } else {
              $$output_ref .=  "<index></index>\n";
            }
          }
          if (!$Texinfo::Commands::root_commands{$cmdname}
              and !$Texinfo::Commands::def_commands{$cmdname}) {
            $reader->skip_children($element);
          }
          # ignore all the other line commands
        } elsif ($e_type
                 and $e_type eq 'definfoenclose_command') {
        } elsif (exists($Texinfo::Commands::brace_commands{$cmdname})) {
        #Texinfo::Common::debug_list(" brace command with args", $element->{'contents'});
          if ($style_commands_formatting{$cmdname}) {
            my $formatting = $style_commands_formatting{$cmdname};
            my $in_monospace_not_normal;
            if ((defined($default_args_code_style{$cmdname})
                 and $default_args_code_style{$cmdname}->[0])
                or $Texinfo::Commands::math_commands{$cmdname}) {
              $in_monospace_not_normal = 1;
            } elsif ($brace_commands{$cmdname}
                     and $brace_commands{$cmdname} eq 'style_no_code') {
              $in_monospace_not_normal = 0;
            }
            my ($style, $attribute_text)
             = _parse_attribute($formatting->{'attribute'});

            if ($Texinfo::Commands::brace_commands{$cmdname} eq 'context') {
              _new_document_context($self);
            }

            if ($formatting->{'upper_case'}) {
              push @{$self->{'document_context'}->[-1]->{'upper_case'}}, 1;
            }
            if ($cmdname eq 'w') {
              push @{$self->{'document_context'}->[-1]->{'no_break'}}, 1;
            }
            push @{$self->{'document_context'}->[-1]->{'monospace'}},
              $in_monospace_not_normal
                if (defined($in_monospace_not_normal));

            if (defined($formatting->{'quote'})) {
              $$output_ref .= $self->get_conf('OPEN_QUOTE_SYMBOL');
            }
            if ($cmdname eq 'math') {
              $$output_ref .= '<inlineequation>';
            }
            if ($style ne '' and (!$self->{'document_context'}->[-1]->{'inline'}
                                 or $inline_elements{$style})) {
              $$output_ref .= "<$style${attribute_text}>";
            }
          } elsif ($cmdname eq 'anchor' or $cmdname eq 'namedanchor') {
            $$output_ref .= _output_anchor($element);
            $reader->skip_children($element);
          } elsif ($Texinfo::Commands::ref_commands{$cmdname}) {
            my $args_nr = scalar(@{$element->{'contents'}});
            my $command_name;
            my $book_element;
            my ($section_name, $node_name);
            my $manual_file_index = 3;
            if ($cmdname eq 'inforef') {
              $manual_file_index = 2;
              $command_name = 'xref';
            } elsif ($cmdname eq 'link') {
              $manual_file_index = 2;
              $command_name = 'ref';
            } else {
              if ($args_nr >= 5) {
                my $book_arg = $element->{'contents'}->[4];
                if ($book_arg->{'contents'}) {
                  $reader->register_token_element_child(4);
                  $book_element = $book_arg;
                }
              }
              if ($args_nr >= 3) {
                my $section_arg = $element->{'contents'}->[2];
                if ($section_arg->{'contents'}) {
                  $reader->register_token_element_child(2);
                  $section_name = $self->convert_tree($section_arg);
                }
              }
              $command_name = $cmdname;
            }
            my $manual_file_element;
            if ($args_nr >= $manual_file_index+1) {
              my $manual_file_arg
                 = $element->{'contents'}->[$manual_file_index];
              if ($manual_file_arg->{'contents'}) {
                $reader->register_token_element_child($manual_file_index);
                $manual_file_element = $manual_file_arg;
              }
            }
            if (! defined($section_name) and $args_nr >= 2
                and $element->{'contents'}->[1]->{'contents'}) {
              my $section_arg = $element->{'contents'}->[1];
              $reader->register_token_element_child(1);
              $section_name = $self->convert_tree($section_arg);
            } elsif ($element->{'contents'}->[0]->{'contents'}) {
              my $node_arg = $element->{'contents'}->[0];
              $reader->register_token_element_child(0);
              push @{$self->{'document_context'}->[-1]->{'upper_case'}}, 0;
              $node_name = $self->convert_tree($node_arg);
              pop @{$self->{'document_context'}->[-1]->{'upper_case'}};

              if (($book_element or $manual_file_element)
                  and $node_name eq 'Top') {
                $node_name = undef;
              }
            }

            push @{$self->{'document_context'}->[-1]->{'upper_case'}}, 0;
            # external book ref
            if ($book_element) {
              if ($section_name) {
                my $substituted_strings = {
                    'section_name' =>
                      $self->new_tree_element({'type' => '_converted',
                                                 'text' => $section_name}, 1),
                    'book' => $book_element
                  };
                if ($command_name eq 'ref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt(
                       'section ``{section_name}\'\' in @cite{{book}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'xref') {
                  $$output_ref .= $self->convert_tree(
                   $self->tree_element_cdt(
                     'See section ``{section_name}\'\' in @cite{{book}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'pxref') {
                  $$output_ref .= $self->convert_tree(
                   $self->tree_element_cdt(
                     'see section ``{section_name}\'\' in @cite{{book}}',
                               $substituted_strings, 1));
                }
              } elsif ($node_name) {
                my $substituted_strings = {
                   'node_name' =>
                      $self->new_tree_element({'type' => '_converted',
                                                 'text' => $node_name}, 1),
                   'book' => $book_element
                  };
                if ($command_name eq 'ref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('``{node_name}\'\' in @cite{{book}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'xref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('See ``{node_name}\'\' in @cite{{book}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'pxref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt(
                         'see ``{node_name}\'\' in @cite{{book}}',
                               $substituted_strings, 1));
                }
              } else {
                if ($command_name eq 'ref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('@cite{{book}}',
                      {'book' => $book_element }, 1));
                } elsif ($command_name eq 'xref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('See @cite{{book}}',
                               {'book' => $book_element }, 1));
                } elsif ($command_name eq 'pxref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('see @cite{{book}}',
                      {'book' => $book_element }, 1));
                }
              }
            } elsif ($manual_file_element) {
              if ($section_name) {
                my $substituted_strings = {
                  'section_name' =>
                     $self->new_tree_element({'type' => '_converted',
                                                'text' => $section_name}, 1),
                  'manual' => $manual_file_element
                 };
                if ($command_name eq 'ref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt(
                      'section ``{section_name}\'\' in @file{{manual}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'xref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt(
                       'See section ``{section_name}\'\' in @file{{manual}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'pxref') {
                  $$output_ref .= $self->convert_tree(
                     $self->tree_element_cdt(
                     'see section ``{section_name}\'\' in @file{{manual}}',
                               $substituted_strings, 1));
                }
              } elsif ($node_name) {
                my $substituted_strings = {
                    'node_name' =>
                      $self->new_tree_element({'type' => '_converted',
                                                 'text' => $node_name}, 1),
                    'manual' => $manual_file_element
                  };
                if ($command_name eq 'ref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('``{node_name}\'\' in @file{{manual}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'xref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt(
                      'See ``{node_name}\'\' in @file{{manual}}',
                               $substituted_strings, 1));
                } elsif ($command_name eq 'pxref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt(
                        'see ``{node_name}\'\' in @file{{manual}}',
                               $substituted_strings, 1));
                }
              } else {
                if ($command_name eq 'ref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('@file{{manual}}',
                      {'manual' => $manual_file_element }, 1));
                } elsif ($command_name eq 'xref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('See @file{{manual}}',
                      {'manual' => $manual_file_element }, 1));
                } elsif ($command_name eq 'pxref') {
                  $$output_ref .= $self->convert_tree(
                    $self->tree_element_cdt('see @file{{manual}}',
                      {'manual' => $manual_file_element }, 1));
                }
              }
            } elsif ($cmdname eq 'inforef') {
            } else {
              my $linkend = '';
              my $node_arg = $element->{'contents'}->[0];
              if ($node_arg and $node_arg->{'extra'}
                  and defined($node_arg->{'extra'}->{'normalized'})
                  and !$node_arg->{'extra'}->{'manual_content'}) {
                $linkend = " linkend=\"$node_arg->{'extra'}->{'normalized'}\"";
              }
              my $link_text = $section_name;
              $link_text = $node_name if (! defined($link_text));
              my $argument = "<link${linkend}>".$link_text."</link>";
              if ($cmdname eq 'ref'
                  or $cmdname eq 'link') {
                $$output_ref .= $self->convert_tree(
                        $self->tree_element_cdt('{title_ref}',
                         {'title_ref' =>
                            $self->new_tree_element({'type' => '_converted',
                                               'text' => $argument}, 1)}, 1));
              } elsif ($cmdname eq 'xref') {
                $$output_ref .= $self->convert_tree(
                        $self->tree_element_cdt('See {title_ref}',
                         {'title_ref' =>
                            $self->new_tree_element({'type' => '_converted',
                                            'text' => $argument}, 1)}, 1));
              } elsif ($cmdname eq 'pxref') {
                $$output_ref .= $self->convert_tree(
                        $self->tree_element_cdt('see {title_ref}',
                         {'title_ref' =>
                           $self->new_tree_element({'type' => '_converted',
                                               'text' => $argument}, 1)}, 1));
              }
            }
            pop @{$self->{'document_context'}->[-1]->{'upper_case'}};
            $reader->skip_children($element);
          } elsif ($cmdname eq 'image') {
            if ($element->{'contents'}
                and $element->{'contents'}->[0]->{'contents'}) {
              Texinfo::Convert::Text::set_options_code(
                                     $self->{'convert_text_options'});
              Texinfo::Convert::Text::set_options_encoding_if_not_ascii($self,
                                      $self->{'convert_text_options'});
              my $basefile = Texinfo::Convert::Text::convert_to_text(
                                            $element->{'contents'}->[0],
                                        $self->{'convert_text_options'});
              Texinfo::Convert::Text::reset_options_code(
                                     $self->{'convert_text_options'});
              Texinfo::Convert::Text::reset_options_encoding(
                                     $self->{'convert_text_options'});

              my $is_inline = Texinfo::Common::element_is_inline($element);
              if ($is_inline) {
                $$output_ref .= "<inlinemediaobject>";
              } else {
                $$output_ref .= "<informalfigure><mediaobject>";
              }
              my @files;
              foreach my $extension (@docbook_image_extensions) {
                my ($file_name, $file_name_encoding)
                   = $self->encoded_input_file_name("$basefile.$extension");
                if (Texinfo::Common::locate_include_file($file_name,
                                      $self->get_conf('INCLUDE_DIRECTORIES'))) {
                  push @files, ["$basefile.$extension", uc($extension)];
                }
              }
              my $image_file_found = scalar(@files);;
              if (!$image_file_found) {
                push @files, ["$basefile.jpg", 'JPG'];
              }
              foreach my $file (@files) {
                $$output_ref .= "<imageobject><imagedata fileref=\""
                   .$self->xml_protect_text($file->[0])
                   ."\" format=\"$file->[1]\"></imagedata></imageobject>";
              }
              my ($image_text, $image_width)
                    = $self->txt_image_text($element, $basefile);
              if (defined($image_text)) {
                # remove last end of line
                chomp($image_text);
                $$output_ref .= "<textobject><literallayout>"
                   ._protect_text($self, $image_text)
                   .'</literallayout></textobject>';
              }
              if (!defined($image_text) and !$image_file_found) {
                $self->converter_line_warn(sprintf(
                         __("\@image file `%s' not found, using `%s'"),
                       $basefile, "$basefile.jpg"), $element->source_info());
              }

              if ($is_inline) {
                $$output_ref .= "</inlinemediaobject>";
              } else {
                $$output_ref .= "</mediaobject></informalfigure>";
              }
            }
            $reader->skip_children($element);
          } elsif ($cmdname eq 'email') {
            my $name;
            my $email;
            my $args_nr = 0;
            $args_nr = scalar(@{$element->{'contents'}})
              if ($element->{'contents'});
            if ($args_nr) {
              my $email_arg = $element->{'contents'}->[0];
              if ($email_arg->{'contents'}) {
                $reader->register_token_element_child(0);
                $email = $email_arg;
              }
            }
            my $email_text;
            if ($args_nr >= 2) {
              my $name_arg = $element->{'contents'}->[1];
              if ($name_arg->{'contents'}) {
                $reader->register_token_element_child(1);
                $name = $name_arg;
              }
            }
            if ($email) {
              Texinfo::Convert::Text::set_options_code(
                                   $self->{'convert_text_options'});
              Texinfo::Convert::Text::set_options_encoding_if_not_ascii($self,
                                    $self->{'convert_text_options'});
              $email_text
                = _protect_text($self, Texinfo::Convert::Text::convert_to_text(
                              $email, $self->{'convert_text_options'}));
              Texinfo::Convert::Text::reset_options_code(
                                   $self->{'convert_text_options'});
              Texinfo::Convert::Text::reset_options_encoding(
                                   $self->{'convert_text_options'});
            }
            if ($name and $email) {
              # FIXME DocBook 5 ulink -> link
              # There is no possibility to do something similar in DocBook 5.
              # The best is probably either to forget about the name, or
              # follow <email> by the name in parentheses
              my $link_name = $self->convert_tree($name);
              $$output_ref
                .= "<ulink url=\"mailto:$email_text\">$link_name</ulink>";
            } elsif ($email) {
              $$output_ref .= "<email>$email_text</email>";
            } elsif ($name) {
              $$output_ref .= $self->convert_tree($name);
            }
            $reader->skip_children($element);
          } elsif ($cmdname eq 'uref' or $cmdname eq 'url') {
            my $args_nr = scalar(@{$element->{'contents'}});
            my $url_text;
            my $url_arg = $element->{'contents'}->[0];
            if ($url_arg->{'contents'}) {
              $reader->register_token_element_child(0);
              Texinfo::Convert::Text::set_options_code(
                                   $self->{'convert_text_options'});
              Texinfo::Convert::Text::set_options_encoding_if_not_ascii($self,
                                    $self->{'convert_text_options'});
              $url_text = _protect_text($self,
                Texinfo::Convert::Text::convert_to_text($url_arg,
                                         $self->{'convert_text_options'}));
              Texinfo::Convert::Text::reset_options_code(
                                   $self->{'convert_text_options'});
              Texinfo::Convert::Text::reset_options_encoding(
                                   $self->{'convert_text_options'});
            } else {
              $url_text = '';
            }
            my $replacement;
            if ($args_nr >= 2) {
              my $replacement_arg = $element->{'contents'}->[1];
              if ($replacement_arg->{'contents'}) {
                $reader->register_token_element_child(1);
                $replacement = $self->convert_tree($replacement_arg);
              }
            }
            if (!defined($replacement) or $replacement eq '') {
              if ($args_nr >= 3) {
                my $replacement_arg = $element->{'contents'}->[2];
                if ($replacement_arg->{'contents'}) {
                  $reader->register_token_element_child(2);
                  $replacement = $self->convert_tree($replacement_arg);
                }
              }
            }
            if (!defined($replacement) or $replacement eq '') {
              $replacement = $url_text;
            }
            $$output_ref .= "<ulink url=\"$url_text\">$replacement</ulink>";
            $reader->skip_children($element);
            # FIXME DocBook 5
            # need to add in the preamble
            #    xmlns:xlink="http://www.w3.org/1999/xlink"
            # return "<link xlink:href=\"$url_text\">$replacement</link>";
          } elsif ($cmdname eq 'abbr' or $cmdname eq 'acronym') {
            my $args_nr = scalar(@{$element->{'contents'}});
            if ($args_nr) {
              my $argument;
              my $arg_element = $element->{'contents'}->[0];
              if ($arg_element->{'contents'}) {
                $reader->register_token_element_child(0);
                my $arg_text = $self->convert_tree($arg_element);
                if ($arg_text ne '') {
                  my $format_element;
                  if ($cmdname eq 'abbr') {
                    $format_element = 'abbrev';
                  } else {
                    $format_element = $cmdname;
                  }
                  $argument = "<$format_element>$arg_text</$format_element>";
                }
              }
              my $explanation_e;
              if ($args_nr >= 2) {
                $reader->register_token_element_child(1);
                $explanation_e = $element->{'contents'}->[1];
              }
              if ($explanation_e and $explanation_e->{'contents'}) {
                if (defined($argument)) {
                  my $tree = $self->tree_element_cdt(
                              '{abbr_or_acronym} ({explanation})',
                                 {'abbr_or_acronym' =>
                            $self->new_tree_element({'type' => '_converted',
                                                     'text' => $argument}, 1),
                                  'explanation' => $explanation_e}, 1);
                  $$output_ref .= $self->convert_tree($tree);
                } else {
                  $$output_ref .= $self->convert_tree($explanation_e);
                }
              } elsif (defined($argument)) {
                $$output_ref .= $argument;
              }
            }
            $reader->skip_children($element);
          } elsif ($cmdname eq 'U') {
            if ($element->{'contents'}) {
              my $arg = $element->{'contents'}->[0];
              if ($arg->{'contents'}) {
                my $arg_text = $arg->{'contents'}->[0]->{'text'};
                if (defined($arg_text)) {
                  $$output_ref .= "&#x$arg_text;";
                }
              }
            }
            $reader->skip_children($element);
          } elsif ($Texinfo::Commands::brace_commands{$cmdname} eq 'inline') {
            my $expand = 0;
            if ($Texinfo::Commands::inline_format_commands{$cmdname}) {
              if ($cmdname eq 'inlinefmtifelse'
                  or ($element->{'extra'} and $element->{'extra'}->{'format'}
                      and $self->{'expanded_formats'}->{$element->{'extra'}->{'format'}})) {
                $expand = 1;
              }
            } elsif (defined($element->{'extra'}->{'expand_index'})) {
              $expand = 1;
            }
            if ($expand) {
              my $arg_index = 1;
              if ($cmdname eq 'inlineraw') {
                _new_document_context($self);
                $self->{'document_context'}->[-1]->{'raw'} = 1;
              } elsif ($cmdname eq 'inlinefmtifelse'
      and ! $self->{'expanded_formats'}->{$element->{'extra'}->{'format'}}) {
                $arg_index = 2;
              }
              if (scalar(@{$element->{'contents'}}) > $arg_index) {
                my $converted_arg = $element->{'contents'}->[$arg_index];
                if ($converted_arg->{'contents'}) {
                  $reader->register_token_element_child($arg_index);
                  $$output_ref .= $self->convert_tree($converted_arg);
                }
              }
              if ($cmdname eq 'inlineraw') {
                pop @{$self->{'document_context'}};
              }
            }
            #warn "  returning after braced cmd result\n";
            $reader->skip_children($element);
          } elsif ($cmdname eq 'seeentry' or $cmdname eq 'seealso') {
            # gather the text to output it when the index entry closes
            # and not where the command appears
            if (!$self->{'document_context'}->[-1]->{$cmdname.'_info'}) {
              my $command_text = '';
              $self->{'document_context'}->[-1]->{$cmdname.'_info'}
                = [\$command_text, $output_ref];
              $output_ref = \$command_text;
            } else {
              $reader->skip_children($element);
            }
          } else {
            # ignored brace command
            #warn "  returning empty string for ignored braced cmd\n";
            $reader->skip_children($element);
          }
        } elsif (exists($Texinfo::Commands::block_commands{$cmdname})) {
          if ($ignored_block_commands{$cmdname}
              or ($Texinfo::Commands::block_commands{$cmdname} eq 'raw'
                  and $cmdname ne 'verbatim')
              or $Texinfo::Commands::block_commands{$cmdname} eq 'menu'
              or ($Texinfo::Commands::block_commands{$cmdname} eq 'format_raw'
                  and !$self->{'expanded_formats'}->{$cmdname})) {
            $reader->skip_children($element);
            next;
          }

          push @format_elements_stack, [];

          if ($self->{'context_block_commands'}->{$cmdname}) {
            _new_document_context($self);
          }
          my @attributes;
          my $appended = '';
          my @format_elements;
          if (exists($docbook_preformatted_formats{$cmdname})) {
            push @{$self->{'document_context'}->[-1]->{'preformatted_stack'}},
               $docbook_preformatted_formats{$cmdname};
          } elsif ($cmdname eq 'enumerate') {
            push @format_elements, 'orderedlist';
            my $numeration;
            my $arguments_line = $element->{'contents'}->[0];
            my $block_line_arg = $arguments_line->{'contents'}->[0];
            if (exists($block_line_arg->{'contents'})
                and exists($block_line_arg->{'contents'}->[0]->{'text'})) {
              my $enumerate_specification
                = $block_line_arg->{'contents'}->[0]->{'text'};
              if ($enumerate_specification =~ /^[A-Z]/) {
                $numeration = 'upperalpha';
              } elsif ($enumerate_specification =~ /^[a-z]/) {
                $numeration = 'loweralpha';
              } else {
                $numeration = 'arabic';
              }
            } else {
              $numeration = 'arabic';
            }
            push @attributes, " numeration=\"$numeration\"";
          } elsif ($Texinfo::Commands::block_commands{$cmdname} eq 'item_line') {
            push @format_elements, 'variablelist';
          } elsif ($cmdname eq 'itemize') {
            push @format_elements, 'itemizedlist';
            #push @attributes, " mark=\"\"";
          } elsif ($cmdname eq 'multitable') {
            push @format_elements, "informaltable";
            push @attributes, '';
            my $columns_count;
            if ($element->{'extra'}
                and defined($element->{'extra'}->{'max_columns'})) {
              $columns_count = $element->{'extra'}->{'max_columns'};
            } else {
              $columns_count = 0;
            }
            push @format_elements, 'tgroup';
            push @attributes, " cols=\"$columns_count\"";
            my @fractions;
            my $multiply;
            my $columnfractions
              = Texinfo::Common::multitable_columnfractions($element);
            if ($columnfractions) {
              if ($columnfractions->{'extra'}
                  and $columnfractions->{'extra'}->{'misc_args'}) {
                @fractions = @{$columnfractions->{'extra'}->{'misc_args'}};
                $multiply = 100;
              }
            } else {
              # @multitable line arguments_line type element
              my $arguments_line = $element->{'contents'}->[0];
              my $block_line_arg = $arguments_line->{'contents'}->[0];
              my $contents = $block_line_arg->{'contents'};
              if ($contents) {
                $multiply = 1;
                foreach my $content (@$contents) {
                  if ($content->{'type'}
                      and $content->{'type'} eq 'bracketed_arg') {
                    my $prototype_text = '';
                    if ($content->{'contents'}) {
                      Texinfo::Convert::Text::set_options_encoding_if_not_ascii(
                                      $self, $self->{'convert_text_options'});
                      $prototype_text
                        = Texinfo::Convert::Text::convert_to_text(
                                         $content,
                                         $self->{'convert_text_options'});
                      Texinfo::Convert::Text::reset_options_encoding(
                                         $self->{'convert_text_options'});
                    }
                    push @fractions,
                      Texinfo::Convert::Unicode::string_width($prototype_text);
                  }
                }
              }
            }
            foreach my $fraction (@fractions) {
              $appended .= '<colspec colwidth="'.($fraction*$multiply)
                           .'*"></colspec>';
            }
          } elsif ($cmdname eq 'float') {
            my $anchor = _output_anchor($element);
            $$output_ref .= $anchor . "\n" if ($anchor ne '');
          } elsif ($cmdname eq 'verbatim') {
            push @format_elements, 'screen';
          } elsif ($cmdname eq 'displaymath') {
            push @format_elements, 'informalequation';
            push @format_elements, 'mathphrase';
          } elsif ($cmdname eq 'quotation' or $cmdname eq 'smallquotation') {
            my $quotation_authors = [];
            $reader->register_token_element();
            Texinfo::Example::TreeElementConverter::find_element_authors(
                                                        $element,
                                                        $quotation_authors);
            foreach my $author (@$quotation_authors) {
              my $arg = $author->get_child(0);
              if ($arg->{'contents'}) {
                $appended .= '<attribution>'.
                       $self->convert_tree($arg)
                           ."</attribution>\n";
              }
            }
            my $format_element;
            # arguments_line type element
            $reader->register_token_element_child(0);
            my $arguments_line = $element->{'contents'}->[0];
            my $block_line_arg = $arguments_line->{'contents'}->[0];
            if ($block_line_arg->{'contents'}) {
              my $quotation_arg_text
                = Texinfo::Convert::Text::convert_to_text($block_line_arg,
                                           $self->{'convert_text_options'});
              if ($docbook_special_quotations{lc($quotation_arg_text)}) {
                $format_element = lc($quotation_arg_text);
              } else {
                $self->{'pending_prepend'}
                  = $self->convert_tree(
                          $self->tree_element_cdt('@b{{quotation_arg}:} ',
                                {'quotation_arg' => $block_line_arg}, 1));
              }
            }
            $format_element = 'blockquote' if (!defined($format_element));
            push @format_elements, $format_element;
          } elsif ($cmdname eq 'cartouche') {
            push @format_elements, 'sidebar';
          } elsif ($Texinfo::Commands::block_commands{$cmdname} eq 'format_raw') {
            # the document_context was opened for the command, so this is
            # forgotten once all the raw internal text has been formatted
            # when the document_context is closed
            $self->{'document_context'}->[-1]->{'raw'} = 1;
          }
          foreach my $format_element (@format_elements) {
            my $attribute = shift @attributes;
            $attribute = '' if (!defined($attribute));
            $$output_ref .= "<$format_element${attribute}>";
            unshift @{$format_elements_stack[-1]}, $format_element;
          }
          $$output_ref .= $appended if (defined($appended));

          if ($cmdname eq 'cartouche') {
            # arguments_line type element
            my $arguments_line = $element->{'contents'}->[0];
            my $block_line_arg = $arguments_line->{'contents'}->[0];
            if ($block_line_arg->{'contents'}) {
              # Keep the previous output reference and
              # accumulate in a separate text to be able to add the opening
              # element only if not empty
              my $title_text = '';
              $self->{'document_context'}->[-1]->{'cartouche_title'}
                = [$output_ref, \$title_text];
              $output_ref = \$title_text;
            }
          } elsif ($Texinfo::Commands::preformatted_code_commands{$cmdname}
              or $Texinfo::Commands::math_commands{$cmdname}) {
            push @{$self->{'document_context'}->[-1]->{'monospace'}}, 1;
          }
        }
        #warn " end of cmdname\n";

      } elsif ($e_type) {
        #warn " START have type $e_type\n";

        if (defined($type_elements{$e_type})) {
          $$output_ref .= "<$type_elements{$e_type}>";
        } elsif ($e_type eq 'preformatted') {
          $$output_ref .= "<$self->{'document_context'}->[-1]->{'preformatted_stack'}->[-1]>";
          $self->{'document_context'}->[-1]->{'in_preformatted'} = 1;
        } elsif ($e_type eq 'def_line') {
          $reader->register_token_element();
          my $def_line_result = _begin_def_line($self, $element);
          $$output_ref .= $def_line_result if (defined($def_line_result));
        } elsif ($e_type eq 'table_term') {
          # should be closed by the @item.  Allows to have the index entries in
          # term, which is better than out.
          $$output_ref .= "<term>";
        } elsif ($e_type eq 'before_node_section') {
          if (!$self->get_conf('_DOCBOOK_PIECE')) {
            # ignore text before the first @node or sectioning command
            # as DocBook does not allow content not within some semantic
            # markup, unless _DOCBOOK_PIECE is set to mean that a the output is not
            # a full book.
            $output_ref = \$void;
          }
        } elsif ($e_type eq 'def_category') {
          $$output_ref .= "<phrase role=\"category\"><emphasis role=\"bold\">";
        } elsif ($e_type eq 'def_name') {
          my $def_command
            = $element->{'parent'}->{'parent'}->{'extra'}->{'def_command'};
          $$output_ref .= "<$defcommand_name_type{$def_command}>";
        } elsif ($def_argument_types_docbook{$e_type}) {
          foreach my $element_attribute (
                               @{$def_argument_types_docbook{$e_type}}) {
            my ($element, $attribute_text)
              = _parse_attribute($element_attribute);
            $$output_ref .= "<$element${attribute_text}>";
          }
        } elsif (exists($docbook_preformatted_types{$e_type})) {
          push @{$self->{'document_context'}->[-1]->{'preformatted_stack'}},
             $docbook_preformatted_types{$e_type};
        } elsif ($ignored_types{$e_type}
                 or ($e_type eq 'arguments_line'
                     and not (
             $self->{'document_context'}->[-1]->{'cartouche_title'}))) {
          $reader->skip_children($element);
        }

          # not restricted enough, includes line_args, for instance
          #and tree_element_is_inline($element, 1))
        if (defined($self->{'pending_prepend'})
            and ($e_type eq 'paragraph'
                 or $e_type eq 'preformatted')) {
          $$output_ref .= $self->{'pending_prepend'};
          delete $self->{'pending_prepend'};
        }
      }
      #warn " end of START\n";


    } elsif ($category == $TXI_READ_ELEMENT_END) {
      my $cmdname = $element->{'cmdname'};
      if (defined($cmdname)) {
        if ($style_commands_formatting{$cmdname}
            and !($e_type and $e_type eq 'definfoenclose_command')) {
          my $formatting = $style_commands_formatting{$cmdname};
          my $in_monospace_not_normal;
          if (defined($default_args_code_style{$cmdname})
              and $default_args_code_style{$cmdname}->[0]) {
             $in_monospace_not_normal = 1;
          } elsif ($brace_commands{$cmdname}
                   and $brace_commands{$cmdname} eq 'style_no_code') {
            $in_monospace_not_normal = 0;
          }
          my ($style, $attribute_text)
           = _parse_attribute($formatting->{'attribute'});

          if ($style ne '' and (!$self->{'document_context'}->[-1]->{'inline'}
                                 or $inline_elements{$style})) {
            $$output_ref .= "</$style>";
          }
          if ($cmdname eq 'math') {
            $$output_ref .= '</inlineequation>';
          }
          if (defined($formatting->{'quote'})) {
            $$output_ref .= $self->get_conf('CLOSE_QUOTE_SYMBOL');
          }
          if (defined($formatting->{'upper_case'})) {
            pop @{$self->{'document_context'}->[-1]->{'upper_case'}};
          }
          if ($cmdname eq 'w') {
            pop @{$self->{'document_context'}->[-1]->{'no_break'}};
          }
          pop @{$self->{'document_context'}->[-1]->{'monospace'}}
            if (defined($in_monospace_not_normal)
                or $Texinfo::Commands::math_commands{$cmdname});
          if ($Texinfo::Commands::brace_commands{$cmdname} eq 'context') {
            pop @{$self->{'document_context'}};
          }
          if ($cmdname eq 'w') {
            $$output_ref .= $w_command_mark;
          }
        } elsif ($cmdname eq 'item' or $cmdname eq 'itemx'
                 or $cmdname eq 'headitem' or $cmdname eq 'tab') {
          my $close_format_elements = pop @format_elements_stack;
          foreach my $format_element (@$close_format_elements) {
            $$output_ref .= "</$format_element>";
          }
        } elsif (exists($Texinfo::Commands::block_commands{$cmdname})) {
          my $close_format_elements = pop @format_elements_stack;
          foreach my $format_element (@$close_format_elements) {
            $$output_ref .= "</$format_element>";
          }
          if ($Texinfo::Commands::preformatted_code_commands{$cmdname}
                 or $Texinfo::Commands::math_commands{$cmdname}) {
            pop @{$self->{'document_context'}->[-1]->{'monospace'}};
          }

        # a pending_prepend still there may happen if a quotation is empty.
          delete $self->{'pending_prepend'};
          if (!$self->{'document_context'}->[-1]->{'raw'}
              and exists($docbook_preformatted_formats{$cmdname})) {
            my $format = pop @{$self->{'document_context'}->[-1]->{'preformatted_stack'}};
            die "BUG $format ne $docbook_preformatted_formats{$cmdname}"
              if ($format ne $docbook_preformatted_formats{$cmdname});
          }
          if ($self->{'context_block_commands'}->{$cmdname}) {
            pop @{$self->{'document_context'}};
          }

        # close sectioning command
        } elsif ($cmdname ne 'node'
                 and $Texinfo::Commands::root_commands{$cmdname}) {
       # other functions could have been called but this one has an XS override
          my $sections_list = $self->tree_element_sections_list();
          my $section_relations
            = $sections_list->[$element->{'extra'}->{'section_number'} -1];
          my $docbook_sectioning_element
             = _docbook_section_element($self, $element);
          if ($docbook_sectioning_element eq 'part'
              and not ($section_relations
                       and $section_relations->{'part_associated_section'})
                       and !Texinfo::Common::is_content_empty($element)) {
            $$output_ref .= "</partintro>\n";
          }
          my $level_adjusted_cmdname
           = Texinfo::Structuring::section_level_adjusted_command_name(
                                                                    $element);
          if (!($section_relations
                and $section_relations->{'section_children'}
                and scalar(@{$section_relations->{'section_children'}}))
              or $level_adjusted_cmdname eq 'top') {
            $$output_ref .= "</$docbook_sectioning_element>\n";
            pop @{$self->{'lang_stack'}};
            my $current = $element;
            my $current_relations
              = $sections_list->[$current->{'extra'}->{'section_number'} -1];
            while ($current_relations->{'section_directions'}
                   and $current_relations->{'section_directions'}->{'up'}
                   and !$current_relations->{'section_directions'}->{'next'}
         and Texinfo::Structuring::section_level_adjusted_command_name(
       $current_relations->{'section_directions'}->{'up'}->{'element'}) ne 'top') {
              $current_relations = $current_relations->{'section_directions'}->{'up'};
              $current = $current_relations->{'element'};
              $$output_ref
                 .= '</'._docbook_section_element($self, $current) .">\n";
              pop @{$self->{'lang_stack'}};
            }
          }
        } elsif ($cmdname eq 'seeentry' or $cmdname eq 'seealso') {
          $output_ref
            = $self->{'document_context'}->[-1]->{$cmdname.'_info'}->[1];
        } elsif ($e_type
                 and $e_type eq 'index_entry_command') {
          my $result = '';
          my ($index_entry, $index_info)
            = $self->get_tree_element_index_entry($element);

          my $entry_element = $index_entry->{'entry_element'};
          if ($self->{'document_context'}->[-1]->{'subentry_output'}) {
            $output_ref = shift(@{$self->{'document_context'}
                            ->[-1]->{'subentry_output'}});
            foreach my $subentry_output
               (@{$self->{'document_context'}->[-1]->{'subentry_output'}}) {
              $result .= $$subentry_output;
            }
          }
          if (defined($self->{'document_context'}->[-1]->{'seeentry_info'})) {
            my $seeentry_ref
              = $self->{'document_context'}->[-1]->{'seeentry_info'}->[0];
            $result .= "<see>";
            $result .= $$seeentry_ref;
            $result .= "</see>";
            delete $self->{'document_context'}->[-1]->{'seeentry_output'};
          }
          if (defined($self->{'document_context'}->[-1]->{'seealso_info'})) {
            my $seealso_ref
              = $self->{'document_context'}->[-1]->{'seealso_info'}->[0];
            $result .= "<seealso>";
            $result .= $$seealso_ref;
            $result .= "</seealso>";
            delete $self->{'document_context'}->[-1]->{'seealso_output'};
          }
          $$output_ref .= "</primary>";
          $$output_ref .= $result;
          $$output_ref .= "</indexterm>";

          pop @{$self->{'document_context'}};
          my ($comment, $end_line) = $self->comment_or_end_line($element);
          if ($comment) {
            $end_line = $self->_format_comment($comment);
          }
          if ($self->{'document_context'}->[-1]->{'in_preformatted'}) {
            chomp($end_line);
          }
          $$output_ref .= $end_line;
        } elsif (exists($docbook_line_commands{$cmdname})) {
          if ($Texinfo::Commands::def_commands{$cmdname}) {
            pop @{$self->{'document_context'}};
            $$output_ref .= "</synopsis>\n";
          } elsif ($cmdname eq 'subentry') {
            my $subentry_level
              = $self->{'document_context'}->[-1]->{'subentry_level'};
            my $level;
            if ($subentry_level == 1) {
              $level = 'secondary';
            } else {
              $level = 'tertiary';
            }
            $self->{'document_context'}->[-1]->{'subentry_level'}--;
            $output_ref
              = $self->{'document_context'}->[-1]
                    ->{'subentry_output'}->[$subentry_level];
            $$output_ref .= "</$level>";
          }
        }

      } elsif ($e_type) {
        if (defined($type_elements{$e_type})) {
          $$output_ref .= "</$type_elements{$e_type}>";
        } elsif ($e_type eq 'preformatted') {
          $$output_ref
            .= "</$self->{'document_context'}->[-1]->{'preformatted_stack'}->[-1]>";
          delete $self->{'document_context'}->[-1]->{'in_preformatted'};
        } elsif ($e_type eq 'def_line') {
          pop @{$self->{'document_context'}};
          $$output_ref .= "</synopsis>\n";
        } elsif ($e_type eq 'def_category') {
          $$output_ref .= "</emphasis>:</phrase>";
        } elsif ($e_type eq 'def_name') {
          my $def_command
            = $element->{'parent'}->{'parent'}->{'extra'}->{'def_command'};
          $$output_ref .= "</$defcommand_name_type{$def_command}>";
        } elsif ($def_argument_types_docbook{$e_type}) {
          foreach my $element_attribute (reverse (
                               @{$def_argument_types_docbook{$e_type}})) {
            my ($element, $attribute_text)
              = _parse_attribute($element_attribute);
            $$output_ref .= "</$element>";
          }
        } elsif ($e_type eq 'block_line_arg') {
          my $top_cartouche_title
            = $self->{'document_context'}->[-1]->{'cartouche_title'};
          if ($top_cartouche_title) {
            my $title_text_ref;
            ($output_ref, $title_text_ref) = @$top_cartouche_title;
            if ($$title_text_ref ne '') {
              $$output_ref .= '<title>'.$$title_text_ref.'</title>'."\n";
            }
            delete $self->{'document_context'}->[-1]->{'cartouche_title'};
          }
        } elsif (exists($docbook_preformatted_types{$e_type})) {
          my $format
           = pop @{$self->{'document_context'}->[-1]->{'preformatted_stack'}};
          die "BUG $format ne $docbook_preformatted_types{$e_type}"
            if ($format ne $docbook_preformatted_types{$e_type});
        } elsif ($e_type eq 'before_node_section'
                 and !$self->get_conf('_DOCBOOK_PIECE')) {
          $output_ref = \$result;
        }
      }

    } else {# EMPTY
      my $cmdname = $element->{'cmdname'};
      if ($cmdname) {
        if (defined($docbook_no_arg_commands_formatting{$cmdname})) {
          $$output_ref .= $docbook_no_arg_commands_formatting{$cmdname};
        } elsif ($cmdname eq 'w') {
        # special case to ensure that @w leads to something even if empty
          $$output_ref .= $w_command_mark;
        } elsif ($Texinfo::Commands::accent_commands{$cmdname}) {
          $reader->register_token_element();
          $result .= $self->tree_element_xml_accents($element,
                 $self->{'document_context'}->[-1]->{'upper_case'}->[-1]);
        } elsif (!exists($docbook_no_warn_empty_commands{$cmdname})
                # brace commands without braces lead to EMPTY element tokens
                 and !exists($Texinfo::Commands::brace_commands{$cmdname})
                 and !($e_type and $e_type eq 'definfoenclose_command')) {
          print STDERR "UNEXPECTED EMPTY C $cmdname\n";
        }
      } elsif ($e_type) {
        if (!exists($docbook_no_warn_empty_types{$e_type})) {
          print STDERR "UNEXPECTED EMPTY T $e_type\n";
        }
      } else {
        print STDERR "UNEXPECTED no type\n";
        cluck();
      }
    }
  }

  #print STDERR " ---- E\n";
  return $result;
}

# figure: mandatory title->use it with shortcaption?. Has a caption.

1;

__END__
