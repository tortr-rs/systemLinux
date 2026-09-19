# Common.pm: Common code of other Texinfo modules.
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
# Parts (also from Patrice Dumas) come from texi2html.pl or texi2html.init.

package Texinfo::Common;

# for unicode/layer support in binmode
# for binmode documented as pushing :utf8 on top of :encoding
use 5.008001;

use strict;

# have :alpha: match only ASCII
use if $] >= 5.014, re => '/a';

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

# to determine the null file
use Config;
use File::Spec;
# for find_encoding, resolve_alias
use Encode;

# debugging
use Carp qw(cluck confess);

# uncomment to check that settable commands are contained in global commands
#use List::Compare;

use Locale::Messages;

use Texinfo::Report;

use Texinfo::Documentlanguages;
use Texinfo::Commands;
use Texinfo::Options;
use Texinfo::CommandsValues;

use Texinfo::TreeElement;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
collect_commands_in_tree
collect_commands_list_in_tree
valid_customization_option
valid_tree_transformation
);

# This is where the Texinfo modules get access to __( without explicit
# import.
our @EXPORT = qw(
__ __p
);

our $VERSION = '7.3';

# TODO document?
use constant {
   MESSAGES_TEXTDOMAIN => 'texinfo',
   DEFAULT_STRINGS_LANG => 'en',
};

# i18n
# For the messages translations.
sub __($) {
  my $msgid = shift;
  return Locale::Messages::dgettext(MESSAGES_TEXTDOMAIN, $msgid);
}

sub __p($$) {
  my $context = shift;
  my $msgid = shift;
  return Locale::Messages::dpgettext(MESSAGES_TEXTDOMAIN, $context, $msgid);
}


# For the in-document output strings translations in the texinfo_document
# textdomain.
#
# Return the string but do nothing else, used to mark strings to be translated
# in the Gettext framework.
# Can be used in other modules.
sub gdt($) {
  return $_[0];
}

# First argument is the translation context.
sub pgdt($$) {
  return $_[1];
}

# to be used when the context needs to be returned too
sub pgdt_context($$) {
  return [$_[0], $_[1]];
}


# determine the null device
my $default_null_device = File::Spec->devnull();
# Used in many converters and init files
our %null_device_file = (
  $default_null_device => 1
);

# equivalence between a @set flag and an @@-command
our %set_flag_command_equivalent = (
  'txicodequoteundirected' => 'codequoteundirected',
  'txicodequotebacktick'   => 'codequotebacktick',
#  'txideftypefnnl'         => 'deftypefnnewline',
);

our %command_equivalent_set_flag;
foreach my $flag (keys(%set_flag_command_equivalent)) {
  $command_equivalent_set_flag{$set_flag_command_equivalent{$flag}} = $flag;
}


# Customization options

# used in main program too, not documented
our %non_decoded_customization_variables;
foreach my $variable_name ('MACRO_EXPAND', 'INTERNAL_LINKS') {
  $non_decoded_customization_variables{$variable_name} = 1;
}

# can be modified through command-line, but not customization options
my %parser_document_state_configuration = (
  # parsed document parsing information still relevant after parsing
  'values' => {'txicommandconditionals' => 1},
                              # the key is the name, the value the @set name
                              # argument.
                              # The txicommandconditionals is a special value
                              # that is set to mark that @ifcommandnotdefined
                              # is implemented
);

# parser keys related to customization
# Set when initializing a parser, but never from command-line/init files
my %parser_inner_options = (
  'accept_internalvalue' => 0, # whether @txiinternalvalue should be added
                               # to the tree or considered invalid.
                               # currently set if called by gdt.
);

# this serves both to set defaults and list customization variable
# valid for the parser.
my $common_parser_regular_options_defaults
  = Texinfo::Options::get_regular_options('common_parser');
# used in main program, not documented
our %default_parser_customization_values = (
                  %Texinfo::Options::parser_options,
                  %$common_parser_regular_options_defaults);

# used in Parser, not documented
our %parser_document_parsing_options = (
                  %default_parser_customization_values,
                  %parser_document_state_configuration,
                  %parser_inner_options);

# check that settable commands are contained in global commands
# from command_data.txt
if (0) {
#if (1) {
  my @global_unique_settable = keys(%Texinfo::Options::unique_at_command_options);
  my @global_unique_commands = keys(%Texinfo::Commands::global_unique_commands);
  my $lcu = List::Compare->new(\@global_unique_settable, \@global_unique_commands);
  # only in the first list
  if (scalar($lcu->get_unique)) {
    warn 'BUG: Unique settable not global: '.join(',',$lcu->get_unique)."\n";
  }
  if (scalar($lcu->get_complement)) {
    print STDERR "REMARK: global_uniq commands not settable: "
                              .join(',', $lcu->get_complement)."\n";
  }

  my @global_multi_settable = keys(%Texinfo::Options::multiple_at_command_options);
  my @global_multi_commands = keys(%Texinfo::Commands::global_commands);
  my $lcm = List::Compare->new(\@global_multi_settable, \@global_multi_commands);
  if (scalar($lcm->get_unique)) {
    warn 'BUG: Multi settable not global: '.join(',',$lcm->get_unique)."\n";
  }
  if (scalar($lcm->get_complement)) {
    print STDERR "REMARK: global commands not settable: "
                                    .join(',', $lcm->get_complement)."\n";
  }
}

# defaults for the main program.
# In general transmitted to converters as defaults.
# Not used in converters, not documented
our %default_main_program_customization_options = (
 %Texinfo::Options::program_cmdline_options,
 %Texinfo::Options::program_customization_options);

# used in converters
our %document_settable_at_commands
  = (%Texinfo::Options::multiple_at_command_options,
     %Texinfo::Options::unique_at_command_options);

my %valid_customization_options;
foreach my $var (keys(%document_settable_at_commands),
         keys(%Texinfo::Options::program_cmdline_options),
         keys(%Texinfo::Options::converter_cmdline_options),
         keys(%Texinfo::Options::program_customization_options),
         keys(%Texinfo::Options::parser_options),
         keys(%Texinfo::Options::converter_customization_options),
         keys(%Texinfo::Options::converter_other_options),
         keys(%Texinfo::Options::array_cmdline_options)) {
  $valid_customization_options{$var} = 1;
}

sub valid_customization_option($) {
  my $option = shift;

  return $valid_customization_options{$option};
}


# Output formats

# used in main program
our %texinfo_output_formats;
foreach my $output_format_command ('info', 'plaintext',
       grep {$Texinfo::Commands::block_commands{$_} eq 'format_raw'}
            keys(%Texinfo::Commands::block_commands)) {
  $texinfo_output_formats{$output_format_command} = $output_format_command;
}


# constants.  Set by the main program.
my %build_constants;

# should only be called from the main program, not documented
sub set_build_constant($$) {
  my ($key, $value) = @_;

  $build_constants{$key} = $value;
}

sub get_build_constant($) {
  my $key = shift;

  return $build_constants{$key};
}


# Tree transformations

my %valid_tree_transformations;
foreach my $valid_transformation (
    'complete_tree_nodes_menus',
    'complete_tree_nodes_missing_menu',
    'fill_gaps_in_sectioning',
    'insert_nodes_for_sectioning_commands',
    'move_index_entries_after_items',
    'regenerate_master_menu',
    'relate_index_entries_to_table_items') {
  $valid_tree_transformations{$valid_transformation} = 1;
}

sub valid_tree_transformation($) {
  my $transformation = shift;

  return 1 if (defined($transformation)
               and exists($valid_tree_transformations{$transformation}));
  return 0;
}


# information on encodings

# in Texinfo up to 5.2, we presume that ISO-8859-1 was considered as
# the default encoding (although it had never been said explicitly in
# the manual, it is consistent with HTML output without encoding
# being the default for makeinfo output in earlier versions and being,
# at that time, considered as ISO-8859-1).  The wording in the Texinfo
# manual implied that setting US-ASCII had no effect, a possible
# interpretation being that it was an alias for ISO-8859-1.  Since
# ISO-8859-1 extends US-ASCII in a compatible way, this interpretation
# is valid.  Also, as long as the same 8bit encoding is used for input and
# output, the precise 8bit encoding used to extend US-ASCII has no
# practical consequence, something consistent with past makeinfo supporting
# any 8bit encoding without documentencoding and also when US-ASCII was
# specified as encoding.
#
# To support old manuals in which US-ASCII can be specified although
# the encoding corresponds to any 8bit encoding compatible with ISO-8859-1,
# we convert US-ASCII as ISO-8859-1 to avoid errors for characters in
# ISO-8859-1 but not in US-ASCII.
# Used in Parser, not documented in Pod nor in the manual on purpose, to
# be considered as not guaranteed backward compatibility.
our %encoding_name_conversion_map;
%encoding_name_conversion_map = (
  'us-ascii' => 'iso-8859-1',
  # The mapping to utf-8 is important for perl code, as it means using a strict
  # conversion to utf-8 and not a lax conversion:
  # https://perldoc.perl.org/perlunifaq#What's-the-difference-between-UTF-8-and-utf8?
  # In more detail, we want to use utf-8 only for two different reasons
  # 1) if input is malformed it is better to error out it as soon as possible
  # 2) we do not want to have different behaviour and hard to find bugs
  #    depending on whether the user used @documentencoding utf-8
  #    or @documentencoding utf8.  There is a warning with utf8, but
  #    we want to be clear in any case.
  'utf8' => 'utf-8',
);


# information on @-commands

# used in Parser, not documented
our %def_map = (
    # basic commands.
    # 'arg' and 'argtype' are for everything appearing after the other
    # arguments.
    'defline',     [ 'category', 'name', 'arg' ],
    'deftypeline', [ 'category', 'type', 'name', 'argtype' ],
    'deffn',     [ 'category', 'name', 'arg' ],
    'defvr',     [ 'category', 'name' ],
    'deftypefn', [ 'category', 'type', 'name', 'argtype' ],
    'deftypeop', [ 'category', 'class' , 'type', 'name', 'argtype' ],
    'deftypevr', [ 'category', 'type', 'name' ],
    'defcv',     [ 'category', 'class' , 'name' ],
    'deftypecv', [ 'category', 'class' , 'type', 'name' ],
    'defop',     [ 'category', 'class' , 'name', 'arg' ],
    'deftp',     [ 'category', 'name', 'argtype' ],
    # shortcuts
    # The strings are marked to be translated in the parsers in type
    # 'untranslated_def_line_arg'.
    'defun',         {'deffn'     => pgdt_context(
                                         'category of functions for @defun',
                                         'Function')},
    # TRANSLATORS: category of macros for @defmac
    'defmac',        {'deffn'     => gdt('Macro')},
    # TRANSLATORS: category of special forms for @defspec
    'defspec',       {'deffn'     => gdt('Special Form')},
    'defvar',        {'defvr'     => pgdt_context(
                                         'category of variables for @defvar',
                                          'Variable')},
    # TRANSLATORS: category of user-modifiable options for @defopt
    'defopt',        {'defvr'     => gdt('User Option')},
    'deftypefun',    {'deftypefn' => pgdt_context(
                      'category of functions for @deftypefun',
                                         'Function')},
    'deftypevar',    {'deftypevr' => pgdt_context(
                     'category of variables in typed languages for @deftypevar',
                                         'Variable')},
    'defivar',       {'defcv'     => pgdt_context(
      'category of instance variables in object-oriented programming for @defivar',
                                          'Instance Variable')},
    'deftypeivar',   {'deftypecv' => pgdt_context(
      'category of instance variables with data type in object-oriented programming for @deftypeivar',
                                          'Instance Variable')},
    'defmethod',     {'defop'     => pgdt_context(
       'category of methods in object-oriented programming for @defmethod',
                                         'Method')},
    'deftypemethod', {'deftypeop' => pgdt_context(
        'category of methods with data type in object-oriented programming for @deftypemethod',
                                         'Method')},
);

# Argument not metasyntactic variables only.
our %def_no_var_arg_commands;
our %def_aliases;
foreach my $def_command(keys %def_map) {
  if (ref($def_map{$def_command}) eq 'HASH') {
    my ($real_command) = keys(%{$def_map{$def_command}});
    $def_aliases{$def_command} = $real_command;
    $def_aliases{$def_command.'x'} = $real_command.'x';
  }
  $def_no_var_arg_commands{$def_command} = 1 if ($def_command =~ /^deftype/);
}

our %small_block_associated_command;
for my $cmd ('example', 'display', 'format', 'lisp', 'quotation',
             'indentedblock') {
  $small_block_associated_command{'small'.$cmd} = $cmd;
};

my %command_structuring_level
  = %Texinfo::CommandsValues::command_structuring_level;

# Not directly used in converters, not documented
our %level_to_structuring_command;

{
  my $sections = [ ];
  my $appendices = [ ];
  my $unnumbered = [ ];
  my $headings = [ ];

  # set levels for synonyms
  $level_to_structuring_command{'appendixsection'} = $appendices;
  $level_to_structuring_command{'majorheading'} = $headings;
  $level_to_structuring_command{'centerchap'} = $unnumbered;

  foreach my $command (keys (%command_structuring_level)) {
    next if (exists($level_to_structuring_command{$command}));
    if ($command =~ /^appendix/) {
      $level_to_structuring_command{$command} = $appendices;
    } elsif ($command =~ /^unnumbered/ or $command eq 'top') {
      $level_to_structuring_command{$command} = $unnumbered;
    } elsif ($command =~ /section$/ or $command eq 'chapter') {
      $level_to_structuring_command{$command} = $sections;
    } else {
      # no mapping for part, it is outside of the main hierarchy
      next if ($command eq 'part');
      $level_to_structuring_command{$command} = $headings;
    }
    my $command_level = $command_structuring_level{$command};
    if (defined($level_to_structuring_command{$command}->[$command_level])) {
      die "$command: level_to_structuring_command already set to "
             .$level_to_structuring_command{$command}->[$command_level]."\n";
    }
    $level_to_structuring_command{$command}->[$command_level]
      = $command;
  }
}

# %all_commands includes user-settable commands only.
# The internal commands are not in %all_commands.
# used in util/txicmdlist and in a check that needs to be manually
# enabled in HTML code
our %all_commands;
foreach my $command (
  keys(%Texinfo::Commands::block_commands),
  keys(%Texinfo::Commands::brace_commands),
  keys(%Texinfo::Commands::line_commands),
  keys(%Texinfo::Commands::nobrace_commands),
 ) {
  $all_commands{$command} = 1;
}

foreach my $internal_command (keys(%Texinfo::Commands::internal_commands)) {
  delete $all_commands{$internal_command};
}


# functions used in main program, Parser and/or Texinfo::Structuring.
# Not supposed to be called in user-defined code.

# ALTIMP C/main/utils.c analyze_documentlanguage_argument (no message)
# for Parser and main program
sub warn_unknown_language($) {
  my $lang = shift;

  my @messages = ();
  my $lang_code = $lang;
  my $region_code;

  if ($lang =~ /^([a-z]+)_([A-Z]+)$/) {
    $lang_code = $1;
    $region_code = $2;
  }

  if (! $Texinfo::Documentlanguages::language_codes{$lang_code}) {
    push @messages, sprintf(__("%s is not a valid language code"),
                            $lang_code);
  }
  if (defined($region_code)
       and ! $Texinfo::Documentlanguages::region_codes{$region_code}) {
    push @messages, sprintf(__("%s is not a valid region code"),
                            $region_code);
  }
  return @messages;
}

# next functions are for code used in Structuring or Indices in addition
# to Parser.  Also possibly used in Texinfo::Transformations.

# ALTIMP C/main/utils.c
sub ultimate_index($$) {
  my ($indices_information, $index) = @_;

  while (exists($index->{'merged_in'})) {
    $index = $indices_information->{$index->{'merged_in'}};
  }
  return $index;
}

# ALTIMP C/main/manipulate_tree.c
# relocate $SOURCE_MARKS source marks with position between
# $BEGIN_POSITION and $BEGIN_POSITION + $ADDED_LEN to be relative to
# $BEGIN_POSITION, and move to element $E.
# return $BEGIN_POSITION + $ADDED_LEN if there were source marks
sub relocate_source_marks($$$$) {
  my $source_marks = shift;

  return undef if (!defined($source_marks));

  my ($e, $begin_position, $added_len) = @_;

  my $end_position = $begin_position + $added_len;

  my @indices_to_remove;
  # collect source marks to remove starting from the beginning to keep
  # the correct order in the $e element.  Order indices to remove
  # in the reverse order to start from the last in order not to change
  # the array order when the entry is splice'd away.
  for (my $i = 0; $i < scalar(@$source_marks); $i++) {
    my $source_mark = $source_marks->[$i];
    if (($begin_position == 0
         and (!exists($source_mark->{'position'})
              # this should never happen
              or $source_mark->{'position'} == 0))
        or (exists($source_mark->{'position'})
            and $source_mark->{'position'} > $begin_position
            and $source_mark->{'position'} <= $end_position)) {
      unshift @indices_to_remove, $i;
      if (exists($e->{'text'})) {
        if ($source_mark->{'position'}) {
          $source_mark->{'position'}
             = $source_mark->{'position'} - $begin_position;
        } elsif ($begin_position) {
          warn "BUG: no $source_mark->{'position'} but $begin_position\n";
        }
      } else {
        # if the source mark is to be added to a command, it can only be right
        # after the command.  The current use case is a symbol with a source
        # mark after the symbol replaced by an @-command, so we are in
        # the case of $added_length = 1 and
        # $source_mark->{'position'} == $end_position
        if ($source_mark->{'position'}
            and $source_mark->{'position'} - $begin_position > 1) {
          warn "BUG? after command $source_mark->{'position'} way past $begin_position\n";
        }
        delete $source_mark->{'position'};
      }
      $e->{'source_marks'} = [] if (! exists($e->{'source_marks'}));
      push @{$e->{'source_marks'}}, $source_mark;
    } elsif (exists($source_marks->[$i]->{'position'})
             and $source_marks->[$i]->{'position'} > $end_position) {
      # only correct if positions are always monotonically increasing
      # but should be the case for now
      last;
    }
  }
  foreach my $i (@indices_to_remove) {
    splice (@$source_marks, $i, 1);
  }
  return $end_position;
}

sub _find_end_brace($$) {
  my ($text, $braces_count) = @_;

  my $before = '';
  while ($braces_count > 0 and length($text)) {
    if ($text =~ s/([^()]*)([()])//) {
      $before .= $1.$2;
      my $brace = $2;
      if ($brace eq '(') {
        $braces_count++;
      } else {
        $braces_count--;
        if ($braces_count == 0) {
          return ($before, $text, 0);
        }
      }
    } else {
      $before .= $text;
      $text = '';
    }
  }
  return ($before, undef, $braces_count);
}

# This only counts opening braces, and returns 0 once all the parentheses
# are closed
sub _count_opened_tree_braces($$);
sub _count_opened_tree_braces($$) {
  my ($current, $braces_count) = @_;

  if (defined($current->{'text'})) {
    my ($before, $after);
    ($before, $after, $braces_count) = _find_end_brace($current->{'text'},
                                                          $braces_count);
  }
  return $braces_count;
}

# ALTIMP C/main/manipulate_tree.c
# retrieve a leading manual name in parentheses, if there is one.
# $LABEL_CONTENTS_CONTAINER->{'contents'} is the Texinfo for the specification
# of a node.  It is relevant in any situation when a label is expected,
# @node, menu entry, float, anchor...  For the @node command, for instance,
# $LABEL_CONTENTS_CONTAINER is typically
# $node->{'contents'}->[0]->{'contents'}->[0].
#
# Returned object is a hash with two fields:
#
#     manual_content - Texinfo tree for a manual name extracted from the
#                      node specification.
#     node_content - Texinfo tree for the node name on its own
#
# If $MODIFY_TREE is set and manual name is retrieved, modify the
# $LABEL_CONTENTS_CONTAINER contents such that the parentheses, the manual
# part and the node part are not in the same elements in the contents,
# and use the corresponding elements in the returned object.
#
# Could be documented, but only if there is evidence that this function
# is useful in user-defined code.
sub parse_node_manual($;$) {
  my ($label_contents_container, $modify_node) = @_;

  return undef if (!exists($label_contents_container->{'contents'}));

  my $contents = $label_contents_container->{'contents'};

  my $idx = 0;

  my $manual;
  my $result;
  my $node_content = [];

  if (exists($contents->[0]->{'text'}) and $contents->[0]->{'text'} =~ /^\(/) {
    my ($new_first, $opening_brace);
    $manual = [];
    my $braces_count = 1; # Number of ( seen minus number of ) seen.
    # the leading ( from @$contents is not in manual.
    # If the first contents element is "(" followed by more text, split
    # the leading "(" into its own element.
    my $first = $contents->[0];
    if ($first->{'text'} ne '(') {
      if ($modify_node) {
        $opening_brace
          = Texinfo::TreeElement::new({'text' => '('});
      }
      my $brace_text = $first->{'text'};
      $brace_text =~ s/^\(//;
      $new_first = Texinfo::TreeElement::new({'text' => $brace_text});
    } else {
      # first element is "(", it is not part of the manual, keep it
      $idx++;
    }
    for (; $idx < scalar(@$contents); $idx++) {
      my $content;
      if ($idx == 0) {
        $content = $new_first;
      } else {
        $content = $contents->[$idx];
      }
      if (!exists($content->{'text'}) or $content->{'text'} !~ /\)/) {
        push @$manual, $content;
        $braces_count = _count_opened_tree_braces($content, $braces_count);
        # This is an error, braces were closed in a command
        if ($braces_count == 0) {
          last;
        }
      } else {
        my ($before, $after);
        ($before, $after, $braces_count) = _find_end_brace($content->{'text'},
                                                              $braces_count);
        if ($braces_count == 0) {
          my $current_position = 0;
          # At this point, we are sure that there is a manual part,
          # so the pending removal/addition of elements at the beginning
          # of the manual can proceed (if modify_node).
          if ($modify_node) {
            if ($opening_brace) {
              # remove the original $first first element and prepend the
              # split "(" and text elements
              shift @$contents;
              unshift @$contents, $new_first;
              unshift @$contents, $opening_brace;
              $idx++;
              if (exists($first->{'source_marks'})) {
                my $current_position = relocate_source_marks(
                                   $first->{'source_marks'}, $opening_brace,
                                   0, length($opening_brace->{'text'}));
                relocate_source_marks($first->{'source_marks'}, $new_first,
                              $current_position, length($new_first->{'text'}));
              }
            }
            # Remove current element $content with closing brace from the tree.
            splice(@$contents, $idx, 1);
          }

          # remove the closing ), it is not in manual_content
          $before =~ s/(\))$//;
          if ($before ne '') {
            # text before ), part of the manual name
            my $last_manual_element
              = Texinfo::TreeElement::new({ 'text' => $before });
            push @$manual, $last_manual_element;
            if ($modify_node) {
              splice(@$contents, $idx, 0, $last_manual_element);
              $idx++;
              $current_position = relocate_source_marks(
                         $content->{'source_marks'}, $last_manual_element,
                         $current_position, length($before));
            }
          }
          if ($modify_node) {
            my $closing_brace
              = Texinfo::TreeElement::new({'text' => ')'});
            splice(@$contents, $idx, 0, $closing_brace);
            $idx++;
            $current_position = relocate_source_marks(
                         $content->{'source_marks'}, $closing_brace,
                         $current_position, length($closing_brace->{'text'}));
          }
          $after =~ s/^(\s*)//;
          my $spaces_after = $1;
          if ($spaces_after and $modify_node) {
            my $spaces_element
              = Texinfo::TreeElement::new({'text' => $spaces_after,});
            splice(@$contents, $idx, 0, $spaces_element);
            $idx++;
            $current_position = relocate_source_marks(
                         $content->{'source_marks'}, $spaces_element,
                         $current_position, length($spaces_after));
          }
          if ($after ne '') {
            # text after ), part of the node name.
            my $leading_node_content
              = Texinfo::TreeElement::new({'text' => $after});
            push @$node_content, $leading_node_content;
            if ($modify_node) {
              splice(@$contents, $idx, 0, $leading_node_content);
              $current_position = relocate_source_marks(
                           $content->{'source_marks'}, $leading_node_content,
                           $current_position, length($after));
            }
            $idx++;
          }
          last;
        } else {
          push @$manual, $content;
        }
      }
    }
    if ($braces_count != 0) {
      # unclosed brace, reset
      $manual = undef;
      $idx = 0;
    } else {
      $result = {};
      $result->{'manual_content'}
        = Texinfo::TreeElement::new({'contents' => $manual});
    }
  }

  if ($idx < scalar(@$contents)) {
    push(@$node_content, @$contents[$idx .. scalar(@$contents)-1]);
  }

  if (scalar(@$node_content)) {
    $result = Texinfo::TreeElement::new({}) if (!defined($result));
    $result->{'node_content'}
      = Texinfo::TreeElement::new({'contents' => $node_content});
  }

  return $result;
}



# misc functions used in diverse contexts and useful in converters

# Wrapper around File::Spec->canonpath that replace backslashes by
# forward slashes.
sub file_separator_canonpath($) {
  my $dir = shift;

  my $canon_dir = File::Spec->canonpath($dir);

  # normalize to forward slash, as we use forward slashes as much as
  # possible in the code.
  if ($^O eq 'MSWin32') {
    my @dir_parts = File::Spec->splitdir($canon_dir);
    return join('/', @dir_parts);
  } else {
    return $canon_dir;
  }
}

# ALTIMP C/convert/converter.c
# Used in converters
# find the accent commands stack and the innermost text contents
sub find_innermost_accent_contents($) {
  my $current = shift;

  my @accent_commands = ();
  my $debug = 0;
 ACCENT:
  while (1) {
    my $current_cmdname = $current->{'cmdname'};
    # the following can happen if called with a bad tree
    if (!defined($current_cmdname)
        or !exists($Texinfo::Commands::accent_commands{$current_cmdname})) {
      #print STDERR "BUG: Not an accent command in accent\n";
      cluck "BUG: Not an accent command in accent\n";
      #print STDERR Texinfo::Convert::Texinfo::convert_to_texinfo($current)."\n";
      #print STDERR Data::Dumper->Dump([$current]);
      return (undef, \@accent_commands);
    }
    push @accent_commands, $current;
    # A bogus accent, that may happen
    if (!exists($current->{'contents'})) {
      return (undef, \@accent_commands);
    }
    my $arg = $current->{'contents'}->[0];
    if (!exists($arg->{'contents'})) {
      return (undef, \@accent_commands);
    }
    # inside the argument of an accent
    my $text_contents = [];
    foreach my $content (@{$arg->{'contents'}}) {
      if (exists($content->{'cmdname'})) {
        my $cmdname = $content->{'cmdname'};
        if (exists($Texinfo::Commands::accent_commands{$cmdname})) {
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
    my $element_inside
        = Texinfo::TreeElement::new({'contents' => $text_contents});
    return ($element_inside, \@accent_commands);
  }
}

# ALTIMP C/main/utils.c
# TODO document
# Used in converters
sub multitable_columnfractions($) {
  my $multitable = shift;

  my $arguments_line = $multitable->{'contents'}->[0];
  my $block_line_arg = $arguments_line->{'contents'}->[0];
  my $columnfractions;
  if (exists($block_line_arg->{'contents'})
      and $block_line_arg->{'contents'}->[0]->{'cmdname'}
      and $block_line_arg->{'contents'}->[0]->{'cmdname'}
                                              eq 'columnfractions') {
    $columnfractions = $block_line_arg->{'contents'}->[0];
  }

  return $columnfractions;
}

# ALTIMP C/main/utils.c
# there is a command as argument for a block command (@itemize or
# @table, @vtable...) if there is only one argument on the line,
# it is a brace command but not an accent command and it is empty.
sub block_line_argument_command($) {
  my $block_line_arg = shift;

  if (exists($block_line_arg->{'contents'})
      and scalar(@{$block_line_arg->{'contents'}}) == 1) {
    my $arg = $block_line_arg->{'contents'}->[0];
    if (exists($arg->{'cmdname'})
        and (!exists($arg->{'contents'})
             or (scalar(@{$arg->{'contents'}}) == 1
                 and !exists($arg->{'contents'}->[0]->{'contents'})))) {
      my $cmdname = $arg->{'cmdname'};
      if ((exists($Texinfo::Commands::brace_commands{$cmdname})
           and !exists($Texinfo::Commands::accent_commands{$cmdname}))
          or (exists($arg->{'type'})
              and $arg->{'type'} eq 'definfoenclose_command')) {
        return $arg;
      }
    }
  }
  return undef;
}

my $default_bullet_command = Texinfo::TreeElement::new({'cmdname' => 'bullet'});

# ALTIMP C/main/convert_utils.c
sub itemize_line_prepended_element($) {
  my $block_line_arg = shift;

  my $arg = block_line_argument_command($block_line_arg);
  if (defined($arg)) {
    return $arg;
  } elsif (!exists($block_line_arg->{'contents'})) {
    return $default_bullet_command;
  } else {
    return $block_line_arg;
  }
}

# ALTIMP main/convert_utils.c
sub item_itemize_prepended($) {
  my $element = shift;

  # parent line arguments_line type element
  my $arguments_line = $element->{'parent'}->{'contents'}->[0];
  my $block_line_arg = $arguments_line->{'contents'}->[0];

  return itemize_line_prepended_element($block_line_arg);
}

# ALTIMP C/main/convert_utils.c
sub item_line_block_line_argument_command($) {
  my $block_line_arg = shift;

  my $arg = block_line_argument_command($block_line_arg);

  if (defined($arg)) {
    my $brace_category = $Texinfo::Commands::brace_commands{$arg->{'cmdname'}};
    # $Texinfo::Commands::brace_commands{} is undef
    # for definfoenclose'd commands
    if (defined($brace_category) and $brace_category eq 'noarg') {
      $arg = undef;
    }
  }
  return $arg;
}

my $default_asis_command = Texinfo::TreeElement::new({'cmdname' => 'asis'});

# ALTIMP C/main/convert_utils.c
# always return something
sub block_item_line_command($) {
  my $block_line_arg = shift;

  my $arg = item_line_block_line_argument_command($block_line_arg);

  if (!defined($arg)) {
    $arg = $default_asis_command;
  }
  return $arg;
}

# ALTIMP C/main/utils.c
sub find_float_caption_shortcaption($) {
  my $float = shift;

  my $caption;
  my $shortcaption;

  foreach my $content (@{$float->{'contents'}}) {
    if (exists($content->{'cmdname'})) {
      if ($content->{'cmdname'} eq 'caption') {
        $caption = $content unless($caption);
        last if $shortcaption;
      } elsif ($content->{'cmdname'} eq 'shortcaption') {
        $shortcaption = $content unless($shortcaption);
        last if $caption;
      }
    }
  }
  return ($caption, $shortcaption);
}

# ALTIMP C/main/utils.c
# TODO document
# used in Texinfo::Indices and converters
sub collect_subentries($$);
sub collect_subentries($$) {
  my ($current, $subentries) = @_;

  my $line_arg = $current->{'contents'}->[0];
  foreach my $content (@{$line_arg->{'contents'}}) {
    if (exists($content->{'cmdname'})
        and $content->{'cmdname'} eq 'subentry') {
      push @$subentries, $content;
      collect_subentries($content, $subentries);
    }
  }
}

sub index_entry_referred_entry($$);

# ALTIMP C/main/utils.c
# TODO document
# Used in converters
sub index_entry_referred_entry($$) {
  my ($element, $referred_cmdname) = @_;

  my $line_arg = $element->{'contents'}->[0];

  if (exists($line_arg->{'contents'})) {
    foreach my $content (@{$line_arg->{'contents'}}) {
      if (exists($content->{'cmdname'})) {
        if ($content->{'cmdname'} eq $referred_cmdname) {
          return $content->{'contents'}->[0]
                                 if (exists($content->{'contents'}));
        } elsif ($content->{'cmdname'} eq 'subentry') {
          return index_entry_referred_entry($content, $referred_cmdname);
        }
      }
    }
  }
  return undef;
}

# ALTIMP C/main/utils.c
# Used in main program, tests and HTML Converter.
# TODO document?
#
# $INPUT_FILE_PATH: file name to locate.  Binary string.  If it is a file
#                   path, it is not searched for in directories.
# $DIRECTORIES: a reference on a array containing a list of directories to
#               search the file in. Binary strings.
# $ALL_FILES:   if true collect all the files with that name, otherwise stop
#               at first match.
# $DEPRECATED_DIRS:  optional argument.  If set, associates deprecated directory
#                    names with the directory name that should be used
#
# Return an array reference with the files found, only one if $ALL_FILES
# is false, and an array reference with the deprecated directories used.
sub locate_file_in_dirs($$$;$) {
  my ($input_file_path, $directories, $all_files, $deprecated_dirs) = @_;

  my $deprecated_dirs_used;

  if (File::Spec->file_name_is_absolute($input_file_path)) {
    return ([$input_file_path], undef)
       if (-e $input_file_path and -r $input_file_path);
  } else {
    my ($volume, $path_directories, $file)
       = File::Spec->splitpath($input_file_path);
    my @path_directories = File::Spec->splitdir($path_directories);
    if (scalar(@path_directories) > 0) {
      # do not search in directories if the file name already contains
      # directories.
      return ([$input_file_path], undef)
         if (-e $input_file_path and -r $input_file_path);
    } else {
      my @files;
      foreach my $dir (@$directories) {
        next unless (-d $dir);
        my $possible_file = "$dir/$input_file_path";
        if (-e $possible_file and -r $possible_file) {
          if ($deprecated_dirs and $deprecated_dirs->{$dir}) {
            $deprecated_dirs_used = [] if (!defined($deprecated_dirs_used));
            push @$deprecated_dirs_used, $dir;
          }
          if ($all_files) {
            push (@files, $possible_file);
          } else {
            return [$possible_file], $deprecated_dirs_used;
          }
        }
      }
      return (\@files, $deprecated_dirs_used)
        if ($all_files and scalar(@files));
    }
  }
  return undef, undef;
}

sub processing_output_encoding($) {
  my $encoding = shift;

  my $perl_encoding;

  if (defined($encoding) and $encoding ne '') {
    $encoding = $encoding_name_conversion_map{$encoding}
      if (defined($encoding_name_conversion_map{$encoding}));
    my $Encode_encoding_object = Encode::find_encoding($encoding);
    if (defined($Encode_encoding_object)) {
      $perl_encoding = $Encode_encoding_object->name();
      $perl_encoding = undef if (defined($perl_encoding)
                                 and $perl_encoding eq '');
    }
  }

  return $perl_encoding;
}

sub associated_processing_encoding($) {
  my $element = shift;

  my $encoding = $element->{'extra'}->{'input_encoding_name'}
    if (exists($element->{'extra'}));

  return processing_output_encoding($encoding);
}

# Reverse the decoding of the file name from the input encoding.  When
# dealing with file names, we want Perl strings representing sequences of
# bytes, not Unicode codepoints.
#     This is necessary even if the name of the included file is purely
# ASCII, as the name of the directory it is located within may contain
# non-ASCII characters.
#   Otherwise, the -e operator and similar may not work correctly.
sub encode_file_name($$) {
  my ($file_name, $input_encoding) = @_;

  my $encoding;

  return ($file_name, $encoding)
    if (not defined($input_encoding));

  if ($input_encoding eq 'utf-8' or $input_encoding eq 'utf-8-strict') {
    $encoding = 'utf-8';
  } else {
    $encoding = $input_encoding;
  }
  my $encoded_file_name = Encode::encode($encoding, $file_name);
  return ($encoded_file_name, $encoding);
}

# ALTIMP C/main/utils.c
sub locate_include_file($;$) {
  my ($input_file_path, $include_directories) = @_;

  my $ignore_include_directories = 0;

  # If the path is absolute or begins with . or .., do not search in
  # include directories.  This is consistent with Kpathsea for Texinfo TeX.
  if (File::Spec->file_name_is_absolute($input_file_path)) {
    $ignore_include_directories = 1;
  } else {
    my ($volume, $directories, $filename)
      = File::Spec->splitpath($input_file_path);
    my @directories = File::Spec->splitdir($directories);

    foreach my $dir (@directories) {
      if ($dir eq File::Spec->updir() or $dir eq File::Spec->curdir()) {
        $ignore_include_directories = 1;
        last;
      } elsif ($dir ne '') {
        last;
      }
    }
  }

  if ($ignore_include_directories) {
    if (-e $input_file_path and -r $input_file_path) {
      return $input_file_path;
    }
  } else {
    if (!$include_directories) {
      # no directory list and not an absolute path, never succeed
      return undef;
    }
    foreach my $include_dir (@$include_directories) {
      my $possible_file = "$include_dir/$input_file_path";
      if (-e $possible_file and -r $possible_file) {
        return $possible_file;
      }
    }
  }
  return undef;
}

# ALTIMP C/main/utils.c
# TODO document?
sub informative_command_value($) {
  my $element = shift;

  my ($cmdname, $value) = element_value_equivalent($element);

  if (defined($cmdname)) {
    return ($cmdname, $value);
  }

  $cmdname = $element->{'cmdname'};
  $cmdname = 'shortcontents' if ($cmdname eq 'summarycontents');

  if ($Texinfo::Commands::line_commands{$cmdname} eq 'lineraw') {
    if (not $Texinfo::Commands::commands_args_number{$cmdname}) {
      return $cmdname, 1;
    } elsif (exists($element->{'contents'})) {
      return $cmdname, join(' ', map {$_->{'text'}} @{$element->{'contents'}});
    }
  } elsif (exists($element->{'extra'})
           and exists($element->{'extra'}->{'text_arg'})) {
    return $cmdname, $element->{'extra'}->{'text_arg'};
  } elsif (exists($element->{'extra'})
           and exists($element->{'extra'}->{'misc_args'})
           and exists($element->{'extra'}->{'misc_args'}->[0])) {
    return $cmdname, $element->{'extra'}->{'misc_args'}->[0];
  } elsif ($Texinfo::Commands::line_commands{$cmdname} eq 'line'
           and exists($element->{'contents'}->[0]->{'contents'})
           and exists($element->{'contents'}->[0]->{'contents'}->[0]->{'text'})) {
    return $cmdname, $element->{'contents'}->[0]->{'contents'}->[0]->{'text'};
  }
  return undef, undef;
}

# ALTIMP C/main/utils.c
# Handle @set txicodequoteundirected as an
# alternative to @codequoteundirected.
sub element_value_equivalent($) {
  my $element = shift;

  my $cmdname = $element->{'cmdname'};

  if ($cmdname eq 'set' or $cmdname eq 'clear') {
    my $misc_args;
    if (exists($element->{'extra'})
        and exists($element->{'extra'}->{'misc_args'})) {
      $misc_args = $element->{'extra'}->{'misc_args'};
      if (scalar(@$misc_args)) {
        my $flag = $misc_args->[0];
        my $equivalent_cmdname = $set_flag_command_equivalent{$flag};
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
    # returning a cmdname avoid having the argument checked, and
    # having an undef value means that the value will be ignored.
    # So this return value leads to the command being ignored.
    return ($cmdname, undef);
  }

  return (undef, undef);
}

# ALTIMP C/main/customization_options.c
# REMARK documentencoding handling is not reverted by resetting a value with
# set_conf, as the encodings are set using other sources of information
# (possibly based on @documentencoding) in converter.
sub set_informative_command_value($$) {
  my ($self, $element) = @_;

  my ($cmdname, $value) = informative_command_value($element);

  if (defined($value)) {
    my $set = $self->set_conf($cmdname, $value);
    return $set;
  }
  return 0;
}

sub _in_preamble($) {
  my $element = shift;

  my $current_element = $element;
  while (exists($current_element->{'parent'})) {
    if (exists($current_element->{'parent'}->{'type'})
        and $current_element->{'parent'}->{'type'} eq 'preamble_before_content') {
      return 1;
    }
    $current_element = $current_element->{'parent'};
  }
  return 0;
}

# ALTIMP C/main/utils.c
# $COMMAND_LOCATION is 'last', 'preamble' or 'preamble_or_first'
# 'preamble' means setting sequentially to the values in the preamble.
# 'preamble_or_first'  means setting to the first value for the command
# in the document if the first command is not in the preamble, else set
# sequentially to the values in the preamble.
# 'last' means setting to the last value for the command in the document.
#
# For unique command, the last may be considered to be the same as the first.
sub get_global_document_command($$$) {
  my ($global_commands_information, $global_command, $command_location) = @_;

  if ($command_location ne 'last' and $command_location ne 'preamble_or_first'
      and $command_location ne 'preamble') {
    warn "BUG: get_global_document_command: unknown command_location: $command_location";
  }

  my $element;
  if (defined($global_commands_information)
      and $global_commands_information->{$global_command}) {
    if (ref($global_commands_information->{$global_command}) eq 'ARRAY') {
      if ($command_location eq 'last') {
        $element = $global_commands_information->{$global_command}->[-1];
      } else {
        if ($command_location eq 'preamble_or_first'
            and not _in_preamble($global_commands_information->{$global_command}->[0])) {
          $element =
            $global_commands_information->{$global_command}->[0];
        } else {
          foreach my $command_element (@{$global_commands_information->{$global_command}}) {
            if (_in_preamble($command_element)) {
              $element = $command_element;
            } else {
              last;
            }
          }
        }
      }
    } else {
      # unique command, first, preamble and last are the same
      $element = $global_commands_information->{$global_command};
    }
  }
  return $element;
}

# ALTIMP C/main/customization_options.c
# Notice that the only effect is to use set_conf (directly or through
# set_informative_command_value), no @-commands setting side effects are done
# and associated customization variables are not set/reset either.
sub set_global_document_command($$$$) {
  my ($self, $global_commands_information, $global_command,
      $command_location) = @_;

  my $element = get_global_document_command($global_commands_information,
                                            $global_command, $command_location);

  if ($element) {
    set_informative_command_value($self, $element);
  }
  return $element;
}

# ALTIMP C/main/utils.c
sub lookup_index_entry($$) {
  my ($index_entry_info, $indices_information) = @_;

  if (!defined($index_entry_info)) {
    cluck ("BUG: lookup_index_entry: index_entry_info undef\n");
  }
  my ($entry_index_name, $entry_number) = @{$index_entry_info};

  my $index_info;

  if ($indices_information->{$entry_index_name}) {
    $index_info = $indices_information->{$entry_index_name};
    if (exists($index_info->{'index_entries'})
        and $index_info->{'index_entries'}->[$entry_number-1]) {
      return ($index_info->{'index_entries'}->[$entry_number-1], $index_info);
    }
  }
  return (undef, $index_info);
}

# only used from Perl
# Remove or replace first $REMOVED from $ARRAY
sub replace_remove_list_element($$;$) {
  my ($array, $removed, $replacement) = @_;

  #if (!defined($array)) {
  #  cluck();
  #}

  for (my $index = 0; $index < scalar(@$array); $index++) {
    if ($array->[$index] eq $removed) {
      if (!defined($replacement)) {
        return splice(@$array, $index, 1);
      } else {
        return splice(@$array, $index, 1, $replacement);
      }
    }
  }
  return undef;
}

# ALTIMP C/main/document.c
sub set_output_encoding($$) {
  my ($customization_information, $document) = @_;

  my $document_information;
  if (defined($document)) {
    $document_information = $document->global_information();
  }

  if (!defined($customization_information->get_conf('OUTPUT_ENCODING_NAME'))
      and defined($document_information)
      and exists($document_information->{'input_encoding_name'})) {
    $customization_information->set_conf('OUTPUT_ENCODING_NAME',
                 $document_information->{'input_encoding_name'})
  }
}

# ALTIMP C/main/utils.c
# $DOCUMENT is the parsed Texinfo document.  It is optional, but it
# is recommended to pass it to get the input encoding name.
# The input file encoding can be given as $INPUT_FILE_ENCODING optional
# argument, it will be used if $DOC_ENCODING_FOR_INPUT_FILE_NAME is
# undef or set.
sub input_file_name_encoding($$$;$$) {
  my ($name_encoding, $doc_encoding_for_input_file_name, $locale_encoding,
      $document, $input_file_encoding) = @_;

  my $encoding;

  if (defined($name_encoding)) {
    $encoding = $name_encoding;
  } elsif (!defined($doc_encoding_for_input_file_name)
           or $doc_encoding_for_input_file_name) {
    if (defined($input_file_encoding)) {
      $encoding = $input_file_encoding;
    } else {
      my $document_info;

      if ($document) {
        $document_info = $document->global_information();
      }

      $encoding = $document_info->{'input_encoding_name'}
        if (defined($document_info)
          and exists($document_info->{'input_encoding_name'}));
    }
  } else {
    $encoding = $locale_encoding;
  }

  return $encoding;
}

my $min_level = $command_structuring_level{'chapter'};
my $max_level = $command_structuring_level{'subsubsection'};

# ALTIMP C/main/utils.c
# Return numbered level of an element, as modified by raise/lowersections
sub section_level($) {
  my $section = shift;

  my $level = $command_structuring_level{$section->{'cmdname'}};
  # correct level according to raise/lowersections
  if (exists($section->{'extra'})
      and $section->{'extra'}->{'level_modifier'}) {
    $level -= $section->{'extra'}->{'level_modifier'};
    if ($level < $min_level) {
      if ($command_structuring_level{$section->{'cmdname'}} < $min_level) {
        $level = $command_structuring_level{$section->{'cmdname'}};
      } else {
        $level = $min_level;
      }
    } elsif ($level > $max_level) {
      $level = $max_level;
    }
  }
  return $level;
}

# decompose a decimal number on a given base.  It is not the
# decomposition used for counting as we start at 0, not 1 for all
# the factors.  This is in order to get aa and not ba in calling
# code.
sub _decompose_integer($$) {
  my ($number, $base) = @_;

  my @result = ();

  while ($number >= 0) {
    my $factor = $number % $base;
    push (@result, $factor);
    $number = int(($number - $factor) / $base) - 1;
  }
  return @result;
}

# ALTIMP C/main/utils.c
sub enumerate_number_representation($$) {
  my ($specification, $number) = @_;

  if ($specification =~ /^[[:alpha:]]$/) {
    my $result = '';
    my $base_letter = ord('a');
    $base_letter = ord('A') if (ucfirst($specification) eq $specification);
    my @letter_ords
        = _decompose_integer(ord($specification) - $base_letter + $number - 1, 26);
    foreach my $ord (@letter_ords) {
      $result = chr($base_letter + $ord) . $result;
    }
    return $result;
  } elsif ($specification =~ /^[0-9]+$/) {
    return $specification + $number -1;
  }
  return $number;
}

# ALTIMP C/main/utils.c
sub enumerate_item_representation($) {
  my $element = shift;

  my $number = $element->{'extra'}->{'item_number'};

  my $enumerate = $element->{'parent'};
  my $arguments_line = $enumerate->{'contents'}->[0];
  my $block_line_arg = $arguments_line->{'contents'}->[0];

  if (exists($block_line_arg->{'contents'})
      and exists($block_line_arg->{'contents'}->[0]->{'text'})) {
    return enumerate_number_representation(
                  $block_line_arg->{'contents'}->[0]->{'text'}, $number);
  }
  return $number;
}

# ALTIMP C/main/utils.c
sub is_content_empty($;$);
sub is_content_empty($;$) {
  my ($tree, $do_not_ignore_index_entries) = @_;

  if (!defined($tree) or !exists($tree->{'contents'})) {
    return 1;
  }

  foreach my $content (@{$tree->{'contents'}}) {
    if (exists($content->{'text'})) {
      if ($content->{'text'} =~ /\S/) {
        return 0;
      } else {
        next;
      }
    }
    next if (exists($content->{'type'})
             and $content->{'type'} eq 'arguments_line');
    if (exists($content->{'cmdname'})) {
      if (exists($content->{'type'})
          and $content->{'type'} eq 'index_entry_command') {
        if ($do_not_ignore_index_entries) {
          return 0;
        } else {
          next;
        }
      }
      if (exists($Texinfo::Commands::line_commands{$content->{'cmdname'}})) {
        if (exists(
             $Texinfo::Commands::formatted_line_commands{$content->{'cmdname'}})
            or exists(
                $Texinfo::Commands::formattable_line_commands{$content->{'cmdname'}})) {
          return 0;
        } else {
          next;
        }
      } elsif (exists(
                $Texinfo::Commands::nobrace_commands{$content->{'cmdname'}})) {
        if (exists(
            $Texinfo::Commands::formatted_nobrace_commands{$content->{'cmdname'}})) {
          return 0;
        } else {
          next;
        }
      } elsif (exists(
                $Texinfo::Commands::non_formatted_brace_commands{$content->{'cmdname'}})
               or exists(
                   $Texinfo::Commands::non_formatted_block_commands{$content->{'cmdname'}})) {
        next;
      } else {
        return 0;
      }
    }
    if (exists($content->{'type'})) {
      if ($content->{'type'} eq 'paragraph') {
        return 0;
      }
    }
    if (not is_content_empty($content, $do_not_ignore_index_entries)) {
      return 0;
    }
  }
  return 1;
}

# if in this container, we are 'inline', within a running text
my @inline_types = ('def_line', 'paragraph', 'preformatted',
  'line_arg', 'block_line_arg', 'menu_entry_name', 'menu_entry_node');

my %inline_types;
foreach my $type (@inline_types) {
  $inline_types{$type} = 1;
}

my %not_inline_commands;
foreach my $command (
     keys(%Texinfo::Commands::root_commands),
     keys(%Texinfo::Commands::block_commands),
     grep {$Texinfo::Commands::brace_commands{$_} eq 'context'}
           keys(%Texinfo::Commands::brace_commands)) {
  $not_inline_commands{$command} = 1;
}

# Return 1 if inline in a running text, 0 if right in top-level or block
# environment, and undef otherwise.
# internal, not documented.
sub element_inline_or_block($) {
  my $current = shift;

  if (exists($current->{'type'}) and $inline_types{$current->{'type'}}) {
    return 1;
  } else {
    my $cmdname = $current->{'cmdname'};
    if (exists($current->{'cmdname'})
        and exists($not_inline_commands{$current->{'cmdname'}})) {
      return 0;
    }
  }
  return undef;
}

# return true if in running text context.
# If $CHECK_CURRENT is set, check the element itself, too, in
# addition to the parent context.
sub element_is_inline($;$) {
  my ($current, $check_current) = @_;

  if ($check_current) {
    my $inline_or_block = element_inline_or_block($current);
    return ($inline_or_block) if (defined($inline_or_block));
  }

  while (exists($current->{'parent'})) {
    $current = $current->{'parent'};
    my $inline_or_block = element_inline_or_block($current);
    return ($inline_or_block) if (defined($inline_or_block));
  }
  return 0;
}



sub normalize_top_node_name($) {
  my $node_name = shift;

  if ($node_name =~ /^top$/i) {
    return 'Top';
  }
  return $node_name;
}

# Used in count_bytes
my $Encode_encoding_object;
my $last_encoding;

# Only used in the unmaintained IXIN converter, but could be useful in
# other converters, so it is better to keep it.
sub count_bytes($;$) {
  my ($string, $encoding) = @_;

  # TODO encoding is unlikely to be ascii, as documentencoding ascii
  # is mapped to output encoding name us-ascii, also it may have been
  # better to call Texinfo::Common::processing_output_encoding, in
  # which case us-ascii would be mapped to iso-8859-1.
  if (defined($encoding) and $encoding ne 'ascii') {
    if (!defined($last_encoding) or $last_encoding ne $encoding) {
      # Look up and save encoding object for next time.  This is
      # slightly faster than calling Encode::encode.
      $last_encoding = $encoding;
      $Encode_encoding_object = Encode::find_encoding($encoding);
      if (!defined($Encode_encoding_object)) {
        Carp::croak "Unknown encoding '$encoding'";
      }
    }
    return length($Encode_encoding_object->encode($string));
  } else {
    return length($string);
  }
}

# ALTIMP C/main/manipulate_indices.c
# if $PREFER_REFERENCE_ELEMENT is set, prefer an untranslated element.
# Seems to be used in converter only
sub index_content_element($;$) {
  my ($element, $prefer_reference_element) = @_;

  if (exists($element->{'extra'})
      and exists($element->{'extra'}->{'def_command'})) {
    if ($prefer_reference_element
        and exists($element->{'extra'}->{'def_index_ref_element'})) {
      return $element->{'extra'}->{'def_index_ref_element'};
    } else {
      return $element->{'extra'}->{'def_index_element'};
    }
  } else {
    return $element->{'contents'}->[0];
  }
}

# custom heading command line is split at @|
sub split_custom_heading_command_contents($) {
  my $element = shift;

  my $contents_nr = scalar(@{$element->{'contents'}});

  if (!$contents_nr) {
    return undef;
  }

  my $nr_split_contents = 0;

  my $result = {'contents' => []};
  my $heading_element = {'contents' => []};
  push @{$result->{'contents'}}, $heading_element;

  for (my $i = 0; $i < $contents_nr; $i++) {
    my $current_content = $element->{'contents'}->[$i];
    #print STDERR "$nr_split_contents : "
    #          .debug_print_element($current_content)."\n";
    if (exists($current_content->{'cmdname'})
        and $current_content->{'cmdname'} eq '|') {
      if ($nr_split_contents < 2) {
        $heading_element = {'contents' => []};
        push @{$result->{'contents'}}, $heading_element;
        $nr_split_contents++;
      }
    } else {
      push @{$heading_element->{'contents'}}, $current_content;
    }
  }

  return $result;
}

# not currently used
sub find_parent_root_command($$);
sub find_parent_root_command($$) {
  my ($self, $current) = @_;

  my $root_command;
  while (1) {
    if (exists($current->{'cmdname'})) {
      if (exists($Texinfo::Commands::root_commands{$current->{'cmdname'}})) {
        return $current;
      } elsif (exists($Texinfo::Commands::block_commands{$current->{'cmdname'}})
               and $Texinfo::Commands::block_commands{$current->{'cmdname'}} eq 'region') {
        if ($current->{'cmdname'} eq 'copying' and defined($self)
            and exists($self->{'document'})) {
          my $global_commands = $self->{'document'}->global_commands_information();
          if (defined($global_commands)
              and exists($global_commands->{'insertcopying'})) {
            foreach my $insertcopying(@{$global_commands->{'insertcopying'}}) {
              my $root_command
                = find_parent_root_command($self, $insertcopying);
              return $root_command if (defined($root_command));
            }
          }
        } else {
          return undef;
        }
      }
    }
    if (exists($current->{'parent'})) {
      $current = $current->{'parent'};
    } else {
      return undef;
    }
  }
  # Should never get there
  return undef;
}

# In the default case, global informative commands are collected
# by the parsers.  The following functions allow to collect
# any @-command.
# Used in customization init files code and should be useful in
# particular in user-defined init files.

sub collect_commands_in_tree($$) {
  my ($root, $commands_list) = @_;

  my $commands_hash = {};
  foreach my $command_name (@$commands_list) {
    $commands_hash->{$command_name} = [];
  }
  _collect_commands_in_tree($root, $commands_hash);
  return $commands_hash;
}

sub _collect_commands_in_tree($$);
sub _collect_commands_in_tree($$) {
  my ($current, $commands_hash) = @_;

  if (exists($current->{'cmdname'})
      and defined($commands_hash->{$current->{'cmdname'}})) {
    push @{$commands_hash->{$current->{'cmdname'}}}, $current;
  }
  if (exists($current->{'contents'})) {
    foreach my $child (@{$current->{'contents'}}) {
      _collect_commands_in_tree($child, $commands_hash);
    }
  }
}

sub collect_commands_list_in_tree($$) {
  my ($root, $commands_list) = @_;

  my $collected_commands_list = [];
  my $commands_hash = {};
  foreach my $command_name (@$commands_list) {
    $commands_hash->{$command_name} = 1;
  }
  _collect_commands_list_in_tree($root, $commands_hash, $collected_commands_list);
  return $collected_commands_list;
}

sub _collect_commands_list_in_tree($$$);
sub _collect_commands_list_in_tree($$$) {
  my ($current, $commands_hash, $collected_commands_list) = @_;

  if (exists($current->{'cmdname'})
      and defined($commands_hash->{$current->{'cmdname'}})) {
    push @{$collected_commands_list}, $current;
  }
  if (exists($current->{'contents'})) {
    foreach my $child (@{$current->{'contents'}}) {
      _collect_commands_list_in_tree($child, $commands_hash,
                                     $collected_commands_list);
    }
  }
}


# Common to different module, but not meant to be used in user-defined
# codes.

# ALTIMP C/main/utils.c
sub get_label_element($) {
  my $current = shift;

  return undef if (!exists($current->{'cmdname'}));

  if ($current->{'cmdname'} eq 'node') {
    # first content of arguments_line type element
    return $current->{'contents'}->[0]->{'contents'}->[0];
  } elsif (($current->{'cmdname'} eq 'anchor'
            or $current->{'cmdname'} eq 'namedanchor')
           and exists($current->{'contents'})) {
    return $current->{'contents'}->[0];
  } elsif ($current->{'cmdname'} eq 'float'
           and scalar(@{$current->{'contents'}->[0]->{'contents'}}) >= 2) {
    # second content of arguments_line, ie second argument on line
    return $current->{'contents'}->[0]->{'contents'}->[1];
  }
  return undef;
}

# For code that can be called both from the main
# context and from a converter.  With either a converter, and, if
# not given, a document.
# NOTE it is considered internal and should not be called in user-defined
# code.  If this changes, should be documented.
sub converter_or_document_line_warn($$$$;$) {
  my ($document, $converter, $text, $error_location_info, $continuation) = @_;

  if (defined($converter)) {
    $converter->converter_line_warn($text, $error_location_info,
                                    $continuation);
  } else {
    $document->document_line_warn($text, $error_location_info,
                                  $continuation);
  }
}

# functions used for debugging.  May be used in other modules.
# Not documented.

sub _parent_string($) {
  my $current = shift;

  my $parent_string;
  if (exists($current->{'parent'})) {
    my $parent = $current->{'parent'};
    my $parent_cmd = '';
    my $parent_type = '';
    $parent_cmd = "\@$parent->{'cmdname'}" if (exists($parent->{'cmdname'}));
    $parent_type = "($parent->{'type'})" if (exists($parent->{'type'}));
    $parent_string = " <- $parent_cmd$parent_type";
  }
  return $parent_string
}

sub debug_command_name($) {
  my $cmdname = shift;

  if ($cmdname eq "\n") {
    return '\n';
  } elsif ($cmdname eq "\t") {
    return '\t';
  } else {
    return $cmdname;
  }
}

# informations on a tree element, short version
sub debug_print_element($;$) {
  my ($current, $print_parent) = @_;

  if (!defined($current)) {
    return "debug_print_element: UNDEF";
  }
  my $warning = '';
  if (ref($current) ne 'Texinfo::TreeElement') {
    if (ref($current) eq 'HASH') {
      $warning = '[ERROR:HASH]';
    } else {
      return "debug_print_element: $current not a tree element";
    }
  }
  my $type = '';
  my $cmd = '';
  my $text = '';
  my $args = '';
  my $contents = '';
  $type = "($current->{'type'})" if (exists($current->{'type'}));
  if (exists($current->{'text'})) {
    if ($current->{'text'} eq '') {
      $text = "[T]";
    } else {
      my $text_str = $current->{'text'};
      $text_str =~ s/\n/\\n/g;
      $text = "[T: $text_str]";
    }
  } else {
    if (exists($current->{'cmdname'})) {
      $cmd = '@' . debug_command_name($current->{'cmdname'});
    }
    $contents = "[C".scalar(@{$current->{'contents'}}).']'
       if $current->{'contents'};
  }
  my $parent_string = '';
  if ($print_parent) {
    $parent_string = _parent_string($current);
    $parent_string = '' if (!defined($parent_string));
  }
  return "$warning$cmd$type$text$args$contents$parent_string";
}

# for debugging
sub debug_print_element_details($;$) {
  my ($current, $print_parent) = @_;

  my $string = debug_print_element($current, $print_parent);
  foreach my $key (keys (%$current)) {
    $string .= "   $key: $current->{$key}\n";
  }
  if (defined($current->{'extra'})) {
    $string .= " EXTRA\n";
    foreach my $key (keys (%{$current->{'extra'}})) {
      $string .= "  $key: $current->{'extra'}->{$key}\n";
    }
  }
  if (exists($current->{'info'})) {
    $string .= " INFO\n";
    foreach my $key (keys (%{$current->{'info'}})) {
      $string .= "  $key: $current->{'info'}->{$key}\n";
    }
  }
  return $string;
}

sub debug_print_output_unit($) {
  my $current = shift;

  if (!defined($current)) {
    return "debug_print_output_unit: UNDEF\n";
  }
  if (ref($current) ne 'HASH') {
    return "debug_print_output_unit: $current not a hash\n";
  }
  my $type = $current->{'unit_type'};
  # Should never happen
  $type = 'UNDEF' if (!defined($type));
  my $node_unit_cmd = '';
  if (exists($current->{'unit_node'})) {
    my $node_element = $current->{'unit_node'}->{'element'};
    $node_unit_cmd = '{N';
    if ($node_element eq $current->{'unit_command'}) {
      $node_unit_cmd .= '*';
    }
    $node_unit_cmd .= ':' . debug_print_element($node_element, 0)
    .Texinfo::Convert::Texinfo::root_heading_command_to_texinfo(
                                                $node_element).'}';
  }
  my $section_unit_cmd = '';
  if (exists($current->{'unit_section'})) {
    my $section_element = $current->{'unit_section'}->{'element'};
    $section_unit_cmd = '{S';
    if ($section_element eq $current->{'unit_command'}) {
      $section_unit_cmd .= '*';
    }
    $section_unit_cmd .= ':'.debug_print_element($section_element, 0)
      .Texinfo::Convert::Texinfo::root_heading_command_to_texinfo(
                                               $section_element).'}';
  }
  my $fname = '';
  if (exists($current->{'unit_filename'})) {
    $fname = "{F:$current->{'unit_filename'}}";
  }
  my $variety = '';
  if (exists($current->{'special_unit_variety'})) {
    $variety = "{V:$current->{'special_unit_variety'}}";
  }
  my $contents = '';
  $contents = "{C".scalar(@{$current->{'unit_contents'}}).'}'
    if (exists($current->{'unit_contents'}));
  return "{$type}$fname$variety$contents$node_unit_cmd$section_unit_cmd";
}

# format list for debugging messages
sub debug_list {
  my $label = shift;
  my (@list) = (ref $_[0] && $_[0] =~ /.*ARRAY.*/) ? @{$_[0]} : @_;

  my $str = "$label: [";
  my @items = ();
  for my $item (@list) {
    $item = "" if ! defined ($item);
    $item =~ s/\n/\\n/g;
    push (@items, $item);
  }
  $str .= join (" ", @items);
  $str .= "]";

  warn "$str\n";
}

# format hash for debugging messages
sub debug_hash {
  my ($label) = shift;
  my (%hash) = (ref $_[0] && $_[0] =~ /.*HASH.*/) ? %{$_[0]} : @_;

  my $str = "$label: {";
  my @items = ();
  for my $key (sort keys %hash) {
    my $val = $hash{$key} || ""; # no undef
    $key =~ s/\n/\\n/g;
    $val =~ s/\n/\\n/g;
    push (@items, "$key:$val");
  }
  $str .= join (",", @items);
  $str .= "}";

  warn "$str\n";
}

# for debugging
use Data::Dumper;

my @kept_keys = ('contents', 'cmdname', 'type', 'text',
  'extra', 'info', 'spaces_before_argument',
  'spaces_after_argument', 'comment_at_end', 'index_entry'
);
my %kept_keys;
foreach my $key (@kept_keys) {
  $kept_keys{$key} = 1;
}
my @kept_keys_output_unit = ('unit_contents');
foreach my $key (@kept_keys_output_unit) {
  $kept_keys{$key} = 1;
}
my @kept_keys_handle = ('tree_document_descriptor');
foreach my $key (@kept_keys_handle) {
  $kept_keys{$key} = 1;
}
sub _filter_print_keys { [grep {$kept_keys{$_}} ( sort keys %{$_[0]} )] };
sub debug_print_tree($) {
  my $tree = shift;

  local $Data::Dumper::Sortkeys = \&_filter_print_keys;
  local $Data::Dumper::Purity = 1;
  local $Data::Dumper::Indent = 1;

  my $result = Data::Dumper->Dump([$tree]);

  # Tree elements are blessed into the 'Texinfo::TreeElement' class, but
  # this information is useless clutter for someone reading it.
  $result =~ s/bless\( //g;
  $result =~ s/ 'Texinfo::TreeElement' \)//g;

  return $result;

}

# Export debug_print_tree with a short name as a convenience for
# working on the program.  With this, you can inspect part of the
# parse tree with "warn print_tree($root);" rather than
# "warn Texinfo::Common::debug_print_tree($root);", which is more typing.
*print_tree = \&debug_print_tree;
push @EXPORT, 'print_tree';


1;

__END__

=head1 NAME

Texinfo::Common - Texinfo modules common data and miscellaneous methods

=head1 SYNOPSIS

  use Texinfo::Common;


  my @commands_to_collect = ('math');
  my $collected_commands
    = Texinfo::Common::collect_commands_in_tree($document_root,
                                             \@commands_to_collect);

  my $package_version
    = Texinfo::Common::get_build_constant('PACKAGE_AND_VERSION');

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

Texinfo::Common holds hashes with miscellaneous information and some
hashes with information on Texinfo @-commands, as well as miscellaneous
methods.

=head1 MISC INFORMATION

Values defined for a Texinfo build independently of any document or
output format are available by calling C<get_build_constant>:

=over

=item $value = get_build_constant($name)

The following build constants are available:

=over

=item PACKAGE

=item PACKAGE_CONFIG

=item PACKAGE_AND_VERSION

=item PACKAGE_AND_VERSION_CONFIG

=item PACKAGE_NAME

=item PACKAGE_NAME_CONFIG

=item PACKAGE_VERSION

=item PACKAGE_VERSION_CONFIG

=item PACKAGE_URL

=item PACKAGE_URL_CONFIG

Texinfo package name and versions.  Values of build constants without
C<_CONFIG> appended are set by configure.  For each variable set by
configure there is another one with C<_CONFIG> appended
to the name set to the same value, to match the name of the macros set in
C.  So, for example C<PACKAGE_VERSION_CONFIG> value is the same as
C<PACKAGE_VERSION>, set to the C<PACKAGE_VERSION> value set by configure.

=back

=back

Hashes are defined as C<our> variables, and are therefore available
outside of the module.

=over

=item %document_settable_at_commands

Keys are customization options corresponding to @-commands.  For example
C<frenchspacing> or C<footnotestyle>.

=item %null_device_file

Keys are null devices names, such as C</dev/null> or C<NUL>.

=item %texinfo_output_formats
X<C<%texinfo_output_formats>>

Cannonical output formats that have associated conditionals.  In
practice corresponds to C<format_raw> C<%block_commands> plus C<info>
and C<plaintext>.

=back


=head1 @-COMMAND INFORMATION

Hashes are defined as C<our> variables, and are therefore available
outside of the module.

The key of the hashes are @-command names without the @.  The
following hashes are available:

=over

=item %all_commands
X<C<%all_commands>>

All the @-commands.

=item %def_aliases

=item %def_no_var_arg_commands
X<C<%def_aliases>>
X<C<%def_no_var_arg_commands>>

C<%def_aliases> associates an aliased command to the original command, for
example C<defun> is associated to C<deffn>.

C<%def_no_var_arg_commands> associates a definition command name with
a true value if the I<argument> on the definition command line can contain
non-metasyntactic variables.  For instance, it is true for C<deftypevr>
but false for C<defun>, since C<@defun> I<argument> is supposed to contain
metasyntactic variables only.

=item %small_block_associated_command
X<C<%small_block_associated_command>>

Associate small command like C<smallexample> to the regular command
C<example>.

=back

=head1 METHODS

Two methods are exported in the default case for Texinfo modules messages
translation in the Uniforum gettext framework, C<__> and C<__p>.

The Texinfo tree and Texinfo tree elements used in argument of some functions
are documented in L<Texinfo::Parser/TEXINFO TREE>.  When customization
information is needed, an object that defines C<set_conf> and/or C<get_conf> is
expected, for example a converter inheriting from
C<Texinfo::Convert::Converter>, see L<Texinfo::Convert::Converter/Getting and
setting customization variables>.

=over

=item $translated_string = __($msgid)

=item $translated_string = __p($msgctxt, $msgid)

Returns the I<$msgid> string translated in the Texinfo messages text domain.
C<__p> can be used instead of C<__> to pass a I<$msgctxt> context string to
provide translators with information on the string context when the string is
short or if the translation could depend on the context. C<__> corresponds to
the C<gettext> function and C<__p> to the C<pgettext> function.

It is not advised to use those functions in user-defined code.  It is not
practical either, as the translatable strings marked by C<__> or C<__p> need to
be collected and added to the Texinfo messages domain.  This facility could
only be used in user-defined code with translatable strings already present in
the domain anyway.  In fact, these functions are documented mainly because they
are automatically exported.

See L<Locale::Messages>,
L<C<gettext> C interface|https://www.gnu.org/software/gettext/manual/html_node/gettext.html>,
L<Perl in GNU Gettext|https://www.gnu.org/software/gettext/manual/html_node/Perl.html>.
For translation of strings in output, see L<Texinfo::Translations>.

=item collect_commands_in_tree($tree, $commands_list)
X<C<collect_commands_in_tree>>

Returns a hash reference with keys @-commands names specified
in the I<$commands_list> array reference and values arrays of
tree elements corresponding to those @-command found in I<$tree>
by traversing the tree.

=item collect_commands_list_in_tree($tree, $commands_list)
X<C<collect_commands_list_in_tree>>

Return a list reference containing the tree elements corresponding
to the @-commands names specified in the I<$commands_list> found
in I<$tree> by traversing the tree.  The order of the @-commands
should be kept.

=item $encoding_name = associated_processing_encoding($element)
X<C<associated_processing_encoding>>

Returns the encoding name that can be used for decoding derived
from the encoding that was set where I<$element> appeared.

=item $result = element_is_inline($element, $check_current)
X<C<element_is_inline>>

Return true if the element passed in argument is in running text
context.  If the optional I<$check_current> argument is set,
check the element itself, in addition to the parent context.

=item ($encoded_file_name, $encoding) = encode_file_name($file_name, $input_encoding)

Encode the I<$file_name> text string to a binary string I<$encoded_file_name>
based on I<$input_encoding>.  Also returns the I<$encoding> name actually
used which may have undergone some normalization.  This function is mostly
a wrapper around L<Encode::encode|Encode/encode> which avoids calling the module if not
needed.  Do nothing if I<$input_encoding> is C<undef>.

=item $text = enumerate_item_representation($specification, $number)
X<C<enumerate_item_representation>>

This function returns the number or letter correponding to item
number I<$number> for an C<@enumerate> specification I<$specification>,
appearing on an C<@enumerate> line.  For example

  enumerate_item_representation('c', 3)

is C<e>.

=item ($contents_element, \@accent_commands) = find_innermost_accent_contents($element)
X<C<find_innermost_accent_contents>>

I<$element> should be an accent command Texinfo tree element.  Returns
an element containing the innermost accent @-command contents,
normally a text element with one or two letter, and an array reference
containing the accent commands nested in I<$element> (including
I<$element>).  If there is no argument at all for the accent command,
I<$contents_element> is C<undef>.

=item $command = find_parent_root_command($object, $tree_element)
X<C<find_parent_root_command>>

Find the parent root command (sectioning command or node) of a tree element.
The I<$object> argument is optional, its C<global_commands> field is used
to continue through C<@insertcopying> if in a C<@copying>.

=item $entry_content_element = index_content_element($element, $prefer_reference_element)

Return a Texinfo tree element corresponding to the content of the index
entry associated to I<$element>.  If I<$prefer_reference_element> is set,
prefer an untranslated element.  If the element is an index command like
C<@cindex> or an C<@ftable> C<@item>, the content element is the argument
of the command.  If the element is a definition line, the index entry
element is based on the name and class.

=item $encoding = input_file_name_encoding($name_encoding, $doc_encoding_for_input_file_name, $locale_encoding, $document, $input_file_encoding)
X<C<input_file_encoding>>

Returns the encoding assumed for input file names.
I<$name_encoding> is used as encoding name if defined. If
I<$doc_encoding_for_input_file_name> is set, the encoding is based on the input
file content encoding, otherwise I<$locale_encoding> is used.  The I<$document>
argument is an optional Texinfo parsed document used to get the input document
content encoding.  The I<$input_file_encoding> argument is optional, it will be
used in priority if the the encoding is based on the input file encoding.  If
I<$input_file_encoding> is not given, it is recommended to pass I<$document>,
otherwise there is no way to determine the input document content encoding.

=item $result = is_content_empty($tree, $do_not_ignore_index_entries)
X<C<is_content_empty>>

Return true if the I<$tree> has content that could be formatted.
I<$do_not_ignore_index_entries> is optional.  If set, index entries
are considered to be formatted.

=item $file = locate_include_file($customization_information, $file_path)
X<C<locate_include_file>>

Locate I<$file_path>.  If I<$file_path> is an absolute path or has C<.>
or C<..> in the path directories it is checked that the path exists and is a
file.  Otherwise, the file name in I<$file_path> is located in include
directories also used to find texinfo files included in Texinfo documents.
I<$file_path> should be a binary string.  C<undef> is returned if the file was
not found, otherwise the file found is returned as a binary string.

=item ($index_entry, $index_info) = lookup_index_entry($index_entry_info, $indices_information)

Returns an I<$index_entry> hash based on the I<$index_entry_info> and
I<$indices_information>.  Also returns the I<$index_info> hash with information on
the index associated to the index entry.  I<$index_entry_info> should be
an array reference with an index name as first element and the index entry number
in that index (1-based) as second element.  In general, the I<$index_entry_info>
is an L<C<extra> I<index_entry>|Texinfo::Parser/index_entry> associated to an element.

The I<$index_entry> hash is described in L<Texinfo::Document/index_entries>.  The
I<$index_info> hash is described in L<< C<Texinfo::Document::indices_information>|Texinfo::Document/$indices_information = $document->indices_information() >>.

=item $normalized_name = normalize_top_node_name($node_string)
X<C<normalize_top_node_name>>

Normalize the node name string given in argument, by normalizing
Top node case.

=item $result = replace_remove_list_element($array, $element, $replacement)

Remove first occurence of I<$element> in the array reference I<$array>.
If the optional I<$replacement> argument is given, replace the I<$element>
by I<$replacement>.  Return the removed element, or C<undef> if not found.

=item $level = section_level($section)
X<C<section_level>>

Return numbered level of the tree sectioning element I<$section>, as modified by
raise/lowersections.

=item $element = set_global_document_command($customization_information, $global_commands_information, $cmdname, $command_location)
X<C<set_global_document_command>>

Set the Texinfo customization variable corresponding to I<$cmdname> in
I<$customization_information>.  The I<$global_commands_information> should
contain information about global commands in a Texinfo document, typically obtained
from a parsed document L<< $document->global_commands_information()|Texinfo::Document/$commands = global_commands_information($document) >>.
I<$command_location> specifies where in the document the value should be taken from,
for commands that may appear more than once. The possibilities are:

=over

=item last

Set to the last value for the command.

=item preamble

Set sequentially to the values in the Texinfo preamble.

=item preamble_or_first

Set to the first value of the command if the first command is not
in the Texinfo preamble, else set as with I<preamble>,
sequentially to the values in the Texinfo preamble.

=back

The I<$element> returned is the last element that was used to set the
customization value, or C<undef> if no customization value was found.

Notice that the only effect of this function is to set a customization
variable value, no @-command side effects are run, no associated customization
variables are set.

=item $status = set_informative_command_value($customization_information, $element)
X<C<set_informative_command_value>>

Set the Texinfo customization option corresponding to the tree element
I<$element>.  The command associated to the tree element should be
a command that sets some information, such as C<@documentlanguage>,
C<@contents> or C<@footnotestyle> for example.  Return true if the command
argument was found and the customization variable was set.

=item set_output_encoding($customization_information, $document)
X<C<set_output_encoding>>

If not already set, set C<OUTPUT_ENCODING_NAME> based on input file
encoding.

=item $split_contents = split_custom_heading_command_contents($element)
X<C<split_custom_heading_command_contents>>

Split the I<$element> contents at C<@|> in at max three parts.
Return an element containing the split parts in contents, or C<undef> if
the I<$element> has no useful content.  The input I<$element>
is supposed to be the argument line element of
C<%Texinfo::Commands::heading_spec_commands> commands such as C<@everyheading>.

=item $status = valid_customization_option($name)
X<C<valid_option>>

Return true if the I<$name> is a known customization option.

=item $status = valid_tree_transformation($name)
X<C<valid_tree_transformation>>

Return true if the I<$name> is a known tree transformation name
that may be passed with C<TREE_TRANSFORMATIONS> to modify a Texinfo
tree.

=back

=head1 SEE ALSO

L<Texinfo::Parser>, L<Texinfo::Convert::Converter> and L<Texinfo::Report>.

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
