# Unicode.pm: handle conversion to unicode.
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

package Texinfo::Convert::Unicode;

# Documentation of earlier releases for perluniintro is missing.
# charnames::vianame is not documented in 5.6.0.
use 5.008;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Carp qw(cluck);

use Encode;
use Unicode::Normalize;
use Unicode::EastAsianWidth;
# To obtain unicode characters based on code points represented as
# strings
use charnames ();

use Texinfo::XSLoader;
use Texinfo::MiscXS;

use Texinfo::CommandsValues;
use Texinfo::UnicodeData;

require Exporter;

# Some extra initialization for the first time this module is loaded.
# This could be done in a UNITCHECK block, but they were introduced in
# Perl 5.10.
our $module_loaded = 0;
sub import {
  if (!$module_loaded) {
    Texinfo::XSLoader::override("Texinfo::Convert::Unicode::unicode_text",
                                "Texinfo::MiscXS::unicode_text");
    $module_loaded = 1;
  }
  # The usual import method.
  goto &Exporter::import;
}

our @EXPORT_OK = qw(
  unicode_accent
  encoded_accents
  brace_no_arg_command
  unicode_text
  string_width
);

our $VERSION = '7.3';

my %unicode_accented_letters = %Texinfo::UnicodeData::unicode_accented_letters;
my %unicode_to_eight_bit = %Texinfo::UnicodeData::unicode_to_eight_bit;

my %unicode_diacritics = %Texinfo::CommandsValues::unicode_diacritics;

our %diacritics_accent_commands;
foreach my $diacritic(keys(%unicode_diacritics)) {
  $diacritics_accent_commands{$unicode_diacritics{$diacritic}} = $diacritic;
}

our %unicode_map = (%Texinfo::CommandsValues::base_unicode_map,
                    %Texinfo::CommandsValues::extra_unicode_map);

# set the %unicode_character_brace_no_arg_commands value to the character
# corresponding to the textual hex value in %unicode_map.
our %unicode_character_brace_no_arg_commands;
foreach my $command (keys(%unicode_map)) {
# TODO Using charnames::vianame as in the following is the clean documented
# way to create an unicode character at runtime.  However, in tests of perl
# 5.10.1 (on solaris), if charnames::vianame is used for @aa{} '00E5', uc()
# on the resulting character does not leads to \x{00C5} (@AA{}) (when
# formatting @sc{@aa{}} or @var{@aa{}} in plaintext).
#  $unicode_character_brace_no_arg_commands{$command}
#    = charnames::vianame("U+$unicode_map{$command}");
  my $char_nr = hex($unicode_map{$command});
  if ($char_nr > 126 and $char_nr < 255) {
    # this is very strange, indeed.  The reason lies certainly in the
    # magic backward compatibility support in Perl for 8bit encodings.
    $unicode_character_brace_no_arg_commands{$command} =
       Encode::decode("iso-8859-1", chr($char_nr));
  } else {
    $unicode_character_brace_no_arg_commands{$command} = chr($char_nr);
  }
}

our %unicode_entities;
# set entities corresponding to unicode_map
foreach my $command (keys(%unicode_map)) {
  $unicode_entities{$command}
   = '&#'.hex($unicode_map{$command}).';';
}


our %transliterate_map = (
  # Text::Unicode starting from version 1.25_01 maps C1 controls in the
  # 0080 to 009F range to Windows-1252 characters.  We still consider
  # the Unicode standard to rule and keep on transliterating to empty
  # strings
               '0080'  => '',
               '0081'  => '',
               '0082'  => '',
               '0083'  => '',
               '0084'  => '',
               '0085'  => '',
               '0086'  => '',
               '0087'  => '',
               '0088'  => '',
               '0089'  => '',
               '008A'  => '',
               '008B'  => '',
               '008C'  => '',
               '008D'  => '',
               '008E'  => '',
               '008F'  => '',
               '0090'  => '',
               '0091'  => '',
               '0092'  => '',
               '0093'  => '',
               '0094'  => '',
               '0095'  => '',
               '0096'  => '',
               '0097'  => '',
               '0098'  => '',
               '0099'  => '',
               '009A'  => '',
               '009B'  => '',
               '009C'  => '',
               '009D'  => '',
               '009E'  => '',
               '009F'  => '',
               # explicit transliterations
               '00A3' => 'GBP', # iconv @pounds
               '00A9' => '(C)', # iconv
               '00AA' => 'a', # ordf iconv and unidecode
               '00AE' => '(R)', # iconv
               '00BA' => 'o', # ordm iconv and unidecode
               #'00B0' => '?', #iconv @textdegree, probably no translit
               #'00BF' => '?', #iconv @questiondown
               '00C5' => 'A',
               '00E5' => 'a',
               '00D8' => 'O',
               '00F8' => 'o',
               '00E6' => 'ae',
               '0153' => 'oe',
               '00C6' => 'AE',
               '0152' => 'OE',
               '00DF' => 'ss',
               '0141' => 'L',
               '0142' => 'l',
               '00D0' => 'D',
               '00F0' => 'd',
               '00DE' => 'TH',
               '00FE' => 'th',
               # Cyrillic.  Based on Sergey Poznyakoff when different from
               # unidecode.
               '0415'  => 'E',
               '0435'  => 'e',
               '0426'  => 'C',
               '042A'  => 'W',
               '044A'  => 'w',
               '042C'  => 'X',
               '044C'  => 'x',
               '042E'  => 'yu',
               '042F'  => 'YA',
               '044F'  => 'ya',
               '0433'  => 'g',
               '0446'  => 'c',
               '04D7'  => 'IO',
               # other unidecode considered wrong
               '00DD'  => 'Y', # unidecode gets this wrong ?
               '0237'  => 'j', # unknown dotless j for unidecode, returns [?]
               # iconv and unidecode
               '20AC'  => 'EUR',
               # following based on iconv
               '2022'  => 'o', # bullet
               '2026'  => '...', # ellipsis
               #'21A6'  => '?', # expansion, probably no translit
               '2192'  => '->', # arrow and click
               '21D2'  => '=>', # result
               '2212'  => '-',
               #'2261'  => '?', # equiv, probably no translit
               '2264'  => '<=', # leq
               '2265'  => '>=', # geq
               #'22A3'  => '?', # print, probably no translit
               #'22C6'  => '?', # point, probably no translit

               # unidecode for the following fullwidth characters
               'FF08' => '(',
               'FF09' => ')',
               'FF0C' => ',',
          );

my %tests_specific_transliterate_map = (
               # following appears in tests, this is required to have
               # the same output with and without unidecode.
               # East asian fullwidth and japanese characters.
               # based on unidecode.
               '4E00'  => 'Yi',
               '4E2D'  => 'Zhong',
               '6587'  => 'Wen',
               '793A'  => 'Shi',
               '4F8B'  => 'Li',
               '7B2C'  => 'Di',
               '7AE0'  => 'Zhang',
               '53E6'  => 'Ling',
               '4E2A'  => 'Ge',
               '5B66' => 'Xue',
               '7FD2' => 'Xi',
               '30DE' => 'ma',
               '30CB' => 'ni',
               '30E5' => 'yu',
               '30A2' => 'a',
               '30EB' => 'ru',
          );

our %tests_transliterate_map = (%transliterate_map,
                                %tests_specific_transliterate_map);

our %no_transliterate_map;
foreach my $symbol(keys(%unicode_map)) {
  if (!exists($transliterate_map{$symbol})) {
    $no_transliterate_map{$unicode_map{$symbol}} = 1;
  }
}

our %transliterate_accent_map;
foreach my $command (keys(%unicode_accented_letters)) {
  foreach my $letter(keys (%{$unicode_accented_letters{$command}})) {
    $transliterate_accent_map{$unicode_accented_letters{$command}->{$letter}} = $letter
      unless (exists($transliterate_map{$unicode_accented_letters{$command}->{$letter}}));
  }
}

sub unicode_accent($$$$) {
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

sub unicode_text($;$) {
  my ($text, $in_code) = @_;

  if (!$in_code) {
    $text =~ s/---/\x{2014}/g;
    $text =~ s/--/\x{2013}/g;
    $text =~ s/``/\x{201C}/g;
    $text =~ s/''/\x{201D}/g;
    $text =~ s/'/\x{2019}/g;
    $text =~ s/`/\x{2018}/g;
  }
  return $text;
}

# return the hexadecimal 8 bit string, if it exists, and the unicode codepoint
sub eight_bit_and_unicode_point($$) {
  my ($char, $encoding) = @_;

  my ($eight_bit, $codepoint);
  if (ord($char) < 127) {
    # 7bit ascii characters (excluding 127, \x{7F}, DEL), the same in every
    # 8bit encodings
    $eight_bit = uc(sprintf("%02x",ord($char)));
    $codepoint = uc(sprintf("%04x",ord($char)));
  } elsif (ord($char) <= hex(0xFFFF)) {
    $codepoint = uc(sprintf("%04x",ord($char)));
    if (exists($unicode_to_eight_bit{$encoding}->{$codepoint})) {
     $eight_bit = $unicode_to_eight_bit{$encoding}->{$codepoint};
    }
  }
  return ($eight_bit, $codepoint);
}

# format a stack of accents as unicode.
# Since unicode_accent cannot return undef in practice, the use of
# $format_accent to format the remaining of the stack never happens,
# see comments in unicode_accent.
sub _format_unicode_accents_stack($$$$;$) {
  my ($converter, $inner_text, $stack, $format_accent, $set_case) = @_;

  my $result = $inner_text;
  my $i = scalar(@$stack) -1;

  for (; $i >= 0; $i--) {
    my $accent_command = $stack->[$i];
    my $formatted_result
      = unicode_accent($result, $accent_command, $i, $stack);
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
    $result = &$format_accent($converter, $result, $accent_command, $i,
                              $stack, $set_case);
  }
  return $result;
}

sub _format_eight_bit_accents_stack($$$$$;$) {
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
      = unicode_accent($results_stack[$i+1], $accent_command, $i, $stack);
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
      = eight_bit_and_unicode_point($char, $encoding);
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

sub encoded_accents($$$$$;$) {
  my ($converter, $text, $stack, $encoding, $format_accent, $set_case) = @_;

  if ($encoding) {
    # in case an encoding is directly specified with -c OUTPUT_ENCODING_NAME
    # in upper case to match with the encodings in Texinfo input, we convert
    # to lower case to match the encoding names used here.  In the code
    # encoding names are lower cased early.
    $encoding = lc($encoding);
    if ($encoding eq 'utf-8') {
      return _format_unicode_accents_stack($converter, $text, $stack,
                                           $format_accent, $set_case);
    } elsif (exists($unicode_to_eight_bit{$encoding})) {
      return _format_eight_bit_accents_stack($converter, $text, $stack,
                                             $encoding,
                                             $format_accent, $set_case);
    }
  }
  return undef;
}

# $UNICODE_POINT is a string describing an hexadecimal number with
# letters in upper case.
sub unicode_point_decoded_in_encoding($$) {
  my $encoding = shift;
  my $unicode_point = shift;

  if ($encoding) {
    # in case an encoding is directly specified with -c OUTPUT_ENCODING_NAME
    # in upper case to match with the encodings in Texinfo input, we convert
    # to lower case to match the encoding names used here.  In the code
    # encoding names are lower cased early.
    $encoding = lc($encoding);
  }

  return 1 if ((!defined($encoding) or $encoding eq 'utf-8')
               or (exists($unicode_to_eight_bit{$encoding})
                   and (exists($unicode_to_eight_bit{$encoding}->{$unicode_point})
                        # excludes 127 \x{7F} DEL
                        or hex($unicode_point) < 127)));
  return 0;
}

# returns the text for a command with brace and no arg
# if it is known that it is present for $encoding
sub brace_no_arg_command($$) {
  my ($command, $encoding) = @_;

  if (exists($unicode_character_brace_no_arg_commands{$command})
      and unicode_point_decoded_in_encoding($encoding, $unicode_map{$command})) {
    return $unicode_character_brace_no_arg_commands{$command};
  } else {
    return undef;
  }
}

# this function checks that it is possible to output
# actual UTF-8 binary bytes, by checking that chr(hex($arg)) is valid.
# Perl gives a warning and will not output UTF-8 for Unicode
# non-characters such as U+10FFFF.
#
# return 1 if the conversion is possible and can be attempted, 0 otherwise.
# the second argument triggers debugging output if the conversion failed.
sub check_unicode_point_conversion($;$) {
  my ($arg, $output_debug) = @_;

  # The warning about non-characters is only given when the code
  # point is attempted to be output, not just manipulated.
  # http://stackoverflow.com/questions/5127725/how-could-i-catch-an-unicode-non-character-warning
  # In perl 5.36.0, Encoding and printing also do not give a warning, so
  # no warning for:
  #
  # my ($fh, $string);
  # open($fh, ">", \$string);
  # my $char = chr(hex("110000"));
  # print $fh Encode::encode("utf-8", $char);
  #
  # but there is a warning if going through an encoding layer as below.
  #
  # In perl 5.10.1 on solaris 11, but not on solaris 10, the warning all does
  # not catch the nonchar warning (this warning seems to be defined on
  # 5.13.10 or newer).  This may be a consequence of what is described in
  # http://stackoverflow.com/questions/5127725/how-could-i-catch-an-unicode-non-character-warning
  # as a compiler bug, but it is unclear.  This does not happen with the
  # lax conversion to utf8, but we prefer to use a strict conversion.
  #
  # To avoid outputting a warning, we do not even try to encode the string
  # in the 5.10.0 5.13.8 range.
  #
  # We still use an eval to catch $arg that are illegal for hex
  if ($] >= 5.010 and $] <= 5.013008) {
    eval {
      use warnings FATAL => qw(all);
      my $var;
      if (hex($arg) > 0x10FFFF) {
        $var = 1;
      }
    };
    if ($@) {
      warn "Unicode hex($arg) eval failed: $@\n" if ($output_debug);
      return 0;
    } elsif (hex($arg) > 0x10FFFF) {
      return 0;
    }
  }
  #
  # For the other cases, we have to try to output it within an eval.
  # Since opening /dev/null or a temporary file means
  # more system-dependent checks, use a string as our
  # filehandle.
  eval {
    use warnings FATAL => qw(all);
    my ($fh, $string);
    open($fh, ">", \$string) || die "open(U string eval) failed: $!";
    binmode($fh, ":encoding(utf-8)") || die "binmode(U string eval) failed: $!";
    print $fh chr(hex("$arg"));
  };
  if ($@) {
    warn "Unicode chr(hex($arg)) eval failed: $@\n" if ($output_debug);
    return 0;
  } elsif (hex($arg) > 0x10FFFF) {
    # The check above appears not to work in older versions of Perl,
    # so check the argument is not greater the maximum Unicode code
    # point.
    return 0;
  }
  return 1;
}

# string length size taking into account that east asian characters
# may take 2 spaces.
sub string_width($) {
  my $string = shift;

  # Optimise for the common case where we can just return the length
  # of the string.  These regexes are faster than making the substitutions
  # below.
  # IsPrint without \p{Mark}.  Matches classes Letter, Number, Punct, Symbol,
  # and Space_Separator.
  if ($string =~ /^[\p{L}\p{N}\p{P}\p{S}\p{Zs}]*$/
      and $string !~ /[\p{InFullwidth}]/) {
    return length($string);
  }

  $string =~ s/\p{InFullwidth}/\x{02}/g;
  $string =~ s/[\p{L}\p{N}\p{P}\p{S}\p{Zs}]/\x{01}/g;
  $string =~ s/[^\x{01}\x{02}]/\x{00}/g;

  # This sums up the byte values of the bytes in $string, which now are
  # all either 0, 1 or 2.  This is faster.  The original, more readable
  # version is below.
  return unpack("U0%32A*", $string);

  if (! defined($string)) {
    cluck();
  }
  my $width = 0;
  foreach my $character(split '', $string) {
    if ($character =~ /\p{InFullwidth}/) {
      $width += 2;
    } elsif ($character =~ /[\p{L}\p{N}\p{P}\p{S}\p{Zs}]/) {
      $width += 1;
    } else {
      # zero width character: \pC (including controls), \pM, \p{Zl}, \p{Zp}
    }
  }
  return $width;
}

1;
__END__

=head1 NAME

Texinfo::Convert::Unicode - Representation as Unicode characters

=head1 SYNOPSIS

  use Texinfo::Convert::Unicode qw(unicode_accent encoded_accents
                                   unicode_text);
  use Texinfo::Convert::Text qw(convert_to_text);

  my ($contents_element, $stack)
      = Texinfo::Common::find_innermost_accent_contents($accent);

  my $formatted_accents = encoded_accents($converter,
                 convert_to_text($contents_element), $stack, $encoding,
                        \&Texinfo::Text::ascii_accent_fallback);

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

C<Texinfo::Convert::Unicode> provides methods dealing with Unicode
representation and conversion of Unicode code points, to be used in Texinfo
converters.

When an encoding supported in Texinfo is given as argument of a method of the
module, the accented letters or characters returned by the method should only
be represented by Unicode code points if it is known that Perl should manage
to convert the Unicode code points to encoded characters in the encoding
character set.  Note that the actual conversion is done by Perl, not by the
module.

=head1 METHODS

=over

=item $result = brace_no_arg_command($command_name, $encoding)
X<C<brace_no_arg_command>>

Return the Unicode representation of a command with brace and no argument
I<$command_name> (like C<@bullet{}>, C<@aa{}> or C<@guilsinglleft{}>),
or C<undef> if the Unicode representation cannot be converted to encoding
I<$encoding>.

=item $possible_conversion = check_unicode_point_conversion($arg, $output_debug)
X<C<check_unicode_point_conversion>>

Check that it is possible to output actual UTF-8 binary bytes
corresponding to the Unicode code point string I<$arg> (such as
C<201D>).  Perl gives a warning and will not output UTF-8 for
Unicode non-characters such as U+10FFFF.  If the optional
I<$output_debug> argument is set, a debugging output warning
is emitted if the test of the conversion failed.
Returns 1 if the conversion is possible and can be attempted,
0 otherwise.

=item $result = encoded_accents($converter, $text, $stack, $encoding, $format_accent, $set_case)
X<C<encoded_accents>>

I<$encoding> is the encoding the accented characters should be encoded to.  If
I<$encoding> not set, I<$result> is set to C<undef>.  Nested accents and
their content are passed with I<$text> and I<$stack>.  I<$text> is the text
appearing within nested accent commands.  I<$stack> is an array reference
holding the nested accents texinfo tree elements.  In general, I<$text> is
the formatted contents and I<$stack> the stack returned by
L<Texinfo::Common::find_innermost_accent_contents|Texinfo::Common/($contents_element,
\@accent_commands) = find_innermost_accent_contents($element)>.  The function
tries to convert as much as possible the accents to I<$encoding> starting from the
innermost accent.

I<$format_accent> is a function reference that is used to format the accent
commands if there is no encoded character available at some point of the
conversion of the I<$stack>.  I<$converter> is a converter object optionaly
used by I<$format_accent>.  It may be C<undef> if there is no need of
converter object in I<$format_accent>.

The I<$set_case> argument is optional.  If I<$set_case> is positive, the result
is upper-cased, while if it is negative, the result is lower-cased.

=item $width = string_width($string)
X<C<string_width>>

Return the string width, taking into account the fact that some characters
have a zero width (like composing accents) while some have a width of 2
(most chinese characters, for example).

=item $result = unicode_accent($text, $accent_command, $index_in_stack, $accents_stack)
X<C<unicode_accent>>

I<$text> is the text appearing within an accent command.  I<$accent_command>
should be a Texinfo tree element corresponding to an accent command taking
an argument.  I<$index_in_stack> is the position in the I<$accents_stack>
of the accent command being converted.  The function returns the Unicode
representation of the accented character.

=item $is_decoded = unicode_point_decoded_in_encoding($encoding, $unicode_point)
X<C<unicode_point_decoded_in_encoding>>

Return true if the I<$unicode_point> will be encoded in the encoding
I<$encoding>.  The I<$unicode_point> should be specified as a four letter
string describing an hexadecimal number with letters in upper case
(such as C<201D>).  Tables are used to determine if the I<$unicode_point>
will be encoded, when the encoding does not cover the whole Unicode range.

If the encoding is not supported in Texinfo, the result will always be false.

=item $result = unicode_text($text, $in_code)
X<C<unicode_text>>

Return I<$text> with dashes and quotes corresponding, for example to C<---> or
C<'>, represented as Unicode code points.  If I<$in_code> is set, the text is
considered to be in code style.

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
