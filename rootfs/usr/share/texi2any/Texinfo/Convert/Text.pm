# Text.pm: output tree as simple text.
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

# ALTIMP perl/XSTexinfo/convert/ConvertXS.xs
# ALTIMP C/main/convert_to_text.c

package Texinfo::Convert::Text;

use 5.006;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use File::Basename;

use Storable qw(dclone);

#use Data::Dumper;
use Carp qw(cluck carp confess);

use Encode qw(decode);

use Texinfo::Convert::ConvertXS;
use Texinfo::XSLoader;

use Texinfo::Report;
use Texinfo::Commands;
use Texinfo::CommandsValues;

use Texinfo::TreeElement;

use Texinfo::Common;
use Texinfo::Convert::Unicode;
# for debugging
use Texinfo::Convert::Texinfo;
# misc functions and data
use Texinfo::Convert::Utils;

use Texinfo::Translations;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
  convert_to_text
  text_accents
);

our $VERSION = '7.3';

my $XS_convert = Texinfo::XSLoader::XS_convert_enabled();

my %XS_overrides = (
  # We do not override directly convert_to_text, we must check at runtime
  # that the document tree was stored by the XS parser.
  "Texinfo::Convert::Text::_convert_tree_with_XS"
   => "Texinfo::Convert::ConvertXS::text_convert_tree",
  "Texinfo::Convert::Text::destroy_converter"
   => "Texinfo::Convert::ConvertXS::destroy_text_converter",


  # if the output or convert functions are overriden the following
  # should probably be overriden using that kind of function
  #"Texinfo::Convert::Text::get_converter_errors"
  # => "Texinfo::Convert::ConvertXS::get_converter_errors",

  # Probably no use overriding, as if XS/C is used they are only
  # called from C
  #"Texinfo::Convert::Text::converter_line_error"
  # => "Texinfo::Convert::ConvertXS::converter_line_error",
  #"Texinfo::Convert::Text::converter_document_warn"
  # => "Texinfo::Convert::ConvertXS::converter_document_warn",
);

our $module_loaded = 0;
sub import {
  if (!$module_loaded) {
    if ($XS_convert) {
      foreach my $sub (keys(%XS_overrides)) {
        Texinfo::XSLoader::override($sub, $XS_overrides{$sub});
      }
    }

    $module_loaded = 1;
  }
  # The usual import method
  goto &Exporter::import;
}


my %ignored_brace_commands;
foreach my $ignored_brace_command (
   'anchor', 'namedanchor', 'sortas', 'seealso', 'seeentry',
   'footnote', 'shortcaption', 'caption', 'hyphenation', 'errormsg') {
  $ignored_brace_commands{$ignored_brace_command} = 1;
}

my %ignored_block_commands;
foreach my $ignored_command ('titlepage', 'copying', 'documentdescription',
  'documentinfo', 'publication',
  'ignore', 'macro', 'rmacro', 'linemacro', 'nodedescriptionblock') {
  $ignored_block_commands{$ignored_command} = 1;
}

my %ignored_format_raw_commands;
foreach my $ignored_command ('html', 'tex', 'xml', 'docbook', 'latex') {
  $ignored_format_raw_commands{$ignored_command} = 1;
}

my %accent_commands = %Texinfo::Commands::accent_commands;
my %nobrace_symbol_text = %Texinfo::CommandsValues::nobrace_symbol_text;
my %formatted_line_commands = %Texinfo::Commands::formatted_line_commands;
my %def_commands = %Texinfo::Commands::def_commands;
my %line_commands = %Texinfo::Commands::line_commands;
# 'page' is a formatted_line_commands and therefore is replaced by an empty
# line.

my %ignored_types;
foreach my $type (
            'postamble_after_end',
            'preamble_before_beginning',
            'preamble_before_setfilename',
            'arguments_line') {
  $ignored_types{$type} = 1;
}

my %ignored_text_types;
foreach my $type ('ignorable_spaces_after_command',
            'ignorable_spaces_before_command',
            'spaces_at_end',
            'space_at_end_menu_node',
            'spaces_before_paragraph',
            'spaces_after_close_brace') {
  $ignored_text_types{$type} = 1;
}

my @text_indicator_converter_options
      = ('ASCII_GLYPH', 'DEBUG', 'DOC_ENCODING_FOR_INPUT_FILE_NAME',
         'NUMBER_SECTIONS', 'TEST');

# for this module converter
sub _initialize_text_options_encoding($) {
  my $text_options = shift;

  if ($text_options->{'ENABLE_ENCODING'}
       and defined($text_options->{'OUTPUT_ENCODING_NAME'})) {
    $text_options->{'enabled_encoding'}
       = $text_options->{'OUTPUT_ENCODING_NAME'};
  }
}

# for a converter inheriting Texinfo::Convert::Converter
sub _initialize_converter_text_options_encoding($$) {
  my ($converter, $text_options) = @_;

  if ($converter->get_conf('ENABLE_ENCODING')
       and defined($converter->get_conf('OUTPUT_ENCODING_NAME'))) {
    $text_options->{'enabled_encoding'}
       = $converter->get_conf('OUTPUT_ENCODING_NAME');
  }
}

# NOTE not documented.  In general, it is not useful to call that
# function, as it the function is already called in Texinfo::Convert::Converter
# to setup options that can be reused.
#
# $CONVERTER is an object implementing get_conf and other methods for
# translation, in general a converter.
# Setup options as used by Texinfo::Convert::Text::convert_to_text
# based on the converter information.
# This is relevant for file names, for instance.
# $OPTIONS_IN can be used to pass additional options, for now 'sort_string'.
sub copy_options_for_convert_text($;$) {
  my ($converter, $options_in) = @_;

  # same as Converter.pm common_converters_non_options_defaults
  my %options;

  _initialize_converter_text_options_encoding($converter, \%options);

  foreach my $option (@text_indicator_converter_options) {
    my $conf = $converter->get_conf($option);
    if ($conf) {
      $options{$option} = 1;
    } elsif (defined($conf)) {
      $options{$option} = 0;
    }
  }
  my $expanded_formats = $converter->get_conf('EXPANDED_FORMATS');
  if (defined($expanded_formats)) {
    $options{'expanded_formats'} = {};
    foreach my $expanded_format(@$expanded_formats) {
      $options{'expanded_formats'}->{$expanded_format} = 1;
    }
  }

  foreach my $string_option ('COMMAND_LINE_ENCODING',
                             'documentlanguage', 'INPUT_FILE_NAME_ENCODING',
                             'LOCALE_ENCODING') {
    $options{$string_option} = $converter->get_conf($string_option);
  }

  my $documentlanguage = $options{'documentlanguage'};
  if (defined($documentlanguage)) {
    Texinfo::Convert::Utils::switch_lang_translations(\%options,
                                                      $documentlanguage,
                                        $options{'COMMAND_LINE_ENCODING'});
  }

  my $include_directories = $converter->get_conf('INCLUDE_DIRECTORIES');
  if (defined($include_directories) and scalar(@{$include_directories})) {
    $options{'INCLUDE_DIRECTORIES'} = [@{$include_directories}];
  }

  if (exists($converter->{'translated_commands'})) {
    $options{'translated_commands'}
      = dclone($converter->{'translated_commands'});
  }

  $options{'converter'} = $converter;

  if (defined($options_in)) {
    foreach my $option (keys(%$options_in)) {
      $options{$option} = $options_in->{$option};
    }
  }
  return \%options;
}

sub set_options_code($) {
  my $options = shift;

  $options->{'_code_state'}++;
}

sub reset_options_code($) {
  my $options = shift;

  $options->{'_code_state'}--;
}

# $CONVERTER is an object implementing get_conf, in general a converter.
# set enabled_encoding unless the encoding is ascii, even if
# ENABLE_ENCODING is not set.
sub set_options_encoding_if_not_ascii($$) {
  my ($converter, $options) = @_;

  my $output_encoding_name = $converter->get_conf('OUTPUT_ENCODING_NAME');
  if (defined($output_encoding_name) and $output_encoding_name ne 'us-ascii') {
    if (exists($options->{'_saved_enabled_encoding'})) {
       print STDERR "BUG: if_not_ascii _saved_enabled_encoding set: "
                            .$options->{'_saved_enabled_encoding'}." / ".
                     $output_encoding_name ."\n";
      #cluck();
    }
    $options->{'_saved_enabled_encoding'} = $options->{'enabled_encoding'};
    $options->{'enabled_encoding'} = $output_encoding_name;
  }
}

sub set_options_encoding($$) {
  my ($options, $encoding) = @_;

  if (exists($options->{'_saved_enabled_encoding'})) {
     print STDERR "BUG: _saved_enabled_encoding set: "
                          .$options->{'_saved_enabled_encoding'}." / ".
                            $encoding."\n";
  }
  $options->{'_saved_enabled_encoding'} = $options->{'enabled_encoding'};
  $options->{'enabled_encoding'} = $encoding;
}

sub reset_options_encoding($) {
  my $options = shift;

  if (exists($options->{'_saved_enabled_encoding'})) {
    $options->{'enabled_encoding'} = $options->{'_saved_enabled_encoding'};
    delete $options->{'_saved_enabled_encoding'};
  }
}

sub set_language($$) {
  my ($options, $lang) = @_;

  Texinfo::Convert::Utils::switch_lang_translations($options, $lang,
                                       $options->{'COMMAND_LINE_ENCODING'});
}


sub _ascii_accent($$) {
  my ($text, $command) = @_;

  my $accent = $command->{'cmdname'};
  return $text if ($accent eq 'dotless');
  return $text . "''" if ($accent eq 'H');
  return $text . '.' if ($accent eq 'dotaccent');
  return $text . '*' if ($accent eq 'ringaccent');
  return $text . '[' if ($accent eq 'tieaccent');
  return $text . '(' if ($accent eq 'u');
  return $text . '_' if ($accent eq 'ubaraccent');
  return '.' . $text  if ($accent eq 'udotaccent');
  return $text . '<' if ($accent eq 'v');
  return $text . ';' if ($accent eq 'ogonek');
  return $text . $accent;
}

# format a stack of accents as ascii
sub _ascii_accents($$;$) {
  my ($result, $stack, $set_case) = @_;

  if ($set_case and $result =~ /^\w+$/) {
    if ($set_case > 0) {
      $result = uc($result);
    } else {
      $result = lc($result);
    }
  }
  foreach my $accent_command (reverse(@$stack)) {
    $result = _ascii_accent($result, $accent_command);
  }
  return $result;
}

# Same as _ascii_accent, but with a converter as first argument to be consistent
# with calling conventions of fallback accent formatting functions given
# to Convert::Converter::convert_accents()
# or Convert::Unicode::encoded_accents()
sub ascii_accent_fallback($$$;$$$) {
my ($converter, $text, $command, $index_in_stack, $accents_stack,
    $in_upper_case) = @_;

  return _ascii_accent($text, $command);
}

sub _convert($$);

# format an accent command and nested accents within as Text.
sub text_accents($;$$) {
  my ($accent, $encoding, $set_case) = @_;

  my ($contents_element, $stack)
      = Texinfo::Common::find_innermost_accent_contents($accent);
  my $options = {};
  $options->{'enabled_encoding'} = $encoding if (defined($encoding));
  $options->{'set_case'} = $set_case if (defined($set_case));
  my $text = '';
  if (defined($contents_element)) {
    # FIXME there is nothing really relevant for conversion of
    # text in accent command in convert_to_text as opposed to _convert,
    # but text_accents may be called from outside of convert_to_text,
    # it may be considered cleaner to go through convert_to_text.
    #$text = convert_to_text($contents_element, $options);
    $text = _convert($options, $contents_element);
  }

  my $result = Texinfo::Convert::Unicode::encoded_accents(undef, $text,
                     $stack, $encoding, \&ascii_accent_fallback, $set_case);
  if (defined($result)) {
    return $result;
  } else {
    return _ascii_accents($text, $stack, $set_case);
  }
}

# TODO document?
sub brace_no_arg_command($;$$$$) {
  my ($element, $encoding, $ascii_glyph, $sort_string, $set_case) = @_;

  my $command_name = $element->{'cmdname'};
  my $result;
  if (defined($encoding) and
      (!$ascii_glyph
       or !exists($Texinfo::CommandsValues::extra_unicode_map{$command_name}))) {
    $result
      = Texinfo::Convert::Unicode::brace_no_arg_command($command_name,
                                                        $encoding);
  }
  if (!defined($result)) {
    if ($sort_string
        and exists(
         $Texinfo::CommandsValues::sort_brace_no_arg_commands{$command_name})) {
      $result
        = $Texinfo::CommandsValues::sort_brace_no_arg_commands{$command_name};
    } else {
      $result
       = $Texinfo::CommandsValues::text_brace_no_arg_commands{$command_name};
    }
  }
  if ($set_case
      and exists($Texinfo::Commands::letter_no_arg_commands{$command_name})) {
    if ($set_case > 0) {
      $result = uc($result);
    # NOTE does not seems to be decreased/set to negative anywhere, but
    # should work ok if it is.
    } else {
      $result = lc($result);
    }
  }
  return $result;
}

my %underline_symbol = (
  0 => '*',
  1 => '*',
  2 => '=',
  3 => '-',
  4 => '.'
);

# Return the text of an underlined heading
sub _text_heading($$$;$) {
  my ($current, $text, $numbered, $lang_translations) = @_;

  # end of lines spaces are ignored in conversion.  However in
  # rare cases, invalid nestings leave an end of line, so we chomp.
  chomp($text);

  my $number;

  $text = Texinfo::Convert::Utils::add_heading_number($current,
                           $text, $numbered, $lang_translations);
  # What about non-ascii spaces?
  return '' if ($text !~ /\S/);
  my $result = $text ."\n";
  my $section_level;
  if (!exists($current->{'extra'})
      or !exists($current->{'extra'}->{'section_level'})) {
    $section_level = Texinfo::Common::section_level($current);
  } else {
    $section_level = $current->{'extra'}->{'section_level'};
  }
  $result .= ($underline_symbol{$section_level}
     x (Texinfo::Convert::Unicode::string_width($text)))."\n";
  return $result;
}

sub _convert_def_line($$) {
  my ($options, $element) = @_;

  my $result = '';

  #print STDERR "DEF: $element->{'extra'}->{'def_command'}\n";
  my ($category_element, $class_element,
      $type_element, $name_element, $arguments)
       = Texinfo::Convert::Utils::definition_arguments_content($element);

  my $parsed_definition_category
    = Texinfo::Convert::Utils::definition_category_tree($element,
                                   $options->{'current_lang_translations'},
                                   $options->{'COMMAND_LINE_ENCODING'},
                                   $options->{'DEBUG'});
  if (defined($parsed_definition_category)) {
    my $converted_element = Texinfo::TreeElement::new(
       {'contents' => [$parsed_definition_category,
                       Texinfo::TreeElement::new({'text' => ': '})]});
    my $contents = $converted_element->{'contents'};
    if (defined($type_element)) {
      push @$contents, ($type_element,
          Texinfo::TreeElement::new({'text' => ' '}));
    }
    if (defined($name_element)) {
      push @$contents, $name_element;
    }

    if (defined($arguments)) {
      push @$contents, (Texinfo::TreeElement::new({'text' => ' '}),
                        $arguments);
    }
    push @$contents, Texinfo::TreeElement::new({'text' => "\n"});
    $options->{'_code_state'}++;
    $result = _convert($options, $converted_element);
    $options->{'_code_state'}--;
  }
  return $result;
}

# Will never be called, used for the override.
sub _convert_tree_with_XS($$) {
}

sub _convert($$) {
  my ($options, $element) = @_;

  #print STDERR "E: c: ".(defined($options->{'_code_state'})
  #                         ? $options->{'_code_state'} : 'UNDEF')
  #   ." r: ".(defined($options->{'_raw_state'})
  #                         ? $options->{'_raw_state'} : 'UNDEF')
  #   .", ".Texinfo::Common::debug_print_element($element, 1)."\n";

  if (!defined($element)) {
    confess("Texinfo::Convert::Text::_convert: element undef");
  }

  if (exists($element->{'text'})) {
    if (exists($element->{'type'})
         and $ignored_text_types{$element->{'type'}}) {
      return '';
    }
    my $result = $element->{'text'};
    if ((! exists($element->{'type'})
         or $element->{'type'} ne 'raw')
        and !$options->{'_raw_state'}) {
      if ($options->{'set_case'}) {
        if ($options->{'set_case'} > 0) {
          $result = uc($result);
        } else {
          $result = lc($result);
        }
      }
      if (!$options->{'_code_state'}) {
        $result =~ s/``/"/g;
        $result =~ s/\'\'/"/g;
        $result =~ s/---/\x{1F}/g;
        $result =~ s/--/-/g;
        $result =~ s/\x{1F}/--/g;
      }
    }
    return $result;
  }

  my $cmdname;
  my $data_cmdname;
  if (exists($element->{'cmdname'})) {
    $cmdname = $element->{'cmdname'};
    if ($cmdname eq 'item'
        and exists($element->{'contents'})
        and exists($element->{'contents'}->[0]->{'type'})
        and $element->{'contents'}->[0]->{'type'} eq 'line_arg') {
      $data_cmdname = 'item_LINE';
    } else {
      $data_cmdname = $cmdname;
    }
  }

  return '' if (!(exists($element->{'type'})
                  and $element->{'type'} eq 'def_line')
     and ((exists($element->{'type'}) and $ignored_types{$element->{'type'}})
          or (defined($cmdname)
             and (exists($ignored_brace_commands{$cmdname})
                 or exists($ignored_block_commands{$cmdname})
                 or (exists($ignored_format_raw_commands{$cmdname})
                     and !(defined($options->{'expanded_formats'})
                           and $options->{'expanded_formats'}->{$cmdname}))
                 or (exists($Texinfo::Commands::brace_commands{$cmdname})
                     and $Texinfo::Commands::brace_commands{
                                             $cmdname} eq 'inline'
                     and $cmdname ne 'inlinefmtifelse'
                     and ((exists(
                           $Texinfo::Commands::inline_format_commands{$cmdname})
                           and (!exists($element->{'extra'})
                                or !exists($element->{'extra'}->{'format'})
                                or !exists($options->{'expanded_formats'})
                                or !$options->{'expanded_formats'}
                                           ->{$element->{'extra'}->{'format'}}))
                         or (!exists(
                          $Texinfo::Commands::inline_format_commands{$cmdname})
                             and (!exists($element->{'extra'})
                                  or !defined($element->{'extra'}
                                                         ->{'expand_index'})))))
             # here ignore most of the line commands
                 or (exists($element->{'type'})
                     and $element->{'type'} eq 'index_entry_command')
                 or (exists($line_commands{$data_cmdname})
                     and !exists($formatted_line_commands{$data_cmdname})
                     and !exists($def_commands{$data_cmdname})
                     and ($data_cmdname ne 'sp'
                          and $data_cmdname ne 'verbatiminclude'))))));

  my $result = '';
  if (defined($cmdname)) {
    if (exists($nobrace_symbol_text{$cmdname})) {
      return $nobrace_symbol_text{$cmdname};
    } elsif ($cmdname eq 'today') {
      if ($options->{'sort_string'}
          and exists(
            $Texinfo::CommandsValues::sort_brace_no_arg_commands{$cmdname})) {
        return $Texinfo::CommandsValues::sort_brace_no_arg_commands{$cmdname};
      } else {
        my $expanded_tree
          = Texinfo::Convert::Utils::expand_today($options->{'TEST'},
                                     $options->{'current_lang_translations'},
                                     $options->{'DEBUG'});
        return _convert($options, $expanded_tree);
      }
    } elsif (exists($Texinfo::CommandsValues::text_brace_no_arg_commands{$cmdname})) {
      my $tree
        = Texinfo::Convert::Utils::translated_command_tree(
                         $options->{'translated_commands'}, $cmdname,
                         $options->{'current_lang_translations'},
                         $options->{'DEBUG'});
      if ($tree) {
        return _convert($options, $tree);
      }
      return brace_no_arg_command($element,
                $options->{'enabled_encoding'}, $options->{'ASCII_GLYPH'},
                $options->{'sort_string'}, $options->{'set_case'});
    # commands with braces
    } elsif (exists($accent_commands{$cmdname})) {
      my $result = text_accents($element, $options->{'enabled_encoding'},
                                $options->{'set_case'});
      return $result;
    } elsif ($cmdname eq 'image') {
      if (exists($element->{'contents'})) {
        $options->{'_code_state'}++;
        my $text = _convert($options, $element->{'contents'}->[0]);
        $options->{'_code_state'}--;
        return $text;
      } else {
        return '';
      }
    } elsif ($cmdname eq 'email') {
      if (exists($element->{'contents'})) {
        my $text;
        $text = _convert($options, $element->{'contents'}->[1])
           if (defined($element->{'contents'}->[1]));
        return $text if (defined($text) and ($text ne ''));
        $options->{'_code_state'}++;
        my $mail = _convert($options, $element->{'contents'}->[0]);
        $options->{'_code_state'}--;
        return $mail;
      } else {
        return '';
      }
    } elsif ($cmdname eq 'uref' or $cmdname eq 'url') {
      if (exists($element->{'contents'})) {
        my $replacement;
        $replacement = _convert($options, $element->{'contents'}->[2])
          if (defined($element->{'contents'}->[2]));
        return $replacement if (defined($replacement) and $replacement ne '');
        my $text;
        $text = _convert($options, $element->{'contents'}->[1])
          if (defined($element->{'contents'}->[1]));
        $options->{'_code_state'}++;
        my $url = _convert($options, $element->{'contents'}->[0]);
        $options->{'_code_state'}--;
        if (defined($text) and $text ne '') {
          return "$url ($text)";
        } else {
          return $url;
        }
      } else {
        return '';
      }
    # if there is only one argument, it is processed below with the other
    # brace commands
    } elsif (exists($Texinfo::Commands::explained_commands{$cmdname})
             and exists($element->{'contents'})
             and scalar(@{$element->{'contents'}}) >= 2) {
      my $explanation = _convert($options, $element->{'contents'}->[1]);
      if ($explanation ne '') {
        return _convert($options, $element->{'contents'}->[0])
                                             ." ($explanation)";
      } else {
        return _convert($options, $element->{'contents'}->[0]);
      }
    } elsif (exists($Texinfo::Commands::brace_commands{$cmdname})
             and $Texinfo::Commands::brace_commands{$cmdname} eq 'inline') {
      if ($cmdname eq 'inlineraw') {
        $options->{'_raw_state'}++;
      }
      my $arg_index = 1;
      if ($cmdname eq 'inlinefmtifelse'
          and (!exists($element->{'extra'})
               or !exists($element->{'extra'}->{'format'})
               or !exists($options->{'expanded_formats'})
               or !$options->{'expanded_formats'}
                                   ->{$element->{'extra'}->{'format'}})) {
        $arg_index = 2;
      }
      my $result = '';
      if (exists($element->{'contents'})
          and scalar(@{$element->{'contents'}}) > $arg_index) {
        $result = _convert($options, $element->{'contents'}->[$arg_index]);
      }
      if ($cmdname eq 'inlineraw') {
        $options->{'_raw_state'}--;
      }
      return $result;
    } elsif (exists($element->{'contents'})
           and ((exists($element->{'contents'}->[0]->{'type'})
                and ($element->{'contents'}->[0]->{'type'} eq 'brace_container'
                     or $element->{'contents'}->[0]->{'type'} eq 'brace_arg'))
                or (exists($Texinfo::Commands::math_commands{$cmdname})
                    and exists($Texinfo::Commands::brace_commands{$cmdname})))) {
      my $result;
      my $in_code;
      $options->{'set_case'}++ if ($cmdname eq 'sc');
      if (exists($Texinfo::Commands::brace_code_commands{$cmdname})
          or exists($Texinfo::Commands::math_commands{$cmdname})) {
        $in_code = 1;
      }
      $options->{'_code_state'}++ if ($in_code);
      $result = _convert($options, $element->{'contents'}->[0]);
      $options->{'_code_state'}-- if ($in_code);
      $options->{'set_case'}-- if ($cmdname eq 'sc');
      return $result;
    # block commands
    } elsif ($cmdname eq 'quotation'
             or $cmdname eq 'smallquotation'
             or $cmdname eq 'float'
             or $cmdname eq 'cartouche') {
      # arguments_line type element
      my $arguments_line = $element->{'contents'}->[0];
      foreach my $block_line_arg (@{$arguments_line->{'contents'}}) {
        my $converted_arg = _convert($options, $block_line_arg);
        if ($converted_arg =~ /\S/) {
          $result .= $converted_arg.", ";
        }
      }
      $result =~ s/, $//;
      chomp ($result);
      $result .= "\n" if ($result =~ /\S/);
    } elsif (exists($Texinfo::Commands::sectioning_heading_commands{$cmdname})) {
      my $line_arg;
      if (exists($Texinfo::Commands::root_commands{$cmdname})) {
        # arguments_line type element
        my $arguments_line = $element->{'contents'}->[0];
        $line_arg = $arguments_line->{'contents'}->[0];
      } else {
        # @heading* command
        $line_arg = $element->{'contents'}->[0];
      }
      my $heading_text = _convert($options, $line_arg);
      $result = _text_heading($element, $heading_text,
                              $options->{'NUMBER_SECTIONS'},
                              $options->{'current_lang_translations'});
      unless (exists($Texinfo::Commands::root_commands{$cmdname})) {
        return $result;
      }
    } elsif (exists($formatted_line_commands{$data_cmdname})) {
      if ($cmdname ne 'node') {
        if ($cmdname eq 'page') {
          $result = '';
        } else {
          $result = _convert($options, $element->{'contents'}->[0]);
        }
        # we always want an end of line even if is was eaten by a command
        chomp($result);
        $result .= "\n";
        return $result;
      }
    } elsif (exists($line_commands{$data_cmdname})) {
      if (exists($def_commands{$cmdname})) {
        $result = _convert_def_line($options, $element);
      } elsif ($cmdname eq 'sp') {
        if (exists($element->{'extra'})
            and exists($element->{'extra'}->{'misc_args'})
            and defined($element->{'extra'}->{'misc_args'}->[0])) {
          # this useless copy avoids perl changing the type to integer!
          my $sp_nr = $element->{'extra'}->{'misc_args'}->[0];
          $result = "\n" x $sp_nr;
        }
      } elsif ($cmdname eq 'verbatiminclude') {
        my $verbatim_include_verbatim;
        my $input_file_name_encoding
         = $options->{'INPUT_FILE_NAME_ENCODING'};
        my $doc_encoding_for_input_file_name
         = $options->{'DOC_ENCODING_FOR_INPUT_FILE_NAME'};
        my $locale_encoding = $options->{'LOCALE_ENCODING'};

        my $include_directories
         = $options->{'INCLUDE_DIRECTORIES'};

        my $document = $options->{'document'};

        $verbatim_include_verbatim
          = Texinfo::Convert::Utils::expand_verbatiminclude($element,
              $include_directories, $input_file_name_encoding,
              $doc_encoding_for_input_file_name, $locale_encoding,
              $document, $options);

        if (defined($verbatim_include_verbatim)) {
          $result .= _convert($options, $verbatim_include_verbatim);
        }
      }
      return $result;
    } elsif ($cmdname eq 'item'
            and exists($element->{'parent'}->{'cmdname'})
            and $element->{'parent'}->{'cmdname'} eq 'enumerate') {
      $result .= Texinfo::Common::enumerate_item_representation($element).'. ';
    }
  }
  if (exists($element->{'type'})) {
    if ($element->{'type'} eq 'def_line') {
      $result = _convert_def_line($options, $element);
      return $result;
    } elsif ($element->{'type'} eq 'untranslated_def_line_arg') {
      my $tree;
      my $category_text = $element->{'contents'}->[0]->{'text'};
      my $translation_context;
      if (exists($element->{'extra'})
          and defined($element->{'extra'}->{'translation_context'})) {
        $translation_context = $element->{'extra'}->{'translation_context'};
      }

      if ($options and exists($options->{'current_lang_translations'})) {
        # the tree documentlanguage corresponds to the documentlanguage
        # at the place of the tree, but the caller may want to use
        # another documentlanguage, for instance the documentlanguage at
        # the end of the preamble, so we let the caller set it.
        $tree = Texinfo::Translations::gdt($category_text,
                               $options->{'current_lang_translations'}, undef,
                               $options->{'DEBUG'}, $translation_context);
      } else {
        # if there is no documentlanguage information, we use the
        # documentlanguage available in the tree.
        my $new_lang_translations
           = Texinfo::Translations::new_lang_translation(
                                  $element->{'extra'}->{'documentlanguage'},
                                  $options->{'COMMAND_LINE_ENCODING'});

        $tree = Texinfo::Translations::gdt($category_text,
                             $new_lang_translations, undef, undef,
                             $translation_context);
      }
      $result = _convert($options, $tree);
      return $result;
    }
  }
  if (exists($element->{'contents'})) {
    my $in_code;
    my $in_raw;
    if ((defined($cmdname)
         and (exists($Texinfo::Commands::preformatted_code_commands{$cmdname})
              or exists($Texinfo::Commands::math_commands{$cmdname})
              or (exists($Texinfo::Commands::block_commands{$cmdname})
                  and $Texinfo::Commands::block_commands{$cmdname} eq 'raw')))
         or ($element->{'type'} and $element->{'type'} eq 'menu_entry_node')) {
      $in_code = 1;
    } elsif (defined($cmdname)
             and exists($Texinfo::Commands::block_commands{$cmdname})
             and $Texinfo::Commands::block_commands{$cmdname} eq 'format_raw') {
      $in_raw = 1;
    }
    if (ref($element->{'contents'}) ne 'ARRAY') {
      cluck "contents not an array($element->{'contents'}).";
    }
    $options->{'_code_state'}++ if ($in_code);
    $options->{'_raw_state'}++ if ($in_raw);
    foreach my $content (@{$element->{'contents'}}) {
      $result .= _convert($options, $content);
    }
    $options->{'_raw_state'}-- if ($in_raw);
    $options->{'_code_state'}-- if ($in_code);
  }
  if (exists($element->{'type'}) and $element->{'type'} eq 'menu_entry'
      and (!exists($element->{'parent'}->{'type'})
           or ($element->{'parent'}->{'type'} ne 'preformatted'
               and $element->{'parent'}->{'type'} ne 'rawpreformatted'))) {
    chomp($result);
    $result .= "\n";
  }
  #print STDERR "  RR ($element) -> $result\n";
  return $result;
}

# the main entry point
sub convert_to_text($;$) {
  my ($root, $options) = @_;

  if (ref($root) ne 'HASH' and ref($root) ne 'Texinfo::TreeElement') {
  #if (ref($root) ne 'Texinfo::TreeElement') {#}
    confess "root not a hash";
  }

  #print STDERR "CONVERT\n";
  if (!defined($options)) {
    $options = {};
  } elsif (ref($options) eq '' and ref($options) ne 'HASH') {
    confess("convert_to_text options not a hash ref\n");
  }

  if (!exists($options->{'translated_commands'})) {
    $options->{'translated_commands'} = {'error' => 'error@arrow{}',};
  }

  # Interface with XS converter.
  if ($XS_convert
      and (defined($root->{'tree_document_descriptor'})
           or defined($root->{'element_document_descriptor'}))
      and $Texinfo::Convert::ConvertXS::XS_package) {
    return _convert_tree_with_XS($options, $root);
  }

  # needed for converter_document_warn call for verbatiminclude for t/*.t TESTS.
  bless $options, "Texinfo::Convert::Text";

  my $result = _convert($options, $root);

  if ($options->{'converter'}) {
    $options->{'converter'}->merge_converter_error_messages_lists_noxs($options);
  }

  return $result;
}


# Implement the converters API simply.  The POD documentation does not
# cover this possibility for doing the conversion.
# initialization
sub converter($;$) {
  my ($class, $conf) = @_;

  my $converter = {};
  bless $converter, $class;

  if (defined($conf)) {
    %{$converter} = %{$conf};
    #print STDERR "CTe ".join("|", sort(keys(%{$conf})))."\n";
  }

  if (!exists($converter->{'translated_commands'})) {
    $converter->{'translated_commands'} = {'error' => 'error@arrow{}',};
  }

  my $expanded_formats = $converter->{'EXPANDED_FORMATS'};
  if (defined($expanded_formats)) {
    $converter->{'expanded_formats'} = {};
    foreach my $expanded_format(@$expanded_formats) {
      $converter->{'expanded_formats'}->{$expanded_format} = 1;
    }
  }

  return $converter;
}

# This function is not called (except in a test testing the function),
# it is implemented to be in line with Texinfo::Convert::Converter
# documentation on functions defined for a converter.
# We assume that $SELF is defined and a Texinfo::Convert::Text converter
# that will supply the options.
sub convert_tree($$) {
  my ($self, $element) = @_;

  return _convert($self, $element);
}

# This function is not called (except in a test testing the function),
# it is implemented to be in line with Texinfo::Convert::Converter
# documentation on functions defined for a converter.
# We assume that $SELF is defined and a Texinfo::Convert::Text converter.
sub convert($$) {
  my ($self, $document) = @_;

  my $global_info;
  if (defined($document)) {
    $global_info = $document->global_information();

    # similar to Texinfo::Common::set_output_encoding
    $self->{'OUTPUT_ENCODING_NAME'} = $global_info->{'input_encoding_name'}
      if (defined($global_info)
          and exists($global_info->{'input_encoding_name'}));
  }

  # Cf comment in output() on using $self for options.
  _initialize_text_options_encoding($self);

  # for expand_verbatiminclude call.
  $self->{'document'} = $document;

  my $root = $document->tree();

  my $result;
  # Interface with XS converter.
  if ($XS_convert
      and (defined($root->{'tree_document_descriptor'})
           or defined($root->{'element_document_descriptor'}))
      and $Texinfo::Convert::ConvertXS::XS_package) {
    $result = _convert_tree_with_XS($self, $root);
  } else {
    $result = _convert($self, $root);
  }

  return $result;
}

# determine outfile and output to that file
my $STDIN_DOCU_NAME = 'stdin';
sub output($$) {
  my ($self, $document) = @_;

  my $global_info;
  if ($document) {
    $global_info = $document->global_information();

    # similar to Texinfo::Common::set_output_encoding
    $self->{'OUTPUT_ENCODING_NAME'} = $global_info->{'input_encoding_name'}
      if (defined($global_info)
          and exists($global_info->{'input_encoding_name'}));
  }

  # Text options and converter are of different nature.
  # However, since the option keys are very similar between the converter
  # and text options and expanded_formats is already set in the converter,
  # we use the converter object as text options and we call
  # _initialize_text_options_encoding for the only option that is set up
  # based on other customization options.
  # Also, we need a blessed reference as converter_line_error
  # and other methods can be called on the options, using the converter
  # brings that too.
  _initialize_text_options_encoding($self);

  # for expand_verbatiminclude call.
  $self->{'document'} = $document;

  my $root = $document->tree();

  #print STDERR "OUTPUT\n";
  my $input_basename;
  if (defined($global_info) and exists($global_info->{'input_file_name'})) {
    my $input_file_name_bytes = $global_info->{'input_file_name'};
    my $encoding = $self->{'COMMAND_LINE_ENCODING'};
    my $input_file_name;
    if (defined($encoding)) {
      $input_file_name = decode($encoding, $input_file_name_bytes);
    } else {
      $input_file_name = $input_file_name_bytes;
    }
    my ($directories, $suffix);
    ($input_basename, $directories, $suffix) = fileparse($input_file_name);
  } else {
    # This could happen if called on a piece of texinfo
    $input_basename = '';
  }
  $input_basename = $STDIN_DOCU_NAME if ($input_basename eq '-');
  $input_basename =~ s/\.te?x(i|info)?$//;

  my $setfilename;
  if (defined($global_info) and exists($global_info->{'setfilename'})) {
    $setfilename = $global_info->{'setfilename'};
  }
  my $outfile;
  if (!defined($self->{'OUTFILE'})) {
    if (defined($setfilename)) {
      $outfile = $setfilename;
      $outfile =~ s/\.[^\.]*$//;
    } elsif ($input_basename ne '') {
      $outfile = $input_basename;
    }
    if (defined($outfile)) {
      $outfile .= '.txt';
      if (defined($self->{'SUBDIR'})) {
        my $destination_directory
         = Texinfo::Common::file_separator_canonpath($self->{'SUBDIR'});
        my ($encoded_destination_directory, $destination_directory_encoding)
          = Texinfo::Convert::Utils::encoded_output_file_name(
             $destination_directory, $self->{'OUTPUT_FILE_NAME_ENCODING'},
             $self->{'DOC_ENCODING_FOR_OUTPUT_FILE_NAME'},
             $self->{'LOCALE_ENCODING'}, $document);
        if (! -d $encoded_destination_directory) {
          if (!mkdir($encoded_destination_directory, oct(755))) {
            warn sprintf(__(
               "could not create directory `%s': %s"),
               $destination_directory, $!)."\n";
            return undef;
          }
        }
        $outfile = join('/', ($destination_directory, $outfile));
      }
    }
  } else {
    $outfile = $self->{'OUTFILE'};
    my ($output_basename, $output_directories, $output_suffix)
      = fileparse($outfile);
    if (defined($output_directories) and $output_directories ne './'
        and $output_directories ne '.' and $output_directories ne '') {
      my ($encoded_output_directories, $output_directories_encoding)
        = Texinfo::Convert::Utils::encoded_output_file_name(
             $output_directories, $self->{'OUTPUT_FILE_NAME_ENCODING'},
             $self->{'DOC_ENCODING_FOR_OUTPUT_FILE_NAME'},
             $self->{'LOCALE_ENCODING'}, $document);
      if (! -d $encoded_output_directories) {
        if (!mkdir($encoded_output_directories, oct(755))) {
          warn sprintf(__(
             "could not create directory `%s': %s"),
             $output_directories, $!)."\n";
        }
      }
    }
  }
  my $fh;
  $self->{'output_files'} = Texinfo::Convert::Utils::output_files_initialize();
  my ($encoded_outfile, $outfile_encoding);
  if (defined($outfile)) {
    ($encoded_outfile, $outfile_encoding)
      = Texinfo::Convert::Utils::encoded_output_file_name($outfile,
                       $self->{'OUTPUT_FILE_NAME_ENCODING'},
                       $self->{'DOC_ENCODING_FOR_OUTPUT_FILE_NAME'},
                       $self->{'LOCALE_ENCODING'}, $document);

    my $error_message;
    # the third return information, set if the file has already been used
    # in this files_information is not checked as this cannot happen.
    ($fh, $error_message) = Texinfo::Convert::Utils::output_files_open_out(
                             $self->{'output_files'},
                             $encoded_outfile, undef,
                             $self->{'OUTPUT_ENCODING_NAME'});
    if (!defined($fh)) {
      warn sprintf(__("could not open %s for writing: %s"),
                   $outfile, $error_message)."\n";
      return undef;
    }
  }

  # We use $self as text options, see the comment above.

  my $result;
  # Interface with XS converter.
  if ($XS_convert
      and (defined($root->{'tree_document_descriptor'})
           or defined($root->{'element_document_descriptor'}))
      and $Texinfo::Convert::ConvertXS::XS_package) {
    $result = _convert_tree_with_XS($self, $root);
  } else {
    $result = _convert($self, $root);
  }

  if (defined($fh)) {
    print $fh $result;
    # Do not close STDOUT now such that the file descriptor is not reused
    # by open, which uses the lowest-numbered file descriptor not open,
    # for another filehandle.  Closing STDOUT is handled by the caller.
    if ($outfile ne '-') {
      Texinfo::Convert::Utils::output_files_register_closed(
                  $self->{'output_files'}, $encoded_outfile);

      if (!close($fh)) {
        warn sprintf(__("error on closing %s: %s"), $outfile, $!)."\n";
        return undef;
      }
    }
    $result = '';
  }
  return $result;
}

# Nothing to do in perl.  XS function frees memory
sub destroy_converter($) {
}

# Following not used anywhere.  Would not be an issue if they were.
#sub get_conf($$)
#{
#  my $self = shift;
#  my $key = shift;
#
#  return $self->{$key};
#}

#sub set_conf($$$)
#{
#  my $self = shift;
#  my $conf = shift;
#  my $value = shift;
#
#  $self->{$conf} = $value;
#
#  return 1;
#}

# used in Texinfo::Convert::Utils::expand_verbatiminclude
sub converter_line_error($$$;$) {
  my ($self, $text, $error_location_info, $continuation) = @_;

  my $message = Texinfo::Report::format_line_message('error', $text,
                                 $error_location_info, $continuation,
                                            $self->{'DEBUG'});
  push @{$self->{'error_warning_messages'}}, $message;
}

# used in Texinfo::Convert::Utils::expand_verbatiminclude
sub converter_document_warn($$;$) {
  my ($self, $text, $continuation) = @_;

  my $program_name;

  if ($self->{'PROGRAM'} && $self->{'PROGRAM'} ne '') {
    $program_name = $self->{'PROGRAM'};
  }

  my $message
      = Texinfo::Report::format_document_message('warning', $text,
                                        $program_name, $continuation);
  push @{$self->{'error_warning_messages'}}, $message;
}

sub get_converter_errors($) {
  my $self = shift;

  return $self->{'error_warning_messages'};
}

sub converter_defaults($;$) {
  return undef;
}

sub output_files_information($) {
  my $self = shift;

  return $self->{'output_files'};
}

1;

__END__

=head1 NAME

Texinfo::Convert::Text - Convert Texinfo tree to simple text

=head1 SYNOPSIS

  use Texinfo::Convert::Text qw(convert_to_text text_accents);

  my $result = convert_to_text($tree);

  my $accents_text = text_accents($accents, 'utf-8');

  # using text conversion options set in $converter derived from
  # Texinfo::Convert::Converter
  my $text_options = $converter->{'convert_text_options'};

  set_options_code($text_options);
  my $result_with_converter = convert_to_text($tree, $text_options);
  reset_options_code($text_options);

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

C<Texinfo::Convert::Text> is a simple backend that converts a Texinfo tree
to simple text.  It is used in converters, especially for file names.

Converters derived from L<Texinfo::Convert::Converter> should have conversion
text options preset associated to the C<convert_text_options> key.

The main function is C<convert_to_text>.  The text conversion options
can be modified with the C<set_*> functions before calling C<convert_to_text>,
and reset afterwards with the corresponding C<reset_*> functions.

=head1 METHODS

=over

=item $result = convert_to_text($tree, $text_options)
X<C<convert_to_text>>

Convert a Texinfo tree to simple text.  I<$text_options> is a hash reference of
options.

The C<ASCII_GLYPH>, C<DEBUG>, C<DOC_ENCODING_FOR_INPUT_FILE_NAME>,
C<COMMAND_LINE_ENCODING>,
C<NUMBER_SECTIONS>, C<TEST>, C<documentlanguage>, C<INPUT_FILE_NAME_ENCODING>,
C<LOCALE_ENCODING> and C<INCLUDE_DIRECTORIES> options corresponding to
customization variables may be set in I<$text_options>.

The following options may also be set:

=over

=item converter

If a converter object is passed to the function, generated error
messages are passed back to the converter.  See also
L<Texinfo::Convert::Converter>.

=item enabled_encoding

If set, the value is considered to be the encoding name texinfo accented
letters should be converted to.  In the default case, this option is set from
the main program directly or through converters calling conversion to text if
the C<--enable-encoding> option, or the C<ENABLE_ENCODING> customization
variable is set.  For file names in HTML and LaTeX, and for DocBook or Texinfo
XML, this variable should in general be set unless the output encoding is
US-ASCII.

=item expanded_formats

A reference on a hash.  The keys should be format names (like C<html>,
C<tex>), and if the corresponding value is set, the format is expanded.

=item set_case

If positive, the text is upper-cased, if negative, the text is lower-cased.

=item sort_string

A somehow internal option to convert to text more suitable for alphabetical
sorting rather than presentation.

=back

=item $result_accent_text = ascii_accent_fallback($converter, $text, $accent_command, $index_in_stack, $accents_stack, $in_upper_case $converter)
X<C<ascii_accent_fallback>>

I<$text> is the text appearing within an accent command.  I<$accent_command>
should be a Texinfo tree element corresponding to an accent command taking
an argument.  The function returns a transliteration of the accented
character.  The I<$converter> argument is ignored, but needed for this
function to be in argument of functions that need a fallback for accents
conversion.  The remaining arguments are also ignored and similarly
may be needed for this function to be in argument of functions that need a
fallback for accents conversion.

=item set_options_code($text_options)

=item reset_options_code($text_options)
X<C<set_options_code>>X<C<reset_options_code>>

C<set_options_code> sets I<$text_options> to be in code style.
(mostly C<-->, C<--->, C<''> and C<``> are kept as is).  C<reset_options_code>
undo the effect of C<set_options_code>.

C<reset_options_code> should always be called after C<set_options_code>.

=item set_options_encoding($text_options, $encoding)

=item set_options_encoding_if_not_ascii($customization_information, $text_options)

=item reset_options_encoding($text_options)
X<C<set_options_encoding>>X<C<set_options_encoding_if_not_ascii>>
X<C<reset_options_encoding>>

C<set_options_encoding> sets C<enabled_encoding> in I<$text_options>
to I<$encoding>.  C<set_options_encoding_if_not_ascii> sets C<enabled_encoding>
in I<$text_options> based on customization options associated to
I<$customization_information>.  In that case, C<enabled_encoding> is set unless
the output encoding is US-ASCII even if C<ENABLE_ENCODING> is not set.

C<reset_options_encoding> undo the effect of C<set_options_encoding> and
C<set_options_encoding_if_not_ascii> and should always be called after these
functions.

=item $accents_text = text_accents($accents, $encoding, $set_case)
X<C<text_accents>>

I<$accents> is an accent command that may contain other nested accent
commands.  The function will format the whole stack of nested accent
commands and the innermost text.  If I<$encoding> is set, the formatted
text is converted to this encoding as much as possible instead of being
converted as simple ASCII.  If I<$set_case> is positive, the result
is meant to be upper-cased, if it is negative, the result is to be
lower-cased.

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
