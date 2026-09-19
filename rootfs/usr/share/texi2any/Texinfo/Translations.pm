# Translations.pm: translate strings in output.
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
# ALTIMP C/main/translations.c

# This code is used for output documents strings translations, not for
# error messages translations.

package Texinfo::Translations;

use 5.006;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Encode;
use POSIX qw(setlocale LC_ALL LC_MESSAGES);
use Carp qw(cluck confess);

sub fake_setlocale { return "en_US.UTF-8"; }
BEGIN {
  if ($^O eq 'openbsd') {
    # It appears impossible for POSIX::setlocale(LC_MESSAGES, ...) to return
    # anything but "C" on OpenBSD, which breaks translations of document
    # strings.
    # Overriding this here means that Locale::Messages uses our fake version
    # and enables translations.
    no warnings;
    *POSIX::setlocale = \&fake_setlocale;
  }
}

use Locale::Messages;

use Storable qw(dclone);

use Texinfo::XSLoader;

use Texinfo::TreeElement;

# for __()
use Texinfo::Common;

# note that there is a circular dependency with the parser module, as
# the parser uses complete_indices() from this modules, while this module
# uses a parser.  This is not problematic, however, as the
# modules do not setup data such that their order of loading is not
# important, as long as they load after their dependencies.

use Texinfo::DocumentXS;

use Texinfo::Convert::Unicode;

# to load a parser
use Texinfo::Parser;

use Texinfo::ManipulateTree;

our $VERSION = '7.3';

my $XS_parser = Texinfo::XSLoader::XS_parser_enabled();

# we want a reliable way to switch locale for the document
# strings translations so we don't use the system gettext.
Locale::Messages->select_package ('gettext_pp');

our $module_loaded = 0;
sub import {
  if (!$module_loaded) {
    if ($XS_parser) {
      Texinfo::XSLoader::override(
        "Texinfo::Translations::_XS_configure",
        "Texinfo::DocumentXS::configure_output_strings_translations");
    }
    $module_loaded = 1;
  }
  # The usual import method
  goto &Exporter::import;
}

# i18n

my $messages_textdomain = 'texinfo';
my $strings_textdomain = 'texinfo_document';

sub _XS_configure($;$$) {
  # do nothing if there is no XS code loaded
}

sub configure($;$) {
  my ($localesdir, $in_strings_textdomain) = @_;

  if (defined($in_strings_textdomain)) {
    $strings_textdomain = $in_strings_textdomain;
  }
  if (defined($localesdir)) {
    Locale::Messages::bindtextdomain($strings_textdomain, $localesdir);
    # set the directory for the XS code too
    _XS_configure($localesdir, $strings_textdomain);
  } else {
    warn 'WARNING: string textdomain directory undefined'."\n";
  }
}

# libintl converts between encodings but doesn't decode them into the
# perl internal format.
sub _decode_i18n_string($$) {
  my ($string, $encoding) = @_;

  #if (!defined($encoding)) {
  #  confess("_decode_i18n_string $string undef encoding\n");
  #}
  return Encode::decode($encoding, $string);
}

my $working_locale;

my $no_local_found_error_output;

sub _switch_messages_locale() {
  my $locale;

  if (defined($working_locale)) {
    $locale = POSIX::setlocale(LC_MESSAGES, $working_locale);
  }
  if (!defined($locale)) {
    $locale = POSIX::setlocale(LC_MESSAGES, "en_US.UTF-8");
  }
  if (!defined($locale)) {
    $locale = POSIX::setlocale(LC_MESSAGES, "en_US")
  }
  # try the output of 'locale -a' (but only once)
  our $locale_command;
  if (!defined($locale) and !defined($locale_command)) {
    # we ignore the errors as we have a more general warning message below
    # and we are not really interested by locale errors
    $locale_command = "locale -a 2>/dev/null";
    my @local_command_locales = split("\n", `$locale_command`);
    if ($? == 0) {
      foreach my $try (@local_command_locales) {
        # Exclude "C", "C.UTF-8" (or similar) and "POSIX"
        next if $try eq 'C' or $try eq 'POSIX' or $try =~ /^C\./;
        $locale = POSIX::setlocale(LC_MESSAGES, $try);
        last if (defined($locale));
      }
    }
  }
  if (defined($locale)) {
    # NOTE according to perllocale on the setlocal return value:
    #  "on some platforms the string is opaque, not something that most
    #   people would be able to decipher as to what locale it means"
    # Therefore, the following comparisons may not be useful on those
    # platforms.
    if ($locale ne 'C' and $locale ne 'POSIX' and $locale !~ /^C\./) {
      $working_locale = $locale;
    } elsif (!defined($working_locale)) {
      # There is no access to converter/document/... so the warning
      # is unconditionally output here and now.  This may be
      # annoying if the user cannot fix the issue, but let's wait for
      # actual cases
      warn
  __("Cannot switch to a locale compatible with document strings translations")."\n";
      $working_locale = $locale;
    }
  } else {
    if (!$no_local_found_error_output) {
      warn
    __("Cannot find a locale compatible with document strings translations")."\n";
      $no_local_found_error_output = 1;
    }
  }
}

# TODO document?
# LANG should not be undef nor an empty string.
sub translate_string($$$;$) {
  my ($string, $lang, $encoded_lang, $translation_context) = @_;

  my ($saved_LC_MESSAGES, $saved_LANGUAGE);

  # We need to set LC_MESSAGES to a valid locale other than "C" or "POSIX"
  # for translation via LANGUAGE to work.  (The locale is "C" if the
  # tests are being run.)
  #   LC_MESSAGES was reported not to exist for Perl on MS-Windows.  We
  # could use LC_ALL instead, but (a) it's not clear if this would help,
  # and (b) this could interfere with the LC_CTYPE setting in XSParagraph.

  if ($^O ne 'MSWin32') {
    $saved_LC_MESSAGES = POSIX::setlocale(LC_MESSAGES);
    _switch_messages_locale();
  }
  $saved_LANGUAGE = $ENV{'LANGUAGE'};

  Locale::Messages::textdomain($strings_textdomain);

  Locale::Messages::bind_textdomain_codeset($strings_textdomain, 'UTF-8');
  Locale::Messages::bind_textdomain_filter($strings_textdomain,
                          \&_decode_i18n_string, 'UTF-8');
  # Previously we used the encoding used for input or output to be converted
  # to and then decoded to the perl internal encoding.  But it should be safer
  # to use UTF-8 as we cannot know in advance if the encoding actually used
  # is compatible with the specified encoding, while it should be compatible
  # with UTF-8.  If there are actually characters that cannot be encoded in the
  # output encoding issues will still show up when encoding to output, though.
  # Should be more similar with code used in XS modules, too.
  # As a side note, the best could have been to directly decode using the
  # charset used in the po/gmo files, but it does not seems to be available.

  my @langs = ($encoded_lang);
  # TODO use /a modifier?
  if ($encoded_lang =~ /^([a-z]+)_([A-Z]+)/) {
    my $main_lang = $1;
    my $region_code = $2;
    push @langs, $main_lang;
  }

  my $locales = join(':', @langs);

  Locale::Messages::nl_putenv("LANGUAGE=$locales");

  my $translated_string;
  if (defined($translation_context)) {
    $translated_string = Locale::Messages::pgettext($translation_context,
                                                     $string);
  } else {
    $translated_string = Locale::Messages::gettext($string);
  }

  Locale::Messages::textdomain($messages_textdomain);

  if (!defined($saved_LANGUAGE)) {
    delete ($ENV{'LANGUAGE'});
  } else {
    $ENV{'LANGUAGE'} = $saved_LANGUAGE;
  }

  if ($^O ne 'MSWin32') {
    if (defined($saved_LC_MESSAGES)) {
      POSIX::setlocale(LC_MESSAGES, $saved_LC_MESSAGES);
    } else {
      POSIX::setlocale(LC_MESSAGES, '');
    }
  }

  return $translated_string;
}

sub new_lang_translation($;$) {
  my ($lang, $locale_encoding) = @_;

  my $encoded_lang;
  if (defined($lang) and defined($locale_encoding)) {
    $encoded_lang = Encode::encode($locale_encoding, $lang);
  } else {
    $encoded_lang = $lang;
  }
  return [$lang, $encoded_lang];
}

# Cache translations in a hash to avoid having to go through the locale
# system rigmarole every time.
our $translation_cache = {};

# Return an array reference with a translated string.
# The LANG_TRANSLATIONS argument is an array reference with the language
# translated to as first element, and as optional second element an hash
# that is used to hold translations already done for that language.
# If the language is undef or an empty string, no translation is needed.
sub cache_translate_string($$;$) {
  my ($string, $lang_translations, $translation_context) = @_;

  #if (!defined($string)) {
  #  confess("cache_translate_string: undef string\n");
  #}
  my $lang;
  my $encoded_lang;
  my $translations;
  if (defined($lang_translations)) {
    $lang = $lang_translations->[0];
    $encoded_lang = $lang_translations->[1];
    if (scalar(@$lang_translations) > 2) {
      $translations = $lang_translations->[2];
    }
  }

  if (!defined($lang)) {
    $lang = '';
    $encoded_lang = '';
  }

  if (!defined($encoded_lang)) {
    cluck("cache_translate_string '$lang' encoded_lang undef");
  }

  my $translation_context_str;
  if (defined($translation_context)) {
    $translation_context_str = $translation_context;
  } else {
    $translation_context_str = '';
  }
  my $strings_cache;
  # use default translated string and tree cache if none was passed
  if (!defined($translations)) {
    if (!exists($translation_cache->{$lang})) {
      $translation_cache->{$lang} = {}
    }
    $translations = $translation_cache->{$lang};
  }

  if (exists($translations->{$translation_context_str})) {
    if (exists($translations->{$translation_context_str}->{$string})) {
      # return cached translation and tree
      return $translations->{$translation_context_str}->{$string};
    }
  } else {
    $translations->{$translation_context_str} = {};
  }

  $strings_cache = $translations->{$translation_context_str};

  # no translation, but still needed to setup caching for the associated
  # tree
  if ($lang eq '') {
    my $result = [undef];
    $strings_cache->{$string} = $result;
    return $result;
  }

  my $translated_string = translate_string($string, $lang, $encoded_lang,
                                           $translation_context);

  my $result = [$translated_string];

  $strings_cache->{$string} = $result;

  #print STDERR "_GDT '$string' '$translated_string'\n";
  return $result;
}

# Get document translation - handle translations of in-document strings.
# Return a parsed Texinfo tree.
# The LANG_TRANSLATIONS argument is an array reference with the language
# translated to as first element, and as optional second element an hash
# that is used to hold translations already done for that language.
# If the language is undef or an empty string, no translation is needed.
# NOTE If called from a converter, the language will in general be set from
# the document documentlanguage when it is encountered.  Before the first
# @documentlanguage, it depends on the converter.  Some do not set
# @documentlanguage before it is encountered, some set based on
# @documentlanguage if in the preamble.
# $TRANSLATED_STRING_METHOD is optional.  If set, it is called instead
# of cache_translate_string.  $TRANSLATED_STRING_METHOD takes
# $CUSTOMIZATION_INFORMATION as first argument in addition to other
# cache_translate_string arguments.
sub gdt($;$$$$$$) {
  my ($string, $lang_translations, $replaced_substrings, $debug_level,
      $translation_context, $customization_information,
      $translate_string_method) = @_;

  my $result_tree;
  my $translated_string_tree;
  if (defined($translate_string_method)) {
    $translated_string_tree
           = &$translate_string_method($customization_information,
                                       $string, $lang_translations,
                                       $translation_context);

  } else {
    $translated_string_tree
     = cache_translate_string($string, $lang_translations,
                              $translation_context);
  }

  if (scalar(@$translated_string_tree) == 1) {
    my $translated_string = $translated_string_tree->[0];
    $translated_string = $string if (!defined($translated_string));
    # No need to convert this more than once as we should get the same
    # every time.  Cache the non-substituted tree in translated_string_tree.
    my $tree
      = _replace_convert_substrings($translated_string, $replaced_substrings,
                                    $debug_level);
    push @$translated_string_tree, $tree;

    # remove parents in translated string tree, to avoid cycles such that
    # this part of the tree is destroyed as soon as the tree root is
    # out of scope.
    Texinfo::ManipulateTree::tree_remove_parents($tree);
  }

  $result_tree = dclone($translated_string_tree->[1]);

  if (defined($replaced_substrings)) {
    $result_tree = _substitute_substrings_in_tree($result_tree,
                                                  $replaced_substrings);
  }

  if ($debug_level) {
    my $translated_string = $translated_string_tree->[0];
    $translated_string = $string if (!defined($translated_string));

    print STDERR "RESULT GDT: '$string' '$translated_string' ".
       Texinfo::Convert::Texinfo::convert_to_texinfo($result_tree)."'\n";
  }
  return $result_tree;
}

# Get document translation - handle translations of in-document strings.
# In general for already converted strings that do not need to go through
# a Texinfo tree.
sub gdt_string($;$$$$$) {
  my ($string, $lang_translations, $replaced_substrings, $translation_context,
      $customization_information, $translate_string_method) = @_;

  my $translated_string;
  if (defined($translate_string_method)) {
    $translated_string
           = &$translate_string_method($customization_information,
                                       $string, $lang_translations,
                                       $translation_context);
  } else {
    $translated_string = cache_translate_string($string, $lang_translations,
                                                $translation_context);
  }

  my $converted_string = $translated_string->[0];
  $converted_string = $string if (!defined($converted_string));
  return _replace_substrings ($converted_string, $replaced_substrings);
}

sub _replace_substrings($;$) {
  my ($translated_string, $replaced_substrings) = @_;

  my $translation_result = $translated_string;

  if (defined($replaced_substrings) and ref($replaced_substrings) ne '') {
    my $re = join '|', map { quotemeta $_ } keys %$replaced_substrings;
    $translation_result
  =~ s/\{($re)\}/defined $replaced_substrings->{$1} ? $replaced_substrings->{$1} : "{$1}"/ge;
  }
  return $translation_result;
}

sub _replace_convert_substrings($;$$) {
  my ($translated_string, $replaced_substrings, $debug_level) = @_;

  my $texinfo_line = $translated_string;

  # we change the substituted brace-enclosed strings to internal
  # values marked by @txiinternalvalue such that their location
  # in the Texinfo tree can be marked.  They are substituted
  # after the parsing in the final tree.
  # Using a special command that is invalid unless a special
  # configuration is set means that there should be no clash
  # with @-commands used in translations.
  if (defined($replaced_substrings) and ref($replaced_substrings) ne '') {
    my $re = join '|', map { quotemeta $_ } keys %$replaced_substrings;
    $texinfo_line =~ s/\{($re)\}/\@txiinternalvalue\{$1\}/g;
  }

  # accept @txiinternalvalue as a valid Texinfo command, used to mark
  # location in tree of substituted brace enclosed strings.
  my $parser_conf = {'accept_internalvalue' => 1,
           # Ignore index and user-defined commands.
                     'NO_INDEX' => 1,
                     'NO_USER_COMMANDS' => 1,};

  # set parser debug level to one less than $debug_level
  if (defined($debug_level)) {
    my $parser_debug_level = $debug_level;
    if ($parser_debug_level > 0) {
      $parser_debug_level--;
    }
    $parser_conf->{'DEBUG'} = $parser_debug_level;
  }
  my $parser = Texinfo::Parser::parser($parser_conf);

  if ($debug_level) {
    print STDERR "IN TR PARSER '$texinfo_line'\n";
  }

  my $tree = $parser->parse_texi_line($texinfo_line, undef, 1);
  my $errors = $parser->errors();
  my $errors_count = Texinfo::Report::count_errors($errors);
  if ($errors_count) {
    warn "translation $errors_count error(s)\n";
    warn "translated string: $translated_string\n";
    warn "Error messages: \n";
    foreach my $error_message (@$errors) {
      warn $error_message->{'error_line'};
    }
  }

  return $tree;
}

sub _substitute_substrings_in_tree($$);
sub _substitute_element_array($$) {
  my ($array, $replaced_substrings) = @_;

  my $nr = scalar(@$array);

  for (my $idx = 0; $idx < $nr; $idx++) {
    my $element = $array->[$idx];
    if (!exists($element->{'text'})) {
      if (exists($element->{'cmdname'})
          and $element->{'cmdname'} eq 'txiinternalvalue') {
        my $name = $element->{'contents'}->[0]->{'contents'}->[0]->{'text'};
        if (exists($replaced_substrings->{$name})) {
          if ($replaced_substrings->{$name}->{'tree_document_descriptor'}) {
            Texinfo::Document::build_tree($replaced_substrings->{$name});
          }
          $array->[$idx] = $replaced_substrings->{$name};
        }
      } else {
        _substitute_substrings_in_tree($element, $replaced_substrings);
      }
    }
  }
}

# Recursively substitute @txiinternalvalue elements in $TREE with
# their values given in $REPLACED_SUBSTRINGS.
sub _substitute_substrings_in_tree($$) {
  my ($tree, $replaced_substrings) = @_;

  if (exists($tree->{'contents'})) {
    _substitute_element_array($tree->{'contents'}, $replaced_substrings);
  }

  return $tree;
}

# Same as gdt but with mandatory translation context, used for marking
# of strings with translation contexts
sub pgdt($$;$$$$$) {
  my ($translation_context, $string,
      $lang_translations, $replaced_substrings, $debug_level,
      $customization_information, $translate_string_method) = @_;

  return gdt($string, $lang_translations, $replaced_substrings, $debug_level,
             $translation_context, $customization_information,
             $translate_string_method);
}

my $lang_translations = {};

# For some @def* commands, we delay storing the contents of the
# index entry until now to avoid needing Texinfo::Translations::gdt
# in the main code of ParserNonXS.pm.
sub complete_indices($;$$) {
  my ($index_names, $command_line_encoding, $debug_level) = @_;

  my $current_lang;
  my $current_lang_translations;

  foreach my $index_name (sort(keys(%{$index_names}))) {
    next if (not exists($index_names->{$index_name}->{'index_entries'}));
    foreach my $entry (@{$index_names->{$index_name}->{'index_entries'}}) {
      my $main_entry_element = $entry->{'entry_element'};
      if (exists($main_entry_element->{'extra'})
          and exists($main_entry_element->{'extra'}->{'def_command'})
          and
           not exists($main_entry_element->{'extra'}->{'def_index_element'})) {
        my ($name, $class);
        if (exists($main_entry_element->{'contents'}->[0]->{'contents'})) {
          foreach my $arg (@{$main_entry_element->{'contents'}->[0]->{'contents'}}) {
            my $type = $arg->{'type'};
            if ($type eq 'def_name') {
              $name = $arg;
            } elsif ($type eq 'def_class') {
              $class = $arg;
            } elsif ($type eq 'def_arg' or $type eq 'def_typearg'
                     or $type eq 'delimiter') {
              last;
            }
          }
        }

        if (defined($name) and defined($class)) {
          my ($index_entry, $text_element);
          my $index_entry_normalized = Texinfo::TreeElement::new({});

          my $def_command = $main_entry_element->{'extra'}->{'def_command'};

          my $class_copy = Texinfo::ManipulateTree::copy_treeNonXS($class);
          my $name_copy = Texinfo::ManipulateTree::copy_treeNonXS($name);
          my $ref_class_copy = Texinfo::ManipulateTree::copy_treeNonXS($class);
          my $ref_name_copy = Texinfo::ManipulateTree::copy_treeNonXS($name);
          foreach my $element_copy ($class_copy, $name_copy, $ref_class_copy,
                                    $ref_name_copy) {
            delete $element_copy->{'type'};
            if (exists($element_copy->{'contents'})
                and exists($element_copy->{'contents'}->[0]->{'type'})
            # use brace_arg instead of bracketed_arg to avoid specific def
            # type for the conversion of the index entry, but still have
            # a type that have the same memory layout as bracketed_arg for C
            and $element_copy->{'contents'}->[0]->{'type'} eq 'bracketed_arg') {
              $element_copy->{'contents'}->[0]->{'type'} = 'brace_arg';
            }
          }

          # Use the document language that was current when the command was
          # used for getting the translation.
          my $entry_language
             = $main_entry_element->{'extra'}->{'documentlanguage'};
          $entry_language = '' if (!defined($entry_language));
          if (!defined($current_lang)
              or $entry_language ne $current_lang) {
            if (!exists($lang_translations->{$entry_language})) {
              $lang_translations->{$entry_language} = {};
            }
            $current_lang_translations
              = new_lang_translation($entry_language, $command_line_encoding);
            $current_lang_translations->[2]
              = $lang_translations->{$entry_language};
          }
          if ($def_command eq 'defop'
              or $def_command eq 'deftypeop'
              or $def_command eq 'defmethod'
              or $def_command eq 'deftypemethod') {
  # TRANSLATORS: association of a method or operation name with a class
  # in descriptions of object-oriented programming methods or operations.
            $index_entry = gdt('{name} on {class}', $current_lang_translations,
                               {'name' => $name_copy, 'class' => $class_copy},
                               $debug_level);
            $text_element = Texinfo::TreeElement::new({'text' => ' on '});
          } elsif ($def_command eq 'defcv'
                   or $def_command eq 'defivar'
                   or $def_command eq 'deftypeivar'
                   or $def_command eq 'deftypecv') {
  # TRANSLATORS: association of a variable or instance variable with
  # a class in descriptions of object-oriented programming variables or
  # instance variable.
            $index_entry = gdt('{name} of {class}',
                               $current_lang_translations,
                               {'name' => $name_copy, 'class' => $class_copy},
                               $debug_level);
            $text_element = Texinfo::TreeElement::new({'text' => ' of '});
          }
          $ref_name_copy->{'parent'} = $index_entry_normalized;
          $ref_class_copy->{'parent'} = $index_entry_normalized;
          $index_entry_normalized->{'contents'}
              = [$ref_name_copy, $text_element, $ref_class_copy];

          # prefer a type-less container rather than 'root_line' returned by gdt
          delete $index_entry->{'type'};

          $main_entry_element->{'extra'}->{'def_index_element'} = $index_entry;
          $main_entry_element->{'extra'}->{'def_index_ref_element'}
                                                  = $index_entry_normalized;
        }
      }
    }
  }
}



1;

__END__

=head1 NAME

Texinfo::Translations - Translations of output documents strings for Texinfo modules

=head1 SYNOPSIS

  @ISA = qw(Texinfo::Translations);

  Texinfo::Translations::configure('LocaleData');

  my $tree_translated
    = Texinfo::Translations::gdt('See {reference} in @cite{{book}}',
                           [$converter->get_conf('documentlanguage')],
                          {'reference' => $tree_reference,
                           'book'  => {'text' => $book_name}});


=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

The C<Texinfo::Translations> module helps with translations
in output documents.

Translation of error messages is not described here, some
elements are in L<Texinfo::Common C<__> and C<__p>|Texinfo::Common/$translated_string = __($msgid)>.

=head1 METHODS

No method is exported.

The C<configure> method sets the translation files base directory.  If not
called, system defaults are used.

=over

=item configure($localesdir, $strings_textdomain)

I<$localesdir> is the directory where translation files are found. The
directory structure and files format should follow the L<conventions expected
for gettext based
internationalization|https://www.gnu.org/software/gettext/manual/html_node/Locating-Catalogs.html>.
The I<$strings_textdomain> is optional, if set, it determines the translation
domain.

=back

The C<new_lang_translation> method sets up a lang translation object that
is used as argument inthe other method, that contains the language and
associated already translated strings.

=over

=item $lang_translations = new_lang_translation($lang, $locale_encoding)
X<C<new_lang_translation>>

I<$lang> is the language of the returned lang translations.  I<$locale>
encoding is optional and should be the encoding used to encode character
strings to for environment variables.  In general, you should base it on
the I<COMMAND_LINE_ENCODING> customization variable value.

The returned I<$lang_translations> is an array reference.  The first element of
the array is the language.  The second element is the language encoded to the
local encoding.  The third element should be set to an hash reference holding
translations already done.


=back

The C<gdt> and C<pgdt> methods are used to translate strings to be output in
converted documents, and return a Texinfo tree.  The C<gdt_string> is similar
but returns a simple string, for already converted strings.

=over

=item $tree = gdt($string, $lang_translations, $replaced_substrings, $translation_context, $debug_level, $object, $translate_string_method)

=item $string = gdt_string($string, $lang_translations, $replaced_substrings, $translation_context, $object, $translate_string_method)

X<C<gdt>> X<C<gdt_string>>

The I<$string> is a string to be translated.  With C<gdt>
the function returns a Texinfo tree, as the string is interpreted
as Texinfo code after translation.  With C<gdt_string> a string
is returned.

The I<$lang_translations>
argument should be an array reference with one or two elements.  The first
element of the array is the language used for the translation.  The second
element, if set, should be an hash reference holding translations already done.

I<$replaced_substrings> is an optional hash reference specifying
some substitution to be done after the translation.  The key of the
I<$replaced_substrings> hash reference identifies what is to be substituted.
In the string to be translated word in brace matching keys of
I<$replaced_substrings> are replaced.
For C<gdt>, the value is a Texinfo tree element that is substituted in the
resulting Texinfo tree. For C<gdt_string>, the value is a string that
is replaced in the resulting string.

I<$debug_level> is an optional debugging level supplied to C<gdt>, similar to
the C<DEBUG> customization variable.  If set, the debug level minus one is
passed to the Texinfo string parser called in C<gdt>.

The I<$translation_context> is optional.  If not C<undef> this is a translation
context string for I<$string>.  It is the first argument of C<pgettext>
in the C API of Gettext.

For example, in the following call, the string
C<See {reference} in @cite{{book}}> is translated, then
parsed as a Texinfo string, with I<{reference}> substituted by
I<$tree_reference> in the resulting tree, and I<{book}>
replaced by the associated Texinfo tree text element:

  $tree = gdt('See {reference} in @cite{{book}}', ['ca'],
              {'reference' => $tree_reference,
               'book'  => {'text' => $book_name}});

By default, C<gdt> and C<gdt_string> call C<cache_translate_string> to use a
gettext-like infrastructure to retrieve the translated strings, using the
I<texinfo_document> domain.  You can change the method used to retrieve the
translated strings by providing a I<$translate_string_method> argument.  If not
undef it should be a reference on a function that is called instead of
C<cache_translate_string>.  The I<$object> is passed as first argument of the
I<$translate_string_method>, the other arguments are the same as
L<< C<cache_translate_string>|/$translated_string_tree = cache_translate_string($string, $lang_translations, $translation_context) >>
arguments.

=item $tree = pgdt($translation_context, $string, $lang_translations, $replaced_substrings, $debug_level, $object, $translate_string_method)
X<C<pgdt>>

Same to C<gdt> except that the I<$translation_context> is not optional.
Calls C<gdt>.  This function is useful to mark strings with a
translation context for translation.  This function is similar to pgettext
in the Gettext C API.

=back

By default, in C<gdt>, C<gdt_string> and C<pgdt> a string is translated with
C<cache_translate_string>.

=over

=item $translated_string_tree = cache_translate_string($string, $lang_translations, $translation_context)
X<C<cache_translate_string>>

The I<$string> is a string to be translated.  The I<$lang_translations>
argument should be an array reference with one or two elements.  The first
element of the array is the language used for the translation.  The second
element, if set, should be an hash reference holding translations already done.
If the language is C<undef> or an empty string, the input string does not
need to be translated.  The I<$translation_context> is optional.  If not
C<undef> this is a translation context string for I<$string>.  It is the first
argument of C<pgettext> in the C API of Gettext.

C<cache_translate_string> uses a gettext-like infrastructure to retrieve the
translated strings, using the I<texinfo_document> domain.  Returns an array
reference with the translated string as first element, or undef if the
input string should be used as translation.  The second element of the
reference array, if present, should be the Texinfo tree corresponding to
the translated string, without the braced arguments substituted.

=back

=head1 SEE ALSO

L<GNU gettext utilities manual|https://www.gnu.org/software/gettext/manual/>.

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
