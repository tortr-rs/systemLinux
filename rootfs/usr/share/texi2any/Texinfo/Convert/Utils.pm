# Utils.pm: miscellaneous functions usable in simple converters
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
#
# This module contains the methods that can be used in converters
# even if they do not inherit Texinfo::Convert::Converter.  In practice
# it means that the converter argument will not be defined and
# there will be no error reporting in that case.

# ALTIMP C/main/convert_utils.c

package Texinfo::Convert::Utils;

use strict;

use 5.006;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

# debugging
use Carp qw(cluck);

use Texinfo::Commands;

use Texinfo::TreeElement;

use Texinfo::Common;
# only needed in debugging comments.  Ok to keep it here anyway.
use Texinfo::Convert::Texinfo;

require Exporter;

our @ISA = qw(Exporter);

# There is no specific reason to export those functions and not
# other functions of the module.  It could be possible not to
# export any function.
our @EXPORT_OK = qw(
expand_verbatiminclude
add_heading_number
);

our $VERSION = '7.3';

# API to open, set encoding and register files.  Used in main program
# and converters.
# In general $SELF is stored as $converter->{'output_files'}
# and should be accessed through $converter->output_files_information();

# TODO next five functions not documented anywhere, probably relevant to
# document both in POD and in HTML Customization API.
sub output_files_initialize {
  return {'unclosed_files' => {}, 'opened_files' => {}};
}

sub output_files_reset($) {
  my $self = shift;

  $self->{'unclosed_files'} = {};
  $self->{'opened_files'} = {};
}

sub output_files_disable_output_encoding($$) {
  my ($self, $no_output_encoding) = @_;

  $self->{'output_encoding_disabled'} = $no_output_encoding;
}

# All the opened files are registered, except for stdout,
# and the closing of files should be registered too with
# output_files_register_closed() below.  This makes possible to
# unlink all the opened files and close the files not already
# closed.
#
# $FILE_PATH is the file path, it should be a binary string.
# If $USE_BINMODE is set, call binmode() to set binary mode.
# $OUTPUT_ENCODING argument sets the output encoding.
# Returns
#  - the opened filehandle, or undef if opening failed,
#  - the $! error message or undef if opening succeeded.
#  - 1 if the $FILE_PATH was already opened, which means overwriting.
sub output_files_open_out($$;$$) {
  my ($self, $file_path, $use_binmode, $output_encoding) = @_;

  #if (!defined($file_path)) {
  #  cluck('output_files_open_out: file_path undef');
  #}

  my $encoding;
  if ($self->{'output_encoding_disabled'}) {
   # leave $encoding undefined
  } elsif (defined($output_encoding)) {
    $encoding = Texinfo::Common::processing_output_encoding($output_encoding);
  }

  if ($file_path eq '-') {
    binmode(STDOUT) if $use_binmode;
    binmode(STDOUT, ":encoding($encoding)") if (defined($encoding));
    if ($self) {
      $self->{'unclosed_files'}->{$file_path} = \*STDOUT;
    }
    return \*STDOUT, undef;
  }

  # Check that this file has not already been registered
  # as opened_file.  If yes, it will be overwritten if open succeeds.
  # It is not possible to use the file name twice in converters
  # for regular output as files are only closed when all the output
  # units have been written.  It could be possible in HTML with js
  # scripts licence file set by the user to the same name as an output
  # file.
  my $overwritten_file = 0;
  # NOTE paths are not normalized, therefore different paths names
  # that refers to the same file will not be found.
  if (exists($self->{'opened_files'}->{$file_path})) {
    $overwritten_file = 1;
  }
  my $filehandle = do { local *FH };
  if (!open($filehandle, '>', $file_path)) {
    my $error_message = $!;
    return undef, $error_message, $overwritten_file;
  }
  # If $use_binmode is true, we run binmode to turn off outputting LF as CR LF
  # under MS-Windows, so that Info tag tables will have correct offsets.  This
  # must be done before setting the encoding filters with binmode.
  binmode($filehandle) if $use_binmode;
  if (defined($encoding)) {
    binmode($filehandle, ":encoding($encoding)");
  }
  if ($self) {
    if (exists($self->{'unclosed_files'}->{$file_path})) {
      warn "BUG: already open: $file_path\n";
    } else {
      $self->{'opened_files'}->{$file_path} = 1;
    }
    $self->{'unclosed_files'}->{$file_path} = $filehandle;
  }
  return $filehandle, undef, $overwritten_file;
}

# see the description of $SELF in comment above output_files_open_out.
#
# $FILE_PATH is the file path, it should be a binary string.
sub output_files_register_closed($$) {
  my ($self, $file_path) = @_;

  if (exists($self->{'unclosed_files'}->{$file_path})) {
    delete $self->{'unclosed_files'}->{$file_path};
  } else {
    cluck "BUG: $file_path not opened\n";
  }
}

# The next two functions should not be called from user-defined
# code, only from the main program.  They are defined here for
# consistency of the API and clarity of the code.
#
# see the description of $SELF in comment above output_files_open_out.
sub output_files_opened_files($) {
  my $self = shift;

  return $self->{'opened_files'};
}

# see the description of $SELF in comment above output_files_open_out.
sub output_files_unclosed_files($) {
  my $self = shift;

  return $self->{'unclosed_files'};
}
# end of output_files API



# TODO document?
# SELF is a converter or Texinfo::Text options hash
sub switch_lang_translations($$;$) {
  my ($self, $lang, $command_line_encoding) = @_;

  $lang = '' if (!defined($lang));

  if (exists($self->{'current_lang_translations'})
      and $self->{'current_lang_translations'}->[0] eq $lang) {
    # Nothing to do
    return;
  }

  my $translations;
  if (!exists($self->{'translations'})) {
    $translations = $Texinfo::Translations::translation_cache;
    $self->{'translations'} = $translations;
  } else {
    $translations = $self->{'translations'};
  }

  if (!exists($translations->{$lang})) {
    $translations->{$lang} = {};
  }

  my $new_lang_translations
    = Texinfo::Translations::new_lang_translation($lang,
                                      $command_line_encoding);
  $new_lang_translations->[2] = $translations->{$lang};
  $self->{'current_lang_translations'} = $new_lang_translations;
}



our @month_name =
    (
     Texinfo::Common::gdt('January'),
     Texinfo::Common::gdt('February'),
     Texinfo::Common::gdt('March'),
     Texinfo::Common::gdt('April'),
     Texinfo::Common::gdt('May'),
     Texinfo::Common::gdt('June'),
     Texinfo::Common::gdt('July'),
     Texinfo::Common::gdt('August'),
     Texinfo::Common::gdt('September'),
     Texinfo::Common::gdt('October'),
     Texinfo::Common::gdt('November'),
     Texinfo::Common::gdt('December')
    );

my %documentinfo_commands = ();
foreach my $cmdname ('title', 'subtitle', 'author') {
  $documentinfo_commands{$cmdname} = 1;
}

# TODO document
sub get_document_documentinfo($) {
  my $document = shift;

  my $global_commands = $document->global_commands_information();

  return undef if (!defined($global_commands));

  my $document_info = $global_commands->{'documentinfo'};

  return undef if (!defined($document_info));

  my $result;
  for (my $i = 1; $i < scalar(@{$document_info->{'contents'}}); $i++) {
    my $content = $document_info->{'contents'}->[$i];
    if (exists($content->{'cmdname'})) {
      my $cmdname = $content->{'cmdname'};
      if (exists($documentinfo_commands{$cmdname})) {
        $result = {} if (!defined($result));
        $result->{$cmdname} = [] if (!exists($result->{$cmdname}));
        push @{$result->{$cmdname}}, $content;
      }
    }
  }

  return $result;
}

# TODO document
sub get_titlepage_publication_info($) {
  my $document = shift;

  my $global_commands = $document->global_commands_information();

  return undef if (!defined($global_commands));

  my $result;

  my $document_info = get_document_documentinfo($document);

  if (defined($document_info)) {
    $result = $document_info;
  }

  foreach my $cmdname ('copying', 'publication') {
    if (exists($global_commands->{$cmdname})) {
      $result = {} if (!defined($result));
      $result->{$cmdname} = $global_commands->{$cmdname};
    }
  }
  return $result;
}

sub _comma_index_subentries_tree($$$);
sub _comma_index_subentries_tree($$$) {
  my ($current, $separator, $results) = @_;

  my $line_arg = $current->{'contents'}->[0];
  foreach my $content (@{$line_arg->{'contents'}}) {
    if (exists($content->{'cmdname'}) and $content->{'cmdname'} eq 'subentry') {
      push @$results, Texinfo::TreeElement::new({'text' => $separator,
                                               'type' => 'other_text'});
      _comma_index_subentries_tree($content, $separator, $results);
    } else {
      push @$results, $content;
    }
  }
}

# index sub-entries specified with @subentry, separated by commas, or by
# $SEPARATOR, if set
sub comma_index_subentries_tree($;$) {
  my ($current, $separator) = @_;

  $separator = ', ' if (!defined($separator));

  my @contents;
  # start with the first subentry in the index entry
  my $line_arg = $current->{'contents'}->[0];
  foreach my $content (@{$line_arg->{'contents'}}) {
    if (exists($content->{'cmdname'}) and $content->{'cmdname'} eq 'subentry') {
      push @contents, Texinfo::TreeElement::new({'text' => $separator,
                                                 'type' => 'other_text'});
      _comma_index_subentries_tree($content, $separator, \@contents);
    }
  }

  if (scalar(@contents)) {
    return Texinfo::TreeElement::new({'contents' => \@contents});
  }
  return undef;
}

sub definition_arguments_content($) {
  my $element = shift;

  my ($category, $class, $type, $name, $args);
  return ($category, $class, $type, $name, $args)
     if (!exists($element->{'contents'}->[0]->{'contents'}));

  my @args = @{$element->{'contents'}->[0]->{'contents'}};
  while (@args) {
    my $arg_type = $args[0]->{'type'};
    if ($arg_type eq 'def_category') {
      $category = shift @args;
    } elsif ($arg_type eq 'def_class') {
      $class = shift @args;
    } elsif ($arg_type eq 'def_type') {
      $type = shift @args;
    } elsif ($arg_type eq 'def_name') {
      $name = shift @args;
    } elsif ($arg_type eq 'def_arg' or $arg_type eq 'def_typearg'
             or $arg_type eq 'delimiter') {
      last;
    }
    shift @args;
  }
  if (scalar(@args) > 0) {
    $args = Texinfo::TreeElement::new({'contents' => \@args});
  }
  return ($category, $class, $type, $name, $args);
}

# $CONVERTER argument is optional.  It is not needed for translations,
# but it is needed to translate with a call to cdt, in case one want to
# use the cdt method of the specific converter and not the generic cdt,
# which is equivalent with the use of gdt in the function.  This should
# only be relevant for the HTML converter which redefines cdt.
sub definition_category_tree($;$$$$) {
  my ($current, $lang_translations, $command_line_encoding,
      $debug, $converter) = @_;

  return undef if (!exists($current->{'contents'}->[0]->{'contents'}));

  # NOTE we take care of not changing the parent of the tree elements.
  # We could also copy them and set the parent (as in the XS code).

  my $arg_category;
  my $arg_class;
  foreach my $arg (@{$current->{'contents'}->[0]->{'contents'}}) {
    my $type = $arg->{'type'};
    if ($type eq 'def_category') {
      $arg_category = $arg;
    } elsif ($type eq 'def_class') {
      $arg_class = $arg;
    } elsif ($type eq 'space') {
    } elsif ($type eq 'def_arg' or $type eq 'def_typearg'
             or $type eq 'delimiter') {
      last;
    }
  }

  return $arg_category
    if (!defined($arg_class));

  my $def_command = $current->{'extra'}->{'def_command'};
  if ($def_command eq 'defop'
      or $def_command eq 'deftypeop'
      or $def_command eq 'defmethod'
      or $def_command eq 'deftypemethod') {
    my $substrings = {'category' => $arg_category, 'class' => $arg_class};
    if (defined($converter)) {
      return $converter->cdt('{category} on @code{{class}}', $substrings);
    } elsif (defined($lang_translations)) {
      # TRANSLATORS: association of a method or operation category with a class
      # in descriptions of object-oriented programming methods or operations.
      my $tree = Texinfo::Translations::gdt('{category} on @code{{class}}',
                                            $lang_translations, $substrings,
                                            $debug);
    } else {
      my $new_lang_translations = Texinfo::Translations::new_lang_translation(
                                  $current->{'extra'}->{'documentlanguage'},
                                  $command_line_encoding);
      my $tree = Texinfo::Translations::gdt('{category} on @code{{class}}',
                                 $new_lang_translations, $substrings);
      return $tree;
    }
  } elsif ($def_command eq 'defivar'
           or $def_command eq 'deftypeivar'
           or $def_command eq 'defcv'
           or $def_command eq 'deftypecv') {
    my $substrings = {'category' => $arg_category, 'class' => $arg_class};
    if (defined($converter)) {
      return $converter->cdt('{category} of @code{{class}}', $substrings);
    } elsif (defined($lang_translations)) {
      # TRANSLATORS: association of a variable or instance variable with
      # a class in descriptions of object-oriented programming variables
      # or instance variable.
      return Texinfo::Translations::gdt('{category} of @code{{class}}',
                                        $lang_translations, $substrings,
                                        $debug);
    } else {
      my $new_lang_translations = Texinfo::Translations::new_lang_translation(
                                  $current->{'extra'}->{'documentlanguage'},
                                  $command_line_encoding);
      return Texinfo::Translations::gdt('{category} of @code{{class}}',
                                 $new_lang_translations, $substrings);
    }
  }
}

sub expand_today($;$$$) {
  my ($test, $lang_translations, $debug, $converter) = @_;

  if ($test) {
    return Texinfo::TreeElement::new({'text' => 'a sunny day'});
  }

  my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst)
    = ($ENV{SOURCE_DATE_EPOCH}
        ? gmtime($ENV{SOURCE_DATE_EPOCH})
        : localtime(time));
  # See https://reproducible-builds.org/specs/source-date-epoch/.

  $year += ($year < 70) ? 2000 : 1900;

  my $tree;

  if (defined($converter)) {
    $tree = $converter->cdt('{month} {day}, {year}',
          { 'month' => $converter->cdt(
                          $Texinfo::Convert::Utils::month_name[$mon]),
            'day' => Texinfo::TreeElement::new({'text' => $mday}),
            'year' => Texinfo::TreeElement::new({'text' => $year}) });
  } elsif (defined($lang_translations)) {
    my $month_tree
      = Texinfo::Translations::gdt($Texinfo::Convert::Utils::month_name[$mon],
                                   $lang_translations, 0, $debug);
    $tree = Texinfo::Translations::gdt('{month} {day}, {year}',
          $lang_translations,
          { 'month' => $month_tree,
            'day' => Texinfo::TreeElement::new({'text' => $mday}),
            'year' => Texinfo::TreeElement::new({'text' => $year}) },
           $debug);
  } else {
    $tree = Texinfo::TreeElement::new({'text' =>
             "$Texinfo::Convert::Utils::month_name[$mon] $mday, $year"});
  }
  return $tree;
}

sub translated_command_tree($$$$;$) {
  my ($translated_commands, $cmdname, $lang_translations, $debug,
      $converter) = @_;

  if (defined($translated_commands)
      and defined($translated_commands->{$cmdname})) {
    my $to_translate = $translated_commands->{$cmdname};
    if ($converter) {
      return $converter->cdt($to_translate);
    } else {
      return Texinfo::Translations::gdt($to_translate,
                             $lang_translations, 0, $debug);
    }
  }
  return undef;
}

# $CONVERTER is optional, but without this argument there is no error
# reporting.
sub expand_verbatiminclude($$$$$;$$) {
  my ($current, $include_directories, $input_file_name_encoding,
      $doc_encoding_for_input_file_name, $locale_encoding,
      $document, $converter) = @_;

  return undef unless (exists($current->{'extra'})
                       and exists($current->{'extra'}->{'text_arg'}));

  my $file_name_text = $current->{'extra'}->{'text_arg'};

  my $input_encoding
    = Texinfo::Common::associated_processing_encoding($current);

  my ($file_name, $file_name_encoding)
    = encoded_input_file_name($file_name_text, $input_file_name_encoding,
                  $doc_encoding_for_input_file_name, $locale_encoding,
                                          $document, $input_encoding);

  my $file = Texinfo::Common::locate_include_file($file_name,
                                                  $include_directories);

  my $verbatiminclude;

  if (defined($file)) {
    if (!open(VERBINCLUDE, $file)) {
      if (defined($converter)) {
        my $decoded_file = $file;
        # need to decode to the internal perl codepoints for error message
        $decoded_file = Encode::decode($file_name_encoding, $file)
           if (defined($file_name_encoding));
        $converter->converter_line_error(
                      sprintf(__("could not read %s: %s"), $decoded_file, $!),
                      $current->{'source_info'});
      }
    } else {
      if (defined($input_encoding)) {
        binmode(VERBINCLUDE, ":encoding($input_encoding)");
      }
      $verbatiminclude
        = Texinfo::TreeElement::new({ 'cmdname' => 'verbatim',
                                      'contents' => [],});
      while (<VERBINCLUDE>) {
        push @{$verbatiminclude->{'contents'}},
          Texinfo::TreeElement::new({'type' => 'raw', 'text' => $_ });
      }
      if (!close (VERBINCLUDE)) {
        if (defined($converter)) {
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
  } elsif (defined($converter)) {
    $converter->converter_line_error(
                           sprintf(__("\@%s: could not find %s"),
                                       $current->{'cmdname'}, $file_name_text),
                           $current->{'source_info'});
  }
  return $verbatiminclude;
}

sub add_heading_number($$;$$) {
  my ($current, $text, $numbered, $lang_translations) = @_;

  my $number;
  if (exists($current->{'extra'})
      and defined($current->{'extra'}->{'section_heading_number'})
      and ($numbered or !defined($numbered))) {
    $number = $current->{'extra'}->{'section_heading_number'};
  }

  my $result;
  if (defined($lang_translations)) {
    # NOTE we reach here when called from Texinfo::Convert::Text
    # only if associated with a converter.
    # There is a test especially crafted to reach that point in
    # convert_to_text.t
    if (defined($number)) {
      if ($current->{'cmdname'} eq 'appendix'
          and $current->{'extra'}->{'section_level'} == 1) {
        $result = Texinfo::Translations::gdt_string(
                    'Appendix {number} {section_title}', $lang_translations,
                    {'number' => $number, 'section_title' => $text});
      } else {
        $result = Texinfo::Translations::gdt_string(
                       '{number} {section_title}', $lang_translations,
                       {'number' => $number, 'section_title' => $text});
      }
    } else {
      $result = $text;
    }
  } else {
    $result = $text;
    $result = $number.' '.$result if (defined($number));
    if ($current->{'cmdname'} eq 'appendix'
        # in case structuring code was not called could be undef
        and defined($current->{'extra'}->{'section_level'})
        and $current->{'extra'}->{'section_level'} == 1) {
      $result = 'Appendix '.$result;
    }
  }
  return $result;
}

sub _find_element_authors_internal($$);

sub _find_element_authors_internal($$) {
  my ($element, $quotation_authors) = @_;

  return if (exists($element->{'text'}));

  if (exists($element->{'cmdname'})) {
    my $cmdname = $element->{'cmdname'};
    if ($cmdname eq 'author') {
      push @$quotation_authors, $element;
      return;
    }
    if ($cmdname eq 'quotation'
        or $cmdname eq 'smallquotation'
        or $cmdname eq 'titlepage'
        or $cmdname eq 'menu'
        or (exists($Texinfo::Commands::brace_commands{$cmdname})
            and $Texinfo::Commands::brace_commands{$cmdname} eq 'context')
        or exists($Texinfo::Commands::line_commands{$cmdname})) {
      return;
    }
  } elsif (exists($element->{'type'})
           and $element->{'type'} eq 'arguments_line') {
    return;
  }
  if (exists($element->{'contents'})) {
    foreach my $content (@{$element->{'contents'}}) {
      _find_element_authors_internal($content, $quotation_authors);
    }
  }
}

# TODO document.
# Find authors in element body.
sub find_element_authors($$) {
  my ($element, $quotation_authors) = @_;

  foreach my $content (@{$element->{'contents'}}) {
    _find_element_authors_internal($content, $quotation_authors);
  }
}

# Similar to Texinfo::Common::is_content_empty
# Unused
sub find_root_command_next_heading_command($$;$$) {
  my ($root, $expanded_format_raw, $do_not_ignore_contents,
      $do_not_ignore_index_entries) = @_;

  return undef if (!exists($root->{'contents'}));

  $expanded_format_raw = {} if (!defined($expanded_format_raw));

  foreach my $content (@{$root->{'contents'}}) {
    #print STDERR Texinfo::Common::debug_print_element($content)."\n";
    if (exists($content->{'cmdname'})) {
      if (exists(
           $Texinfo::Commands::sectioning_heading_commands{$content->{'cmdname'}})) {
        #print STDERR "HEADING FOUND ASSOCIATED $content->{'cmdname'}\n";
        return $content;
      }
      if (exists($content->{'type'})
          and $content->{'type'} eq 'index_entry_command') {
        if ($do_not_ignore_index_entries) {
          return undef;
        } else {
          next;
        }
      }
      if (exists($Texinfo::Commands::line_commands{$content->{'cmdname'}})) {
        if (exists(
              $Texinfo::Commands::formatted_line_commands{$content->{'cmdname'}})
            or exists(
                 $Texinfo::Commands::formattable_line_commands{$content->{'cmdname'}})
            or ($do_not_ignore_contents
                and ($content->{'cmdname'} eq 'contents'
                     or $content->{'cmdname'} eq 'shortcontents'
                     or $content->{'cmdname'} eq 'summarycontents'))) {
          return undef;
        } else {
          next;
        }
      } elsif (exists($Texinfo::Commands::nobrace_commands{$content->{'cmdname'}})) {
        if (exists(
            $Texinfo::Commands::formatted_nobrace_commands{$content->{'cmdname'}})) {
          return undef;
        } else {
          next;
        }
      } elsif (exists($Texinfo::Commands::block_commands{$content->{'cmdname'}})) {
        if (exists(
             $Texinfo::Commands::non_formatted_block_commands{$content->{'cmdname'}})
            or $Texinfo::Commands::block_commands{$content->{'cmdname'}} eq 'region'
            # ignored conditional
            or $Texinfo::Commands::block_commands{$content->{'cmdname'}} eq 'conditional'
            or ($Texinfo::Commands::block_commands{$content->{'cmdname'}} eq 'format_raw'
                and !$expanded_format_raw->{$content->{'cmdname'}})) {
          next;
        } else {
          return undef;
        }
      # brace commands
      } else {
        if (exists(
             $Texinfo::Commands::non_formatted_brace_commands{$content->{'cmdname'}})) {
          next;
        } else {
          return undef;
        }
      }
    }
    if (exists($content->{'type'})) {
      if ($content->{'type'} eq 'paragraph') {
        return undef;
      }
    }
    # normally should not happen at the top level as text at top
    # level should only contain spaces (empty lines, text before
    # paragraphs).
    if (exists($content->{'text'}) and $content->{'text'} =~ /\S/) {
      return undef;
    }
  }
  return undef;
}

# ALTIMP C/main/convert_utils.c
sub encoded_output_file_name($$$$;$) {
  my ($file_name, $output_file_name_encoding,
      $doc_encoding_for_output_file_name, $locale_encoding, $document) = @_;

  my $encoding;
  if (defined($output_file_name_encoding)) {
    $encoding = $output_file_name_encoding;
  } elsif ($doc_encoding_for_output_file_name) {
    my $document_info;

    if (defined($document)) {
      $document_info = $document->global_information();
    }

    $encoding = $document_info->{'input_encoding_name'}
      if (defined($document_info)
          and defined($document_info->{'input_encoding_name'}));
  } else {
    $encoding = $locale_encoding;
  }

  return Texinfo::Common::encode_file_name($file_name, $encoding);
}

# ALTIMP C/main/convert_utils.c
# The input file encoding can be given as $INPUT_FILE_ENCODING optional
# argument, it will be used if $DOC_ENCODING_FOR_INPUT_FILE_NAME is
# undef or set.
# Reverse the decoding of the file name from the input encoding.
sub encoded_input_file_name($$$$;$$) {
  my ($file_name, $input_file_name_encoding,
      $doc_encoding_for_input_file_name, $locale_encoding, $document,
      $input_file_encoding) = @_;

  my $encoding
    = Texinfo::Common::input_file_name_encoding($input_file_name_encoding,
                 $doc_encoding_for_input_file_name, $locale_encoding,
                           $document, $input_file_encoding);

  return Texinfo::Common::encode_file_name($file_name, $encoding);
}

1;

__END__

=head1 NAME

Texinfo::Convert::Utils - miscellaneous functions usable in all converters

=head1 SYNOPSIS

  use Texinfo::Convert::Utils;

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

Miscellaneous methods that may be useful for backends converting Texinfo
trees.  This module contains the methods that can be used in converters
which do not inherit from L<Texinfo::Convert::Converter>.

=head1 METHODS

No method is exported in the default case.

Some methods take an optional I<$converter> argument for error reporting, see
L<Texinfo::Convert::Converter/Registering error and warning messages>.  Even
when the caller does not inherit from L<Texinfo::Convert::Converter>, it could
implement the required interfaces and could also have a converter available in
some cases, to call the functions with the converter argument set.

=over

=item $result = add_heading_number($heading_element, $heading_text, $do_number, $lang_translations)
X<C<add_heading_number>>

I<$heading_element> is a heading command tree element.  I<$heading_text> is the
already formatted heading text.  if the I<$do_number> optional argument is
defined and false, no number is used and the text is returned as is.  The
I<$lang_translations> optional argument should be an array reference with one
or two elements.  The first element of the array is the language the resulting
string is translated to.  The second element, if set, should be an hash
reference holding translations already done.  If a language is set in
I<$lang_translations>, the string is translated and the optional I<$debug>
argument is passed to the translation function.

This function returns the heading with a number and the appendix part if
needed.

=item $contents_element = comma_index_subentries_tree($entry, $separator)
X<C<comma_index_subentries_tree>>

I<$entry> is a Texinfo tree index entry element. The function sets up
an array with the C<@subentry> contents.  The result is returned as
C<contents> in the I<$contents_element> element, or C<undef> if there is no
such content.  I<$separator> is an optional separator argument used, if given,
instead of the default: a comma followed by a space.

=item ($category, $class, $type, $name, $arguments) = definition_arguments_content($element)
X<C<definition_arguments_content>>

I<$element> should be a C<@def*> Texinfo tree element.  The
I<$category>, I<$class>, I<$type>, I<$name> are elements corresponding
to the definition @-command line.  Texinfo elements
on the @-command line corresponding to arguments in the function
definition are returned in the I<$arguments> element.
Arguments correspond to text following the other elements
on the @-command line.  If there is no argument, I<$arguments>
will be C<undef>.

=item $tree = definition_category_tree($def_line, $lang_translations, $command_line_encoding, $debug, $converter)
X<C<definition_category_tree>>

I<$def_line> is a C<def_line> Texinfo tree container.  This function returns a
Texinfo tree corresponding to the category of the I<$def_line> taking the class
into account, if there is one.  The I<$lang_translations> optional argument
should be an array reference holding information on the current language and
translations.  It could be obtained from the converter
C<current_lang_translations> or be setup by a call to
L<< C<Texinfo::Translations::new_lang_translation>|Texinfo::Translations/$lang_translations = new_lang_translation($lang, $locale_encoding) >>.
If I<$lang_translations> is set,
I<$command_line_encoding> should be set to the encoding suitable for
environment variables, usually obtained from the I<COMMAND_LINE_ENCODING>
customization variable, and the optional I<$debug> argument is passed to the
translation function.  If the optional I<$converter> argument is set, the
translation is done by a converter method.  In that case, I<$lang_translations>
and I<$debug> are ignored, the converter method uses similar converter
information.

=item ($encoded_name, $encoding) = encoded_input_file_name($character_string_name, $input_file_name_encoding, $doc_encoding_for_input_file_name, $locale_encoding, $document, $input_file_encoding)

=item ($encoded_name, $encoding) = encoded_output_file_name($character_string_name, $output_file_name_encoding, $doc_encoding_for_output_file_name, $locale_encoding, $document)

X<C<encoded_input_file_name>> X<C<encoded_output_file_name>>

C<encoded_input_file_name> encodes I<$character_string_name> as an input file
name.  If I<$doc_encoding_for_input_file_name> is set, the encoding is based on
the input file content encoding, otherwise I<$locale_encoding> is used.  The
I<$document> argument is an optional Texinfo parsed document used to get the
input document content encoding.  C<encoded_output_file_name> encodes
I<$character_string_name> as an output file name and takes similar arguments.
Return the encoded name and the encoding used to encode the name.

The I<$input_file_encoding> argument is optional and only available for
C<encoded_input_file_name>.  If set, it is used for the input file encoding.
It is useful if there is more precise information on the input file encoding
where the file name appeared.

=item $tree = expand_verbatiminclude($verbatiminclude, $include_directories, $name_encoding, $doc_encoding_for_input_file_name, $locale_encoding, $document, $converter)
X<C<expand_verbatiminclude>>

I<$verbatiminclude> is a C<@verbatiminclude> tree element.
I<$include_directories> is an array
reference with include directories where the file specified as
C<@verbatiminclude> argument is searched for.
I<$name_encoding>, I<$doc_encoding_for_input_file_name>, I<$locale_encoding>
and I<$document> are L<< C<encoded_input_file_name> arguments|/($encoded_name,
$encoding) = encoded_input_file_name($character_string_name,
$input_file_name_encoding, $doc_encoding_for_input_file_name, $locale_encoding,
$document, $input_file_encoding) >>.  The optional I<$converter>
argument is used to output error messages.  This function returns a
C<@verbatim> tree elements after finding the included file and reading it.

=begin comment

=item $heading_element = find_root_command_next_heading_command($element, $expanded_format_raw, $do_not_ignore_contents, $do_not_ignore_index_entries)

Return an heading element found in the I<$element> contents if it
appears before contents that could be formatted.  I<$expanded_format_raw>
is a hash reference with raw output formats (html, docbook, xml...) as
keys, associated value should be set for expanded raw output formats.
I<$do_not_ignore_contents> is optional.  If set, C<@contents> and
C<@shortcontents> are considered to be formatted.
I<$do_not_ignore_index_entries> is optional.  If set, index entries
are considered to be formatted.

Only heading elements corresponding to C<@heading>, C<@subheading> and similar
@-commands that are not associated to nodes in general are found, not
sectioning commands.

=end comment

=item $documentinfo_info = get_document_documentinfo($document)
X<C<get_document_documentinfo>>

I<$document> is a Texinfo parsed document.  If C<@documentinfo> is found
in the document, return an hash reference with
@-command names appearing in C<@documentinfo> as keys associated to
an array reference as value containing the @-commands Texinfo tree elements.
Otherwise, returns C<undef>.

=back

=head1 SEE ALSO

L<Texinfo::Common>, L<Texinfo::Convert::Converter> and L<Texinfo::Translations>.

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
