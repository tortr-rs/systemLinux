# TreeElementConverter.pm: functions for Converters using TreeElement
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

# The methods in this file are only needed for the TreeElement and Reader
# interfaces.  Some functions are pure Perl, some are useful for XS
# overriding, to call C code that registers Perl tree elements and add
# keys be able to find the document and C element in XS code.
# The functions correspond to functions in Texinfo::Convert::Converter,
# Texinfo::Common, Texinfo::Convert::Utils and Texinfo::Structuring.

# This module is not used in texi2any converters.  Using the TreeElement
# interface is slow in Perl and using the XS interface requires careful code
# and many functions replacements.  The SWIG interface should be used instead.

package Texinfo::Example::TreeElementConverter;

use 5.006;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Carp qw(cluck confess);

use Encode;
use Unicode::Normalize;

use Texinfo::XSLoader;

use Texinfo::Example::TreeElementConverterXS;

use Texinfo::Commands;
use Texinfo::CommandsValues;
use Texinfo::Common;

use Texinfo::TreeElement;

use Texinfo::Convert::Converter;

use Texinfo::Translations;

use Texinfo::UnicodeData;
use Texinfo::Convert::Utils;

our @ISA = qw(Texinfo::Convert::Converter);

our $VERSION = '7.3';

my $XS_structuring = Texinfo::XSLoader::XS_structuring_enabled();

our $module_loaded = 0;

my %XS_overrides = (
  "Texinfo::Example::TreeElementConverter::new_tree_element"
    => "Texinfo::Example::TreeElementConverterXS::new_tree_element",
  "Texinfo::Example::TreeElementConverter::get_tree_element_index_entry"
    => "Texinfo::Example::TreeElementConverterXS::get_tree_element_index_entry",
  "Texinfo::Example::TreeElementConverter::get_global_unique_tree_element"
    => "Texinfo::Example::TreeElementConverterXS::get_global_unique_tree_element",
  "Texinfo::Example::TreeElementConverter::global_commands_information_command_list"
    => "Texinfo::Example::TreeElementConverterXS::global_commands_information_command_list",
  "Texinfo::Example::TreeElementConverter::tree_element_item_itemize_prepended"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_item_itemize_prepended",
  "Texinfo::Example::TreeElementConverter::item_itemize_prepended"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_item_itemize_prepended",
  "Texinfo::Example::TreeElementConverter::find_element_authors"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_find_element_authors",
  "Texinfo::Example::TreeElementConverter::tree_element_find_element_authors"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_find_element_authors",
  "Texinfo::Example::TreeElementConverter::tree_element_table_item_content_tree"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_table_item_content_tree",
  "Texinfo::Example::TreeElementConverter::table_item_content_tree"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_table_item_content_tree",
  "Texinfo::Example::TreeElementConverter::comment_or_end_line"
    => "Texinfo::Example::TreeElementConverterXS::comment_or_end_line",
  "Texinfo::Example::TreeElementConverter::tree_element_comment_or_end_line"
    => "Texinfo::Example::TreeElementConverterXS::comment_or_end_line",
  "Texinfo::Example::TreeElementConverter::argument_comment_end_line"
    => "Texinfo::Example::TreeElementConverterXS::argument_comment_end_line",
  "Texinfo::Example::TreeElementConverter::tree_element_argument_comment_end_line"
    => "Texinfo::Example::TreeElementConverterXS::argument_comment_end_line",
  "Texinfo::Example::TreeElementConverter::_utils_tree_element_expand_verbatiminclude"
    => "Texinfo::Example::TreeElementConverterXS::utils_tree_element_expand_verbatiminclude",
  "Texinfo::Example::TreeElementConverter::_utils_expand_verbatiminclude"
    => "Texinfo::Example::TreeElementConverterXS::utils_tree_element_expand_verbatiminclude",
  "Texinfo::Example::TreeElementConverter::_expand_today"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_expand_today",
  "Texinfo::Example::TreeElementConverter::index_content_element"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_index_content_element",
  "Texinfo::Example::TreeElementConverter::tree_element_index_content_element"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_index_content_element",
  "Texinfo::Example::TreeElementConverter::_element_gdt"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_gdt",
  "Texinfo::Example::TreeElementConverter::tree_element_sections_list"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_sections_list",
  "Texinfo::Example::TreeElementConverter::tree_element_nodes_list"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_nodes_list",
  "Texinfo::Example::TreeElementConverter::tree_element_headings_list"
    => "Texinfo::Example::TreeElementConverterXS::tree_element_headings_list",

# could have been in Document too
  "Texinfo::Example::TreeElementConverter::register_document_relations_lists_elements"
    => "Texinfo::Example::TreeElementConverterXS::register_document_relations_lists_elements",
  "Texinfo::Example::TreeElementConverter::build_element_tree"
    => "Texinfo::Example::TreeElementConverterXS::build_element_tree",
);

sub import {
  if (!$module_loaded) {
    if ($XS_structuring) {
      foreach my $sub (keys %XS_overrides) {
        Texinfo::XSLoader::override ($sub, $XS_overrides{$sub});
      }
    }

    $module_loaded = 1;
  }
  # The usual import method
  goto &Exporter::import;
}


# The XS override register a reference to the C element in Perl
# nodes, sectioning and heading commands.  Only needed if the
# TreeElement/Reader interfaces are used, which is not the case for
# converters used in texi2any.
sub register_document_relations_lists_elements($$) {
  my ($self, $document) = @_;
}

# Build the Perl tree of an element with an handle.  Only relevant with
# XS, and only in some case, see the code.
sub build_element_tree($) {
  my $tree = shift;
}

# information on tree elements

my %xml_accent_entities = %Texinfo::Convert::Converter::xml_accent_entities;
my %xml_accent_text_with_entities
  = %Texinfo::Convert::Converter::xml_accent_text_with_entities;

my %command_structuring_level
  = %Texinfo::CommandsValues::command_structuring_level;

my $min_level = $command_structuring_level{'chapter'};
my $max_level = $command_structuring_level{'subsubsection'};

# same as in Texinfo::Common, but using the TreeElement interface
sub tree_element_section_level($)
{
  my $section = shift;

  my $cmdname = $section->{'cmdname'};
  my $level = $command_structuring_level{$cmdname};
  # correct level according to raise/lowersections
  my $level_modifier = $section->get_attribute('level_modifier');
  if ($level_modifier) {
    $level -= $level_modifier;
    if ($level < $min_level) {
      if ($command_structuring_level{$cmdname} < $min_level) {
        $level = $command_structuring_level{$cmdname};
      } else {
        $level = $min_level;
      }
    } elsif ($level > $max_level) {
      $level = $max_level;
    }
  }
  return $level;
}

# same as in Texinfo::Structuring, but using the TreeElement interface
sub tree_element_section_level_adjusted_command_name($)
{
  my $element = shift;

  my $cmdname = $element->{'cmdname'};

  # the following condition should only be false if sectioning_structure was
  # not called
  my $heading_level = $element->get_attribute('section_level');
  if (defined($heading_level)) {
    if ($heading_level ne $Texinfo::CommandsValues::command_structuring_level{
                                                                  $cmdname}) {
      my $command
        = $Texinfo::Common::level_to_structuring_command{$cmdname}
                                                            ->[$heading_level];
      return $command;
    }
  }
  return $cmdname;
}

sub tree_element_is_content_empty($;$);
sub tree_element_is_content_empty($;$)
{
  my $tree = shift;
  my $do_not_ignore_index_entries = shift;

  if (!defined($tree)) {
    return 1;
  }

  my $contents = $tree->get_children();

  if (!$contents) {
    return 1;
  }

  foreach my $content (@$contents) {
    my $text = $content->{'text'};
    if (defined($text)) {
      if ($text =~ /\S/) {
        return 0;
      } else {
        next;
      }
    }
    my $type = $content->{'type'};
    next if ($type and $type eq 'arguments_line');

    my $cmdname = $content->{'cmdname'};
    if ($cmdname) {
      if ($type and $type eq 'index_entry_command') {
        if ($do_not_ignore_index_entries) {
          return 0;
        } else {
          next;
        }
      }
      if (exists($Texinfo::Commands::line_commands{$cmdname})) {
        if ($Texinfo::Commands::formatted_line_commands{$cmdname}
            or $Texinfo::Commands::formattable_line_commands{$cmdname}) {
          return 0;
        } else {
          next;
        }
      } elsif (exists($Texinfo::Commands::nobrace_commands{$cmdname})) {
        if ($Texinfo::Commands::formatted_nobrace_commands{$cmdname}) {
          return 0;
        } else {
          next;
        }
      } elsif ($Texinfo::Commands::non_formatted_brace_commands{$cmdname}
               or $Texinfo::Commands::non_formatted_block_commands{$cmdname}) {
        next;
      } else {
        return 0;
      }
    }
    if ($type) {
      if ($type eq 'paragraph') {
        return 0;
      }
    }
    if (not tree_element_is_content_empty($content,
                                          $do_not_ignore_index_entries)) {
      return 0;
    }
  }
  return 1;
}

# same as in Texinfo::Common, but using TreeElement interface
sub tree_element_element_is_inline($;$)
{
  my $current = shift;
  my $check_current = shift;

  if ($check_current) {
    my $inline_or_block = Texinfo::Common::element_inline_or_block($current);
    return ($inline_or_block) if (defined($inline_or_block));
  }

  while ($current->parent()) {
    $current = $current->parent();
    my $inline_or_block = Texinfo::Common::element_inline_or_block($current);
    return ($inline_or_block) if (defined($inline_or_block));
  }
  return 0;
}



# access to element with XS interface to add information to find C element

sub new_tree_element($$;$)
{
  my $self = shift;
  my $element_hash = shift;

  return Texinfo::TreeElement::new($element_hash);
}

# NOTE not used, not tested
sub get_tree_element_by_identifier($$)
{
  my $self = shift;
  my $identifier = shift;

  if ($self->{'document'}) {
    my $identifiers_target = $self->{'document'}->labels_information();
    if (defined($identifiers_target->{$identifier})) {
      return $identifiers_target->{$identifier};
    }
  }
  return undef;
}

sub get_tree_element_index_entry($$)
{
  my $self = shift;
  my $element = shift;

  my $index_entry_info = $element->get_attribute('index_entry');
  if ($index_entry_info) {

    my $indices_information;
    if ($self->{'document'}) {
      $indices_information = $self->{'document'}->indices_information();

      my ($index_entry, $index_info)
       = Texinfo::Common::lookup_index_entry($index_entry_info,
                                             $indices_information);
      return ($index_entry, $index_info);
    }
  }

  return undef, undef
}

sub get_global_unique_tree_element($$)
{
  my $self = shift;
  my $cmdname = shift;

  if ($self->{'document'}) {
    my $global_commands = $self->{'document'}->global_commands_information();
    if (defined($global_commands->{$cmdname})) {
      return $global_commands->{$cmdname};
    }
  }
  return undef;
}

# used for XS override (when there is no XS converter but XS parser/document)
# for the TreeElement interface
sub global_commands_information_command_list($$)
{
  my $document = shift;
  my $global_command = shift;

  return undef if (!$document);

  my $global_commands = $document->global_commands_information();

  return undef if (!$global_commands or !$global_commands->{$global_command}
        or ref($global_commands->{$global_command}) ne 'ARRAY');

  return $global_commands->{$global_command};
}

# similar to Texinfo::Convert::Utils, but simpler as a converter is always
# present.  Also calls tree_element_cdt
sub tree_element_translated_command_tree($$;$)
{
  my $converter = shift;
  my $cmdname = shift;
  my $build_tree = shift;

  my $translated_commands = $converter->{'translated_commands'};
  if ($translated_commands
      and defined($translated_commands->{$cmdname})) {
    my $to_translate = $translated_commands->{$cmdname};
    return $converter->tree_element_cdt($to_translate, undef, $build_tree);
  }
  return undef;
}

# wrapper used for XS overriding
sub index_content_element($;$)
{
  my $element = shift;
  my $prefer_reference_element = shift;

  return Texinfo::Common::index_content_element($element,
                                                $prefer_reference_element);
}

# same as in Texinfo::Common, but using the TreeElement interface
sub tree_element_index_content_element($;$)
{
  my $element = shift;
  my $prefer_reference_element = shift;

  my $def_command = $element->get_attribute('def_command');
  if (defined($def_command)) {
    if ($prefer_reference_element
        and defined($element->get_attribute('def_index_ref_element'))) {
      return $element->get_attribute('def_index_ref_element');
    } else {
      return $element->get_attribute('def_index_element');
    }
  } else {
    return $element->get_child(0);
  }
}



# translations

# for XS override, with a simpler interface to override than tree_element_cdt.
# Should not be called directly.
sub _element_gdt($$$;$$$$)
{
  my ($string, $lang_translations, $document,
      $replaced_substrings, $build_tree, $debug, $translation_context) = @_;
  return Texinfo::Translations::gdt($string,
                                    $lang_translations,
                                    $replaced_substrings,
                                    $debug, $translation_context);
}

# similar interface as cdt
sub tree_element_cdt($$;$$$)
{
  my ($self, $string, $replaced_substrings,
      $build_tree, $translation_context) = @_;

  return _element_gdt($string, $self->{'current_lang_translations'},
                               $self->{'document'},
                               $replaced_substrings, $build_tree,
                               $self->get_conf('DEBUG'),
                               $translation_context);
}



# relations

sub tree_element_sections_list($)
{
  my $self = shift;

  if ($self->{'document'}) {
    my $relations_list = $self->{'document'}->sections_list();
    return $relations_list;
  }
  return undef;
}

sub tree_element_nodes_list($)
{
  my $self = shift;

  if ($self->{'document'}) {
    my $relations_list = $self->{'document'}->nodes_list();
    return $relations_list;
  }
  return undef;
}

sub tree_element_headings_list($)
{
  my $self = shift;

  if ($self->{'document'}) {
    my $relations_list = $self->{'document'}->headings_list();
    return $relations_list;
  }
  return undef;
}



# informative commands

sub _tree_element_element_value_equivalent($)
{
  my $element = shift;
  my $cmdname = $element->{'cmdname'};

  if ($cmdname eq 'set' or $cmdname eq 'clear') {
    my $misc_args;
    if ($element->get_attribute('misc_args')
        and exists($element->get_attribute('misc_args')->[0])) {
      my $flag = $element->get_attribute('misc_args')->[0];
      my $equivalent_cmdname
        = $Texinfo::Common::set_flag_command_equivalent{$flag};
      if (defined($equivalent_cmdname)) {
        my $value;
        if ($cmdname eq 'set') {
          $value = 'on';
        } else {
          $value = 'off';
        }
        return ($equivalent_cmdname, $value);
      }
    }
  }

  return (undef, undef);

}

# same as in Texinfo::Common, but using the TreeElement interface
sub _tree_element_informative_command_value($)
{
  my $element = shift;

  my ($cmdname, $value) = _tree_element_element_value_equivalent($element);
  if (defined($cmdname)) {
    return ($cmdname, $value);
  }

  $cmdname = $element->{'cmdname'};
  $cmdname = 'shortcontents' if ($cmdname eq 'summarycontents');

  if ($Texinfo::Commands::line_commands{$cmdname} eq 'lineraw') {
    if (not $Texinfo::Commands::commands_args_number{$cmdname}) {
      return $cmdname, 1;
    } else {
      my $contents = $element->get_children();
      if ($contents) {
        my @strings;
        foreach my $content (@$contents) {
          push @strings, $content->{'text'};
        }
        return $cmdname, join(' ', @strings);
      }
    }
  } elsif ($element->get_attribute('text_arg')) {
    return $cmdname, $element->get_attribute('text_arg');
  } elsif ($element->get_attribute('misc_args')
           and exists($element->get_attribute('misc_args')->[0])) {
    return $cmdname, $element->get_attribute('misc_args')->[0];
  } elsif ($Texinfo::Commands::line_commands{$cmdname} eq 'line') {
    my $arg = $element->get_child(0);
    if ($arg->children_number()) {
      return $cmdname, $arg->get_child(0)->{'text'};
    }
  }
  return undef, undef;
}

# same as in Texinfo::Common, but using the TreeElement interface
sub tree_element_set_informative_command_value($$)
{
  my $self = shift;
  my $element = shift;

  my ($cmdname, $value) = _tree_element_informative_command_value($element);

  if (defined($value)) {
    my $set = $self->set_conf($cmdname, $value);
    return $set;
  }
  return 0;
}

sub _tree_element_in_preamble($)
{
  my $element = shift;
  my $current_element = $element;
  while (1) {
    my $parent = $current_element->parent();
    last if (!$parent);
    if (defined($parent->{'type'})
        and $parent->{'type'} eq 'preamble_before_content') {
      return 1;
    }
    $current_element = $parent;
  }
  return 0;
}

# same as Texinfo::Common::get_global_document_command for TreeElements
sub tree_element_get_global_document_command($$$)
{
  my $self = shift;
  my $global_command = shift;
  my $command_location = shift;

  if ($command_location ne 'last' and $command_location ne 'preamble_or_first'
      and $command_location ne 'preamble') {
    warn "BUG: get_global_document_command: unknown command_location: $command_location";
  }

  my $element;
  my $commands_list
      = global_commands_information_command_list($self->{'document'},
                                                 $global_command);

  if (!$commands_list) {
    return $self->get_global_unique_tree_element($global_command);
  }

  if ($command_location eq 'last') {
    $element = $commands_list->[-1];
  } else {
    if ($command_location eq 'preamble_or_first'
        and not _tree_element_in_preamble($commands_list->[0])) {
      $element = $commands_list->[0];
    } else {
      foreach my $command_element (@{$commands_list}) {
        if (_tree_element_in_preamble($command_element)) {
          $element = $command_element;
        } else {
          last;
        }
      }
    }
  }
  return $element;
}

# same as in Texinfo::Convert::Converter but with the TreeElement interface
sub tree_element_set_global_document_commands($$$)
{
  my $self = shift;
  my $commands_location = shift;
  my $selected_commands = shift;

  my $init_conf = $self->{'commands_init_conf'};

  if (not defined($selected_commands)) {
    die "tree_element_set_global_document_commands: requires selected commands";
  }
  if ($commands_location eq 'before') {
    foreach my $global_command (@{$selected_commands}) {
      # for commands not appearing in the document, this should set to
      # the converter initialization value, which is in init_conf,
      # or generic default
      $self->set_conf($global_command,
          Texinfo::Convert::Converter::get_command_init($global_command,
                                                        $init_conf));
      # NOTE if the variable is set from an handler, or in the converter after
      # $init_conf was set, but before starting the conversion, it is ignored
      # here and the $init_conf value is set.  The previously set value
      # could be in $self->get_conf(), but what is available from
      # $self->get_conf() could also be a value set by a previous call of
      # set_global_document_commands.
      # There is no easy way to deal with this issue, other than making sure
      # that a customization value that is expected to be set early is set in
      # $init_conf.
    }
  } else {
    foreach my $global_command (@{$selected_commands}) {
      if ($self->get_conf('DEBUG')) {
        print STDERR "SET_global($commands_location) $global_command\n";
      }

      my $element
        = tree_element_get_global_document_command($self, $global_command,
                                                   $commands_location);
      if ($element) {
        tree_element_set_informative_command_value($self, $element);
      } else {
        # for commands not appearing in the document, this should set to
        # the converter initialization value, which is in init_conf,
        # or generic default
        # the NOTE above in 'before' holds here too.
        $self->set_conf($global_command,
            Texinfo::Convert::Converter::get_command_init($global_command,
                                                          $init_conf));
      }
    }
  }
}



# helper methods for conversion

# for XS overriding
sub find_element_authors($$)
{
  my ($element, $quotation_authors) = @_;

  return Texinfo::Convert::Utils::find_element_authors($element,
                                                       $quotation_authors);
}

sub _tree_element_find_element_authors_internal($$);

# same as in Texinfo::Convert::Utils, but using the TreeElement interface
sub _tree_element_find_element_authors_internal($$)
{
  my $element = shift;
  my $quotation_authors = shift;

  return if (defined($element->{'text'}));

  my $cmdname = $element->{'cmdname'};
  if (defined($cmdname)) {
    if ($cmdname eq 'author') {
      push @$quotation_authors, $element;
      return;
    }
    if ($cmdname eq 'quotation'
        or $cmdname eq 'smallquotation'
        or $cmdname eq 'titlepage'
        or $cmdname eq 'menu'
        or ($Texinfo::Commands::brace_commands{$cmdname}
            and $Texinfo::Commands::brace_commands{$cmdname} eq 'context')
        or exists($Texinfo::Commands::line_commands{$cmdname})) {
      return;
    }
  } elsif (defined($element->{'type'})
           and $element->{'type'} eq 'arguments_line') {
    return;
  }
  my $contents = $element->get_children();
  if ($contents) {
    foreach my $content (@$contents) {
      _tree_element_find_element_authors_internal($content, $quotation_authors);
    }
  }
}

# same as in Texinfo::Convert::Utils, but using the TreeElement interface
sub tree_element_find_element_authors($$)
{
  my $element = shift;
  my $quotation_authors = shift;

  my $contents = $element->get_children();
  foreach my $content (@$contents) {
    _tree_element_find_element_authors_internal($content, $quotation_authors);
  }
}

# same as in Texinfo::Common, but using the TreeElement interface
sub _tree_element_block_line_argument_command($)
{
  my $block_line_arg = shift;

  if ($block_line_arg->children_number() == 1) {
    my $arg = $block_line_arg->get_child(0);
    my $cmdname = $arg->{'cmdname'};
    my $contents_nr = $arg->children_number();
    if ($cmdname
        and (!$contents_nr
             or ($contents_nr == 1
                 and !$arg->get_child(0)->children_number()))) {
      if (($Texinfo::Commands::brace_commands{$cmdname}
           and !$Texinfo::Commands::accent_commands{$cmdname})
          or ($arg->{'type'} and $arg->{'type'} eq 'definfoenclose_command')) {
        return $arg;
      }
    }
  }
  return undef;
}

# same as in Texinfo::Common, but with TreeElement interface
sub _tree_element_item_line_block_line_argument_command($)
{
  my $block_line_arg = shift;

  my $arg = _tree_element_block_line_argument_command($block_line_arg);

  if ($arg) {
    my $brace_category = $Texinfo::Commands::brace_commands{$arg->{'cmdname'}};
    # $Texinfo::Commands::brace_commands{} is undef
    # for definfoenclose'd commands
    if ($brace_category and $brace_category eq 'noarg') {
      $arg = undef;
    }
  }
  return $arg;
}

my $default_bullet_command = Texinfo::TreeElement::new({'cmdname' => 'bullet'});

# same as in Texinfo::Common, but using the TreeElement interface
sub tree_element_item_itemize_prepended($)
{
  my $element = shift;

  my $itemize = $element->parent();
  my $arguments_line = $itemize->get_child(0);
  my $block_line_arg = $arguments_line->get_child(0);

  my $arg = _tree_element_block_line_argument_command($block_line_arg);
  if ($arg) {
    return $arg;
  } elsif (!$block_line_arg->children_number()) {
    return $default_bullet_command;
  } else {
    return $block_line_arg;
  }
}

# for XS override
sub item_itemize_prepended($)
{
  my $element = shift;

  return Texinfo::Common::item_itemize_prepended($element);
}

# same as in Texinfo::Common, but with TreeElement interface
# TODO it would be more efficient to have a static asis command reused
sub _tree_element_block_item_line_command($$)
{
  my $self = shift;
  my $block_line_arg = shift;

  my $arg
    = _tree_element_item_line_block_line_argument_command($block_line_arg);

  if (!$arg) {
    $arg = $self->new_tree_element({'cmdname' => 'asis'});
  }
  return $arg;
}

# for XS overriding.
# table_item_content_tree_noxs in Texinfo::Convert::Converter.
sub table_item_content_tree($$;$)
{
  my $self = shift;
  my $element = shift;
  my $build_tree = shift;

  return $self->table_item_content_tree_noxs($element);
}

# same as table_item_content_tree, but using the TreeElement interface
sub tree_element_table_item_content_tree($$;$) {
  my ($self, $element, $build_tree) = @_;

  my $parent = $element->parent();
  my $parent_type = $parent->{'type'};
  # not in a @*table item/itemx.  Exemple in test with @itemx in @itemize
  # in @table
  if (!defined($parent_type) or $parent_type ne 'table_term') {
    return undef;
  }
  my $table_command = $parent->parent()->parent();

  # arguments_line type element
  my $arguments_line = $table_command->get_child(0);
  my $block_line_arg = $arguments_line->get_child(0);

  my $command_as_argument
    = _tree_element_block_item_line_command($self, $block_line_arg);

  if ($command_as_argument) {
    my $command_as_argument_cmdname = $command_as_argument->{'cmdname'};
    my $command = {'cmdname' => $command_as_argument_cmdname,
                   'source_info' => $element->source_info(),};
    if ($table_command->get_attribute('command_as_argument_kbd_code')) {
      $command->{'extra'} = {'code' => 1};
    }
    # command name for the Texinfo::Commands hashes tests
    my $builtin_cmdname;
    my $type = $command_as_argument->{'type'};
    if (defined($type) and $type eq 'definfoenclose_command') {
      $command->{'type'} = $type;
      $command->{'extra'} = {} if (!exists($command->{'extra'}));
      $command->{'extra'}->{'begin'}
        = $command_as_argument->get_attribute('begin');
      $command->{'extra'}->{'end'}
        = $command_as_argument->get_attribute('end');
      $builtin_cmdname = 'definfoenclose_command';
    } else {
      $builtin_cmdname = $command_as_argument_cmdname;
    }
    my $arg;
    if ($Texinfo::Commands::brace_commands{$builtin_cmdname} eq 'context') {
      # This corresponds to a bogus @*table line with command line @footnote
      # or @math.  We do not really care about the formatting of the result
      # but we want to avoid debug messages, so we setup expected trees
      # for those @-commands.
      $arg = {'type' => 'brace_command_context',};
      if ($Texinfo::Commands::math_commands{$builtin_cmdname}) {
        $arg->{'contents'} = [$element->get_child(0)];
      } else {
        my $paragraph = $self->new_tree_element({'type' => 'paragraph',
                                  'contents' => [$element->get_child(0)],});
        $arg->{'contents'} = [$paragraph];
      }
    } elsif ($Texinfo::Commands::brace_commands{$builtin_cmdname}
                                                   eq 'arguments') {
      $arg = {'type' => 'brace_arg',
              'contents' => [$element->get_child(0)],};
    } else {
      $arg = {'type' => 'brace_container',
              'contents' => [$element->get_child(0)],};
    }
    my $arg_element = $self->new_tree_element($arg);
    my $result = $self->new_tree_element($command);
    $result->{'contents'} = [$arg_element];
    return $result;
  }
  return undef;
}

# for XS overriding
sub comment_or_end_line($$)
{
  my $self = shift;
  my $element = shift;

  return $self->Texinfo::Convert::Converter::comment_or_end_line($element);
}

# for XS overriding
sub argument_comment_end_line($$)
{
  my $self = shift;
  my $element = shift;

  my $line_arg;
  my $end_line_element;
  my $first_child = $element->{'contents'}->[0];
  my $first_child_type = $first_child->{'type'};
  if ($first_child_type and $first_child_type eq 'arguments_line') {
    $line_arg = $first_child->{'contents'}->[0];
    $end_line_element = $first_child;
  } else {
    $line_arg = $element->{'contents'}->[0];
    $end_line_element = $element;
  }
  my ($comment, $end_line) = $self->comment_or_end_line($end_line_element);
  return $line_arg, $comment, $end_line;
}

sub tree_element_comment_or_end_line($$)
{
  my $self = shift;
  my $element = shift;

  my $end_line;

  my $last_arg = $element->get_child(-1);

  my $comment = $last_arg->get_attribute('comment_at_end')
    if ($last_arg);

  if ($comment) {
    return ($comment, undef);
  } elsif ($last_arg) {
    my $spaces_after_argument
      = $last_arg->get_attribute('spaces_after_argument');
    if (defined($spaces_after_argument)) {
      my $text = $spaces_after_argument->{'text'};
      if (chomp($text)) {
        $end_line = "\n";
      }
    } else {
      $end_line = '';
    }
  } else {
    $end_line = '';
  }
  return (undef, $end_line);
}

# for TreeElement interface and XS overriding
sub tree_element_argument_comment_end_line($$)
{
  my $self = shift;
  my $element = shift;

  my $line_arg;
  my $end_line_element;
  my $first_child = $element->get_child(0);
  my $first_child_type = $first_child->{'type'};
  if ($first_child_type and $first_child_type eq 'arguments_line') {
    $line_arg = $first_child->get_child(0);
    $end_line_element = $first_child;
  } else {
    $line_arg = $element->get_child(0);
    $end_line_element = $element;
  }
  my ($comment, $end_line)
    = $self->tree_element_comment_or_end_line($end_line_element);
  return $line_arg, $comment, $end_line;
}

sub _tree_element_associated_processing_encoding($)
{
  my $element = shift;

  my $encoding = $element->get_attribute('input_encoding_name');

  return Texinfo::Common::processing_output_encoding($encoding);
}

# same as in Texinfo::Convert::Converter, but with TreeElement interface
sub tree_element_txt_image_text($$$)
{
  my ($self, $element, $basefile) = @_;

  my ($text_file_name, $file_name_encoding)
    = $self->encoded_input_file_name($basefile.'.txt');

  my $txt_file = Texinfo::Common::locate_include_file($text_file_name,
                                  $self->get_conf('INCLUDE_DIRECTORIES'));
  if (!defined($txt_file)) {
    return undef, undef;
  } else {
    my $filehandle = do { local *FH };
    if (open($filehandle, $txt_file)) {
      my $encoding
          = _tree_element_associated_processing_encoding($element);
      if (defined($encoding)) {
        binmode($filehandle, ":encoding($encoding)");
      }
      my $result = '';
      my $max_width = 0;
      while (<$filehandle>) {
        my $width = Texinfo::Convert::Unicode::string_width($_);
        if ($width > $max_width) {
          $max_width = $width;
        }
        $result .= $_;
      }
      if (!close ($filehandle)) {
        my $decoded_file_name = $txt_file;
        $decoded_file_name = Encode::decode($file_name_encoding, $txt_file)
          if (defined($file_name_encoding));
        $self->converter_document_warn(
           sprintf(__("error on closing image text file %s: %s"),
                                     $decoded_file_name, $!));
      }
      return $result, $max_width;
    } else {
      my $decoded_file_name = $txt_file;
      $decoded_file_name = Encode::decode($file_name_encoding, $txt_file)
        if (defined($file_name_encoding));
      $self->converter_line_warn(
               sprintf(__("\@image file `%s' unreadable: %s"),
                          $decoded_file_name, $!), $element->source_info());
    }
  }
  return undef, undef;
}

# same as in Texinfo::Convert::Utils, but with TreeElement interface
sub _tree_element_expand_verbatiminclude($$$$$;$$)
{
  my $current = shift;
  my $include_directories = shift;
  my $input_file_name_encoding = shift;
  my $doc_encoding_for_input_file_name = shift;
  my $locale_encoding = shift;
  my $document = shift;
  my $converter = shift;

  my $file_name_text = $current->get_attribute('text_arg');
  return undef unless (defined($file_name_text));

  my $input_encoding
    = _tree_element_associated_processing_encoding($current);

  my ($file_name, $file_name_encoding)
    = Texinfo::Convert::Utils::encoded_input_file_name($file_name_text,
                  $input_file_name_encoding,
                  $doc_encoding_for_input_file_name, $locale_encoding,
                                          $document, $input_encoding);

  my $file = Texinfo::Common::locate_include_file($file_name,
                                                  $include_directories);

  my $verbatiminclude;

  if (defined($file)) {
    if (!open(VERBINCLUDE, $file)) {
      if ($converter) {
        my $decoded_file = $file;
        # need to decode to the internal perl codepoints for error message
        $decoded_file = Encode::decode($file_name_encoding, $file)
           if (defined($file_name_encoding));
        $converter->converter_line_error(
                      sprintf(__("could not read %s: %s"), $decoded_file, $!),
                      $current->source_info());
      }
    } else {
      if (defined($input_encoding)) {
        binmode(VERBINCLUDE, ":encoding($input_encoding)");
      }
      $verbatiminclude
        = Texinfo::TreeElement::new({ 'cmdname' => 'verbatim',
                                      'parent' => $current->parent(),
                                      'contents' => [],});
      while (<VERBINCLUDE>) {
        push @{$verbatiminclude->{'contents'}},
          Texinfo::TreeElement::new({'type' => 'raw', 'text' => $_ });
      }
      if (!close (VERBINCLUDE)) {
        if ($converter) {
          my $decoded_file = $file;
          # need to decode to the internal perl codepoints for error message
          $decoded_file = Encode::decode($file_name_encoding, $file)
             if (defined($file_name_encoding));
          $converter->converter_document_warn(
                 sprintf(__(
                      "error on closing \@verbatiminclude file %s: %s"),
                          $decoded_file, $!));
        }
      }
    }
  } elsif ($converter) {
    $converter->converter_line_error(
                           sprintf(__("\@%s: could not find %s"),
                                       $current->{'cmdname'}, $file_name_text),
                           $current->source_info());
  }
  return $verbatiminclude;
}

# For XS, lower level interface.  Should not be called directly
sub _utils_tree_element_expand_verbatiminclude($$$$$;$$)
{
  my $current = shift;
  my $include_directories = shift;
  my $input_file_name_encoding = shift;
  my $doc_encoding_for_input_file_name = shift;
  my $locale_encoding = shift;
  my $document = shift;
  my $converter = shift;

  return _tree_element_expand_verbatiminclude($current,
              $include_directories,
              $input_file_name_encoding,
              $doc_encoding_for_input_file_name, $locale_encoding,
              $document, $converter);
}

# converter interface
sub tree_element_expand_verbatiminclude($$)
{
  my $converter = shift;
  my $current = shift;

  my $input_file_name_encoding
    = $converter->get_conf('INPUT_FILE_NAME_ENCODING');
  my $doc_encoding_for_input_file_name
    = $converter->get_conf('DOC_ENCODING_FOR_INPUT_FILE_NAME');
  my $locale_encoding = $converter->get_conf('LOCALE_ENCODING');

  my $include_directories
    = $converter->get_conf('INCLUDE_DIRECTORIES');

  my $document = $converter->{'document'};

  return _utils_tree_element_expand_verbatiminclude($current,
              $include_directories,
              $input_file_name_encoding,
              $doc_encoding_for_input_file_name, $locale_encoding,
              $document, $converter);
}

# for the XS override.  Should not be called directly
sub _utils_expand_verbatiminclude($$$$$;$$)
{
  my $current = shift;
  my $include_directories = shift;
  my $input_file_name_encoding = shift;
  my $doc_encoding_for_input_file_name = shift;
  my $locale_encoding = shift;
  my $document = shift;
  my $converter = shift;

  return Texinfo::Convert::Utils::expand_verbatiminclude($current,
              $include_directories,
              $input_file_name_encoding,
              $doc_encoding_for_input_file_name, $locale_encoding,
              $document, $converter);
}

# converter interface, same as Texinfo::Convert::Converter, including
# the name but with an XS interface for the lower level
sub expand_verbatiminclude($$)
{
  my $converter = shift;
  my $current = shift;

  my $input_file_name_encoding
    = $converter->get_conf('INPUT_FILE_NAME_ENCODING');
  my $doc_encoding_for_input_file_name
    = $converter->get_conf('DOC_ENCODING_FOR_INPUT_FILE_NAME');
  my $locale_encoding = $converter->get_conf('LOCALE_ENCODING');

  my $include_directories
    = $converter->get_conf('INCLUDE_DIRECTORIES');

  my $document = $converter->{'document'};

  return _utils_expand_verbatiminclude($current,
              $include_directories,
              $input_file_name_encoding,
              $doc_encoding_for_input_file_name, $locale_encoding,
              $document, $converter);
}

# Wrapper used for XS override.  Should not be accessed directly.
sub _expand_today($$$$$)
{
  my $test = shift;
  my $lang_translations = shift;
  my $debug = shift;
  my $converter = shift;
  my $build_tree = shift;

  return Texinfo::Convert::Utils::expand_today($test,
                                               $lang_translations,
                                               $debug, $converter);
}

# Does not follow the TreeElement interface when there is no XS,
# as Texinfo::Convert::Utils::expand_today is called.  But calls a function
# that has an XS override, which allows to get the right output with XS.
sub tree_element_expand_today($;$)
{
  my $converter = shift;
  my $build_tree = shift;

  my $test = $converter->get_conf('TEST');
  my $debug = $converter->get_conf('DEBUG');
  return _expand_today($test, $converter->{'current_lang_translations'},
                       $debug, $converter, $build_tree);
}

# same as in Texinfo::Common, but for the TreeElement interface
sub tree_element_multitable_columnfractions($)
{
  my $multitable = shift;

  my $arguments_line = $multitable->get_child(0);
  my $block_line_arg = $arguments_line->get_child(0);
  if ($block_line_arg->children_number()) {
    my $child = $block_line_arg->get_child(0);
    my $child_cmdname = $child->{'cmdname'};
    if ($child_cmdname and $child_cmdname eq 'columnfractions') {
      return $block_line_arg->get_child(0);
    }
  }

  return undef;
}



# Accents formatting

my %unicode_diacritics = %Texinfo::CommandsValues::unicode_diacritics;
my %unicode_accented_letters = %Texinfo::UnicodeData::unicode_accented_letters;
my %unicode_to_eight_bit = %Texinfo::UnicodeData::unicode_to_eight_bit;

# same as in Texinfo::Convert::Unicode, using the TreeElement interface
sub _tree_element_unicode_accent($$$$) {
  my ($text, $command, $index_in_stack, $accents_stack) = @_;

  my $accent = $command->{'cmdname'};

  my $result;

  # special handling of @dotless{i}.
  # \x{0131}\x{0308} for @dotless{i} @" doesn't lead to NFC 00ef.
  # so it is set to a real dotless i only if not in an accent command.
  # Do the same for dotless j, even though we have no clear idea on
  # what is going on for that character.
  if ($accent eq 'dotless') {
    if ($unicode_accented_letters{$accent}->{$text}
        and ($index_in_stack == 0
             or !$unicode_diacritics{$accents_stack->[$index_in_stack -1]
                                                        ->{'cmdname'}})) {
      return chr(hex($unicode_accented_letters{$accent}->{$text}));
    } else {
      return $text;
    }
  }

  if (defined($unicode_diacritics{$accent})) {
    my $diacritic = chr(hex($unicode_diacritics{$accent}));
    if ($accent ne 'tieaccent') {
      # FIXME with a malformed string, there can be an infinite loop
      # in Unicode::Normalize::NFC.
      return Unicode::Normalize::NFC($text . $diacritic);
    } else {
      # tieaccent diacritic is naturally and correctly composed
      # between two characters
      my $remaining_text = $text;
      # \p{L} matches a single code point in the category "letter".
      if ($remaining_text =~ s/^([\p{L}\d])([\p{L}\d])(.*)$/$3/) {
        return Unicode::Normalize::NFC($1.$diacritic.$2 . $remaining_text);
      } else {
        return Unicode::Normalize::NFC($text . $diacritic);
      }
    }
  }
  # There are diacritics for every accent command except for dotless and
  # dotless is handled especially, so we should never end up here.
  return undef;
}

# same as in Texinfo::Convert::Unicode, with the TreeElement interface
sub _tree_element_format_unicode_accents_stack($$$$;$) {
  my ($converter, $inner_text, $stack, $format_accent, $set_case) = @_;

  my $result = $inner_text;
  my $i = scalar(@$stack) -1;

  for (; $i >= 0; $i--) {
    my $accent_command = $stack->[$i];
    my $formatted_result
      = _tree_element_unicode_accent($result, $accent_command, $i, $stack);
    last if (!defined($formatted_result));

    $result = $formatted_result;
  }
  if ($set_case) {
    if ($set_case > 0) {
      $result = uc($result);
    } else {
      $result = lc($result);
    }
  }
  for (; $i >= 0; $i--) {
    my $accent_command = $stack->[$i];
    $result = &$format_accent($converter, $result, $accent_command,  $i,
                              $stack, $set_case);
  }
  return $result;
}

# same as in Texinfo::Convert::Unicode, with the TreeElement interface
sub _tree_element_format_eight_bit_accents_stack($$$$$;$) {
  my ($converter, $text, $stack, $encoding, $convert_accent, $set_case) = @_;

  my $result = $text;

  my $debug;
  #$debug = 1;

  if ($debug) {
    print STDERR "STACK: ".join('|', map {$_->{'cmdname'}} @$stack)."\n";
  }

  # accents are formatted and the intermediate results are kept, such
  # that we can return the maximum of multiaccented letters that can be
  # rendered with a given eight bit formatting.  undef is stored when
  # there is no corresponding unicode anymore.
  my @results_stack;
  # we could have used a smaller array here and different code, but
  # we prefer following the same approach as in C to ease debugging.
  # Start from the top with the text inside the deepest accent command.
  $results_stack[scalar(@$stack)] = $text;
  my $i = scalar(@$stack) -1;

  for (; $i >= 0; $i--) {
    my $accent_command = $stack->[$i];
    my $unicode_formatted
         = _tree_element_unicode_accent($results_stack[$i+1], $accent_command,
                                        $i, $stack);
    if (!defined($unicode_formatted)) {
      # decrease a last time as if the loop had been gone through
      $i--;
      last;
    } elsif ($set_case) {
      if ($set_case > 0) {
        $unicode_formatted = uc($unicode_formatted);
      } else {
        $unicode_formatted = lc($unicode_formatted);
      }
    }
    $results_stack[$i] = $unicode_formatted;
  }
  # undo the last decrease of $i
  $i++;

  if ($debug) {
    print STDERR "PARTIAL_RESULTS_STACK:\n";
    for (my $p = scalar(@$stack); $p >= 0; $p--) {
      my $cmdname = 'TEXT';
      if ($p < scalar(@$stack)) {
        $cmdname = $stack->[$p]->{'cmdname'};
      }
      if (defined($results_stack[$p])) {
        print STDERR "   -> ".Encode::encode('utf-8', $results_stack[$p])
                            ."|$cmdname\n";
      } else {
        print STDERR "   -> NO accented character |$cmdname\n";
      }
    }
  }

  # At this point we have the unicode character results for the accent
  # commands stack, with all the intermediate results.
  # For each one we'll check if it is possible to encode it in the
  # current eight bit output encoding table and, if so set the result
  # to the character.

  my $prev_eight_bit = '';

  my $j = scalar(@$stack);
  for (; $j >= $i; $j--) {
    my $char = $results_stack[$j];
    last if (!defined($char));

    my ($new_eight_bit, $codepoint)
      = Texinfo::Convert::Unicode::eight_bit_and_unicode_point($char, $encoding);
    if ($debug) {
      my $cmdname = 'TEXT';
      if ($j < scalar(@$stack)) {
        $cmdname = $stack->[$j]->{'cmdname'};
      }
      print STDERR "" . Encode::encode('utf-8', $char) . " ($cmdname) "
        . "codepoint: $codepoint "
        ."8bit: ". (defined($new_eight_bit) ? $new_eight_bit : 'UNDEF')
        . " prev: $prev_eight_bit\n";
    }

    # no corresponding eight bit character found for a composed character
    last if (!$new_eight_bit);

    # in that case, the new eight bit character is the same than the one
    # found with one less character (and it isn't a @dotless{i}). It may
    # hapen in 2 case, both meaning that there is no corresponding 8bit char:
    #
    # -> there are 2 characters in accent. This could happen, for example
    #    if an accent that cannot be rendered is found and it leads to
    #    appending or prepending a character. For example this happens for
    #    @={@,{@~{n}}}, where @,{@~{n}} is expanded to a 2 character:
    #    n with a tilde, followed by a ,
    #    In that case, the additional diacritic is appended, which
    #    means that it is composed with the , and leaves n with a tilde
    #    untouched.
    # -> the diacritic is appended but the normal form doesn't lead
    #    to a composed character, such that the first character
    #    of the string is unchanged. This, for example, happens for
    #    @ubaraccent{a} since there is no composed accent with a and an
    #    underbar.
    last if ($new_eight_bit eq $prev_eight_bit
             and !($stack->[$j]->{'cmdname'} eq 'dotless'
                   and $char eq 'i'));
    $result = $results_stack[$j];
    $prev_eight_bit = $new_eight_bit;
  }

  # handle the remaining accents, that have not been converted to 8bit
  # compatible unicode
  for (; $j >= 0; $j--) {
    my $accent_command = $stack->[$j];
    $result = &$convert_accent($converter, $result,
                               $accent_command, $j, $stack,
                               $set_case);
  }

  # An important remark is that the final conversion to 8bit is left to
  # Perl.
  return $result;
}

# same as in Texinfo::Convert::Unicode, with the TreeElement interface
sub _tree_element_encoded_accents($$$$$;$) {
  my ($converter, $text, $stack, $encoding, $format_accent, $set_case) = @_;

  if ($encoding) {
    # in case an encoding is directly specified with -c OUTPUT_ENCODING_NAME
    # in upper case to match with the encodings in Texinfo input, we convert
    # to lower case to match the encoding names used here.  In the code
    # encoding names are lower cased early.
    $encoding = lc($encoding);
    if ($encoding eq 'utf-8') {
      return _tree_element_format_unicode_accents_stack($converter,
                                            $text, $stack,
                                            $format_accent, $set_case);
    } elsif ($unicode_to_eight_bit{$encoding}) {
      return _tree_element_format_eight_bit_accents_stack(
                               $converter, $text, $stack, $encoding,
                               $format_accent, $set_case);
    }
  }
  return undef;
}

# same as in Texinfo::Convert::Utils, but using TreeElement interface
sub _tree_element_find_innermost_accent_contents($$) {
  my ($self, $current) = @_;

  my @accent_commands = ();
  my $debug = 0;
 ACCENT:
  while (1) {
    my $current_cmdname = $current->{'cmdname'};
    # the following can happen if called with a bad tree
    if (!defined($current_cmdname)
        or !$Texinfo::Commands::accent_commands{$current_cmdname}) {
      #print STDERR "BUG: Not an accent command in accent\n";
      cluck "BUG: Not an accent command in accent\n";
      #print STDERR Texinfo::Convert::Texinfo::convert_to_texinfo($current)."\n";
      #print STDERR Data::Dumper->Dump([$current]);
      return (undef, \@accent_commands);
    }
    push @accent_commands, $current;
    # A bogus accent, that may happen
    if (!$current->children_number()) {
      return (undef, \@accent_commands);
    }

    my $arg = $current->get_child(0);
    my $contents = $arg->get_children();
    if (!$contents) {
      return (undef, \@accent_commands);
    }
    # inside the argument of an accent
    my $text_contents = [];

    foreach my $content (@$contents) {
      if (exists($content->{'cmdname'})) {
        my $cmdname = $content->{'cmdname'};
        if ($Texinfo::Commands::accent_commands{$cmdname}) {
        # if outer accent is tieaccent, keep accent inside and do not try to
        # nest more
          if ($current_cmdname ne 'tieaccent') {
            $current = $content;
            next ACCENT;
          }
        } elsif ($cmdname eq 'c' or $cmdname eq 'comment') {
          next;
        }
      }
      push @$text_contents, $content;
    }
    # we go here if there was no nested accent
    return ($self->new_tree_element({'contents' => $text_contents}),
            \@accent_commands);
  }
}

# same as in Texinfo::Convert::Converter, but using TreeElement interface
sub tree_element_convert_accents($$$;$$) {
  my ($self, $accent, $format_accents, $output_encoded_characters,
      $in_upper_case) = @_;

  my ($contents_element, $stack)
   = _tree_element_find_innermost_accent_contents($self, $accent);
  my $arg_text = '';
  if (defined($contents_element)) {
    $arg_text = $self->convert_tree($contents_element);
  }

  if ($output_encoded_characters) {
    my $encoded = _tree_element_encoded_accents($self,
                                       $arg_text, $stack,
                                       $self->get_conf('OUTPUT_ENCODING_NAME'),
                                       $format_accents,
                                       $in_upper_case);
    if (defined($encoded)) {
      return $encoded;
    }
  }
  my $result = $arg_text;
  for (my $i = scalar(@$stack) -1; $i >= 0; $i--) {
    my $accent_command = $stack->[$i];
    $result = &$format_accents ($self, $result, $accent_command, $i,
                                $stack, $in_upper_case);
  }
  return $result;
}

# same as in Texinfo::Convert::Converter
sub _tree_element_xml_numeric_entities_accent($$$;$$$) {
  my ($self, $text, $command, $index_in_stack, $accents_stack,
      $in_upper_case) = @_;

  return $self->xml_accent($text, $command, $index_in_stack,
                           $accents_stack, $in_upper_case, 1);
}

# same as in Texinfo::Convert::Converter, but using TreeElement interface
sub tree_element_xml_accents($$;$)
{
  my ($self, $accent, $in_upper_case) = @_;

  my $format_accents;
  if ($self->get_conf('USE_NUMERIC_ENTITY')) {
    $format_accents = \&_tree_element_xml_numeric_entities_accent;
  } else {
    $format_accents = \&Texinfo::Convert::xml_accent;
  }

  return $self->tree_element_convert_accents($accent, $format_accents,
                                $self->get_conf('OUTPUT_CHARACTERS'),
                                $in_upper_case);
}

1;

__END__

=head1 NAME

Texinfo::Example::TreeElementConverter - Parent class for TreeElement based converters

=head1 SYNOPSIS

  package Texinfo::Convert::MyConverter;

  use Texinfo::Convert::Converter;
  use Texinfo::Example::TreeElementConverter;
  our @ISA = qw(Texinfo::Example::TreeElementConverter);

  # define the methods needed for Texinfo::Convert::Converter

  ...

  sub convert_tree($$) {
    ...
  }

  ...

  # end of Texinfo::Convert::MyConverter

  my $converter = Texinfo::Convert::MyConverter->converter();
  $converter->output($texinfo_parsed_document);

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

Note that this module is not used in C<texi2any>.

Note that this module could be removed at any time.

=head1 DESCRIPTION

C<Texinfo::Example::TreeElementConverter> is a super class that helps
using the L<Texinfo::TreeElement> interface in converters.  It provides
implementations of methods from other Texinfo Perl modules using the
TreeElement L<Texinfo::TreeElement> interface only.  The original
methods can be in the L<Texinfo::Convert::Converter>, L<Texinfo::Common>,
L<Texinfo::Convert::Utils> and L<Texinfo::Structuring> modules.

The Texinfo Perl modules can be setup to use Perl XS module extensions in
native code (written in C) that replace Perl package or methods by native code
for faster execution.
The Texinfo modules XS interface is designed such that the Texinfo tree
actually processed is not the Perl elements tree, but a tree stored in
native code in XS extensions, corresponding to compiled C data structures.
If XS extensions are loaded, finding a Perl element associated C data
is required in some cases, namely to initialize
L<< Texinfo::Reader/C<Texinfo::Reader> and XS extensions >> with XS
on an element (except for the tree root) or to find replaced substrings
elements in translations.

The C<Texinfo::Example::TreeElementConverter> modules helps with
setting up the link from Perl elements to C, first by providing the
methods using the TreeElement interface
since the L<Texinfo::TreeElement> interface automatically sets up this link.
The module also provides XS interfaces for methods also available in other
modules that setup the link from Perl elements to C.  Lastly, some methods are
also available to create or access Texinfo tree elements that also setup
Texinfo elements with the link from Perl elements to C.

Using the Reader, the TreeElement interface and the methods provided in this
module with XS to access and create elements also allows to go through the
Texinfo tree without ever building full Perl element data.  This may be all the
more important that building full Perl element data wipes out the link from
Perl elements to C element data.

=head1 METHODS

The following methods allow to create new elements and get elements.
If XS extensions are used, elements should be created and accessed through
these methods to have a link from Perl to C data setup for the created or
returned element.

=over

=item $converter->new_tree_element($element, $use_sv)
X<C<new_tree_element>>

Create a new tree elements based on the I<$element> hash reference.  The
I<$use_sv> argument is optional; if set and XS is used, the I<$element> hash
reference is associated to the new tree element data in C, otherwise it is
discarded.

=item ($index_entry, $index_info) = $converter->get_tree_element_index_entry($element)
X<C<get_tree_element_index_entry>>

Finds the index entry and index information associated to the tree
element I<$element>.  See L<< Texinfo::Common lookup_index_entry|Texinfo::Common/($index_entry, $index_info) = lookup_index_entry($index_entry_info, $indices_information) >>
for a general description of the return values.  Note that the returned
I<$index_info> information does not contain the index entries associated to
the index, only some basic information on the index.

=item $element = $converter->get_global_unique_tree_element($command_name)

=item $elements = global_commands_information_command_list($document, $command_name)

X<C<get_global_unique_tree_element>>
X<C<global_commands_information_command_list>>

Returns the tree element or tree elements corresponding to the
I<$command_name> @-command with a link from Perl to C element data setup.
Only for @-commands that could also be accessed
through L<< Texinfo::Document global_commands_information|Texinfo::Document/$commands = global_commands_information($document) >>
(if the link from Perl to C element data was not needed).

C<get_global_unique_tree_element> should be called for @-commands that should
appear only once in a Texinfo document.  This method returns the element.

C<global_commands_information_command_list> requires a C<Texinfo::Document>
I<$document> argument.  The I<$document> could be available as
C<< $converter->{'document'} >>. This method should be called for @-commands
that may appear more than once in a Texinfo document.  This method returns
a reference on the array of all the I<$command_name> @-command tree elements
appearing in the document.

=back

The other methods are documented in the modules that provide the
non-TreeElement interface or the methods that do not setup elements with
link from Perl to C element data.   The method name is either the same
as in this module, if the method is used as a wrapper around the method
with the same name, or can be obtained by removing a leading C<tree_element_>.
For example, the C<index_content_element> documentation can be used for the
C<tree_element_index_content_element> method of this module.

=head2 Related methods from other modules

To associate sectioning commands and nodes tree elements Perl to C data, the
C<register_document_relations_lists_elements> C<Texinfo::Document>
method may be called after getting the tree before starting the tree
conversion, such that sectioning commands and nodes elements accessed through
nodes and section relations have the association to C data already setup:

  $converter->{'document'}->register_document_relations_lists_elements()

If you use the L<Texinfo::Reader> to go through the tree you can call
reader methods to associate Perl to C data based on the current element
being read, L<< Texinfo::Reader C<register_token_element>|Texinfo::Reader/$reader->register_token_element() >>
and L<< Texinfo::Reader C<register_token_element_child>|Texinfo::Reader/$reader->register_token_element_child($index) >>.

=head1 SEE ALSO

L<Texinfo::Convert::Converter>, L<Texinfo::Common>, L<Texinfo::Convert::Utils>
and L<Texinfo::Structuring>.

=head1 AUTHOR

Patrice Dumas, E<lt>bug-texinfo@gnu.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2011- Free Software Foundation, Inc.  See the source file for
all copyright years.

This library is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or (at
your option) any later version.

=cut
