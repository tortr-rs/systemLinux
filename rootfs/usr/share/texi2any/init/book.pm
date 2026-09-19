# A style that tries to be analogous with a book, in HTML.
#
# Copyright 2004-2026 Free Software Foundation, Inc.
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
# Originally written by Patrice Dumas in 2004.
#
# This style is based on the scriptbasic style.

use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

#use Carp qw(cluck);

use Texinfo::Commands;
use Texinfo::Common;
use Texinfo::Convert::Texinfo;
# for section_level_adjusted_command_name
use Texinfo::Structuring;

my %sectioning_heading_commands = %Texinfo::Commands::sectioning_heading_commands;

texinfo_set_from_init_file('contents', 1);
texinfo_set_from_init_file('CONTENTS_OUTPUT_LOCATION', 'inline');
texinfo_set_from_init_file('NO_TOP_NODE_OUTPUT', 1);

# Following Rudolf Adamkovič idea, have Contents button for regular output
# units link to the section in table of contents.
sub book_in_contents_button($$$) {
  my ($self, $direction, $element) = @_;

  if (exists($element->{'cmdname'}) and $element->{'cmdname'} eq 'node') {
    my $node_relations = $self->converter_node_relations_of_node($element);
    if (defined($node_relations)
        and exists($node_relations->{'associated_section'})) {
      $element = $node_relations->{'associated_section'}->{'element'};
    }
  }

  my $href = $self->command_contents_href($element, 'contents');

  # Call direction_string to have Contents translated.
  return ("[<a href=\"$href\">".
           $self->direction_string('Contents', 'text')."</a>]", 0);
}

my @book_contents_buttons = ('Back', 'Forward', 'Space', 'Contents', 'Index', 'About');

foreach my $buttons ('TOP_BUTTONS') {
  texinfo_set_from_init_file($buttons, \@book_contents_buttons);
}

my @book_output_unit_buttons = ('Back', 'Forward', 'Space',
                                ['This', \&book_in_contents_button],
                                'Index', 'About');

foreach my $buttons ('SECTION_BUTTONS', 'CHAPTER_BUTTONS') {
  texinfo_set_from_init_file($buttons, \@book_output_unit_buttons);
}

my @book_footer_buttons = ('Contents', 'Index', 'About');
foreach my $buttons ('MISC_BUTTONS', 'SECTION_FOOTER_BUTTONS',
                     'CHAPTER_FOOTER_BUTTONS', 'TOP_FOOTER_BUTTONS') {
  texinfo_set_from_init_file($buttons, \@book_footer_buttons);
}

texinfo_set_from_init_file('NODE_FOOTER_BUTTONS', ['Back', 'Forward']);

texinfo_set_from_init_file('LINKS_DIRECTIONS',
    ['Top', 'Index', 'Contents', 'About', 'Up', 'NextFile', 'PrevFile']);

texinfo_set_from_init_file('WORDS_IN_PAGE', undef);
texinfo_set_from_init_file('FORMAT_MENU', 'nomenu');
texinfo_set_from_init_file('USE_NODES', 0);

texinfo_set_from_init_file('BIG_RULE', '<hr>');

my $toc_numbered_mark_class = 'toc-numbered-mark';

my ($book_previous_default_filename, $book_previous_file_name,
    $book_unumbered_nr);

sub book_init($) {
  my $converter = shift;

  $book_previous_default_filename = undef;
  $book_previous_file_name = undef;
  $book_unumbered_nr = 0;
  return 0;
}

texinfo_register_handler('init', \&book_init);

sub book_print_up_toc($$) {
  my ($converter, $command) = @_;

  my $current_relations
    = $converter->converter_section_relations_of_section($command);
  return '' if (!defined($current_relations));

  my $result = '';

  my @up_commands;
  while (exists($current_relations->{'section_directions'})
         and exists($current_relations->{'section_directions'}->{'up'})
         and ($current_relations->{'section_directions'}->{'up'}
                                                      ne $current_relations)) {
    $current_relations = $current_relations->{'section_directions'}->{'up'};
    unshift @up_commands, $current_relations->{'element'};
  }
  # this happens for example for top tree unit
  return '' if (! scalar(@up_commands));
  my $up = shift @up_commands;
  #print STDERR "$up ".Texinfo::Convert::Texinfo::root_heading_command_to_texinfo($up)."\n";
  $result .= $converter->html_attribute_class('ul', [$toc_numbered_mark_class])."><li>"
  . "<a href=\"".$converter->command_href($up)."\">".$converter->command_text($up)
   . "</a> </li>\n";
  foreach my $up (@up_commands) {
    $result .= '<li>'
    .$converter->html_attribute_class('ul', [$toc_numbered_mark_class])."><li>"
    . "<a href=\"".$converter->command_href($up)."\">".$converter->command_text($up)
   . "</a> </li>\n";
  }
  foreach my $up (@up_commands) {
    $result .= "</ul></li>\n";
  }
  $result .= "</ul>\n";
  return $result;
}

sub book_format_navigation_header($$$$) {
  my ($self, $buttons, $cmdname, $element) = @_;

  my $output_unit = $element->{'associated_unit'};
  if (defined($output_unit) and exists($output_unit->{'unit_section'})
      and exists($output_unit->{'unit_filename'})
      and $self->count_elements_in_filename('current',
                         $output_unit->{'unit_filename'}) == 1) {
    return book_print_up_toc($self,
                             $output_unit->{'unit_section'}->{'element'}) .
       &{$self->default_formatting_function('format_navigation_header')}($self,
                                 $buttons, $cmdname, $element);

  } else {
    return &{$self->default_formatting_function('format_navigation_header')}(
                                          $self, $buttons, $cmdname, $element);
  }
}

texinfo_register_formatting_function('format_navigation_header',
                                     \&book_format_navigation_header);

sub book_print_sub_toc($$);

sub book_print_sub_toc($$) {
  my ($converter, $section_relations) = @_;

  my $result = '';
  my $command = $section_relations->{'element'};
  my $content_href = $converter->command_href($command);
  my $heading = $converter->command_text($command);
  if (defined($content_href)) {
    $result .= "<li> "."<a href=\"$content_href\">$heading</a>" . " </li>\n";
  }
  my $section_children = $section_relations->{'section_children'};
  if (defined($section_children) and scalar(@{$section_children})) {
    $result .= '<li>'.$converter->html_attribute_class('ul',
                                             [$toc_numbered_mark_class])
     .">\n". book_print_sub_toc($converter,
                                $section_children->[0])
     ."</ul></li>\n";
  }
  if (exists($section_relations->{'section_directions'})
      and exists($section_relations->{'section_directions'}->{'next'})) {
    $result .= book_print_sub_toc($converter,
                  $section_relations->{'section_directions'}->{'next'});
  }
  return $result;
}

# this function is very similar with the default function, but there is
# an additional sub toc before the content.  It should be synced with
# the default function.
sub book_convert_heading_command($$$$$) {
  my ($self, $cmdname, $element, $args, $content) = @_;

  my $result = '';

  # No situation where this could happen
  if ($self->in_string()) {
    $result .= $self->command_text($element, 'string') ."\n"
      if ($cmdname ne 'node');
    $result .= $content if (defined($content));
    return $result;
  }

  my $element_id = $self->command_id($element);

  print STDERR "CONVERT elt heading "
        # uncomment next line for the perl object name
        #."$element "
        .Texinfo::Convert::Texinfo::root_heading_command_to_texinfo($element)."\n"
          if ($self->get_conf('DEBUG'));

  my $document = $self->get_info('document');
  my $sections_list;
  my $nodes_list;
  if (defined($document)) {
    $sections_list = $document->sections_list();
    $nodes_list = $document->nodes_list();
  }

  my $output_unit;
  my $section_relations;
  my $node_relations;

  if (exists($Texinfo::Commands::root_commands{$cmdname})) {
    if ($cmdname eq 'node') {
      if (defined($nodes_list) and exists($element->{'extra'})
        and $element->{'extra'}->{'node_number'}) {
        $node_relations
          = $nodes_list->[$element->{'extra'}->{'node_number'} -1];
      }
    } elsif (defined($sections_list)) {
      $section_relations
        = $sections_list->[$element->{'extra'}->{'section_number'} -1];
    }
    # All the root commands are associated to an output unit, the condition
    # on associated_unit is always true.
    if (exists($element->{'associated_unit'})) {
      $output_unit = $element->{'associated_unit'};
    }
  }

  my $element_header = '';
  if ($output_unit) {
    $element_header = &{$self->formatting_function('format_element_header')}(
                                        $self, $cmdname, $element, $output_unit);
  }

  my $toc_or_mini_toc_or_auto_menu = '';
  if ($self->get_conf('CONTENTS_OUTPUT_LOCATION') eq 'after_top'
      and $cmdname eq 'top'
      and defined($sections_list)
      and scalar(@{$sections_list}) > 1) {
    foreach my $content_command_name ('shortcontents', 'contents') {
      if ($self->get_conf($content_command_name)) {
        my $contents_text
          = $self->_contents_inline_element($content_command_name, undef);
        if ($contents_text ne '') {
          $toc_or_mini_toc_or_auto_menu .= $contents_text;
        }
      }
    }
  }

  if ($toc_or_mini_toc_or_auto_menu eq '' and $section_relations
      # avoid a double of contents if already after title
      and ($cmdname ne 'top'
           or $self->get_conf('CONTENTS_OUTPUT_LOCATION') ne 'after_title')) {
    my $section_children = $section_relations->{'section_children'};
    if (defined($section_children) and scalar(@{$section_children})) {
      $toc_or_mini_toc_or_auto_menu
        .= $self->html_attribute_class('ul', [$toc_numbered_mark_class]).">\n";
      $toc_or_mini_toc_or_auto_menu .= book_print_sub_toc($self,
                                                   $section_children->[0]);
      $toc_or_mini_toc_or_auto_menu .= "</ul>\n";
    }
  }

  if ($self->get_conf('NO_TOP_NODE_OUTPUT')
      and exists($Texinfo::Commands::root_commands{$cmdname})) {
    my $in_skipped_node_top
      = $self->get_shared_conversion_state('top', 'in_skipped_node_top');
    $in_skipped_node_top = 0 if (!defined($in_skipped_node_top));
    if ($in_skipped_node_top == 1) {
      my $id_class = $cmdname;
      $result .= &{$self->formatting_function('format_separate_anchor')}($self,
                                                        $element_id, $id_class);
      $result .= $element_header;
      $result .= $toc_or_mini_toc_or_auto_menu;
      return $result;
    }
  }

  my $level_corrected_cmdname = $cmdname;
  my $level_set_class;
  if (exists($element->{'extra'})
      and exists($element->{'extra'}->{'section_level'})) {
    # if the level was changed, use a consistent command name
    $level_corrected_cmdname
      = Texinfo::Structuring::section_level_adjusted_command_name($element);
    if ($level_corrected_cmdname ne $cmdname) {
      $level_set_class = "${cmdname}-level-set-${level_corrected_cmdname}";
    }
  }

  # find the section starting here, can be through the associated node
  # preceding the section, or the section itself
  my $opening_section;
  my $level_corrected_opening_section_cmdname;
  if (defined($node_relations)
      and exists($node_relations->{'associated_section'})) {
    $opening_section = $node_relations->{'associated_section'}->{'element'};
    $level_corrected_opening_section_cmdname
          = Texinfo::Structuring::section_level_adjusted_command_name(
                                                             $opening_section);
  # if there is an associated node, it is not a section opening
  # the section was opened before when the node was encountered
  } elsif (defined($section_relations)
           and !exists($section_relations->{'associated_node'})) {
    $opening_section = $element;
    $level_corrected_opening_section_cmdname = $level_corrected_cmdname;
  }

  # could use empty args information also, to avoid calling command_text
  #my $empty_heading = (!scalar(@$args) or !defined($args->[0]));

  # $heading not defined may happen if the command is a @node, for example
  # if there is an error in the node.
  my $heading = $self->command_text($element);
  my $heading_level;
  # node is used as heading if there is nothing else.
  if (defined($node_relations)) {
    if (defined($output_unit) and exists($output_unit->{'unit_node'})
        and $output_unit->{'unit_node'} eq $node_relations
        and !exists($node_relations->{'associated_title_command'})) {
      if ($element->{'extra'}->{'normalized'} eq 'Top') {
        $heading_level = 0;
      } else {
        # use node
        $heading_level = 3;
      }
    }
  } elsif (exists($element->{'extra'})
           and exists($element->{'extra'}->{'section_level'})) {
    $heading_level = $element->{'extra'}->{'section_level'};
  } else {
    # for *heading* @-commands which do not have a level
    # in the document as they are not associated with the
    # sectioning tree, but still have a $heading_level
    $heading_level = Texinfo::Common::section_level($element);
  }

  my $do_heading = (defined($heading) and $heading ne ''
                    and defined($heading_level));

  # if set, the id is associated to the heading text
  my $heading_id;
  if ($opening_section) {
    my $level;
    if (exists($opening_section->{'extra'})
        and exists($opening_section->{'extra'}->{'section_level'})) {
      $level = $opening_section->{'extra'}->{'section_level'};
    } else {
      # if Structuring sectioning_structure was not called on the
      # document (cannot happen in main program or test_utils.pl tests)
      $level = Texinfo::Common::section_level($opening_section);
    }
    my $closed_strings = $self->close_registered_sections_level(
                                  $self->current_filename(), $level);
    $result .= join('', @{$closed_strings});
    $self->register_opened_section_level($self->current_filename(), $level,
                                         "</div>\n");

    # use a specific class name to mark that this is the start of
    # the section extent. It is not necessary where the section is.
    $result .= $self->html_attribute_class('div',
                 ["${level_corrected_opening_section_cmdname}-level-extent"]);
    $result .= " id=\"$element_id\""
        if (defined($element_id) and $element_id ne '');
    $result .= ">\n";
  } elsif (defined($element_id) and $element_id ne '') {
    if ($element_header ne '') {
      # case of a @node without sectioning command and with a header.
      # put the node element anchor before the header.
      # Set the class name to the command name if there is no heading,
      # else the class will be with the heading element.
      my $id_class = $cmdname;
      if ($do_heading) {
        $id_class = "${cmdname}-id";
      }
      $result .= &{$self->formatting_function('format_separate_anchor')}($self,
                                                        $element_id, $id_class);
    } else {
      $heading_id = $element_id;
    }
  }

  $result .= $element_header;

  if ($do_heading) {
    if ($self->get_conf('TOC_LINKS')
        and exists($Texinfo::Commands::root_commands{$cmdname})
        and exists($sectioning_heading_commands{$cmdname})) {
      my $content_href = $self->command_contents_href($element, 'contents');
      if (defined($content_href)) {
        $heading = "<a href=\"$content_href\">$heading</a>";
      }
    }

    my @heading_classes;
    push @heading_classes, $level_corrected_cmdname;
    if (defined($level_set_class)) {
      push @heading_classes, $level_set_class;
    }
    if ($self->in_preformatted_context()) {
      my $id_str = '';
      if (defined($heading_id)) {
        $id_str = " id=\"$heading_id\"";
      }
      $result .= $self->html_attribute_class('strong', \@heading_classes)
                                   ."${id_str}>".$heading.'</strong>'."\n";
    } else {
      $result .= &{$self->formatting_function('format_heading_text')}($self,
                     $level_corrected_cmdname, \@heading_classes, $heading,
                     $heading_level +$self->get_conf('CHAPTER_HEADER_LEVEL') -1,
                     $heading_id, $element, $element_id);
    }
  } elsif (defined($heading_id)) {
    # case of a lone node and no header, and case of an empty @top
    $result .= &{$self->formatting_function('format_separate_anchor')}($self,
                                                       $heading_id, $cmdname);
  }

  $result .= $toc_or_mini_toc_or_auto_menu;

  $result .= $content if (defined($content));

  return $result;
}

foreach my $command (keys(%Texinfo::Commands::sectioning_heading_commands),
                                                                  'node') {
  texinfo_register_command_formatting($command,
                                \&book_convert_heading_command);
}

sub book_unit_file_name($$$$) {
  my ($converter, $output_unit, $filename, $filepath) = @_;

  return (undef, undef) if (!$converter->get_conf('SPLIT'));

  # should only happen if ! SPLIT, so should be redundant with the
  # condition above
  return ($filename, $filepath) if (defined($filepath));

  if (defined($book_previous_default_filename)
      and ($filename eq $book_previous_default_filename)) {
    return ($book_previous_file_name, undef);
  }

  my $prefix = $converter->get_info('document_name');
  my $new_file_name;
  my $command;
  if (exists($output_unit->{'unit_section'})) {
    $command = $output_unit->{'unit_section'}->{'element'};
  }
  return (undef, undef) unless (defined($command));

  if ($converter->unit_is_top_output_unit($output_unit)) {
    $new_file_name = "${prefix}_top.html";
  } elsif (exists($command->{'extra'}->{'section_heading_number'})
           and ($command->{'extra'}->{'section_heading_number'} ne '')) {
    my $number = $command->{'extra'}->{'section_heading_number'};
    $number .= '.' unless ($number =~ /\.$/);
    $new_file_name = "${prefix}_$number" . 'html';
  } else {
    $book_unumbered_nr++;
    $new_file_name = "${prefix}_U." . $book_unumbered_nr . '.html';
  }
  $book_previous_default_filename = $filename;
  $book_previous_file_name = $new_file_name;
  return ($new_file_name, undef);
}

texinfo_register_file_id_setting_function('unit_file_name',
                                          \&book_unit_file_name);

1;
