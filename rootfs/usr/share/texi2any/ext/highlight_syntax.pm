# highlight_syntax.pm: interface to source-highlight for syntax highlighting
#
#    Copyright (C) 2021-2026 Free Software Foundation, Inc.
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

use 5.006;
use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

use IPC::Open3;
use Symbol;

use Texinfo::Commands;
# also for __(
use Texinfo::Common;
use Texinfo::Convert::Text;
use Texinfo::Convert::NodeNameNormalization;

my %languages_extensions = (
  'texinfo' => 'texi',
  'perl' => 'pl',
);

# No list of languages and no check on language if undef.
# Otherwise a hash reference with possible languages as keys.
my $highlighted_languages_list;

# the list of @-commands that can be highlighted.
# Each of these commands should have a command formatting function
# registered.
my @highlighted_commands_names = ('example');

# The @-commands highlighting is done in two steps
# 1) in highlight_process, before the start of the HTML conversion,
#    * the highlighted commands are collected by going through the
#      Texinfo tree
#    * each collected Texinfo tree element programming language is
#      determined and the tree elements are converted to text if a
#      programming language is found.
#      The text goes through a program that returns highlighted HTML
#      code.
#        - with 'source-highlight' a file is setup by language, the
#          program is called once per language with line counts
#          and separators used to separate the fragments.
#        - otherwise the program is called for each of the Texinfo tree
#          element with the language in the command-line, text is
#          passed on the standard input and the highlighted code fragment
#          is read from the standard output.
#      The Texinfo tree element is associated to the highlighted
#      HTML code fragment in this step.
# 2) During the conversion, the command formatting function associated
#    to each of the Texinfo tree command elements that could be highlighted
#    is called.  In these functions (currently only one,
#    highlight_preformatted_command), the highlighted HTML code fragment
#    associated to the tree element is found and output.

texinfo_register_handler('setup', \&highlight_setup);
texinfo_register_handler('structure', \&highlight_process);
texinfo_register_command_formatting('example', \&highlight_preformatted_command);
# normally this is done in preformatted type, but preformatted
# types conversion output in example is discarded in
# highlight_preformatted_command, so register a replacement.
# Register inline pending content when opening an example block.
texinfo_register_command_opening('example',
                                 \&highlight_open_inline_container_type);

# Run highlighting command to set $highlighted_languages_list to list
# of recognized languages.  This is used to avoid calling the highlighter
# with an unrecognized language.
sub highlight_setup($$) {
  my ($self, $document) = @_;

  my $document_root = $document->tree();

  $highlighted_languages_list = undef;

  my $highlight_syntax = $self->get_conf('HIGHLIGHT_SYNTAX');

  return 1 if (!defined($highlight_syntax) or $highlight_syntax !~ /\S/);

  my $cmd;
  my $highlight_type;
  if ($highlight_syntax eq 'highlight') {
    $highlight_type = 'highlight';
    $cmd = 'highlight --list-scripts=lang';
  } elsif ($highlight_syntax eq 'pygments') {
    $highlight_type = 'pygments';
    $cmd = 'pygmentize -L lexers';
  } elsif ($highlight_syntax eq 'source-highlight') {
    $highlight_type = 'source-highlight';
    $cmd = 'source-highlight --lang-list';
  } else {
    # $highlight_syntax will be used as command, with language substituted
    return 0;
  }

  %$highlighted_languages_list = ();

  # NOTE open failure triggers a warning message if run with -w if the
  # file is not found.  This message can be catched with $SIG{__WARN__}.
  # This message is along:
  # Can't exec "source-highlight": No such file or directory at ./init/highlight_syntax.pm line XX
  # This message is redundant with the message registered below with
  # document_error, using $!.  $! is set to: No such file or directory

  # Tried to show both messages, but through the $self->document_*()
  # facility, either by getting the warning message in the main context or by
  # register the warning message, but failed.  So simply silence the redundant
  # message.

  # does not store the message from within the sub but syntactically
  # needed.
  my $message;
  local $SIG{__WARN__} = sub {
        $message = shift;
        # this shows the message
        #warn "$message";
        # not sure why, but this does not work, the warning is not actually
        # registered, as if it was done in a scope that is later destroyed.
        #$self->converter_document_warn(sprintf(__('%s: %s'), $cmd, $message));
      };

  my $status = open(HIGHLIGHT_LANG_LIST, '-|', $cmd);
  $SIG{__WARN__} = undef;
  if (not($status)) {
    $self->converter_document_error(sprintf(__('%s: %s'), $cmd, $!));
    return 1;
  }

  my $line;
  if ($highlight_type eq 'highlight') {
    my $in_languages;
    while (defined($line = <HIGHLIGHT_LANG_LIST>)) {
      chomp($line);
      #print STDERR "LL $line\n";
      if (!$in_languages) {
        if ($line =~ /^.+: [a-z]/) {
          $in_languages = 1;
        } else {
          next;
        }
      }
      #print STDERR "$line\n";
      if ($line =~ /^.+: ([a-z0-9+_\/-]+)( \( (([a-z0-9+_\/-]+ )+)\))?$/) {
        my $main_language = $1;
        my $other_languages = $3;
        $highlighted_languages_list->{$main_language} = 1;
      } else {
        last;
      }
    }
    #use Data::Dumper;
    #print STDERR Data::Dumper->Dump([$highlighted_languages_list]);
    #exit 1;
  } elsif ($highlight_type eq 'pygments') {
    while (defined($line = <HIGHLIGHT_LANG_LIST>)) {
      chomp($line);
      if ($line =~ /^\* (.+):$/) {
        my @languages = split (/, /, $1);
        if (scalar(@languages) == 0) {
          $self->converter_document_warn(sprintf(__(
                        '%s: %s: cannot parse language line'), $cmd, $line))
        } else {
          my $main_language = shift @languages;
          $highlighted_languages_list->{$main_language} = 1;
        }
      }
    }
    #use Data::Dumper;
    #print STDERR Data::Dumper->Dump([$highlighted_languages_list]);
    #exit 1;
  } else { # $highlight_type eq 'source-highlight'
    while (defined($line = <HIGHLIGHT_LANG_LIST>)) {
      chomp($line);
      if ($line =~ /^([A-Za-z0-9_\-]+) =/) {
        my $language = $1;
        $highlighted_languages_list->{$language} = 1;
      } else {
        $self->converter_document_warn(sprintf(__(
                        '%s: %s: cannot parse language line'), $cmd, $line))
      }
    }
  }
  # FIXME check error status
  close(HIGHLIGHT_LANG_LIST);

  if (scalar(keys(%$highlighted_languages_list)) == 0) {
    # important if $cmd returns no output to have a message.  If there
    # is some output, there will already be some line parse error messages.
    $self->converter_document_warn(sprintf(__(
                            '%s: no highlighted language found'), $cmd));
    # the remaining will be skipped, but no error is returned
  }
  return 0;
}

# Determine the Texinfo tree element $COMMAND converted language command
# argument, or set it with HIGHLIGHT_SYNTAX_DEFAULT_LANGUAGE (if set).
# Determine the normalized language name.  If there is a list of known
# languages, check if the language is known.
# Returns the (normalized language, converted language) pair.  Both
# could be undef.
sub _get_language($$) {
  my ($self, $command) = @_;

  my $language;
  my $converted_language;

  my $cmdname = $command->{'cmdname'};
  if ($cmdname eq 'example') {
    my $arguments_line = $command->{'contents'}->[0];
    if (exists($arguments_line->{'contents'})) {
      $converted_language
        = Texinfo::Convert::NodeNameNormalization::convert_to_normalized(
                                          $arguments_line->{'contents'}->[0]);
      if ($converted_language eq '') {
        $converted_language = undef;
      }
    }
  }

  if (not defined($converted_language) and defined($self)) {
    my $default_highlight_language
      = $self->get_conf('HIGHLIGHT_SYNTAX_DEFAULT_LANGUAGE');
    if (defined($default_highlight_language)) {
      $converted_language = $default_highlight_language;
    }
  }

  if (defined($converted_language)
      and (!defined($highlighted_languages_list)
           or exists($highlighted_languages_list->{$converted_language}))) {
    return ($converted_language, $converted_language);
  } else {
    return (undef, $converted_language);
  }
}

# Convert element argument to simple text.
sub _convert_element($$) {
  my ($self, $element) = @_;

  my @contents = @{$element->{'contents'}};
  while (scalar(@contents) > 0
         and exists($contents[0]->{'type'})
         # ignorable_spaces_after_command cannot actually happen with
         # @example
         and ($contents[0]->{'type'} eq 'ignorable_spaces_after_command'
              or $contents[0]->{'type'} eq 'arguments_line')) {
    shift @contents;
  }
  if (scalar(@contents) > 0 and exists($contents[-1]->{'cmdname'})
      and $contents[-1]->{'cmdname'} eq 'end') {
    pop @contents;
  }

  return "\n" if (!scalar(@contents));

  Texinfo::Convert::Text::set_options_code(
                           $self->{'convert_text_options'});
  my $text = Texinfo::Convert::Text::convert_to_text(
                                {'contents' => \@contents},
                                $self->{'convert_text_options'});
  Texinfo::Convert::Text::reset_options_code(
                                 $self->{'convert_text_options'});
  # make sure that the text ends with a newline
  chomp ($text);
  $text .= "\n";

  return $text;
}

# The end of the string was randomly generated once for all.
# Used for 'source-highlight' only.
my $range_separator
  = '_______________________________________ highlight texinfo _GT Haib0aik zei4YieH';

# Keys are commands names (currently only 'example').
# Associates a command name and element to the resulting highlighted text
# in 'result'.
# Also holds per language counters:
#   input_languages_counters:     number of collected Texinfo tree elements
#                                 for a command name and language
#   retrieved_languages_counters: number of highlighted HTML fragments
#                                 retrieved for a command name and language.
#   output_languages_counters:    number of highlighted HTML fragments
#                                 output in the converted output.
my %highlighted_cmds;

# Initialize %highlighted_cmds for $CMDNAME command name and $LANGUAGE
# language and increase the input counter.
sub _add_collected_command_language($$) {
  my ($cmdname, $language) = @_;

  $highlighted_cmds{$cmdname} = {'input_languages_counters' => {},
                                 'results' => {},
                                 'retrieved_languages_counters'  => {},
                                 'output_languages_counters' => {}}
    if (not exists($highlighted_cmds{$cmdname}));

  # initialize per language counters
  if (not exists($highlighted_cmds{$cmdname}
                      ->{'input_languages_counters'}->{$language})) {
    $highlighted_cmds{$cmdname}->{'input_languages_counters'}->{$language} = 0;
    $highlighted_cmds{$cmdname}
         ->{'retrieved_languages_counters'}->{$language} = 0;
    $highlighted_cmds{$cmdname}->{'output_languages_counters'}->{$language} = 0;
  }

  $highlighted_cmds{$cmdname}->{'input_languages_counters'}->{$language} += 1;
}

# Replace any instances of %l in $HIGHLIGHT_CMD with $LANGUAGE, and any
# instances of %% with %.
sub _substitute_language {
  my ($highlight_cmd, $language) = @_;

  my $result;
  while ($highlight_cmd =~ s/^([^%]*)%(.)//) {
    $result .= $1;
    if ($2 eq '%') {
      $result .= '%';
    } elsif ($2 eq 'l') {
      $result .= $language;
    } else {
      # unrecognized placeholder
      $result .= '%';
      $result .= $2;
    }
  }
  $result .= $highlight_cmd;
  return $result;
}

# collect all the highlighted commands Texinfo tree elements with an
# associated language, convert to text, call the highliting command.
# Store the highlighted HTML code in %highlighted_cmds 'results', associated
# to the Texinfo tree element.
sub highlight_process($$) {
  my ($self, $document) = @_;

  my $document_root = $document->tree();

  # Reset in case multiple manuals are processed.
  %highlighted_cmds = ();

  return 0 if (defined($self->get_conf('OUTFILE'))
        and $Texinfo::Common::null_device_file{$self->get_conf('OUTFILE')});

  return 0 if (defined($highlighted_languages_list)
               and !scalar(keys(%$highlighted_languages_list)));

  my $highlight_syntax = $self->get_conf('HIGHLIGHT_SYNTAX');

  return 1 if (!defined($highlight_syntax) or $highlight_syntax !~ /\S/);

  my $verbose = $self->get_conf('VERBOSE');

  my $collected_commands
    = Texinfo::Common::collect_commands_in_tree($document_root,
                                         \@highlighted_commands_names);

  if ($highlight_syntax ne 'source-highlight') {
    # Pass each fragment to a command.
    foreach my $cmdname (@highlighted_commands_names) {
      if (scalar(@{$collected_commands->{$cmdname}}) > 0) {
        foreach my $element (@{$collected_commands->{$cmdname}}) {
          my ($language, $converted_language)
                = _get_language($self, $element);
          if (!defined($language)) {
            if (defined($converted_language) and $verbose) {
              warn "# highlight_syntax: language not found:"
                                   ." $converted_language\n";
            }
            next;
          }

          _add_collected_command_language($cmdname, $language);

          my $text = _convert_element($self, $element);

          my $cmd;
          if ($highlight_syntax eq 'highlight') {
            # With %l placeholder:
            #$highlight_cmd = 'highlight -f --style-outfile=html --inline-css '
            #                   .'--syntax=%l';
            $cmd = 'highlight -f --style-outfile=html --inline-css '
                                .'--syntax='.$language;
          } elsif ($highlight_syntax eq 'pygments') {
            # With %l placeholder:
            #$highlight_cmd = 'pygmentize -f html -O noclasses=True -l %l';
            $cmd = 'pygmentize -f html -O noclasses=True -l '.$language;
          } else {
            $cmd = _substitute_language($highlight_syntax, $language);
          }

          my ($wtr, $rdr, $err);
          $err = gensym();
          my $pid = IPC::Open3::open3($wtr, $rdr, $err, $cmd);
          if (! $pid) {
            $self->converter_document_error(sprintf(__('%s: %s'), $cmd, $!));
            return 1;
          }
          binmode($wtr, ':utf8');
          binmode($rdr, ':utf8');
          # not so sure here.  Use locale?
          binmode($err, ':utf8');
          print $wtr $text;
          if (!close($wtr)) {
            $self->converter_document_error(
              sprintf(__('%s: error closing input: %s'), $cmd, $!));
            close($rdr);
            close($err);
            return 1;
          }

          my @outlines = <$rdr>;
          my @errlines = <$err>;
          my $status = 0;
          if (!close($rdr)) {
            $self->converter_document_error(
              sprintf(__('%s: error closing output: %s'), $cmd, $!));
            $status = 1;
          }
          if (!close($err)) {
            $self->converter_document_error(
              sprintf(__('%s: error closing errors: %s'), $cmd, $!));
            $status = 1;
          }
          waitpid($pid, 0);
          if (@errlines) {
            $status = 1;
            my $errline = shift @errlines;
            chomp($errline);
            $self->converter_document_error(sprintf(__('%s: errors: %s'),
                                                    $cmd, $errline));
            foreach my $error_line (@errlines) {
              chomp($error_line);
              $self->converter_document_error(sprintf(__('  %s'),
                                                      $error_line), 1);
            }
          }
          return 1 if ($status);
          my $cmdname = $element->{'cmdname'};
          $highlighted_cmds{$cmdname}->{'results'}->{$element}
             = join('', @outlines);
          $highlighted_cmds{$cmdname}->{'retrieved_languages_counters'}
                                                           ->{$language}++;
        }
      }
    }
    return 0;
  }

  # case of 'source-highlight'.
  # Collect per language elements and output all the texts to be highlighted
  # in a file per language.
  my %languages = ();
  foreach my $cmdname (@highlighted_commands_names) {
    if (scalar(@{$collected_commands->{$cmdname}}) > 0) {
      foreach my $element (@{$collected_commands->{$cmdname}}) {
        my ($language, $converted_language)
              = _get_language($self, $element);
        if (defined($language)) {
          _add_collected_command_language($cmdname, $language);

          $languages{$language} = {'counter' => 0, 'commands' => [],
                                   'line_ranges' => []}
            if (not exists($languages{$language}));
          $languages{$language}->{'counter'}++;
          my $counter = $languages{$language}->{'counter'};
          $languages{$language}->{'commands'}->[$counter-1] = $element;
        } elsif (defined($converted_language) and $verbose) {
          warn "# highlight_syntax: language not found: $converted_language\n";
        }
      }
    }
  }

  my $document_name = $self->get_info('document_name');
  my $highlight_basename = "${document_name}_highlight";

  my $highlight_out_dir = $self->get_info('destination_directory');
  if (! -d $highlight_out_dir) {
    if (!mkdir $highlight_out_dir) {
      $self->converter_document_warn(
         sprintf(__("highlight_syntax.pm: could not make directory %s: %s"),
                                      $highlight_out_dir, $!));
    }
  }
  foreach my $language (keys(%languages)) {
    my $suffix;
    if (defined($languages_extensions{$language})) {
      $suffix = $languages_extensions{$language};
    } else {
      $suffix = $language
    }
    my $language_base = ${highlight_basename} . "_${language}";
    $languages{$language}->{'basefile'} = $language_base . "_input.$suffix";
    $languages{$language}->{'html_file'} = $language_base . '_output.html';
    my $input_language_path_name
      = join('/', ($highlight_out_dir, $languages{$language}->{'basefile'}));
    my $html_result_path_name
      = join('/', ($highlight_out_dir, $languages{$language}->{'html_file'}));

    # expand @example texts in an input file for highlight source
    # program
    my ($encoded_input_language_path_name, $input_language_path_encoding)
      = $self->encoded_output_file_name($input_language_path_name);
    unless (open(HIGHLIGHT_LANG_IN, ">$encoded_input_language_path_name")) {
      $self->converter_document_warn(
             sprintf(__("highlight_syntax.pm: could not open %s: %s"),
                                      $input_language_path_name, $!));
      return 1;
    }
    my $output_encoding;
    if (defined($self->get_conf('OUTPUT_ENCODING_NAME'))) {
      my $encoding_name = $self->get_conf('OUTPUT_ENCODING_NAME');
      $output_encoding
        = Texinfo::Common::processing_output_encoding($encoding_name);
      binmode(HIGHLIGHT_LANG_IN, ":encoding($output_encoding)");
    }

    print HIGHLIGHT_LANG_IN "Automatically generated\n\n";
    my $highlight_lang_in_line_nr = 2;

    my $counter = 0;
    foreach my $element (@{$languages{$language}->{'commands'}}) {
      my $text = _convert_element($self, $element);
      # count the number of record separator $/
      my $buffer = $text;
      my $text_lines_nr = ( $buffer =~ s|$/||g );
      print HIGHLIGHT_LANG_IN "_______________________ $counter\n";
      print HIGHLIGHT_LANG_IN $text;
      print HIGHLIGHT_LANG_IN "_______________________ $counter\n";
      $languages{$language}->{'line_ranges'}->[$counter]
                    = [$highlight_lang_in_line_nr+1 +1,
                       $highlight_lang_in_line_nr + $text_lines_nr+1];
      $highlight_lang_in_line_nr += 2 + $text_lines_nr;
      $counter++;
    }
    if (! close(HIGHLIGHT_LANG_IN)) {
      $self->converter_document_warn(
             sprintf(__("highlight_syntax.pm: error on closing %s: %s"),
                                      $input_language_path_name, $!));
      return 1;
    }

    # call source highlighting program
    my $version_option='';
    $version_option='--gen-version ' if ($self->get_conf('TEST'));
    my @option_line_ranges = ();
    foreach my $line_range (@{$languages{$language}->{'line_ranges'}}) {
      push @option_line_ranges, '"'.$line_range->[0].'-'.$line_range->[1].'"';
    }
    my $option_line_range_str = join(',', @option_line_ranges);
    my $cmd = "source-highlight ${version_option}"
       ."--src-lang=$language --out-format=html5 "
       ."-i '$input_language_path_name' -o '$html_result_path_name' "
   ."--line-range=$option_line_range_str --range-separator='$range_separator'";

    warn "# highlight_syntax: exec ($language): $cmd\n" if ($verbose);

    my $encoding = $self->get_conf('COMMAND_LINE_ENCODING');
    my $encoded_cmd;
    if (defined($encoding)) {
      $encoded_cmd = encode($encoding, $cmd);
    } else {
      $encoded_cmd = $cmd;
    }
    if (system($encoded_cmd)) {
      $self->converter_document_error(
          sprintf(__("highlight_syntax.pm: command did not succeed: %s"),
                                  $cmd));
      return 1;
    }

    my $language_fragments_nr = $languages{$language}->{'counter'};
    # extract highlighted fragments
    my ($encoded_html_result_path_name, $html_result_path_encoding)
      = $self->encoded_output_file_name($html_result_path_name);
    unless (open(HIGHLIGHT_LANG_OUT, $encoded_html_result_path_name)) {
      $self->converter_document_warn(
         sprintf(__("highlight_syntax.pm: could not open %s: %s"),
                                  $html_result_path_name, $!));
      return 1;
    }
    binmode(HIGHLIGHT_LANG_OUT, ":encoding($output_encoding)")
      if (defined($output_encoding));
    my $got_count = 0;
    my $line;
    my $text;
    my $separators_count = 0;
    while (defined($line = <HIGHLIGHT_LANG_OUT>)) {
      #print STDERR "$encoded_html_result_path_name: while $line";
      if ($line =~ /$range_separator/) {
        $separators_count++;
        if (defined($text)) {
          $got_count++;
          my $element = $languages{$language}->{'commands'}->[$got_count-1];
          my $cmdname = $element->{'cmdname'};
          $highlighted_cmds{$cmdname}->{'results'}->{$element} = $text;
          $highlighted_cmds{$cmdname}->{'retrieved_languages_counters'}
                                                            ->{$language}++;
          $text = undef;
        }
        #print STDERR "$language $got_count $language_fragments_nr \n";
        if ($got_count < $language_fragments_nr) {
          $text = '';
        }
      } else {
        if (defined($text)) {
          $text .= $line;
        }
      }
    }
    if ($separators_count != $language_fragments_nr +1) {
      $self->converter_document_warn(sprintf(__(
       "highlight_syntax.pm: %s: %d separators; expected %d, the number of fragments +1"),
                      $language, $separators_count, $language_fragments_nr+1));
    }
    if (defined($text) and $text ne '') {
      my $element = $languages{$language}->{'commands'}->[$got_count-1];
      my $cmdname = $element->{'cmdname'};
      $self->converter_document_warn(sprintf(__(
                 "highlight_syntax.pm: %s: end of \@%s item %d not found"),
                                  $language, $cmdname, $got_count));
    }
    # note that this check is not the most detailed that could be done, a check
    # by command could also be done.  Since for now there is only @example
    # it is useless, and even if there were other commands, the failure is
    # for a language, not a command, so it should not be needed either.
    if ($got_count != $languages{$language}->{'counter'}) {
      $self->converter_document_warn(sprintf(__(
         "highlight_syntax.pm: %s: retrieved %d items in HTML; expected %d"),
                            $language, $got_count, $language_fragments_nr));
    }
    if (!close(HIGHLIGHT_LANG_OUT)) {
      $self->converter_document_warn(
             sprintf(__("highlight_syntax.pm: error on closing %s: %s"),
                                      $html_result_path_name, $!));
    }
  }
  return 0;
}

sub highlight_open_inline_container_type($$$) {
  my ($self, $cmdname, $command) = @_;

  if (defined($highlighted_languages_list)
      and !scalar(keys(%$highlighted_languages_list))) {
    my $default_open = $self->default_command_open($cmdname);
    if (defined($default_open)) {
      return &{$default_open}($self, $cmdname, $command);
    } else {
      return '';
    }
  }
  if (exists($highlighted_cmds{$cmdname})
      and exists($highlighted_cmds{$cmdname}->{'results'})) {
    my ($language, $converted_language)
                = _get_language($self, $command);
    if (exists($highlighted_cmds{$cmdname}->{'results'}->{$command})
        and defined($highlighted_cmds{$cmdname}->{'results'}->{$command})) {

      # only replace the example and inside preformatted if the code leading
      # to get_associated_formatted_inline_content being called in
      # example highlighted text formatting will be called
      if (defined($language)) {
        my $pending_formatted = $self->get_pending_formatted_inline_content();

        if (defined($pending_formatted)) {
            $self->associate_pending_formatted_inline_content($command,
                                                          $pending_formatted);
        }
      }
    }
  }
  return '';
}

sub highlight_preformatted_command($$$$$) {
  my ($self, $cmdname, $command, $args, $content) = @_;

  # if no commands were registered nor converted, do not
  # warn if the language is known.  It means that there was
  # no highlighting or some error.
  if (exists($highlighted_cmds{$cmdname})
      and exists($highlighted_cmds{$cmdname}->{'results'})) {
    my ($language, $converted_language)
                = _get_language($self, $command);
    if (exists($highlighted_cmds{$cmdname}->{'results'}->{$command})
        and defined($highlighted_cmds{$cmdname}->{'results'}->{$command})) {

      if (not defined($language)) {
        $self->converter_document_warn(sprintf(__(
       "highlight_syntax.pm: output has HTML item for \@%s but no language %s"),
                                    $cmdname, $command));
      } else {
        $highlighted_cmds{$cmdname}->{'output_languages_counters'}
                                                         ->{$language}++;

        if ($self->in_string()) {
          $content = '' if (!defined($content));
          return $content;
        }

        # need to do all the formatting done for content inside
        # of @example as it is discarded.  So need to do the preformatted
        # type formatting, from _convert_preformatted_type() and
        # _preformatted_class().
        # Since we are formatting @example itself, it is not in the preformatted
        # context anymore, so we readd.
        my $preformatted_classes_stack = $self->preformatted_classes_stack();
        my @pre_classes = @{$preformatted_classes_stack};
        # NOTE $pre_class_format is setup below to correspond to
        # $pre_class_commands{$cmdname}, which cannot be used directly,
        # as it is private.
        my $pre_class_format = $cmdname;
        my $main_cmdname = $cmdname;
        if (exists($Texinfo::Common::small_block_associated_command{$cmdname})) {
          $pre_class_format
            = $Texinfo::Common::small_block_associated_command{$cmdname};
          $main_cmdname
            = $Texinfo::Common::small_block_associated_command{$cmdname};
        }
        push @pre_classes, $pre_class_format;
        my $pre_class;
        foreach my $class (@pre_classes) {
          # FIXME maybe add   or $pre_class eq 'menu'  to override
          # 'menu' with 'menu-comment'?
          $pre_class = $class unless ($pre_class
       and exists($Texinfo::Commands::preformatted_code_commands{$pre_class})
       and !(exists($Texinfo::Commands::preformatted_code_commands{$class})
             or $class eq 'menu'));
        }
        $pre_class = $pre_class.'-preformatted';

        # Add classes as done in the default conversion function.
        # TODO is it correct?  What should be done with @example arguments?
        my @classes;
        if ($cmdname eq 'example') {
          my $arguments_line = $command->{'contents'}->[0];
          if (exists($arguments_line->{'contents'})) {
            for my $example_arg (@{$arguments_line->{'contents'}}) {
              # convert or remove all @-commands, using simple ascii and unicode
              # characters
              my $converted_arg
               = Texinfo::Convert::NodeNameNormalization::convert_to_normalized(
                                                                   $example_arg);
              if ($converted_arg ne '') {
                push @classes, 'user-' . $converted_arg;
              }
            }
          }
        } elsif ($main_cmdname eq 'lisp') {
          push @classes, $main_cmdname;
          $main_cmdname = 'example';
        }
        unshift @classes, $main_cmdname;

        my $result_content
          = $highlighted_cmds{$cmdname}->{'results'}->{$command};
        # do it here, what was done in preformatted is discarded.
        # It should have been correctly registered
        # through highlight_open_inline_container_type.
        $result_content
            = $self->get_associated_formatted_inline_content($command)
                              . $result_content;
        # a newline immediately after a <pre> is ignored.
        $result_content =~ s/^\n/\n\n/;
        my $preformatted_result_content = $self->html_attribute_class('pre',
                                   [$pre_class]).">".$result_content."</pre>";
        return $self->html_attribute_class('div', \@classes).">\n"
               .$preformatted_result_content.'</div>'."\n";
      }
    # no error nor verbose message if there was no retrieved information
    # for that language
    } elsif (defined($language)
       and $highlighted_cmds{$cmdname}->{'retrieved_languages_counters'}
                                                            ->{$language}) {
      my $cmd_language_input_count
        = $highlighted_cmds{$cmdname}->{'input_languages_counters'}
                                                             ->{$language};
      my $cmd_language_retrieved_count
        = $highlighted_cmds{$cmdname}->{'retrieved_languages_counters'}
                                                              ->{$language};
      # Output an message only if the counters are equal, meaning language
      # was processed without failure.
      # If they are not equal there should have been a message already.
      if ($cmd_language_input_count == $cmd_language_retrieved_count) {
        $self->converter_document_warn(sprintf(__(
                "highlight_syntax.pm: output has no HTML item for \@%s %s %s"),
                                    $cmdname, $language, $command));
      } elsif ($self->get_conf('VERBOSE') or $self->get_conf('DEBUG')) {
        warn "highlight_syntax.pm: output has no HTML item for \@$cmdname $language $command\n";
      }
    }
  }

  # fall back on default conversion
  return &{$self->default_command_conversion($cmdname)}($self, $cmdname,
                                               $command, $args, $content);
}

1;
