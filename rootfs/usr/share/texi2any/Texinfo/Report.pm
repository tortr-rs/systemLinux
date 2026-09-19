# Report.pm: prepare error messages.
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
# ALTIMP C/parsetexi/errors_parser.c
# ALTIMP C/main/errors.c

package Texinfo::Report;

use 5.00405;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use Carp qw(cluck);

# for fileparse
use File::Basename;

use Locale::Messages;

my $messages_textdomain = 'texinfo';

# this module does not use Texinfo::Common, therefore does not
# obtain those functions, they are defined here
sub __($) {
  my $msgid = shift;

  return Locale::Messages::dgettext($messages_textdomain, $msgid);
}

sub __p($$) {
  my ($context, $msgid) = @_;

  return Locale::Messages::dpgettext($messages_textdomain, $context, $msgid);
}

sub count_errors($) {
  my $error_messages_list = shift;

  my $error_nr = 0;
  foreach my $message (@$error_messages_list) {
    if ($message->{'type'} eq 'error' and !$message->{'continuation'}) {
      $error_nr++;
    }
  }
  return $error_nr;
}

# Used in generic converter API.
sub format_line_message($$$$;$) {
  my ($type, $text, $error_location_info, $continuation, $warn) = @_;

  if (!defined($error_location_info)) {
    cluck("BUG: format_line_message: error_location_info undef");
    return;
  }

  my $message_line;

  if (exists($error_location_info->{'macro'})) {
    if ($type eq 'warning') {
      $message_line = sprintf(__p("Texinfo source file warning in macro",
                               "warning: %s (possibly involving \@%s)")."\n",
                           $text, $error_location_info->{'macro'});
    } else {
      $message_line = sprintf(__p("Texinfo source file error in macro",
                            "%s (possibly involving \@%s)")."\n",
                         $text, $error_location_info->{'macro'});
    }
  } else {
    if ($type eq 'warning') {
      $message_line = sprintf(__p("Texinfo source file warning",
                               "warning: %s")."\n",
                           $text);
    } else {
      $message_line = $text."\n";
    }
  }
  warn $message_line if ($warn);
  my %location_info = %{$error_location_info};
  my $result
    = { 'type' => $type, 'text' => $text, 'error_line' => $message_line,
         %location_info };
  $result->{'continuation'} = $continuation if (defined($continuation));
  return $result;
}


# format a line warning
sub line_warn($$;$$$) {
  my ($text, $error_location_info, $continuation, $debug, $silent) = @_;

  if (!defined($error_location_info)) {
    cluck("BUG: line_warn: error_location_info undef");
    return;
  }

  my $warn = ($debug and not $silent);

  my $warning = format_line_message('warning', $text, $error_location_info,
                                    $continuation, $warn);

  return $warning;
}

sub line_error($$;$$$) {
  my ($text, $error_location_info, $continuation, $debug, $silent) = @_;

  if (!defined($error_location_info)) {
    cluck("BUG: line_error: error_location_info undef");
    return;
  }

  my $warn = ($debug and not $silent);

  my $error = format_line_message('error', $text, $error_location_info,
                                  $continuation, $warn);
  return $error;
}

sub format_document_message($$;$$) {
  my ($type, $text, $program_name, $continuation) = @_;

  my $message_line;
  if (defined($program_name)) {
    if ($type eq 'warning') {
      $message_line = sprintf(__p("whole document warning", "%s: warning: %s")."\n",
                              $program_name, $text);
    } else {
      $message_line = sprintf("%s: %s\n",
            $program_name, $text);
    }
  } else {
    if ($type eq 'warning') {
      $message_line = sprintf(__p("whole document warning", "warning: %s")."\n",
                           $text);
    } else {
      $message_line = "$text\n";
    }
  }
  my $result = { 'type' => $type, 'text' => $text,
                  'error_line' => $message_line };
  $result->{'continuation'} = $continuation if ($continuation);
  return $result;
}

sub document_warn($;$$) {
  my ($text, $program_name, $continuation) = @_;

  my $warning = format_document_message('warning', $text, $program_name,
                                        $continuation);
  return $warning;
}

sub document_error($;$$) {
  my ($text, $program_name, $continuation) = @_;

  my $error = format_document_message('error', $text, $program_name,
                                      $continuation);
  return $error;
}

# TODO document?
# used in tests
sub print_source_info_details($;$$) {
  my ($source_info, $fname_encoding, $use_filename) = @_;

  return '' if (!defined($source_info));

  my $result = '';

  my $line_nr = $source_info->{'line_nr'};
  my $macro = $source_info->{'macro'};
  if (exists($source_info->{'file_name'})) {
    my $file_name = $source_info->{'file_name'};
    if ($use_filename) {
      my ($directories, $suffix);
      ($file_name, $directories, $suffix) = fileparse($file_name);
    }
    if (defined($fname_encoding)) {
      $file_name = Encode::decode($fname_encoding, $file_name);
    }
    $result .= $file_name;
    $result .= ':' if ($line_nr or defined($macro));
  }

  if ($line_nr) {
    $result .= "l$line_nr";
    $result .= ':' if (defined($macro));
  }

  if (defined($macro)) {
    $result .= '@'.$macro;
  }

  return $result;
}

sub _print_error_details($;$$) {
  my ($error, $fname_encoding, $use_filename) = @_;

  my $result = '* ';
  if ($error->{'type'} eq 'warning') {
    $result .= 'W';
  } else {
    $result .= 'E';
  }
  $result .= 'C' if ($error->{'continuation'});
  $result .= ' '.print_source_info_details($error,
                                        $fname_encoding, $use_filename)
             . '|'.$error->{'text'}."\n ".$error->{'error_line'};
  return $result;
}

# used in tests
sub errors_print_details($;$$) {
  my ($error_messages_list, $fname_encoding, $use_filename) = @_;

  my $result = '';
  foreach my $error_msg (@$error_messages_list) {
    $result .= _print_error_details($error_msg, $fname_encoding,
                                    $use_filename)."\n";
  }
  return $result;
}

1;

__END__

=head1 NAME

Texinfo::Report - Error storing for Texinfo modules

=head1 SYNOPSIS

  use Texinfo::Report;

  my $error_messages = [];

  if ($warning_happened) {
    push @$error_messages, Texinfo::Report::line_warn(
                       sprintf(__("\@%s is wrongly used"),
                       $current->{'cmdname'}), $current->{'source_info'},
                       0, $converter->get_conf('DEBUG'));
  }

  foreach my $error_message (@$error_messages) {
    warn $error_message->{'error_line'};
  }

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

The C<Texinfo::Report> module helps with error handling.  Errors
and warnings can be setup, stored and retrieved later on.
This module methods are used by the L<Texinfo::Parser> and
L<Texinfo::Convert::Converter> modules.

=head1 METHODS

No method is exported in the default case.

The methods allow registering errors and warnings.

=over

=item $error_count = count_errors ($error_messages)

This function returns as I<$error_count> the count of errors in the error
messages list (as opposed to warnings).  The I<$error_warnings_list> is an
array of hash references one for each error, warning or error line
continuation.  Each of these has the following keys:

=over

=item continuation

If set, the line is a continuation line of a message.

=item error_line

The text of the error formatted with the macro name, as needed.

=item file_name

The file name where the error or warning occurs.

=item line_nr

The line number of the error or warning.

=item macro

The user macro name that is expanded at the location of
the error or warning.

=item text

The text of the error.

=item type

May be C<warning>, or C<error>.

=back

=item $message = line_warn ($text, $error_location_info, $continuation, $debug, $silent)

=item $message = line_error ($text, $error_location_info, $continuation, $debug, $silent)
X<C<line_warn>>
X<C<line_error>>

Register a warning or an error message structure.  The I<$text> is the text of
the error or warning.  The mandatory I<$error_location_info> holds the
information on the error or warning location.  The I<$error_location_info>
reference on hash may be obtained from Texinfo elements I<source_info> keys.
It may also be setup to point to a file name, using the C<file_name> key and to
a line number, using the C<line_nr> key.  The C<file_name> key value should be
a binary string.

The I<$continuation> optional arguments, if true, conveys that
the line is a continuation line of a message.

The I<$debug> optional integer arguments sets the debug level.

The I<$silent> optional arguments, if true, suppresses the output of
a message that is output immediatly if debugging is set.

The I<source_info> key of Texinfo tree elements is described
in more details in L<Texinfo::Parser/source_info>.

=item $message = document_warn ($text, $program_name, $continuation)

=item $message = document_error ($text, $program_name, $continuation)
X<C<document_warn>>
X<C<document_error>>

Returns a document-wide error or warning message structure.  I<$text> is the
error or warning message.  The I<$program_name> is prepended to the message, if
defined.  The I<$continuation> optional arguments, if true, conveys that the
line is a continuation line of a message.

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
