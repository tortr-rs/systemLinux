# Structuring.pm: extract information about a document structure based on the
#                 document tree.
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
# Parts (also from Patrice Dumas) come from texi2html.pl.

# ALTIMP StructTransfXS.pm
# ALTIMP XSTexinfo/parser_document/StructuringTransfoXS.xs
# ALTIMP C/structuring_transfo/structuring.c

package Texinfo::Structuring;

use 5.006;

# See comment at start of HTML.pm
use if $] >= 5.012, feature => 'unicode_strings';

# stop \s from matching non-ASCII spaces, etc.  \p{...} can still be
# used to match Unicode character classes.
use if $] >= 5.014, re => '/a';

use strict;

# Can be used to check that there is no incorrect autovivfication
#no autovivification qw(fetch delete exists store strict);

use Carp qw(cluck confess);

use Texinfo::StructTransfXS;

use Texinfo::XSLoader;

use Texinfo::Commands;

use Texinfo::TreeElement;

use Texinfo::Common;
use Texinfo::Report;

use Texinfo::ManipulateTree qw(normalized_entry_associated_internal_node);

# for error messages
use Texinfo::Convert::Texinfo qw(target_element_to_texi_label
                                 link_element_to_texi);
# for internal references and misc uses
use Texinfo::Convert::NodeNameNormalization;
# for translations related to new master menu
use Texinfo::Translations;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
  associate_internal_references
  check_node_tree_menu_structure
  check_nodes_are_referenced
  complete_node_tree_with_menus
  construct_nodes_tree
  number_floats
  sectioning_structure
  warn_non_empty_parts
);

our $VERSION = '7.3';

my $XS_structuring = Texinfo::XSLoader::XS_structuring_enabled();

my %XS_overrides = (
  "Texinfo::Structuring::associate_internal_references"
    => "Texinfo::StructTransfXS::associate_internal_references",
  "Texinfo::Structuring::sectioning_structure"
    => "Texinfo::StructTransfXS::sectioning_structure",
  "Texinfo::Structuring::warn_non_empty_parts"
    => "Texinfo::StructTransfXS::warn_non_empty_parts",
  "Texinfo::Structuring::construct_nodes_tree"
    => "Texinfo::StructTransfXS::construct_nodes_tree",
  "Texinfo::Structuring::complete_node_tree_with_menus"
    => "Texinfo::StructTransfXS::complete_node_tree_with_menus",
  "Texinfo::Structuring::check_node_tree_menu_structure"
    => "Texinfo::StructTransfXS::check_node_tree_menu_structure",
  "Texinfo::Structuring::check_nodes_are_referenced"
    => "Texinfo::StructTransfXS::check_nodes_are_referenced",
  "Texinfo::Structuring::number_floats"
    => "Texinfo::StructTransfXS::number_floats",
  "Texinfo::Structuring::print_nodes_list"
    => "Texinfo::StructTransfXS::print_nodes_list",
  "Texinfo::Structuring::print_sections_list"
    => "Texinfo::StructTransfXS::print_sections_list",
  "Texinfo::Structuring::print_headings_list"
    => "Texinfo::StructTransfXS::print_headings_list",
  "Texinfo::Structuring::print_sectioning_root"
    => "Texinfo::StructTransfXS::print_sectioning_root",
  "Texinfo::Structuring::print_document_listoffloats"
    => "Texinfo::StructTransfXS::print_document_listoffloats",
);

our $module_loaded = 0;
sub import {
  if (!$module_loaded) {
    if ($XS_structuring) {
      for my $sub (keys %XS_overrides) {
        Texinfo::XSLoader::override ($sub, $XS_overrides{$sub});
      }
    }
    $module_loaded = 1;
  }
  # The usual import method
  goto &Exporter::import;
}

my %command_structuring_level = %Texinfo::CommandsValues::command_structuring_level;

my %appendix_commands = %Texinfo::Commands::appendix_commands;
my %unnumbered_commands = %Texinfo::Commands::unnumbered_commands;

# Go through the sectioning commands (e.g. @chapter, not @node) and
# associated sectioning commands relations, and set:
# 'section_level'
# 'section_heading_number'
# 'section_children'
# 'section_directions'
# 'toplevel_directions'
sub sectioning_structure($) {
  my $document = shift;

  my $sections_list = $document->sections_list();

  my $customization_information = $document;

  my $sec_root;
  my $previous_section_relations;
  my $previous_toplevel_relations;

  my $in_appendix = 0;
  # lowest level with a number.  This is the lowest level above 0.
  my $number_top_level;

  my $top_relations;

  # holds the current number for all the levels.  It is not possible to use
  # something like the last child index, because of @unnumbered.
  my @command_numbers;
  # keep track of the unnumbered
  my @command_unnumbered;
  foreach my $section_relations (@{$sections_list}) {
    my $content = $section_relations->{'element'};
    if ($content->{'cmdname'} eq 'top' and not defined($top_relations)) {
      $top_relations = $section_relations;
    }

    $content->{'extra'} = {} if (! exists($content->{'extra'}));

    my $level = Texinfo::Common::section_level($content);
    if (!defined($level)) {
      warn "BUG: level not defined for "
           .Texinfo::Common::debug_print_element($content)."\n";
      $level = 0;
    }

    if (defined($previous_section_relations)) {
      my $previous_section = $previous_section_relations->{'element'};
      my $prev_section_level = $previous_section->{'extra'}->{'section_level'};
      if ($prev_section_level < $level) {
        # new command is below
        if ($level - $prev_section_level > 1) {
          $document->document_line_error(
           sprintf(__("raising the section level of \@%s which is too low"),
              $content->{'cmdname'}), $content->{'source_info'});
          $level = $prev_section_level + 1;
        }
        $previous_section_relations->{'section_children'}
          = [$section_relations];

        $section_relations->{'section_directions'} = {};
        $section_relations->{'section_directions'}->{'up'}
           = $previous_section_relations;

        # if the up is unnumbered, the number information has to be kept,
        # to avoid reusing an already used number.
        if (!exists($unnumbered_commands{$previous_section->{'cmdname'}})) {
          $command_numbers[$level] = undef;
        } elsif (!exists($unnumbered_commands{$content->{'cmdname'}})) {
          $command_numbers[$level]++;
        }
        if (exists($unnumbered_commands{$content->{'cmdname'}})) {
          $command_unnumbered[$level] = 1;
        } else {
          $command_unnumbered[$level] = 0;
        }
      } else {
        my $new_upper_part_element;
        # try to find the up in the sectioning hierarchy
        my $up = $previous_section;
        my $up_relations = $previous_section_relations;
        my $up_section_directions = $up_relations->{'section_directions'};

        while (defined($up_section_directions)
               and exists($up_section_directions->{'up'})
               and $up->{'extra'}->{'section_level'} >= $level) {
          $up_relations = $up_section_directions->{'up'};
          $up = $up_relations->{'element'};
          $up_section_directions = $up_relations->{'section_directions'};
        }
        # no up found.  The element is below the sectioning root
        if ($level <= $up->{'extra'}->{'section_level'}) {
          $up = undef;
          $up_relations = $sec_root;
          if ($level <= $sec_root->{'section_root_level'}) {
            # in that case, the level of the element is not in line
            # with being below the sectioning root, something need to
            # be done
            if ($content->{'cmdname'} eq 'part') {
              # the first part just appeared, and there was no @top first in
              # document.  Mark that the sectioning root level needs to be updated
              $new_upper_part_element = 1;
              if ($level < $sec_root->{'section_root_level'}) {
                # level is 0 for part and section level -1 for sec root. The
                # condition means section level > 1, ie below chapter-level.
                $document->document_line_warn(
                 sprintf(__("no chapter-level command before \@%s"),
                         $content->{'cmdname'}), $content->{'source_info'});
              }
            } else {
              $document->document_line_warn(
  sprintf(__("lowering the section level of \@%s appearing after a lower element"),
                  $content->{'cmdname'}), $content->{'source_info'});
              $level = $sec_root->{'section_root_level'} + 1;
            }
          }
        }
        if (exists($appendix_commands{$content->{'cmdname'}}) and !$in_appendix
            and $level <= $number_top_level
            and $up and exists($up->{'cmdname'})
            and $up->{'cmdname'} eq 'part') {
          $up = undef;
          $up_relations = $sec_root;
        }
        if (defined($new_upper_part_element)) {
          # In that case the root level has to be updated because the first
          # 'part' just appeared, no direction to set.
          $sec_root->{'section_root_level'} = $level - 1;
          push @{$sec_root->{'section_children'}}, $section_relations;
          $number_top_level = $level;
          $number_top_level = 1 if (!$number_top_level);
        } else {
          $section_relations->{'section_directions'} = {};
          # do not set sec_root as up, but always put in section_children.
          $section_relations->{'section_directions'}->{'up'} = $up_relations
            if ($up_relations ne $sec_root);
          my $prev_relations = $up_relations->{'section_children'}->[-1];
          $section_relations->{'section_directions'}->{'prev'}
            = $prev_relations;
          $prev_relations->{'section_directions'} = {}
              if (!exists($prev_relations->{'section_directions'}));
          $prev_relations->{'section_directions'}->{'next'}
            = $section_relations;
          push @{$up_relations->{'section_children'}}, $section_relations;
        }
        if (!exists($unnumbered_commands{$content->{'cmdname'}})) {
          $command_numbers[$level]++;
          $command_unnumbered[$level] = 0;
        } else {
          $command_unnumbered[$level] = 1;
        }
      }
    } else {
      # first section determines the level of the root.  It is
      # typically -1 when there is a @top.
      $sec_root = {'section_children' => [$section_relations],
                   'section_root_level' => $level - 1};
      $document->{'sectioning_root'} = $sec_root;
      $number_top_level = $level;
      # if $level of top sectioning element is 0, which means that
      # it is a @top, $number_top_level is 1 as it is associated to
      # the level of chapter/unnumbered...
      $number_top_level = 1 if (!$number_top_level);
      if ($content->{'cmdname'} ne 'top') {
        if (!exists($unnumbered_commands{$content->{'cmdname'}})) {
          $command_unnumbered[$level] = 0;
        } else {
          $command_unnumbered[$level] = 1;
        }
      }
    }

    $content->{'extra'}->{'section_level'} = $level;

    if (!defined($command_numbers[$level])) {
      if (exists($unnumbered_commands{$content->{'cmdname'}})) {
        $command_numbers[$level] = 0;
      } else {
        $command_numbers[$level] = 1;
      }
    }
    if (exists($appendix_commands{$content->{'cmdname'}}) and !$in_appendix
        and $level == $number_top_level) {
      $in_appendix = 1;
      # NOTE we rely on perl auto-increment operator 'magic' for variables
      # in string context, the increment is done as a string, preserving each
      # character within its range, with carry (see perlop).
      $command_numbers[$level] = 'A';
    }
    if (!exists($unnumbered_commands{$content->{'cmdname'}})) {
      # construct the number, if not below an unnumbered
      if (!$command_unnumbered[$number_top_level]) {
        my $section_number = "$command_numbers[$number_top_level]";
        for (my $i = $number_top_level+1; $i <= $level; $i++) {
          $section_number .= ".$command_numbers[$i]";
          # If there is an unnumbered above, then no number is added.
          if ($command_unnumbered[$i]) {
            $section_number = undef;
            last;
          }
        }
        if (defined($section_number)) {
          $content->{'extra'}->{'section_heading_number'} = $section_number;
        }
      }
    }

    $previous_section_relations = $section_relations;

    if ($content->{'cmdname'} ne 'part' and $level <= $number_top_level) {
      if (defined($previous_toplevel_relations)
          or (defined($top_relations)
              and $section_relations ne $top_relations)) {
        $section_relations->{'toplevel_directions'} = {};
        if (defined($previous_toplevel_relations)) {
          $previous_toplevel_relations->{'toplevel_directions'} = {}
           if (!exists($previous_toplevel_relations->{'toplevel_directions'}));
          $previous_toplevel_relations->{'toplevel_directions'}->{'next'}
            = $section_relations;
          $section_relations->{'toplevel_directions'}->{'prev'}
            = $previous_toplevel_relations;
        }
        if (defined($top_relations) and $section_relations ne $top_relations) {
          $section_relations->{'toplevel_directions'}->{'up'} = $top_relations;
        }
      }
      $previous_toplevel_relations = $section_relations;
    } elsif ($content->{'cmdname'} eq 'part'
             and not exists($section_relations->{'part_associated_section'})) {

      $document->document_line_warn(
        sprintf(__("no sectioning command associated with \@%s"),
                $content->{'cmdname'}), $content->{'source_info'});
    }
  }
}

# for debugging
sub _print_sectioning_tree($);
sub _print_sectioning_tree($) {
  my $current_relations = shift;

  my $current = $current_relations->{'element'};
  my $result = ' ' x $current->{'extra'}->{'section_level'}
   . Texinfo::Convert::Texinfo::root_heading_command_to_texinfo($current)."\n";
  foreach my $child_relations (@{$current_relations->{'section_children'}}) {
    $result .= _print_sectioning_tree($child_relations);
  }
  return $result;
}

sub warn_non_empty_parts($) {
  my $document = shift;

  my $customization_information = $document;

  my $global_commands = $document->global_commands_information();

  if (exists($global_commands->{'part'})) {
    foreach my $part (@{$global_commands->{'part'}}) {
      if (!Texinfo::Common::is_content_empty($part)) {
        $document->document_line_warn(
                     sprintf(__("\@%s not empty"), $part->{'cmdname'}),
                       $part->{'source_info'});
      }
    }
  }
}

# No translation of those special Info keywords.
my %direction_texts = (
 'prev' => 'Prev',
 'next' => 'Next',
 'up' => 'Up'
);

sub _check_menu_entry($$$$$) {
  my ($document, $identifier_target, $command, $menu_content,
      $menu_entry_node) = @_;

  if (defined($menu_entry_node->{'extra'}->{'normalized'})) {
    my $normalized_menu_node = $menu_entry_node->{'extra'}->{'normalized'};

    my $menu_node = $identifier_target->{$normalized_menu_node};

    if (!defined($menu_node)) {
      $document->document_line_error(
                  sprintf(__("\@%s reference to nonexistent node `%s'"),
                          $command,
                          link_element_to_texi($menu_entry_node)),
                            $menu_content->{'source_info'});
    } else {
      if (!Texinfo::Convert::Texinfo::check_node_same_texinfo_code($menu_node,
                           $menu_entry_node->{'extra'}->{'node_content'})) {
        $document->document_line_warn(
        sprintf(__("\@%s entry node name `%s' different from %s name `%s'"),
                $command,
                link_element_to_texi($menu_entry_node),
                $menu_node->{'cmdname'},
                target_element_to_texi_label($menu_node)),
                               $menu_content->{'source_info'});
      }
    }
  }
}

sub _register_menu_node_targets($$$) {
  my ($identifier_target, $node_relations, $register) = @_;

  if (exists($node_relations->{'menus'})) {
    foreach my $menu (@{$node_relations->{'menus'}}) {
      foreach my $menu_content (@{$menu->{'contents'}}) {
        if (exists($menu_content->{'type'})
            and $menu_content->{'type'} eq 'menu_entry') {
          my $menu_node = normalized_entry_associated_internal_node
                            ($menu_content, $identifier_target);
          $register->{$menu_node} = 1 if (defined($menu_node));
        }
      }
    }
  }
}

# Should be called after sectioning_structure.
sub get_node_node_childs_from_sectioning($) {
  my $node_relations = shift;

  my @node_childs;

  if (exists($node_relations->{'associated_section'})) {
    my $associated_relations = $node_relations->{'associated_section'};

    if (exists($associated_relations->{'section_children'})) {
      foreach my $child_relations
                        (@{$associated_relations->{'section_children'}}) {
        if (exists($child_relations->{'associated_node'})) {
          push @node_childs, $child_relations->{'associated_node'};
        }
      }
    }
    # Special case for @top.  Gather all the children of the @part following
    # @top.
    if ($associated_relations->{'element'}->{'cmdname'} eq 'top') {
      my $current_relations = $associated_relations;
      while (exists($current_relations->{'section_directions'})
         and exists($current_relations->{'section_directions'}->{'next'})) {
        $current_relations
          = $current_relations->{'section_directions'}->{'next'};
        if ($current_relations->{'element'}->{'cmdname'} eq 'part') {
          if (exists($current_relations->{'section_children'})) {
            foreach my $child_relations
                         (@{$current_relations->{'section_children'}}) {
              if (exists($child_relations->{'associated_node'})) {
                push @node_childs,
                     $child_relations->{'associated_node'};
              }
            }
          }
        } else {
          if (exists($current_relations->{'associated_node'})) {
            # for @appendix, and what follows, as it stops a @part, but is
            # not below @top
            push @node_childs,
                 $current_relations->{'associated_node'};
          }
        }
      }
    }
  }
  return @node_childs;
}

sub _node_automatic_directions ($) {
  my $node = shift;

  my $arguments_line = $node->{'contents'}->[0];
  return (scalar(@{$arguments_line->{'contents'}}) <= 1);
}

my @node_directions_names = ('next', 'prev', 'up');
# In general should be called only after complete_node_tree_with_menus
# to generate the Top node first node directions automatically when there
# are no sections nor menus before checking.
sub check_nodes_are_referenced($) {
  my $document = shift;

  my $customization_information = $document;
  my $nodes_list = $document->nodes_list();
  my $identifier_target = $document->labels_information();
  my $refs = $document->internal_references_information();

  return unless (defined($nodes_list) and scalar(@{$nodes_list}));

  my $top_node = $identifier_target->{'Top'};
  $top_node = $nodes_list->[0]->{'element'} if (!defined($top_node));

  my %referenced_nodes = ($top_node => 1);
  my %referenced_in_menus = ();
  foreach my $node_relations (@{$nodes_list}) {
    my $node = $node_relations->{'element'};
    # gather referenced nodes based on node pointers
    my $node_directions = $node_relations->{'node_directions'};
    if (defined($node_directions)) {
      foreach my $direction (@node_directions_names) {
        if ($node_directions->{$direction}
            and not $node_directions->{$direction}
                                   ->{'extra'}->{'manual_content'}) {
          $referenced_nodes{$node_directions->{$direction}} = 1;
        }
      }
    }
    if (exists($node_relations->{'menus'})) {
      _register_menu_node_targets($identifier_target, $node_relations,
                                 \%referenced_in_menus);
      %referenced_nodes = (%referenced_nodes, %referenced_in_menus);
    } else {
      # If an automatic menu can be setup, consider that all
      # the nodes appearing in the automatic menu are referenced.
      # Note that the menu may not be actually setup, but
      # it is better not to warn for nothing.
      if (_node_automatic_directions($node)) {
        my @node_childs
          = get_node_node_childs_from_sectioning($node_relations);
        foreach my $node_child (@node_childs) {
          $referenced_nodes{$node_child->{'element'}} = 1;
        }
      }
    }
  }

  # consider nodes in internal @*ref commands to be referenced
  if (defined($refs)) {
    foreach my $ref (@$refs) {
      if (exists($ref->{'contents'})
          and exists($ref->{'contents'}->[0]->{'extra'})) {
        my $label_arg = $ref->{'contents'}->[0];
        my $label_normalized = $label_arg->{'extra'}->{'normalized'};
        if ($label_normalized) {
          my $node_target = $identifier_target->{$label_normalized};
          if (defined($node_target) and $node_target->{'cmdname'} eq 'node') {
            $referenced_nodes{$node_target} = 1;
          }
        }
      }
    }
  }

  foreach my $node_relations (@{$nodes_list}) {
    my $node = $node_relations->{'element'};
    # it is normal that a redundant node is not referenced
    if ($node->{'extra'}->{'is_target'}) {
      if (not exists($referenced_nodes{$node})) {
        $document->document_line_warn(sprintf(__("node `%s' unreferenced"),
                                      target_element_to_texi_label($node)),
                              $node->{'source_info'});
      # if the node is referenced, warn if there is no menu up
      } elsif ($customization_information->get_conf(
                                             'CHECK_NORMAL_MENU_STRUCTURE')
               and $node->{'extra'}->{'normalized'} ne 'Top'
               and scalar(@{$nodes_list}) > 1) {
        if (not ((exists($node_relations->{'associated_section'})
                  and _node_automatic_directions($node))
                 or $referenced_in_menus{$node})) {
          $document->document_line_warn(sprintf(__("node `%s' not in menu"),
                                        target_element_to_texi_label($node)),
                               $node->{'source_info'});
        }
      }
    }
  }
}

# Set node_directions and complete automatic directions with menus.
sub complete_node_tree_with_menus($) {
  my $document = shift;

  my $customization_information = $document;
  my $global_commands = $document->global_commands_information();
  my $nodes_list = $document->nodes_list();
  my $identifier_target = $document->labels_information();

  return undef unless (defined($nodes_list) and scalar(@{$nodes_list}));

  my $format_menu = $customization_information->get_conf('FORMAT_MENU');

  my $check_menu_entries = (!$customization_information->get_conf('novalidate')
      and (!defined($format_menu) or $format_menu eq 'menu'
           or $format_menu eq 'menu_no_detailmenu'));
  my $top_node = $identifier_target->{'Top'};

  # First go through all the menus and set menu up, menu next and menu prev,
  # and warn for unknown nodes.
  # Remark: since the @menu are only checked if they are in @node,
  # menu entries before the first node, or @menu nested inside
  # another command such as @format, may be treated slightly
  # differently; at least, there are no error messages for them.
  #
  foreach my $node_relations (@{$nodes_list}) {
    my $node = $node_relations->{'element'};
    if (exists($node_relations->{'menus'})) {
      if (scalar(@{$node_relations->{'menus'}}) > 1) {
        foreach my $menu (@{$node_relations->{'menus'}}[1 .. $#{$node_relations->{'menus'}}]) {
          $document->document_line_warn(sprintf(__("multiple \@%s"),
                       $menu->{'cmdname'}), $menu->{'source_info'});
        }
      }
      foreach my $menu (@{$node_relations->{'menus'}}) {
        my $previous_node_relations;
        my $previous_node;
        foreach my $menu_content (@{$menu->{'contents'}}) {
          if (exists($menu_content->{'type'})
              and $menu_content->{'type'} eq 'menu_entry') {
            my $menu_node;
            my $menu_node_relations;
            foreach my $content (@{$menu_content->{'contents'}}) {
              if ($content->{'type'} eq 'menu_entry_node') {
                if (exists($content->{'extra'})) {
                  if (!exists($content->{'extra'}->{'manual_content'})) {
                    if ($check_menu_entries) {
                      _check_menu_entry($document,
                                        $identifier_target, 'menu',
                                        $menu_content, $content);
                    }
                    if (defined($content->{'extra'}->{'normalized'})) {
                      $menu_node
                        = $identifier_target->{$content->{'extra'}->{'normalized'}};
                      if (defined($menu_node)
                          and $menu_node->{'cmdname'} eq 'node') {
                        $menu_node_relations
                          = $nodes_list->[$menu_node->{'extra'}->{'node_number'} -1];
                        if ((!defined($top_node) or $menu_node ne $top_node)
                            and _node_automatic_directions($menu_node)) {
                          $menu_node_relations->{'node_directions'} = {}
                           if (!exists($menu_node_relations->{'node_directions'}));
                          my $menu_node_directions
                            = $menu_node_relations->{'node_directions'};
                          if (!defined($menu_node_directions)
                              or !exists($menu_node_directions->{'up'})) {
                            $menu_node_directions->{'up'} = $node;
                          }
                        }
                      }
                    }
                  } else {
                    $menu_node = $content;
                  }
                }
                last;
              }
            }
            if (defined($menu_node) and defined($previous_node_relations)
                and !exists($previous_node_relations->{'element'}
                                    ->{'extra'}->{'manual_content'})) {
              if ((!defined($top_node) or $previous_node ne $top_node)
                  and _node_automatic_directions($previous_node)) {
                $previous_node_relations->{'node_directions'} = {}
                  if (!exists($previous_node_relations->{'node_directions'}));
                my $previous_node_directions
                  = $previous_node_relations->{'node_directions'};
                if (!$previous_node_directions->{'next'}) {
                  $previous_node_directions->{'next'} = $menu_node;
                }
              }
            }
            if (defined($menu_node_relations) and defined($previous_node)
                and !exists($menu_node->{'extra'}->{'manual_content'})) {
              if ((!defined($top_node) or $menu_node ne $top_node)
                  and _node_automatic_directions($menu_node)) {
                $menu_node_relations->{'node_directions'} = {}
                  if (!exists($menu_node_relations->{'node_directions'}));
                my $menu_node_directions
                  = $menu_node_relations->{'node_directions'};
                if (!exists($menu_node_directions->{'prev'})) {
                  $menu_node_directions->{'prev'} = $previous_node;
                }
              }
            }
            $previous_node = $menu_node;
            $previous_node_relations = $menu_node_relations;
          }
        } # end menu
      }
    }
  }
  # Check @detailmenu
  if ($check_menu_entries and exists($global_commands->{'detailmenu'})) {
    foreach my $detailmenu (@{$global_commands->{'detailmenu'}}) {
      foreach my $menu_content (@{$detailmenu->{'contents'}}) {
        if (exists($menu_content->{'type'})
            and $menu_content->{'type'} eq 'menu_entry') {
          foreach my $content (@{$menu_content->{'contents'}}) {
            if ($content->{'type'} eq 'menu_entry_node') {
              if (not (exists($content->{'extra'})
                       and exists($content->{'extra'}->{'manual_content'}))) {
                _check_menu_entry($document,
                    $identifier_target, 'detailmenu', $menu_content, $content);
              }
              last;
            }
          }
        }
      }
    }
  }
}

# determine node found through section directions, usually
# from section_directions.  It could also be from
# toplevel_directions if going through parts, except for @top
# as prev or next.
sub _section_direction_associated_node($$) {
  my ($section_relations, $direction) = @_;

  foreach my $direction_base ('section', 'toplevel') {
    if (exists($section_relations->{$direction_base.'_directions'})
        and exists($section_relations->{$direction_base.'_directions'}
                                                             ->{$direction})
        and ($direction_base ne 'toplevel'
             or $direction eq 'up'
             or $section_relations->{$direction_base.'_directions'}->{$direction}
                                          ->{'element'}->{'cmdname'} ne 'top')) {
       my $direction_relation
         = $section_relations->{$direction_base.'_directions'}->{$direction};
       if (exists($direction_relation->{'associated_node'})) {
        return $direction_relation->{'associated_node'};
      }
    }
  }
  return undef;
}

# Checks on structure related to menus.
sub check_node_tree_menu_structure($) {
  my $document = shift;

  my $customization_information = $document;
  my $nodes_list = $document->nodes_list();
  my $identifier_target = $document->labels_information();

  return unless (defined($nodes_list) and scalar(@{$nodes_list}));

  # Used to suppress later errors about a node if an error was
  # already reported to avoid deluging the user with error
  # messages.  Indexed by 'node_number' extra value.
  my %node_errors;

  # Check for nodes listed in the wrong menu(s)
  if ($customization_information->get_conf('CHECK_NORMAL_MENU_STRUCTURE')) {
    foreach my $node_relations (@{$nodes_list}) {
      my $node = $node_relations->{'element'};

      if (exists($node_relations->{'menus'})) {
        foreach my $menu (@{$node_relations->{'menus'}}) {
          foreach my $menu_content (@{$menu->{'contents'}}) {
            next if (!exists($menu_content->{'type'})
                     or $menu_content->{'type'} ne 'menu_entry');
            my $menu_node = normalized_entry_associated_internal_node
                              ($menu_content, $identifier_target);
            if (defined($menu_node) and $menu_node->{'cmdname'} eq 'node') {
              my $menu_node_relations = $nodes_list
                ->[$menu_node->{'extra'}->{'node_number'} -1];

              my $section_relations
                = $menu_node_relations->{'associated_section'};

              # possibly a lone @node that is not part of the
              # section structure.
              next if (!defined($section_relations));
              next if (!_node_automatic_directions($menu_node));

              my $section_up_node
                = _section_direction_associated_node($section_relations,'up');
              if (!defined($section_up_node)) {
                $document->document_line_warn(
    sprintf(__("node `%s' in menu in `%s' but not under it in sectioning"),
                             target_element_to_texi_label($menu_node),
                             target_element_to_texi_label($node)),
                    $menu_content->{'source_info'});
                $node_errors{$menu_node->{'extra'}->{'node_number'}} = 1;
              } elsif ($section_up_node->{'element'} ne $node) {
                $document->document_line_warn(
    sprintf(__("node `%s' in menu in `%s' but under `%s' in sectioning"),
                    target_element_to_texi_label($menu_node),
                    target_element_to_texi_label($node),
                    target_element_to_texi_label
                      ($section_up_node->{'element'})),
                    $menu_content->{'source_info'});
                $node_errors{$menu_node->{'extra'}->{'node_number'}} = 1;
              }
            }
          }
        }
      }
    }
  }

  # Go through all the menus and check if they match subordinate
  # nodes.
  if ($customization_information->get_conf('CHECK_NORMAL_MENU_STRUCTURE')) {
    foreach my $node_relations (@{$nodes_list}) {
      next if (! exists($node_relations->{'menus'}));

      next if (! exists($node_relations->{'associated_section'}));
      my $section_children = $node_relations->{'associated_section'}
                                          ->{'section_children'};
      next if (!defined($section_children) or !scalar(@{$section_children}));

      # Find the first subordinate section, which should appear first
      # in the menu.
      my $first_child = $section_children->[0];
      while (!exists($first_child->{'associated_node'})
             and exists($first_child->{'section_directions'})
             and exists($first_child->{'section_directions'}->{'next'})) {
        $first_child = $first_child->{'section_directions'}->{'next'};
      }

      my $first_child_node_relations = $first_child->{'associated_node'};
      next if (!defined($first_child_node_relations));

      my $section_node = $first_child_node_relations->{'element'};
      next if (!defined($section_node));
      my $last_menu_node_relations;

      foreach my $menu (@{$node_relations->{'menus'}}) {
        # Loop through each each entry in the menu and
        # check if it is the menu entry we were expecting
        # to see based on what came before.
        MENU_CONTENT:
        foreach my $menu_content (@{$menu->{'contents'}}) {
          next if (!exists($menu_content->{'type'})
                   or $menu_content->{'type'} ne 'menu_entry');
          my $menu_node
            = Texinfo::ManipulateTree::normalized_entry_associated_internal_node
                ($menu_content, $identifier_target);
          next if (!defined($menu_node)
                   or !exists($menu_node->{'extra'})
                   or !exists($menu_node->{'extra'}->{'node_number'}));

          my $menu_node_element_number
            = $menu_node->{'extra'}->{'node_number'};

          # If there are explicit node pointers, also allow
          # the "next" node.
          my $next_pointer_node;
          if (!defined($section_node) or $menu_node ne $section_node) {
            if ($last_menu_node_relations) {
              my $last_menu_node = $last_menu_node_relations->{'element'};
              if (!_node_automatic_directions($last_menu_node)) {
                my $last_menu_node_directions
                  = $last_menu_node_relations->{'node_directions'};
                $next_pointer_node = $last_menu_node_directions->{'next'};
              }
            }
          }

          if ($node_errors{$menu_node_element_number}) {
          } elsif (defined($section_node) and $menu_node eq $section_node
                   or defined($next_pointer_node)
                        and $menu_node eq $next_pointer_node) {
            # good
          } elsif (defined($section_node)) {
            $document->document_line_warn(
              sprintf(__("node `%s' in menu where `%s' expected"),
                target_element_to_texi_label($menu_node),
                target_element_to_texi_label($section_node)),
              $menu_content->{'source_info'});
            $node_errors{$menu_node_element_number} = 1;
          } else {
            $document->document_line_warn(
              sprintf(__("unexpected node `%s' in menu"),
                target_element_to_texi_label($menu_node)),
              $menu_content->{'source_info'});
            $node_errors{$menu_node_element_number} = 1;
          }

          # Now set section_node for the section that is
          # expected to follow the current menu node.

          $last_menu_node_relations
            = $nodes_list->[$menu_node_element_number - 1];
          # FIXME is it possible not to have last_menu_node_relations defined?
          next MENU_CONTENT if (!defined($last_menu_node_relations)
              or !exists($last_menu_node_relations->{'associated_section'}));

          my $menu_section_dirs
            = $last_menu_node_relations->{'associated_section'}
                ->{'section_directions'};

          next MENU_CONTENT
            if (!defined($menu_section_dirs)
                or !exists($menu_section_dirs->{'up'})
                or !exists($menu_section_dirs->{'up'}->{'associated_node'}));

          my $menu_node_up = $menu_section_dirs->{'up'}->{'associated_node'};
          if ($menu_node_up ne $node_relations) {
            # Keep the same expected section as the current menu node
            # is misplaced.
          } elsif (exists($menu_section_dirs->{'next'})) {
            my $section_next = $menu_section_dirs->{'next'};
            while (defined($section_next)
                   and !exists($section_next->{'associated_node'})
                   and exists($section_next->{'section_directions'})) {
              $section_next = $section_next->{'section_directions'}->{'next'};
            }
            if (defined($section_next)
                and exists($section_next->{'associated_node'})) {
              $section_node = $section_next->{'associated_node'}->{'element'};
            } else {
              undef $section_node;
            }
          } else {
            # We reached the last subordinate section so no more menu
            # entries are expected.
            undef $section_node;
          }
        }
      }
    }
  }

  my %cached_menu_nodes;

  # check for node up / menu up mismatch
  if ($customization_information->get_conf('CHECK_MISSING_MENU_ENTRY')) {
    foreach my $node_relations (@{$nodes_list}) {
      my $node = $node_relations->{'element'};
      next if $node_errors{$node->{'extra'}->{'node_number'}};

      my $section_relations = $node_relations->{'associated_section'};
      next if (!defined($section_relations));

      # We need to check both toplevel_ and section_directions in case
      # the up section is a @part.
      my $section_directions = $section_relations->{'toplevel_directions'};
      if (!defined($section_directions)) {
        $section_directions = $section_relations->{'section_directions'};
      }

      my ($up_node_relations, $up_node);

      if (defined($section_directions)
          and exists($section_directions->{'up'})) {
        $up_node_relations = $section_directions->{'up'}->{'associated_node'};
        if (defined($up_node_relations)) {
          $up_node = $up_node_relations->{'element'};
        }
      }

      if ($up_node
          # No check if node up is an external manual
          and not exists($up_node->{'extra'}->{'manual_content'})
          # no check for a redundant node, the node registered in the menu
          # was the main equivalent node
          and $node->{'extra'}->{'is_target'}) {

        # check only if there are menus
        next if (!exists($up_node_relations->{'menus'}));

        if (!$cached_menu_nodes{$up_node}) {
          $cached_menu_nodes{$up_node} = {};
          _register_menu_node_targets($identifier_target, $up_node_relations,
                                      $cached_menu_nodes{$up_node});
        }
        if (!$cached_menu_nodes{$up_node}->{$node}) {
          my $node_directions = $node_relations->{'node_directions'};
          # Suppress the error if the node up pointer for the child
          # node is to a different node.
          if (!defined($node_directions)
                or !defined($node_directions->{'up'})
                or $node_directions->{'up'} eq $up_node) {
            $document->document_line_warn(sprintf(
     __("node `%s' lacks menu item for `%s' but is above it in sectioning"),
               target_element_to_texi_label($up_node),
               target_element_to_texi_label($node)),
                              $up_node->{'source_info'});
            $node_errors{$node->{'extra'}->{'node_number'}} = 1;
          }
        }
      }
    }
  }

  # loop over all the menus in all the nodes and check for
  # mismatch with any explicit node pointers.
  if ($customization_information->get_conf('CHECK_NORMAL_MENU_STRUCTURE')) {
    foreach my $node_relations (@{$nodes_list}) {
      my $node = $node_relations->{'element'};
      next if !$node_relations->{'menus'};

      my ($menu_prev_node, $menu_prev_node_directions);
      foreach my $menu (@{$node_relations->{'menus'}}) {
        foreach my $menu_content (@{$menu->{'contents'}}) {
          next if !defined($menu_content->{'type'})
            or $menu_content->{'type'} ne 'menu_entry';
          my $menu_node = normalized_entry_associated_internal_node
                            ($menu_content, $identifier_target);
          next if (!defined($menu_node)
                   or !exists($menu_node->{'extra'})
                   or !exists($menu_node->{'extra'}->{'node_number'}));
          my $menu_node_element_number
            = $menu_node->{'extra'}->{'node_number'};
          my $menu_node_relations
            = $nodes_list->[$menu_node_element_number - 1];
          my $menu_node_directions;

          if (!_node_automatic_directions($menu_node)) {
            $menu_node_directions = $menu_node_relations->{'node_directions'};
          }

          if (defined($menu_node_directions)
              and exists($menu_node_directions->{'up'})
              and $menu_node_directions->{'up'} ne $node) {
            my $direction = 'up';
            $document->document_line_warn(
     sprintf(__("node %s pointer for `%s' is `%s' but %s is `%s' in menu"),
                  $direction,
                  target_element_to_texi_label($menu_node),
                  target_element_to_texi_label(
                      $menu_node_directions->{$direction}),
                  $direction,
                  target_element_to_texi_label($node)),
                                  $menu_content->{'source_info'});
          }

          if (defined($menu_prev_node)) {
            # Check menu entries in pairs.
            # next pointer for menu_prev_node should be menu_node, and
            # prev pointer for menu_node should be menu_prev_node.

            if (defined($menu_prev_node_directions)
                and exists($menu_prev_node_directions->{'next'})
                and $menu_prev_node_directions->{'next'} ne $menu_node) {
                my $direction = 'next';
                $document->document_line_warn(
         sprintf(__("node %s pointer for `%s' is `%s' but %s is `%s' in menu"),
                          $direction,
                          target_element_to_texi_label($menu_prev_node),
                          target_element_to_texi_label(
                              $menu_prev_node_directions->{$direction}),
                          $direction,
                          target_element_to_texi_label($menu_node)),
                                      $menu_content->{'source_info'});
            }


            if (defined($menu_node_directions)
                and exists($menu_node_directions->{'prev'})
                and $menu_node_directions->{'prev'} ne $menu_prev_node) {
              my $direction = 'prev';
              $document->document_line_warn(
         sprintf(__("node %s pointer for `%s' is `%s' but %s is `%s' in menu"),
                          $direction,
                          target_element_to_texi_label($menu_node),
                          target_element_to_texi_label(
                              $menu_node_directions->{$direction}),
                          $direction,
                          target_element_to_texi_label($menu_prev_node)),
                                      $menu_content->{'source_info'});
            }
          }

          $menu_prev_node = $menu_node;
          $menu_prev_node_directions = $menu_node_directions;
        }
      }
    }
  }
}

# As mentioned in the manual, the node next pointer for the Top
# is special, and usually points to the first chapter in the
# document.   Set it using sectioning if possible, otherwise using
# menus.  Return reference to Top node.
sub _set_top_node_next($$) {
  my ($nodes_list, $identifier_target) = @_;

  my $top_node = $identifier_target->{'Top'};

  return undef if (!defined($top_node));

  if (_node_automatic_directions($top_node)) {
    my $top_node_next;
    my $top_node_number = $top_node->{'extra'}->{'node_number'};
    my $node_relations
      = $nodes_list->[$top_node_number -1];

    my $node_directions = $node_relations->{'node_directions'};

    # Special case for Top node, use first section
    if (exists($node_relations->{'associated_section'})) {
      my $associated_relations = $node_relations->{'associated_section'};
      my $section_children = $associated_relations->{'section_children'};
      if (defined($section_children) and scalar(@$section_children)) {
        my $section_child_relations = $section_children->[0];
        if (exists($section_child_relations->{'associated_node'})) {
          $top_node_next
            = $section_child_relations->{'associated_node'}->{'element'};
          $node_directions = {}
              if (! defined($node_directions));
          $node_relations->{'node_directions'} = {}
              if (!exists($node_relations->{'node_directions'}));
          $node_relations->{'node_directions'}->{'next'}
           = $top_node_next;
        }
      }
    }

    if (!defined($top_node_next)) {
      # use first menu entry if available as next for Top
      my $menu_child
         = Texinfo::ManipulateTree::first_menu_node($node_relations,
                                                    $identifier_target);
      if ($menu_child) {
        $top_node_next = $menu_child;
      } else {
        # use the first non top node as next for Top
        foreach my $first_non_top_node_relations (@{$nodes_list}) {
          my $first_non_top_node
            = $first_non_top_node_relations->{'element'};
          if ($first_non_top_node ne $top_node) {
            $top_node_next = $first_non_top_node;
            last;
          }
        }
      }
      if (defined($top_node_next)) {
        $node_relations->{'node_directions'} = {}
           if (!exists($node_relations->{'node_directions'}));
        $node_relations->{'node_directions'}->{'next'}
          = $top_node_next;
        if (exists($top_node_next->{'extra'}->{'manual_content'})
            or $top_node_next->{'cmdname'} ne 'node') {
          $top_node_next = undef;
        }
      }
    }
    # prev defined as first Top node menu entry node
    if (defined($top_node_next)) {
      if (_node_automatic_directions($top_node_next)) {
        my $next_node_number = $top_node_next->{'extra'}->{'node_number'};
        # different from Top node and after Top node
        if ($next_node_number > $top_node_number) {
          my $next_node_relations = $nodes_list->[$next_node_number -1];

          $next_node_relations->{'node_directions'} = {}
            if (!exists($next_node_relations->{'node_directions'}));
          if (!exists($next_node_relations->{'node_directions'}->{'prev'})) {
            $next_node_relations->{'node_directions'}->{'prev'}
              = $top_node;
          }
        }
      }
    }
  }
  return $top_node;
}

# set node directions based on sectioning and @node explicit directions
sub construct_nodes_tree($) {
  my $document = shift;

  my $customization_information = $document;
  my $identifier_target = $document->labels_information();

  my $top_node = $identifier_target->{'Top'};
  # Go through all the nodes and set directions.
  my $nodes_list = $document->nodes_list();

  _set_top_node_next($nodes_list, $identifier_target);

  foreach my $node_relations (@{$nodes_list}) {
    my $node = $node_relations->{'element'};

    if (_node_automatic_directions($node)) {
      if (!defined($top_node) or $node ne $top_node) {
        foreach my $direction (@node_directions_names) {
          if (exists($node_relations->{'associated_section'})) {
            my $direction_relation = $node_relations->{'associated_section'};

            # Prefer the section associated with a @part for node directions.
            if ($direction_relation
                and exists($direction_relation->{'part_associated_section'})) {
              $direction_relation
                = $direction_relation->{'part_associated_section'};
            }

            my $direction_associated_node
              = _section_direction_associated_node($direction_relation,
                                                   $direction);
            if ($direction_associated_node) {
              $node_relations->{'node_directions'} = {}
                 if (!exists($node_relations->{'node_directions'}));
              $node_relations->{'node_directions'}->{$direction}
                              = $direction_associated_node->{'element'};
            }
          }
        }
      }
    } else { # explicit directions
      my $arguments_line = $node->{'contents'}->[0];
      for (my $i = 1; $i < scalar(@{$arguments_line->{'contents'}}); $i++) {
        my $direction_element = $arguments_line->{'contents'}->[$i];
        my $direction = $node_directions_names[$i-1];

        # external node
        if (exists($direction_element->{'extra'})
            and exists($direction_element->{'extra'}->{'manual_content'})) {
          $node_relations->{'node_directions'} = {}
             if (!exists($node_relations->{'node_directions'}));
          $node_relations->{'node_directions'}->{$direction}
             = $direction_element;
        } elsif (exists($direction_element->{'extra'})
                 and defined($direction_element->{'extra'}->{'normalized'})) {
          my $direction_normalized = $direction_element->{'extra'}->{'normalized'};
          if ($identifier_target->{$direction_normalized}) {
            my $node_target
               = $identifier_target->{$direction_normalized};
            $node_relations->{'node_directions'} = {}
               if (!exists($node_relations->{'node_directions'}));
            $node_relations->{'node_directions'}->{$direction} = $node_target;

            if (!$customization_information->get_conf('novalidate')
                and !Texinfo::Convert::Texinfo::check_node_same_texinfo_code(
                                 $node_target,
                                 $direction_element->{'extra'}->{'node_content'})) {
              $document->document_line_warn(sprintf(
             __("%s pointer `%s' (for node `%s') different from %s name `%s'"),
                  $direction_texts{$direction},
                  link_element_to_texi($direction_element),
                  target_element_to_texi_label($node),
                                     $node_target->{'cmdname'},
                  target_element_to_texi_label($node_target)),
                                    $node->{'source_info'});
            }
          } else {
            if (!$customization_information->get_conf('novalidate')) {
              $document->document_line_error(
                   sprintf(__("%s reference to nonexistent `%s'"),
                      $direction_texts{$direction},
                      link_element_to_texi($direction_element)),
                                $node->{'source_info'});
            }
          }
        }
      }
    }
  }
}

sub _print_line_command($) {
  my $element = shift;

  if (exists($Texinfo::Commands::root_commands{$element->{'cmdname'}})) {
    return Texinfo::ManipulateTree::root_command_element_string($element);
  } else {
    if (scalar(@{$element->{'contents'}})
        and exists($element->{'contents'}->[0]->{'contents'})) {
      my $root_command_texi
        = Texinfo::Convert::Texinfo::convert_to_texinfo(
           Texinfo::TreeElement::new(
               {'contents' => $element->{'contents'}->[0]->{'contents'}}));
      return '@'."$element->{'cmdname'} ".$root_command_texi;
    }
    return undef;
  }
}

sub _print_line_command_key_element($$) {
  my ($key, $element) = @_;

  my $line_command_text = _print_line_command($element);
  if (!defined($line_command_text)) {
    return " $key\n";
  } else {
    return " $key: ".$line_command_text."\n";
  }
}

sub _print_key_section_with_number($$) {
  my ($section_key, $element) = @_;

  my $section_texi
      = Texinfo::ManipulateTree::root_command_element_string($element);
  if (!defined($section_texi)) {
    return " $section_key\n";
  } else {
    return " $section_key: ".$section_texi."\n";
  }
}

sub _print_root_command($) {
  my $element = shift;
  #if (!defined($element)) {
  #  confess('_print_root_command element undef');
  #}
  #if (!defined($element->{'contents'})) {
  #  confess('_print_root_command element contents undef');
  #}

  my $argument_line = $element->{'contents'}->[0];
  if (exists($argument_line->{'contents'})
      and exists($argument_line->{'contents'}->[0]->{'contents'})) {
    my $root_command_texi
      = Texinfo::Convert::Texinfo::convert_to_texinfo(
         Texinfo::TreeElement::new(
           {'contents' => $argument_line->{'contents'}->[0]->{'contents'}}));
    return $root_command_texi;
  }
  return undef;
}

# used in t/*.t tests
sub _print_menu_node($) {
  my $element = shift;

  if (exists($element->{'cmdname'}) and $element->{'cmdname'} eq 'node') {
    return _print_root_command($element);
  } elsif (exists($element->{'cmdname'})
           and exists($element->{'contents'})
           and exists($element->{'contents'}->[0]->{'contents'})) {
    return Texinfo::Convert::Texinfo::convert_to_texinfo(
             Texinfo::TreeElement::new(
               {'contents' => $element->{'contents'}->[0]->{'contents'}}));
  } else {
    return Texinfo::Convert::Texinfo::convert_to_texinfo($element);
  }
}

sub print_sections_list($) {
  my $document = shift;

  my $sections_list = $document->sections_list();

  my $result = '';

  my $idx = 1;

  foreach my $section_relations (@$sections_list) {
    my $element = $section_relations->{'element'};
    my $root_command_texi = _print_root_command($element);
    if (!defined($root_command_texi)) {
      $result .= "$idx\n";
    } else {
      $result .= "$idx|$root_command_texi\n";
    }

    foreach my $node_relations_key (('associated_anchor_command',
                                      'associated_node',
                                     'part_following_node')) {
      if (exists($section_relations->{$node_relations_key})) {
        $result .= " $node_relations_key: "
            ._print_root_command(
            $section_relations->{$node_relations_key}->{'element'})."\n";
      }
    }

    foreach my $section_relations_key (('associated_part',
                                        'part_associated_section')) {
      if (exists($section_relations->{$section_relations_key})) {
        $result .= _print_key_section_with_number($section_relations_key,
               $section_relations->{$section_relations_key}->{'element'});
      }
    }

    foreach my $directions_key (('section_directions', 'toplevel_directions')) {
      if (exists($section_relations->{$directions_key})) {
        my $value = $section_relations->{$directions_key};
        $result .= " $directions_key:\n";
        foreach my $d_key (@node_directions_names) {
          if (exists($value->{$d_key})) {
            my $e = $value->{$d_key}->{'element'};
            my $direction_texi = _print_root_command($e);
            if (defined($direction_texi)) {
              $result .= "  ${d_key}->$direction_texi\n";
            } else {
              # happens with empty sections
              $result .= "  ${d_key}->\n";
            }
          }
        }
      }
    }

    if (exists($section_relations->{'section_children'})) {
      my $key = 'section_children';
      $result .= " $key:\n";
      my $value = $section_relations->{$key};
      my $sec_idx = 1;
      foreach my $section_relations (@$value) {
        my $e = $section_relations->{'element'};
        my $section_texi = _print_root_command($e);
        $result .= "  ${sec_idx}|";
        if (defined($section_texi)) {
          $result .= $section_texi;
        }
        $result .= "\n";
        $sec_idx++;
      }
    }

    $idx++;
  }

  return $result;
}

sub print_sectioning_root($) {
  my $document = shift;

  my $sectioning_root = $document->sectioning_root();

  my $result = '';

  if ($sectioning_root) {
    $result .= "level: ".
      $sectioning_root->{'section_root_level'}."\n";
    $result .= "list:\n";
    my $sec_idx = 1;
    foreach my $section_relations (@{$sectioning_root->{'section_children'}}) {
      $result .= " $sec_idx|";
      my $section = $section_relations->{'element'};
      my $section_texi = _print_root_command($section);
      if (defined($section_texi)) {
        $result .= $section_texi;
      }
      $result .= "\n";
      $sec_idx++;
    }
  }

  return $result;
}

sub print_headings_list($) {
  my $document = shift;

  my $headings_list = $document->headings_list();

  my $result = '';

  my $idx = 1;

  foreach my $heading_relations (@$headings_list) {
    my $element = $heading_relations->{'element'};
    my $root_command_texi;
    if (exists($element->{'contents'})
        and exists($element->{'contents'}->[0]->{'contents'})) {
      $root_command_texi
        = Texinfo::Convert::Texinfo::convert_to_texinfo(
            Texinfo::TreeElement::new(
               {'contents' => $element->{'contents'}->[0]->{'contents'}}));
    }
    if (!defined($root_command_texi)) {
      $result .= "$idx\n";
    } else {
      $result .= "$idx|$root_command_texi\n";
    }

    foreach my $node_relations_key (('associated_anchor_command')) {
      if (exists($heading_relations->{$node_relations_key})) {
        $result .= " $node_relations_key: "
       ._print_root_command(
          $heading_relations->{$node_relations_key}->{'element'})."\n";
      }
    }
    $idx++;
  }

  return $result;
}

sub print_nodes_list($) {
  my $document = shift;

  my $nodes_list = $document->nodes_list();

  my $result = '';

  my $idx = 1;

  foreach my $node_relations (@$nodes_list) {
    my $element = $node_relations->{'element'};
    my $root_command_texi = _print_root_command($element);
    if (!defined($root_command_texi)) {
      $result .= "$idx\n";
    } else {
      $result .= "$idx|$root_command_texi\n";
    }
    foreach my $section_key (('associated_section', 'node_preceding_part')) {
      if (exists($node_relations->{$section_key})) {
        $result .= _print_key_section_with_number($section_key,
                             $node_relations->{$section_key}->{'element'});
      }
    }
    foreach my $line_cmd_key (('associated_title_command',
                               'node_description')) {
      if (exists($node_relations->{$line_cmd_key})) {
        $result .= _print_line_command_key_element($line_cmd_key,
                                  $node_relations->{$line_cmd_key});
      }
    }

    foreach my $command_key (('node_long_description')) {
      if (exists($node_relations->{$command_key})) {
        my $command_element = $node_relations->{$command_key};
        $result .= " $command_key: @".$command_element->{'cmdname'}."\n";
      }
    }

    if (exists($node_relations->{'menus'})
        and scalar(@{$node_relations->{'menus'}})) {
      $result .= " menus:\n";
      foreach my $menu (@{$node_relations->{'menus'}}) {
        foreach my $menu_content (@{$menu->{'contents'}}) {
          if (exists($menu_content->{'type'})
              and $menu_content->{'type'} eq 'menu_entry') {
            my $menu_node;
            foreach my $content (@{$menu_content->{'contents'}}) {
              if ($content->{'type'} eq 'menu_entry_node') {
                # This is only supposed to identify the menu
                my $node_menu_entry_texi
                 = Texinfo::Convert::Texinfo::convert_to_texinfo($content);

                $result .= "  ".$node_menu_entry_texi."\n";
              }
            }
          }
        }
      }
    }

    if (exists($node_relations->{'node_directions'})) {
      my $value = $node_relations->{'node_directions'};
      $result .= " node_directions:\n";
      foreach my $d_key (@node_directions_names) {
        if (exists($value->{$d_key})) {
          my $e = $value->{$d_key};
          my $node_direction_texi = _print_menu_node($e);
          $result .= "  ${d_key}->$node_direction_texi\n";
        }
      }
    }
    $idx++;
  }

  return $result;
}

# For each internal reference command, set the 'normalized' key, in the
# @*ref first argument or in 'menu_entry_node' extra.
# NonXS version, used in a test of internal pure Perl function.
sub associate_internal_referencesNonXS($) {
  my $document = shift;

  my $customization_information = $document;

  my $identifier_target = $document->labels_information();
  my $refs = $document->internal_references_information();

  return if (!defined($refs));

  foreach my $ref (@$refs) {
    my $label_element;
    if (exists($ref->{'type'}) and $ref->{'type'} eq 'menu_entry_node') {
      $label_element = $ref;
    } else {
      $label_element = $ref->{'contents'}->[0];
    }

    if (exists($label_element->{'extra'})
        and exists($label_element->{'extra'}->{'node_content'})) {
      my $normalized =
        Texinfo::Convert::NodeNameNormalization::convert_to_node_identifier(
            $label_element->{'extra'}->{'node_content'});
      $label_element->{'extra'}->{'normalized'} = $normalized
        if (defined($normalized) and $normalized ne '');
    }

    if (exists($ref->{'type'}) and $ref->{'type'} eq 'menu_entry_node') {
      # similar messages are output in _check_menu_entry
      next;
    } elsif (exists($label_element->{'extra'})) {
      my $normalized = $label_element->{'extra'}->{'normalized'};
      if (!defined($normalized)
          or !defined($identifier_target->{$normalized})) {
        if (!$customization_information->get_conf('novalidate')) {
          $document->document_line_error(
                     sprintf(__("\@%s reference to nonexistent node `%s'"),
                             $ref->{'cmdname'},
                             link_element_to_texi($label_element)),
                                 $ref->{'source_info'});
        }
      } else {
        my $node_target = $identifier_target->{$normalized};
        if (!$customization_information->get_conf('novalidate')
            and !Texinfo::Convert::Texinfo::check_node_same_texinfo_code(
                               $node_target,
                               $label_element->{'extra'}->{'node_content'})) {
          $document->document_line_warn(
                 sprintf(__("\@%s to `%s', different from %s name `%s'"),
                     $ref->{'cmdname'},
                     link_element_to_texi($label_element),
                     $node_target->{'cmdname'},
                     target_element_to_texi_label($node_target)),
                                $ref->{'source_info'});
        }
      }
    }
  }
}

sub associate_internal_references($) {
  my $document = shift;

  associate_internal_referencesNonXS($document);
}

sub number_floats($) {
  my $document = shift;

  my $listoffloats_and_sections = $document->floats_information();

  return if (!defined($listoffloats_and_sections));

  foreach my $style (keys(%$listoffloats_and_sections)) {
    my $float_index = 0;
    my $current_chapter_relations;
    my $nr_in_chapter = 0;
    foreach my $float_and_section (@{$listoffloats_and_sections->{$style}}) {
      my ($float, $float_section_relations) = @$float_and_section;
      next if (!exists($float->{'extra'})
               or !defined($float->{'extra'}->{'normalized'}));
      $float_index++;
      my $number;
      if (defined($float_section_relations)) {
        my $up_relations = $float_section_relations;
        my $up = $up_relations->{'element'};
        my $up_section_directions = $up_relations->{'section_directions'};
        my $up_cmdname;
        while (defined($up_section_directions)
               and exists($up_section_directions->{'up'})
               and $command_structuring_level{
                 $up_section_directions->{'up'}->{'element'}->{'cmdname'}}) {
          $up_relations = $up_section_directions->{'up'};
          $up = $up_relations->{'element'};
          $up_section_directions = $up_relations->{'section_directions'};
        }
        if (!defined($current_chapter_relations)
            or $current_chapter_relations ne $up_relations) {
          $nr_in_chapter = 0;
          $current_chapter_relations = $up_relations;
        }
        if (!$unnumbered_commands{$up->{'cmdname'}}) {
          $nr_in_chapter++;
          $number = $up->{'extra'}->{'section_heading_number'} .
            '.' . $nr_in_chapter;
        }
      }
      $number = "$float_index" if (!defined($number));
      $float->{'extra'} = {} if (! exists($float->{'extra'}));
      $float->{'extra'}->{'float_number'} = $number;
    }
  }
}

# wrapper on print_listoffloats_types that can be used for XS overriding.
# Used in tests only.
sub print_document_listoffloats($) {
  my $document = shift;

  my $float_text;

  if ($document) {
    my $floats = $document->floats_information();
    if (defined($floats)) {
      $float_text
          = Texinfo::ManipulateTree::print_listoffloats_types($floats);
    }
  }

  return $float_text;
}

sub section_level_adjusted_command_name($) {
  my $element = shift;

  # the following condition should only be false if sectioning_structure was
  # not called
  if (exists($element->{'extra'})
      and defined($element->{'extra'}->{'section_level'})) {
    my $heading_level = $element->{'extra'}->{'section_level'};
    if ($heading_level ne $Texinfo::CommandsValues::command_structuring_level{
                                                       $element->{'cmdname'}}) {
      my $command
        = $Texinfo::Common::level_to_structuring_command{$element->{'cmdname'}}
                                                            ->[$heading_level];
      return $command;
    }
  }
  return $element->{'cmdname'};
}


# The following code is about menu elements creation

# returns the Texinfo tree corresponding to a single menu entry pointing
# to $NODE.
# if $USE_SECTIONS is set, use the section name as menu entry name.
sub new_node_menu_entry($;$) {
  my ($node_relations, $use_sections) = @_;

  my $node = $node_relations->{'element'};

  my $node_name_element;
  if ($node->{'extra'}->{'is_target'}) {
    my $arguments_line = $node->{'contents'}->[0];
    $node_name_element = $arguments_line->{'contents'}->[0];
  }

  # can happen with node without argument or with empty argument
  return undef if (not defined($node_name_element));

  my $menu_entry_name;
  if ($use_sections) {
    my $name_element;
    # use associated_title_command and not associated_section as
    # it is more logical here.
    if (exists($node_relations->{'associated_title_command'})) {
      my $arguments_line = $node_relations->{'associated_title_command'}
               ->{'contents'}->[0];
      $name_element = $arguments_line->{'contents'}->[0];
    } else {
      $name_element = $node_name_element; # shouldn't happen
    }

    $menu_entry_name
     = Texinfo::ManipulateTree::copy_contentsNonXS($name_element,
                                                   'menu_entry_name');
    foreach my $content (@{$menu_entry_name->{'contents'}}) {
      $content->{'parent'}
           = $menu_entry_name unless(exists($content->{'text'}));
    }
    # colons could be doubly protected, but it is probably better
    # than not protected at all.
    Texinfo::ManipulateTree::protect_colon_in_tree($menu_entry_name);
  }

  my $entry = Texinfo::TreeElement::new({'type' => 'menu_entry'});

  if (exists($node->{'source_info'})) {
    $entry->{'source_info'} = {%{$node->{'source_info'}}};
  }

  my $menu_entry_node
   = Texinfo::ManipulateTree::copy_contentsNonXS($node_name_element,
                                                 'menu_entry_node');
  foreach my $content (@{$menu_entry_node->{'contents'}}) {
    $content->{'parent'} = $menu_entry_node unless(exists($content->{'text'}));
  }
  $menu_entry_node->{'parent'} = $entry;

  # do not protect here, as it could already be protected, and
  # the menu entry should be the same as the node
  #Texinfo::ManipulateTree::protect_colon_in_tree($menu_entry_node);

  my $description
    = Texinfo::TreeElement::new({'type' => 'menu_entry_description',
                                 'contents' => []});
  $description->{'contents'}->[0]
    = Texinfo::TreeElement::new({'type' => 'preformatted',
                                 'parent' => $description,
                                 'contents' => []});
  $description->{'contents'}->[0]->{'contents'}->[0]
    = Texinfo::TreeElement::new({'text' => "\n"});
  $description->{'parent'} = $entry;

  if ($use_sections) {
    $entry->{'contents'}
     = [Texinfo::TreeElement::new({'text' => '* ',
                              'type' => 'menu_entry_leading_text'}),
        $menu_entry_name,
        Texinfo::TreeElement::new({'text' => ': ',
                                   'type' => 'menu_entry_separator'}),
        $menu_entry_node,
        Texinfo::TreeElement::new({'text' => '.',
                                   'type' => 'menu_entry_separator'}),
        $description];
    $menu_entry_name->{'parent'} = $entry;
  } else {
    $entry->{'contents'}
     = [Texinfo::TreeElement::new({'text' => '* ',
                                   'type' => 'menu_entry_leading_text'}),
        $menu_entry_node,
        Texinfo::TreeElement::new({'text' => '::',
                                   'type' => 'menu_entry_separator'}),
        $description];
  }

  my $parsed_node_manual
    = Texinfo::Common::parse_node_manual($menu_entry_node, 1);
  if (defined($parsed_node_manual)) {
    foreach my $label_info (keys(%$parsed_node_manual)) {
      $menu_entry_node->{'extra'} = {}
         if (!exists($menu_entry_node->{'extra'}));
      $menu_entry_node->{'extra'}->{$label_info}
         = $parsed_node_manual->{$label_info};

      if ($label_info eq 'node_content') {
        $menu_entry_node->{'extra'}->{'normalized'}
      = Texinfo::Convert::NodeNameNormalization::convert_to_node_identifier(
             $menu_entry_node->{'extra'}->{$label_info});
      }
    }
  }

  return $entry;
}

sub new_block_command($$) {
  my ($element, $command_name) = @_;

  $element->{'cmdname'} = $command_name;

  my $arguments_line
    = Texinfo::TreeElement::new({'type' => 'arguments_line',
                                 'parent' => $element});
  $arguments_line->{'contents'} = [
      Texinfo::TreeElement::new({'type' => 'block_line_arg',
                                  'parent' => $arguments_line,
          'info' => { 'spaces_after_argument'
                      => Texinfo::TreeElement::new({'text' => "\n",
                                 'type' => 'spaces_after_argument'})}})];
  unshift @{$element->{'contents'}}, $arguments_line;

  my $end = Texinfo::TreeElement::new({'cmdname' => 'end',
                                       'parent' => $element,
                               'extra' => {'text_arg' => $command_name}});
  $end->{'info'} = {'spaces_before_argument' =>
                    Texinfo::TreeElement::new({'text' => ' ',
                                 'type' => 'spaces_before_argument'})};
  my $end_args
   = Texinfo::TreeElement::new({'type' => 'line_arg', 'parent' => $end,
                                'contents' => [],
                  'info' => {'spaces_after_argument' =>
                        Texinfo::TreeElement::new({'text' => "\n",
                                   'type' => 'spaces_after_argument'})}});
  $end->{'contents'} = [$end_args];

  my $command_name_text
    = Texinfo::TreeElement::new({'text' => $command_name,});
  push @{$end_args->{'contents'}}, $command_name_text;

  push @{$element->{'contents'}}, $end;

  return $element;
}

sub _insert_menu_comment_content($$$;$) {
  my ($menu_contents, $position, $inserted_element,
      $no_leading_empty_line) = @_;

  my $menu_comment
    = Texinfo::TreeElement::new({'type' => 'menu_comment', 'contents' => []});
  my $preformatted
    = Texinfo::TreeElement::new({'type' => 'preformatted',
                                 'parent' => $menu_comment,
                                 'contents' => []});
  $menu_comment->{'contents'}->[0] = $preformatted;

  if (!$no_leading_empty_line) {
    push @{$preformatted->{'contents'}},
     Texinfo::TreeElement::new({'text' => "\n", 'type' => 'empty_line'});
  }

  push @{$preformatted->{'contents'}},
    @{$inserted_element->{'contents'}},
    Texinfo::TreeElement::new({'text' => "\n", 'type' => 'empty_line'}),
    Texinfo::TreeElement::new({'text' => "\n", 'type' => 'empty_line'});

  foreach my $content (@{$inserted_element->{'contents'}}) {
    $content->{'parent'} = $preformatted unless(exists($content->{'text'}));
  }
  splice (@$menu_contents, $position, 0, $menu_comment);
}

# Creates a new @menu element based on $NODE sectioning information.
# $LANG_TRANSLATIONS and $DEBUG are only used for the top menu.
sub new_complete_node_menu($;$$$)
{
  my ($node_relations, $lang_translations, $debug, $use_sections) = @_;

  my @node_childs
    = get_node_node_childs_from_sectioning($node_relations);

  if (not scalar(@node_childs)) {
    return undef;
  }

  my $associated_relations = $node_relations->{'associated_section'};

  # only holds contents here, will be turned into a proper block
  # command in new_block_command below
  my $new_menu = Texinfo::TreeElement::new({'contents' => []});
  foreach my $child (@node_childs) {
    my $entry = new_node_menu_entry($child, $use_sections);
    if (defined($entry)) {
      $entry->{'parent'} = $new_menu;
      push @{$new_menu->{'contents'}}, $entry;
    }
  }

  my $node = $node_relations->{'element'};
  # in top node, additionally insert menu comments for parts and for
  # the first appendix.
  if (defined($associated_relations)
      and $associated_relations->{'element'}->{'cmdname'} eq 'top'
      and $node->{'extra'}->{'normalized'} eq 'Top') {
    my $content_index = 0;
    my $in_appendix = 0;
    foreach my $node_child_relations (@node_childs) {
      if (!$node_child_relations->{'element'}->{'extra'}->{'is_target'}) {
        next;
      }
      my $child_relations = $node_child_relations->{'associated_section'};
      if (defined($child_relations)) {
        my $child_section = $child_relations->{'element'};
        my $part_added = 0;
        my $associated_part = $child_relations->{'associated_part'};
        if (defined($associated_part)) {
          my $part_arguments_line
            = $associated_part->{'element'}->{'contents'}->[0];
          my $part_line_arg = $part_arguments_line->{'contents'}->[0];
          my $part_title_copy
            = Texinfo::ManipulateTree::copy_contentsNonXS($part_line_arg);
          my $part_title
           = Texinfo::Translations::gdt('Part: {part_title}',
                                        $lang_translations,
                                     {'part_title' => $part_title_copy},
                                         $debug);
          _insert_menu_comment_content($new_menu->{'contents'}, $content_index,
                                       $part_title, ($content_index == 0));
          $content_index++;
          $part_added = 1;
        }
        if (!$in_appendix
            and $appendix_commands{$child_section->{'cmdname'}}) {
          my $appendix_title
             = Texinfo::Translations::gdt('Appendices',
                                 $lang_translations, undef, $debug);
          _insert_menu_comment_content($new_menu->{'contents'}, $content_index,
                                       $appendix_title,
                                       ($content_index == 0 or $part_added));
          $content_index++;
          $in_appendix++;
        }
      }
      $content_index++;
    }
  }

  new_block_command($new_menu, 'menu');

  return $new_menu;
}

# Create a new @detailmenu element.
# used in tree transformations.  Used in converters through
# new_complete_menu_master_menu.
sub new_detailmenu($$$$$$;$$) {
  my ($lang_translations, $converter, $document, $identifier_target,
      $nodes_list, $menus, $debug, $use_sections) = @_;

  # only holds contents here, will be turned into a proper block
  # command in new_block_command
  my $new_detailmenu = Texinfo::TreeElement::new({'contents' => []});
  if (defined($menus) and ref($menus) ne 'ARRAY') {
    cluck();
  }
  if (defined($menus) and scalar(@$menus)) {
    foreach my $menu (@$menus) {
      foreach my $entry (@{$menu->{'contents'}}) {
        if (exists($entry->{'type'}) and $entry->{'type'} eq 'menu_entry') {
          my $node
        = Texinfo::ManipulateTree::normalized_entry_associated_internal_node(
                                                  $entry, $identifier_target);
          if (defined($node)) {
            push @{$new_detailmenu->{'contents'}},
                         _print_down_menus($node, undef,
                                           $converter,
                                           $document,
                                           $identifier_target,
                                           $nodes_list,
                                           $use_sections);
          }
        }
      }
    }
  }
  if (scalar(@{$new_detailmenu->{'contents'}})) {
    # There is a menu comment with a preformatted added in front of each
    # detailed menu section with the node section name
    my $first_preformatted
         = $new_detailmenu->{'contents'}->[0]->{'contents'}->[0];
    my $master_menu_title
           = Texinfo::Translations::gdt(' --- The Detailed Node Listing ---',
                  $lang_translations,
                  undef, $debug);
    my @master_menu_title_contents;
    foreach my $content (@{$master_menu_title->{'contents'}}) {
      $content->{'parent'} = $first_preformatted
                                 unless(exists($content->{'text'}));
    }
    push @master_menu_title_contents, @{$master_menu_title->{'contents'}},
                                Texinfo::TreeElement::new({'text' => "\n"});
    unshift @{$first_preformatted->{'contents'}}, @master_menu_title_contents;
    foreach my $content (@{$new_detailmenu->{'contents'}}) {
      # menu_entry or menu_comment
      $content->{'parent'} = $new_detailmenu;
    }
    Texinfo::Structuring::new_block_command($new_detailmenu, 'detailmenu');
    return $new_detailmenu;
  } else {
    return undef;
  }
}

# TODO document
# Returns a @menu element for $NODE, formatted with a master menu with a
# @detailmenu if $NODE is the Top node.
# $SELF should be a converter.
sub new_complete_menu_master_menu($$$$) {
  my ($self, $labels, $nodes_list, $node_relations) = @_;

  my $menu_node
    = new_complete_node_menu($node_relations,
                        $self->{'current_lang_translations'},
                        $self->get_conf('DEBUG'));

  my $node = $node_relations->{'element'};

  if (defined($menu_node)
      and exists($node->{'extra'}->{'normalized'})
      and $node->{'extra'}->{'normalized'} eq 'Top') {
    if (exists($node_relations->{'associated_section'})
  and $node_relations->{'associated_section'}->{'element'}->{'cmdname'} eq 'top') {
      my $detailmenu = new_detailmenu($self->{'current_lang_translations'},
                                      $self, undef, $labels, $nodes_list,
                                      [$menu_node], $self->get_conf('DEBUG'));
      if ($detailmenu) {
        # add a blank line before the detailed node listing
        my $menu_comment
          = Texinfo::TreeElement::new({'type' => 'menu_comment',
                                       'parent' => $menu_node});
        push @{$menu_node->{'contents'}}, $menu_comment;
        my $preformatted
         = Texinfo::TreeElement::new({'type' => 'preformatted',
                                      'parent' => $menu_comment});
        push @{$menu_comment->{'contents'}}, $preformatted;
        my $empty_line = Texinfo::TreeElement::new(
                          {'type' => 'after_menu_description_line',
                           'text' => "\n"});
        push @{$preformatted->{'contents'}}, $empty_line;

        $detailmenu->{'parent'} = $menu_node;
        push @{$menu_node->{'contents'}}, $detailmenu;
      }
    }
  }
  return $menu_node;
}

# returns menu contents
sub _print_down_menus($$$$$$;$);
sub _print_down_menus($$$$$$;$) {
  my ($node, $up_nodes, $converter, $document, $identifier_target, $nodes_list,
      $use_sections) = @_;

  # NOTE the menus are not used directly, the entry of the menus are copied
  # and returned in @master_menu_contents.
  my @menus;

  my @master_menu_contents;

  return @master_menu_contents unless($node->{'cmdname'} eq 'node');

  my $node_relations = $nodes_list->[$node->{'extra'}->{'node_number'} -1];

  if (exists($node_relations->{'menus'})
      and scalar(@{$node_relations->{'menus'}})) {
    # Re-use a menu unless it has an entry that looks like
    # "* label: node.".   The separate label may not give enough
    # detail when used in the Top node, e.g. just "Menu" for the
    # "Info Format Menu" node in the Texinfo manual.
    my $menu_entry_name_found = 0;
   MENUS:
    foreach my $menu (@{$node_relations->{'menus'}}) {
      next if (!exists($menu->{'contents'}));
      foreach my $entry (@{$menu->{'contents'}}) {
        next if (!exists($entry->{'contents'})
                 or !exists($entry->{'type'})
                 or $entry->{'type'} ne 'menu_entry');
        foreach my $entry_content (@{$entry->{'contents'}}) {
          if (exists($entry_content->{'type'})
              and $entry_content->{'type'} eq 'menu_entry_name') {
            $menu_entry_name_found = 1;
            last MENUS;
          }
        }
      }
    }
    if (!$menu_entry_name_found) {
      @menus = @{$node_relations->{'menus'}};
    }
  }

  if (!scalar(@menus)) {
    my $current_menu
      = new_complete_node_menu($node_relations,
                               undef, undef, $use_sections);
    if (defined($current_menu)) {
      @menus = ( $current_menu );
    } else {
      return @master_menu_contents;
    }
  }

  my @node_children;
  foreach my $menu (@menus) {
    foreach my $entry (@{$menu->{'contents'}}) {
      if (exists($entry->{'type'}) and $entry->{'type'} eq 'menu_entry') {
        push @master_menu_contents,
               Texinfo::ManipulateTree::copy_treeNonXS($entry);
        # gather node children to recursively print their menus
        my $node
          = Texinfo::ManipulateTree::normalized_entry_associated_internal_node(
                                                 $entry, $identifier_target);
        if (defined($node)) {
          push @node_children, $node;
        }
      }
    }
  }
  if (scalar(@master_menu_contents)) {
    # Prepend node title
    my $node_name_element;
    my $node_relations = $nodes_list->[$node->{'extra'}->{'node_number'} -1];
    if (exists($node_relations->{'associated_section'})) {
      my $associated_section
        = $node_relations->{'associated_section'}->{'element'};
      my $arguments_line = $associated_section->{'contents'}->[0];
      $node_name_element = $arguments_line->{'contents'}->[0];
    } else {
      my $arguments_line = $node->{'contents'}->[0];
      $node_name_element = $arguments_line->{'contents'}->[0];
    }

    my $node_title_copy
      = Texinfo::ManipulateTree::copy_contentsNonXS($node_name_element);

    _insert_menu_comment_content(\@master_menu_contents, 0,
                                 $node_title_copy, 0);

    if (!defined($up_nodes)) {
      $up_nodes = [];
    }
    push @$up_nodes, [$node->{'extra'}->{'normalized'}, $node];
    # now recurse in the children
    foreach my $child (@node_children) {
      my $up_node_in_menu = 0;
      my $normalized_child = $child->{'extra'}->{'normalized'};
      foreach my $up_node_normalized (@$up_nodes) {
        if ($normalized_child eq $up_node_normalized->[0]) {
          Texinfo::Common::converter_or_document_line_warn($document,
                   $converter,
                sprintf(__("node `%s' appears in its own menus"),
                target_element_to_texi_label($up_node_normalized->[1])),
                           $up_node_normalized->[1]->{'source_info'});
          $up_node_in_menu = 1;
          last;
        }
      }
      if (!$up_node_in_menu) {
        push @master_menu_contents, _print_down_menus($child,
                                           $up_nodes,
                                           $converter,
                                           $document,
                                           $identifier_target,
                                           $nodes_list,
                                           $use_sections);
      }
    }
    pop @$up_nodes;
  }

  return @master_menu_contents;
}

1;

__END__

=head1 NAME

Texinfo::Structuring - information on Texinfo::Document document structure

=head1 SYNOPSIS

  use Texinfo::Structuring qw(sectioning_structure construct_nodes_tree
    number_floats associate_internal_references);

  # $document is a parsed Texinfo::Document document.
  # When customization variables information is needed, it is obtained
  # from the $document by calling the get_conf() method.
  sectioning_structure($document);
  construct_nodes_tree($document);
  check_node_tree_menu_structure($document);
  complete_node_tree_with_menus($document);
  check_nodes_are_referenced($document);
  associate_internal_references($document);
  number_floats($document->floats_information());

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

C<Texinfo::Structuring> allows to collect information on a Texinfo
document structure.  Thanks to C<sectioning_structure> the hierarchy
of sectioning commands is determined.  The node tree is analysed
with C<construct_nodes_tree>.  Structural checking and warning
on the consistency of menus and sectioning structure is done by
C<check_node_tree_menu_structure>.  Nodes directions are completed
with menu directions with C<complete_node_tree_with_menus>.
Floats get their standard numbering with C<number_floats> and
internal references are matched up with nodes, floats or anchors
with C<associate_internal_references>.

=head1 METHODS

No method is exported in the default case.

Most methods use the error messages list from a parsed document
for error reporting. Most also require Texinfo customization variables
information, which means an object implementing the C<get_conf> method, in
general a parsed document with registered customization, or, sometime,
a converter (L<Texinfo::Convert::Converter/Getting and setting customization
variables>).  Other common data needed such as target elements associated to
identifiers or refs are obtained from a parsed document, see
L<Texinfo::Document>.

=over

=item associate_internal_references($document)
X<C<associate_internal_references>>

Verify that internal references (C<@ref> and similar without fourth of
fifth argument and menu entries) have an associated node, anchor or float.
Set the I<normalized> key in the C<extra> hash of C<menu_entry_node> container
for menu entries and in the first argument C<extra> hash for internal
references C<@ref> and similar @-commands.

=item check_nodes_are_referenced($document)
X<C<check_nodes_are_referenced>>

Check that all the nodes are referenced (in menu, @*ref or node direction).

Should be called after C<complete_node_tree_with_menus> in order to
have corresponding autogenerated node directions set.

=item complete_node_tree_with_menus($document)
X<C<complete_node_tree_with_menus>>

Complete nodes directions with menu directions and I<Top> node first node
directions.

=item check_node_tree_menu_structure($document)
X<C<check_node_tree_menu_structure>>

Check consistency of menus, sectioning and nodes directions.

=item @children_nodes = get_node_node_childs_from_sectioning($node_relations)
X<C<get_node_node_childs_from_sectioning>>

Find the I<$node_relations> node relations children based on the
sectioning structure.  For the node associated with C<@top> sectioning
command, the sections associated with parts are considered.

=item new_block_command($element, $command_name)
X<C<new_block_command>>

Complete I<$element> by adding the I<$command_name>, the command line
argument and C<@end> to turn the element to a proper block command.

=item $new_menu = new_complete_node_menu($node_relations, $lang_translations, $debug_level, $use_sections)
X<C<new_complete_node_menu>>

Returns a C<@menu> Texinfo tree element for the node relations
I<$node_relations>, pointing to the
children of the node obtained with the sectioning structure.
If I<$use_sections> is set, use section names for the menu entry names.  The
I<$lang_translations> argument should be an array reference with one or two
elements.  The first element of the array is the language used for translations.
The second element, if set, should be an hash reference holding
translations already done.  I<$debug_level> is an optional debugging level
similar to the C<DEBUG> customization variable.  If set, it is supplied to the
function called for translations.  Translations are only needed when generating
the top node menu.

=item $detailmenu = new_detailmenu($lang_translations, $converter, $document, $identifier_target, $nodes_list, $debug, $menus)
X<C<new_detailmenu>>

Returns a detailmenu tree element formatted as a master node.
I<$menus> is an array reference containing the regular menus of the Top node.
I<$lang_translations> argument should be an array reference with one or two
elements.  The first element of the array is the language used for translations.
The second element, if set, should be an hash reference holding translations
already done.  If I<$debug> optional arguments is set, debugging mode
is assumed.  I<$converter> should hold information needed for
translations and error reporting.  I<$identifier_target> should hold
information on cross-reference target commands, typically obtained by
calling L<< C<Texinfo::Document::labels_information>|Texinfo::Document/$identifier_target = labels_information($document) >>.
I<$nodes_list> should be the list of nores relations information, typically
obtained by calling L<< C<Texinfo::Document::nodes_list>|Texinfo::Document/$nodes_relations_list = nodes_list($document) >>.

I<$converter>, if set, is used for error reporting
(L<Texinfo::Convert::Converter/Registering error and warning messages>).  If
not set, the I<$document> is used for error reporting instead.

=item $entry = new_node_menu_entry($node_relations, $use_sections)
X<C<new_node_menu_entry>>

Returns the Texinfo tree corresponding to a single menu entry pointing to
I<$node_relations>.
If I<$use_sections> is set, use the section name for the menu
entry name.  Returns C<undef> if the node argument is missing.

=item construct_nodes_tree($document)
X<C<construct_nodes_tree>>

Goes through nodes in I<$document> tree and set directions.
This functions sets, in each node relations element hash:

=over

=item node_directions

Hash reference with I<up>, I<next> and I<prev> keys associated to
the node line direction node relations.

=back

=item number_floats($float_information)
X<C<number_floats>>

Number the floats as described in the Texinfo manual.  Sets
the I<float_number> key in the C<extra> hash of the float
tree elements.

=item $command_name = section_level_adjusted_command_name($element)
X<C<section_level_adjusted_command_name>>

Return the sectioning command name corresponding to the sectioning
element I<$element>, adjusted in order to take into account raised
and lowered sections, when needed.

=item sectioning_structure($document)
X<C<sectioning_structure>>

This function goes through the parsed document tree and gather information
on the document structure for sectioning commands.

It sets section elements C<extra> hash values:

=over

=item section_level

The level in the sectioning tree hierarchy.  0 is for C<@top> or
C<@part>, 1 for C<@chapter>, C<@appendix>...  This level is corrected
by C<@raisesections> and C<@lowersections>.

=item section_heading_number

The sectioning command formatted number.

=back

The following is set in section relations hashes:

=over

=item section_children

An array holding sectioning element children.  The children are also
section relations.

=item section_directions

Hash reference with I<up>, I<next> and I<prev> keys associated to
section directions.

=item toplevel_directions

Hash reference with I<up>, I<next> and I<prev> keys associated to toplevel
sectioning relations directions, for elements like C<@top>, C<@chapter>,
C<@appendix>, not taking into account C<@part> elements.

=back

After calling this function, information on the sectioning tree root
can be obtained by calling C<< $document->sectioning_root() >>.

=item warn_non_empty_parts($document)
X<C<warn_non_empty_parts>>

Register a warning in for each C<@part> in global commands information of
I<$document> that is not empty.

=back

=head1 SEE ALSO

L<Texinfo manual|http://www.gnu.org/s/texinfo/manual/texinfo/>,
L<Texinfo::Document>.

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

