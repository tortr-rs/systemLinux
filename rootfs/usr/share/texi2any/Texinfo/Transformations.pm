# Transformations.pm: some transformations of the document tree
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
#
# ALTIMP perl/XSTexinfo/parser_document/StructuringTransfoXS.xs
# ALTIMP C/structuring_transfo/transformations.c

package Texinfo::Transformations;

use 5.006;

use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);


use Carp qw(cluck confess);

use Texinfo::StructTransfXS;

use Texinfo::XSLoader;

use Texinfo::Commands;

use Texinfo::TreeElement;

use Texinfo::Common;
use Texinfo::Translations;

use Texinfo::Document;
use Texinfo::ManipulateTree;
use Texinfo::Structuring;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
protect_hashchar_at_line_beginning
reference_to_arg_in_tree
);

our $VERSION = '7.3';

my $XS_structuring = Texinfo::XSLoader::XS_structuring_enabled();

my %XS_overrides = (
  "Texinfo::Transformations::fill_gaps_in_sectioning_in_document"
    => "Texinfo::StructTransfXS::fill_gaps_in_sectioning_in_document",
  "Texinfo::Transformations::reference_to_arg_in_document"
    => "Texinfo::StructTransfXS::reference_to_arg_in_document",
  "Texinfo::Transformations::complete_tree_nodes_menus_in_document"
    => "Texinfo::StructTransfXS::complete_tree_nodes_menus_in_document",
  "Texinfo::Transformations::complete_tree_nodes_missing_menu"
    => "Texinfo::StructTransfXS::complete_tree_nodes_missing_menu",
  "Texinfo::Transformations::regenerate_master_menu"
    => "Texinfo::StructTransfXS::regenerate_master_menu",
  "Texinfo::Transformations::insert_nodes_for_sectioning_commands"
    => "Texinfo::StructTransfXS::insert_nodes_for_sectioning_commands",
  "Texinfo::Transformations::protect_hashchar_at_line_beginning_in_document"
    => "Texinfo::StructTransfXS::protect_hashchar_at_line_beginning_in_document",
  "Texinfo::Transformations::protect_first_parenthesis_in_targets_in_document"
    => "Texinfo::StructTransfXS::protect_first_parenthesis_in_targets_in_document",
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

# Add raise/lowersections to be back at the normal level from
# the $SECTION level.  The raise/lowersections are added at the
# end of $PARENT.
# If $MODIFIER is set to -1, add raise/lowersections to go from
# the normal level to the $SECTION level.
sub _correct_level($$;$) {
  my ($section, $parent, $modifier) = @_;

  $modifier = 1 if (!defined($modifier));

  if (exists($section->{'extra'})
      and $section->{'extra'}->{'level_modifier'}) {
    my $level_to_remove = $modifier * $section->{'extra'}->{'level_modifier'};
    my $cmdname;
    if ($level_to_remove < 0) {
      $cmdname = 'raisesections';
    } else {
      $cmdname = 'lowersections';
    }
    my $remaining_level = abs($level_to_remove);
    while ($remaining_level) {
      my $element
       = Texinfo::TreeElement::new({'cmdname' => $cmdname,
                                    'parent' => $parent});
      push @{$parent->{'contents'}}, $element;
      my $line_args
        = Texinfo::TreeElement::new({'type' => 'line_arg',
           'info' => {'spaces_after_argument'
             => Texinfo::TreeElement::new(
                 {'type' => 'spaces_after_argument', 'text' => "\n"})},
                         'parent' => $element});
      push @{$element->{'contents'}}, $line_args;
      $remaining_level--;
    }
  }
}

sub fill_gaps_in_sectioning_in_document($;$) {
  my ($document, $commands_heading_content) = @_;

  my $root = $document->tree();

  my $sections_list = $document->sections_list();

  my $contents_nr = scalar(@{$root->{'contents'}});

  my @added_sections;

  # initialize current and next sections
  my $idx_current_section = -1;
  my $idx_next_section = -1;
  my $idx = 0;
  while ($idx < $contents_nr) {
    my $content = $root->{'contents'}->[$idx];
    if (! exists($content->{'cmdname'}) or $content->{'cmdname'} eq 'node'
      or ! exists($Texinfo::Commands::root_commands{$content->{'cmdname'}})) {
    } elsif ($idx_current_section < 0) {
      $idx_current_section = $idx;
    } elsif ($idx_next_section < 0) {
      $idx_next_section = $idx;
      last;
    }
    $idx++;
  }

  return undef
    if ($idx_current_section < 0);

  return \@added_sections
    if ($idx_next_section < 0);

  # index in sections_list
  my $section_idx = 0;
  while (1) {
    my $current_section = $root->{'contents'}->[$idx_current_section];
    my $current_section_level
       = Texinfo::Common::section_level($current_section);

    my $next_section = $root->{'contents'}->[$idx_next_section];
    my $next_section_level
       = Texinfo::Common::section_level($next_section);

    if ($next_section_level - $current_section_level > 1) {
      _correct_level($next_section, $current_section);
      my @new_sections;
      while ($next_section_level - $current_section_level > 1) {
        $current_section_level++;
        my $new_section =
         Texinfo::TreeElement::new({'cmdname' =>
          $Texinfo::Common::level_to_structuring_command{'unnumbered'}
                                                ->[$current_section_level],
          'parent' => $root,
        });
        $new_section->{'info'}
          = Texinfo::TreeElement::new({'spaces_before_argument' =>
                                              {'text' => ' ',
                                       'type' => 'spaces_before_argument'}});
        my $arguments_line
          = Texinfo::TreeElement::new({'type' => 'arguments_line',
                                       'parent' => $new_section});

        my $line_arg
          = Texinfo::TreeElement::new({'type' => 'line_arg',
                                       'parent' => $arguments_line,
            'info' => {'spaces_after_argument'
                        => Texinfo::TreeElement::new({'text' => "\n",
                                  'type' => 'spaces_after_argument'})}});
        $arguments_line->{'contents'} = [$line_arg];

        my $line_content;
        if (defined($commands_heading_content)) {
          $line_content
            = Texinfo::ManipulateTree::copy_contentsNonXS(
                                               $commands_heading_content);
          $line_content->{'parent'} = $line_arg;
        } else {
          my $asis_command
            = Texinfo::TreeElement::new({'cmdname' => 'asis',
                                         'parent' => $line_arg});
          $asis_command->{'contents'} = [
             Texinfo::TreeElement::new({'type' => 'brace_container',
                                        'parent' => $asis_command})];
          $line_content = $asis_command;
        }
        $line_arg->{'contents'} = [$line_content];
        $new_section->{'contents'} = [$arguments_line,
            Texinfo::TreeElement::new({'type' => 'empty_line',
                                       'text' => "\n"})];

        my $new_section_relations = {'element' => $new_section};
        splice(@{$sections_list}, $section_idx+1, 0, $new_section_relations);
        $section_idx++;

        $new_section->{'extra'} = {'section_number' => $section_idx+1};

        push @new_sections, $new_section;
      }
      splice (@{$root->{'contents'}}, $idx_current_section+1, 0, @new_sections);
      $idx_next_section += scalar(@new_sections);
      $contents_nr += scalar(@new_sections);
      push @added_sections, @new_sections;
      _correct_level($next_section, $new_sections[-1], -1);
    }
    $idx_current_section = $idx_next_section;
    $section_idx++;
    $next_section->{'extra'}->{'section_number'} = $section_idx+1;

    # find the new next section index
    $idx_next_section = $idx_current_section +1;
    while ($idx_next_section < $contents_nr) {
      my $content = $root->{'contents'}->[$idx_next_section];
      if (exists($content->{'cmdname'}) and $content->{'cmdname'} ne 'node'
       and exists($Texinfo::Commands::root_commands{$content->{'cmdname'}})) {
        last;
      }
      $idx_next_section++;
    }
    if ($idx_next_section >= $contents_nr) {
      last;
    }
  }

  return \@added_sections;
}

# This converts a reference @-command to simple text using one of the
# arguments.  This is used to remove reference @-command from
# constructed node names trees, as node names cannot contain
# reference @-command while there could be some in the tree used in
# input for the node name tree.
sub _reference_to_arg($$$) {
  my ($type, $current, $document) = @_;

  if (exists($current->{'cmdname'}) and
      exists($Texinfo::Commands::ref_commands{$current->{'cmdname'}})
      and exists($current->{'contents'})) {

    # remove from internal references
    if (defined($document)) {
      my $internal_references = $document->internal_references_information();
      Texinfo::Common::replace_remove_list_element($internal_references,
                                                   $current);
    }

    my @args_try_order;
    if ($current->{'cmdname'} eq 'inforef'
        or $current->{'cmdname'} eq 'link') {
      @args_try_order = (0, 1, 2);
    } else {
      @args_try_order = (0, 1, 2, 4, 3);
    }
    foreach my $index (@args_try_order) {
      if (defined($current->{'contents'}->[$index])) {
        my $arg = $current->{'contents'}->[$index];
        # this will not detect if the arg expands as spaces only, like
        # @asis{ }, @ , but it is not an issue or could even be considered
        # as a feature.
        if (!Texinfo::Common::is_content_empty($arg)) {
          # avoid the type and spaces by getting only the contents
          my $result
            = Texinfo::TreeElement::new({'contents' => $arg->{'contents'},
                                         'parent' => $current->{'parent'}});
          foreach my $content (@{$arg->{'contents'}}) {
            $content->{'parent'} = $result if (exists($content->{'parent'}));;
          }
          $current = undef;
          return [$result];
        }
      }
    }
    $current = undef;
    return Texinfo::TreeElement::new({'text' => ''});
  } else {
    return undef;
  }
}

sub reference_to_arg_in_tree($;$) {
  my ($tree, $document) = @_;

  return Texinfo::ManipulateTree::modify_tree($tree, \&_reference_to_arg,
                                              $document);
}

# Has an XS override. Defined to be able to test Perl and XS. Undocumented
# on purpose.
sub reference_to_arg_in_document($) {
  my $document = shift;

  reference_to_arg_in_tree($document->tree(), $document);
}

# prepare and add a new node as a possible cross reference targets
# modifies $document

# The $DOCUMENT error_messages is used to register error messages.
# Does not matter much, as the code checks that the new node target label does
# not exist already, therefore there cannot be any error.
sub _new_node($$) {
  my ($node_tree, $document) = @_;

  # We protect for all the contexts, as the node name should be
  # the same in the different contexts, even if some protections
  # are not needed for the parsing.  Also, this way the node tree
  # can be directly reused in the menus for example, without
  # additional protection, some parts could be double protected
  # otherwise, those that are protected with @asis.
  #
  # needed in nodes lines, @*ref and in menus with a label
  $node_tree = Texinfo::ManipulateTree::protect_comma_in_tree($node_tree);
  # always
  Texinfo::ManipulateTree::protect_first_parenthesis($node_tree);
  # in menu entry without label
  $node_tree = Texinfo::ManipulateTree::protect_colon_in_tree($node_tree);
  # in menu entry with label
  $node_tree
    = Texinfo::ManipulateTree::protect_node_after_label_in_tree($node_tree);
  $node_tree = reference_to_arg_in_tree($node_tree, $document);

  my $empty_node = 0;
  if (!exists($node_tree->{'contents'})) {
    $node_tree->{'contents'} = [Texinfo::TreeElement::new({'text' => ''})];
    $empty_node = 1;
  }

  my $comment_at_end;
  if (exists($node_tree->{'contents'}->[-1]->{'cmdname'})
      and ($node_tree->{'contents'}->[-1]->{'cmdname'} eq 'c'
           or $node_tree->{'contents'}->[-1]->{'cmdname'} eq 'comment')) {
    $comment_at_end = pop @{$node_tree->{'contents'}};
  }
  my $spaces_after_argument = '';
  if (scalar(@{$node_tree->{'contents'}}) > 0
             and $node_tree->{'contents'}->[-1]->{'text'}
             and $node_tree->{'contents'}->[-1]->{'text'} =~ s/(\s+)$//) {
    $spaces_after_argument = $1;
  }
  $spaces_after_argument .= "\n" unless ($spaces_after_argument =~ /\n/
                                         or $comment_at_end);

  my $appended_number = 0 +$empty_node;
  my ($node, $normalized);

  my $identifier_target = $document->labels_information();
  while (!defined($node)
         or (defined($identifier_target)
             and $identifier_target->{$normalized})) {

    if (defined($node)) {
      # remove cycles to release the previous node, which will not be used
      # and does not appear in the tree.
      Texinfo::ManipulateTree::tree_remove_parents($node);
    }

    $node = Texinfo::TreeElement::new({'cmdname' => 'node', 'extra' => {}});
    $node->{'info'} = {'spaces_before_argument'
                         => Texinfo::TreeElement::new({'text' => ' ',
                                       'type' => 'spaces_before_argument'})};

    my $arguments_line
      = Texinfo::TreeElement::new({'type' => 'arguments_line',
                                   'parent' => $node});
    $node->{'contents'} = [$arguments_line];

    my $node_line_arg
      = Texinfo::TreeElement::new({'type' => 'line_arg',
                                   'parent' => $arguments_line});
    $arguments_line->{'contents'} = [$node_line_arg];
    $node_line_arg->{'info'} = {'spaces_after_argument' =>
           Texinfo::TreeElement::new({'text' => $spaces_after_argument,
                                      'type' => 'spaces_after_argument'})};
    $node_line_arg->{'info'}->{'comment_at_end'} = $comment_at_end
      if (defined($comment_at_end));
    @{$node_line_arg->{'contents'}} = (@{$node_tree->{'contents'}});
    if ($appended_number) {
      push @{$node_line_arg->{'contents'}},
            Texinfo::TreeElement::new({'text' => " $appended_number"});
    }
    foreach my $content (@{$node_line_arg->{'contents'}}) {
      $content->{'parent'} = $node_line_arg if (exists($content->{'parent'}));
    }

    $normalized
       = Texinfo::Convert::NodeNameNormalization::convert_to_node_identifier(
           Texinfo::TreeElement::new(
                       { 'contents' => $node_line_arg->{'contents'} }));

    if ($normalized !~ /[^-]/) {
      if ($appended_number) {
        warn "BUG: spaces only node name despite appending $appended_number\n";
        return undef;
      } else {
        # remove cycles to release this empty node, which is discarded
        # and does not appear in the tree.
        Texinfo::ManipulateTree::tree_remove_parents($node);
        $node = undef;
      }
    }
    $appended_number++;
  }
  $node->{'extra'}->{'normalized'} = $normalized;

  Texinfo::Document::register_label_element($document, $node,
                                            $document->{'error_messages'},
                                            $document->get_conf('DEBUG'));

  return $node;
}

# reassociate a tree element to the new node, from previous node
sub _reassociate_to_node($$$) {
  my ($type, $current, $argument) = @_;
  my ($new_node_relations, $previous_node_relations) = @{$argument};

  if (exists($current->{'cmdname'}) and $current->{'cmdname'} eq 'menu') {
    if (defined($previous_node_relations)) {
      if (!exists($previous_node_relations->{'menus'})
          or not scalar(@{$previous_node_relations->{'menus'}})
          or not (grep {$current eq $_} @{$previous_node_relations->{'menus'}})) {
        print STDERR
           "BUG: menu $current not in previous node $previous_node_relations->{'element'}\n";
      } else {
        @{$previous_node_relations->{'menus'}}
          = grep {$_ ne $current} @{$previous_node_relations->{'menus'}};
        delete $previous_node_relations->{'menus'}
          if (!scalar(@{$previous_node_relations->{'menus'}}));
      }
    }
    push @{$new_node_relations->{'menus'}}, $current;
  } elsif (exists($current->{'extra'})
           and exists($current->{'extra'}->{'element_node'})) {
    if (defined($previous_node_relations)) {
      my $previous_node = $previous_node_relations->{'element'};
      if ($current->{'extra'}->{'element_node'}
          ne $previous_node->{'extra'}->{'normalized'}) {
        print STDERR "Bug: element $current not in previous node $previous_node; "
          .Texinfo::Common::debug_print_element($current)."\n";
        print STDERR "  previous node: "
        .Texinfo::Convert::Texinfo::root_heading_command_to_texinfo($previous_node)."\n";
        print STDERR "  current node identifier: ".
                          $current->{'extra'}->{'element_node'}."\n";
      }
    }
    $current->{'extra'}->{'element_node'}
      = $new_node_relations->{'element'}->{'extra'}->{'normalized'};
  } elsif (exists($current->{'cmdname'})
           and $current->{'cmdname'} eq 'nodedescription') {
    if (!exists($new_node_relations->{'node_description'})) {
      $new_node_relations->{'node_description'} = $current;
    }
    if (defined($previous_node_relations)
        and exists($previous_node_relations->{'node_description'})
        and $previous_node_relations->{'node_description'} eq $current) {
      delete $previous_node_relations->{'node_description'};
    }
  } elsif (exists($current->{'cmdname'})
           and $current->{'cmdname'} eq 'nodedescriptionblock') {
    if (!exists($new_node_relations->{'node_long_description'})) {
      $new_node_relations->{'node_long_description'} = $current;
    }
    if (defined($previous_node_relations)
        and exists($previous_node_relations->{'node_long_description'})
        and $previous_node_relations->{'node_long_description'} eq $current) {
      delete $previous_node_relations->{'node_long_description'};
    }
  }
  return undef;
}

sub insert_nodes_for_sectioning_commands($) {
  my $document = shift;

  my $root = $document->tree();
  my $nodes_list = $document->nodes_list();
  my $sections_list = $document->sections_list();
  # this is not used in the function.  The call makes sure that the C code
  # considers that the C data is up to date and do not attempts to rebuild
  # from C afterwards and instead returns the Perl data. This is important
  # because the Perl labels_list is modified in _new_node, not the C data,
  # such that the C data is not up to date and should not be accessed again.
  my $labels_list = $document->labels_list();

  my @added_nodes;
  my $previous_node_relations;
  my $contents_nr = scalar(@{$root->{'contents'}});
  my $node_idx = 0;
  for (my $idx = 0; $idx < $contents_nr; $idx++) {
    my $content = $root->{'contents'}->[$idx];
    if (exists($content->{'cmdname'}) and $content->{'cmdname'} ne 'node'
        and $content->{'cmdname'} ne 'part'
        and exists($Texinfo::Commands::root_commands{$content->{'cmdname'}})) {
      my $section_relations
        = $sections_list->[$content->{'extra'}->{'section_number'} -1];
      if ($section_relations->{'associated_node'}) {
        next;
      }
      my $new_node_tree;
      if ($content->{'cmdname'} eq 'top') {
        $new_node_tree
         = Texinfo::TreeElement::new({'contents' => [
                      Texinfo::TreeElement::new({'text' => 'Top'})]});
      } else {
        my $arguments_line = $content->{'contents'}->[0];
        my $line_arg = $arguments_line->{'contents'}->[0];
        $new_node_tree
         = Texinfo::ManipulateTree::copy_contentsNonXS($line_arg);
      }
      my $new_node = _new_node($new_node_tree, $document);
      if (defined($new_node)) {
        # insert before $content
        splice(@{$root->{'contents'}}, $idx, 0, $new_node);
        $idx++;
        $contents_nr++;
        # insert in nodes list
        my $new_node_relations = {'element' => $new_node,
                                  'associated_section' => $section_relations};
        splice(@{$nodes_list}, $node_idx, 0, $new_node_relations);
        $node_idx++;
        $new_node->{'extra'}->{'node_number'} = $node_idx;
        $section_relations->{'associated_node'} = $new_node_relations;
        $new_node->{'parent'} = $content->{'parent'}
          if (exists($content->{'parent'}));
        push @added_nodes, $new_node;
        # reassociate index entries and menus
        Texinfo::ManipulateTree::modify_tree($content, \&_reassociate_to_node,
                             [$new_node_relations, $previous_node_relations]);
      }
    }
    # check is_target to avoid erroneous nodes, such as duplicates
    if (exists($content->{'cmdname'})
        and $content->{'cmdname'} eq 'node'
        and exists($content->{'extra'})
        and $content->{'extra'}->{'is_target'}) {
      $previous_node_relations = $nodes_list->[$node_idx];
      # debug
      if ($previous_node_relations->{'element'} ne $content) {
        confess("insert_nodes_for_sectioning_commands: wrong node: '"
        .$previous_node_relations->{'element'}->{'extra'}->{'normalized'}.
               "' '".$content->{'extra'}->{'normalized'}."'\n");
      }
      $node_idx++;
      # reset node index taking into account the added nodes
      $content->{'extra'}->{'node_number'} = $node_idx;
    }
  }
  return \@added_nodes;
}

sub _prepend_new_menu_in_node_section($$$) {
  my ($node_relations, $section, $current_menu) = @_;

  if (not defined($current_menu)) {
    cluck "input menu undef";
  }
  push @{$section->{'contents'}}, $current_menu;
  $current_menu->{'parent'} = $section;
  push @{$section->{'contents'}},
        Texinfo::TreeElement::new({'type' => 'empty_line',
                                   'text' => "\n",});
  push @{$node_relations->{'menus'}}, $current_menu;
}

sub _complete_node_menu($;$) {
  my ($node_relations, $use_sections) = @_;

  my @node_childs
   = Texinfo::Structuring::get_node_node_childs_from_sectioning(
                                                       $node_relations);

  if (scalar(@node_childs)) {
    my %existing_entries;
    if (exists($node_relations->{'menus'})
        and scalar(@{$node_relations->{'menus'}})) {
      foreach my $menu (@{$node_relations->{'menus'}}) {
        foreach my $entry (@{$menu->{'contents'}}) {
          if (exists($entry->{'type'}) and $entry->{'type'} eq 'menu_entry') {
            my $normalized_entry_node
              = Texinfo::ManipulateTree::normalized_menu_entry_internal_node(
                                                                       $entry);
            if (defined($normalized_entry_node)) {
              $existing_entries{$normalized_entry_node} = [$menu, $entry];
            }
          }
        }
      }
    }
    #print STDERR "existing_entries: ".join('|', keys(%existing_entries))."\n";
    my @pending;
    my $current_menu;
    foreach my $node_entry_relations (@node_childs) {
      my $node_entry = $node_entry_relations->{'element'};
      my $normalized = $node_entry->{'extra'}->{'normalized'};
      if (exists($existing_entries{$normalized})) {
        my $entry;
        ($current_menu, $entry) = @{$existing_entries{$normalized}};
        if (scalar(@pending)) {
          my $index;
          for ($index = 0; $index < scalar(@{$current_menu->{'contents'}}); $index++) {
            #print STDERR "$index, ".scalar(@{$current_menu->{'contents'}})."\n";
            last if ($current_menu->{'contents'}->[$index] eq $entry);
          }
          splice (@{$current_menu->{'contents'}}, $index, 0, @pending);
          foreach my $pending_entry (@pending) {
            $pending_entry->{'parent'} = $current_menu;
          }
          @pending = ();
        }
      } else {
        my $entry
           = Texinfo::Structuring::new_node_menu_entry($node_entry_relations,
                                                              $use_sections);
        # not defined $entry should mean an empty node.  We do not warn as
        # we try, in general, to be silent in the transformations.
        push @pending, $entry if (defined($entry));
      }
    }
    if (scalar(@pending)) {
      if (!defined($current_menu)) {
        my $section = $node_relations->{'associated_section'}->{'element'};
        $current_menu
          = Texinfo::TreeElement::new({'contents' => \@pending,
                                       'parent' => $section});
        Texinfo::Structuring::new_block_command($current_menu, 'menu');
        _prepend_new_menu_in_node_section($node_relations,
                                          $section, $current_menu);
      } else {
        if (exists($current_menu->{'contents'}->[-1]->{'cmdname'})
            and $current_menu->{'contents'}->[-1]->{'cmdname'} eq 'end') {
          splice (@{$current_menu->{'contents'}}, -1, 0, @pending);
        } else {
          # Should probably only happen with menu without end
          push @{$current_menu->{'contents'}}, @pending;
        }
      }
      foreach my $entry (@pending) {
        $entry->{'parent'} = $current_menu;
      }
    }
  }
}

sub _get_non_automatic_nodes_with_sections($) {
  my $document = shift;

  my $root = $document->tree();
  my $nodes_list = $document->nodes_list();

  my @non_automatic_nodes;
  foreach my $node_relations (@{$nodes_list}) {
    my $node_element = $node_relations->{'element'};
    if (not (scalar(@{$node_element->{'contents'}->[0]->{'contents'}}) > 1)
        and exists($node_relations->{'associated_section'})) {
      push @non_automatic_nodes, $node_relations;
    }
  }
  return [ @non_automatic_nodes ];
}

# This should be called after Texinfo::Structuring::sectioning_structure.
sub complete_tree_nodes_menus_in_document($;$) {
  my ($document, $use_sections) = @_;

  my $non_automatic_nodes = _get_non_automatic_nodes_with_sections($document);
  foreach my $node_relations (@{$non_automatic_nodes}) {
    _complete_node_menu($node_relations, $use_sections);
  }
}

# this only complete menus if there was no menu
# The document is used to pass customization information for the gdt() call.
sub complete_tree_nodes_missing_menu($;$) {
  my ($document, $use_sections) = @_;

  my $lang_translations = Texinfo::Translations::new_lang_translation(
                              $document->get_conf('documentlanguage'),
                              $document->get_conf('COMMAND_LINE_ENCODING'));
  my $debug = $document->get_conf('DEBUG');

  my $non_automatic_nodes = _get_non_automatic_nodes_with_sections($document);
  foreach my $node_relations (@{$non_automatic_nodes}) {
    if (not exists($node_relations->{'menus'})
        or not scalar(@{$node_relations->{'menus'}})) {
      my $current_menu
        = Texinfo::Structuring::new_complete_node_menu($node_relations,
                                 $lang_translations, $debug, $use_sections);
      if (defined($current_menu)) {
        my $section = $node_relations->{'associated_section'}->{'element'};
        _prepend_new_menu_in_node_section($node_relations, $section,
                                          $current_menu);
      }
    }
  }
}

# The document is passed as customization information
sub regenerate_master_menu($;$) {
  my ($document, $use_sections) = @_;

  my $identifier_target = $document->labels_information();
  my $nodes_list = $document->nodes_list();

  my $top_node = $identifier_target->{'Top'};

  return undef if (!defined($top_node));

  my $top_node_relations
    = $nodes_list->[$top_node->{'extra'}->{'node_number'} -1];

  return undef if (!exists($top_node_relations->{'menus'})
                   or !scalar(@{$top_node_relations->{'menus'}}));

  my $lang_translation = Texinfo::Translations::new_lang_translation(
                           $document->get_conf('documentlanguage'),
                           $document->get_conf('COMMAND_LINE_ENCODING'));
  my $new_detailmenu
      = Texinfo::Structuring::new_detailmenu(
                      $lang_translation,
                      undef, $document,
                      $identifier_target, $nodes_list,
                      $top_node_relations->{'menus'},
                      $document->get_conf('DEBUG'),
                      $use_sections);
  # no need for a master menu
  return undef if (!defined($new_detailmenu));

  my $global_detailmenu
    = $document->global_commands_information()->{'detailmenu'};
  foreach my $menu (@{$top_node_relations->{'menus'}}) {
    my $menu_contents_len = scalar(@{$menu->{'contents'}});
    for (my $current_idx = 0; $current_idx < $menu_contents_len;
         $current_idx++) {
      my $entry = $menu->{'contents'}->[$current_idx];
      if (exists($entry->{'cmdname'})
          and $entry->{'cmdname'} eq 'detailmenu') {
        # replace existing detailmenu by the master menu
        $new_detailmenu->{'parent'} = $menu;
        splice (@{$menu->{'contents'}}, $current_idx, 1,
                $new_detailmenu);
        # also replace in global commands
        Texinfo::Common::replace_remove_list_element($global_detailmenu,
                                                  $entry, $new_detailmenu);

        # NOTE the menu entries added in @detailmenu are not added as
        # internal references.  However, this is not an issue, as the
        # menu entries in @detailmenu are also in regular menus.
        # As long as internal references are only used to check if all
        # the nodes are referenced, not having @detailmenu entries
        # added is not an issue at all.

        # remove internal refs of removed entries
        my $internal_references = $document->internal_references_information();
        foreach my $detailmenu_entry (@{$entry->{'contents'}}) {
          if (exists($detailmenu_entry->{'type'})
              and $detailmenu_entry->{'type'} eq 'menu_entry') {
            foreach my $entry_content (@{$detailmenu_entry->{'contents'}}) {
              if (exists($entry_content->{'type'})
                  and $entry_content->{'type'} eq 'menu_entry_node') {
                Texinfo::Common::replace_remove_list_element(
                                                      $internal_references,
                                                      $entry_content);
              }
            }
          }
        }
        return 1;
      }
    }
  }

  my $last_menu = $top_node_relations->{'menus'}->[-1];
  my $index = scalar(@{$last_menu->{'contents'}});
  if ($index
      and $last_menu->{'contents'}->[$index-1]->{'cmdname'}
      and $last_menu->{'contents'}->[$index-1]->{'cmdname'} eq 'end') {
    $index--;
  }

  $new_detailmenu->{'parent'} = $last_menu;
  if ($index) {
    my $last_element = $last_menu->{'contents'}->[$index-1];
    if (exists($last_element->{'type'})
        and $last_element->{'type'} eq 'menu_comment'
        and scalar(@{$last_element->{'contents'}})
        and exists($last_element->{'contents'}->[-1]->{'type'})
        and $last_element->{'contents'}->[-1]->{'type'} eq 'preformatted') {
      {
        # already a menu comment at the end of the menu, add an empty line
        my $preformatted = $last_element->{'contents'}->[-1];
        my $empty_line
          = Texinfo::TreeElement::new({'type' => 'empty_line',
                                       'text' => "\n",});
        push @{$preformatted->{'contents'}}, $empty_line;
      }
    } elsif (exists($last_element->{'type'})
             and $last_element->{'type'} eq 'menu_entry') {
      # there is a last menu entry, add a menu comment containing an empty line
      # after it
      my $menu_comment
        = Texinfo::TreeElement::new({'type' => 'menu_comment',
                                     'parent' => $last_menu});
      splice (@{$last_menu->{'contents'}}, $index, 0, $menu_comment);
      $index++;
      my $preformatted
        = Texinfo::TreeElement::new({'type' => 'preformatted',
                                     'parent' => $menu_comment});
      push @{$menu_comment->{'contents'}}, $preformatted;
      my $empty_line = Texinfo::TreeElement::new(
               {'type' => 'after_menu_description_line', 'text' => "\n",});
      push @{$preformatted->{'contents'}}, $empty_line;
    }
  }
  # insert master menu
  splice (@{$last_menu->{'contents'}}, $index, 0, $new_detailmenu);
  push @$global_detailmenu, $new_detailmenu;

  return 1;
}

# modify the menu tree to put description and menu comment content
# together directly in the menu.  Put the menu_entry in a preformatted.
# last merge preformatted.
sub menu_to_simple_menu($);

sub menu_to_simple_menu($) {
  my $menu = shift;

  my @contents;
  foreach my $content (@{$menu->{'contents'}}) {
    if (exists($content->{'type'}) and $content->{'type'} eq 'menu_comment') {
      push @contents, @{$content->{'contents'}};
    } elsif (exists($content->{'type'})
             and $content->{'type'} eq 'menu_entry') {
      my $preformatted = {'type' => 'preformatted', 'contents' => [$content]};
      push @contents, $preformatted;
      $content->{'parent'} = $preformatted;

      my $in_description;
      my @args = @{$content->{'contents'}};
      @{$content->{'contents'}} = ();
      while (@args) {
        if (exists($args[0]->{'type'})
            and $args[0]->{'type'} eq 'menu_entry_description') {
          my $description = shift @args;
          push @contents, @{$description->{'contents'}};
          push @contents, @args;
          last;
        } else {
          my $arg = shift @args;
          push @{$content->{'contents'}}, $arg;
        }
      }
    } elsif (exists($content->{'cmdname'})
   and exists($Texinfo::Commands::block_commands{$content->{'cmdname'}})
  and $Texinfo::Commands::block_commands{$content->{'cmdname'}} eq 'menu') {
      menu_to_simple_menu($content);
      push @contents, $content;
    } else {
      push @contents, $content;
    }
  }

  # reset parent, put in menu and merge preformatted.
  @{$menu->{'contents'}} = ();
  my $current_preformatted;
  foreach my $content (@contents) {
    $content->{'parent'} = $menu;
    if (exists($content->{'type'}) and $content->{'type'} eq 'preformatted') {
      if (!defined($current_preformatted)) {
        $current_preformatted = $content;
        push @{$menu->{'contents'}}, $content;
      } else {
        foreach my $preformatted_content (@{$content->{'contents'}}) {
          push @{$current_preformatted->{'contents'}}, $preformatted_content;
          $preformatted_content->{'parent'} = $current_preformatted;
        }
      }
    } else {
      $current_preformatted = undef;
      push @{$menu->{'contents'}}, $content;
    }
  }
}

sub _protect_hashchar_at_line_beginning($$$) {
  my ($type, $parent, $argument) = @_;

  my $document = $argument;

  return undef if (exists($parent->{'text'})
                   or !exists($parent->{'contents'}));

  my $parent_contents_nr = scalar(@{$parent->{'contents'}});
  for (my $i = 0; $i < $parent_contents_nr; $i++) {
    my $current = $parent->{'contents'}->[$i];
    if (exists($current->{'text'}) and
      $current->{'text'} =~ /^\s*#\s*(line)? (\d+)(( "([^"]+)")(\s+\d+)*)?\s*$/) {
      # protect if first in container, or if after a newline
      if ($i == 0
          or ($i == 1 and exists($parent->{'contents'}->[0]->{'type'})
              and $parent->{'contents'}->[0]->{'type'} eq 'arguments_line')
          or (exists($parent->{'contents'}->[$i-1]->{'text'})
              and $parent->{'contents'}->[$i-1]->{'text'} =~ /\n$/)) {
        # do not actually protect in raw block command, but warn
        if (exists($current->{'type'}) and $current->{'type'} eq 'raw') {
          my $parent_for_warn = $parent;
          while ($parent_for_warn) {
            if (exists($parent_for_warn->{'cmdname'})
                and exists($parent_for_warn->{'source_info'})) {
              if (defined($document)) {
                $document->document_line_warn(sprintf(__(
                    "could not protect hash character in \@%s"),
                         $parent_for_warn->{'cmdname'}),
                                   $parent_for_warn->{'source_info'}, 0);
              }
              last;
            }
            $parent_for_warn = $parent_for_warn->{'parent'};
          }
        } else {
          my $remaining_source_marks;
          my $current_position = 0;
          if (exists($current->{'source_marks'})) {
            $remaining_source_marks = [@{$current->{'source_marks'}}];
            delete $current->{'source_marks'};
          }

          $current->{'text'} =~ s/^(\s*)#//;

          my $e = Texinfo::TreeElement::new({'text' => $1,});
          $current_position = Texinfo::Common::relocate_source_marks(
                                      $remaining_source_marks, $e,
                                      $current_position, length($1));
          if ($e->{'text'} ne '' or $e->{'source_marks'}) {
            splice @{$parent->{'contents'}}, $i, 0, $e;
            $i++;
            $parent_contents_nr++;
          }

          $e = Texinfo::TreeElement::new({'cmdname' => 'hashchar',
                                          'parent' => $parent});
          my $arg = Texinfo::TreeElement::new({'type' => 'brace_container',
                                               'parent' => $e});
          $e->{'contents'} = [$arg];
          $current_position = Texinfo::Common::relocate_source_marks(
                                        $remaining_source_marks, $e,
                                        $current_position, 1);
          splice @{$parent->{'contents'}}, $i, 0, $e;
          $i++;
          $parent_contents_nr++;

          $current_position = Texinfo::Common::relocate_source_marks(
                                        $remaining_source_marks, $current,
                                        $current_position,
                                        length($current->{'text'}));
        }
      }
    }
  }
  return undef;
}

sub protect_hashchar_at_line_beginning($;$) {
  my ($tree, $document) = @_;

  return Texinfo::ManipulateTree::modify_tree($tree,
                     \&_protect_hashchar_at_line_beginning,
                      $document);
}

# Has an XS override. Defined to be able to test Perl and XS. Undocumented
# on purpose.
sub protect_hashchar_at_line_beginning_in_document($) {
  my $document = shift;

  protect_hashchar_at_line_beginning($document->tree(), $document);
  return;
}

sub _protect_first_parenthesis_in_targets($$$) {
  my ($type, $current, $argument) = @_;

  my $element_label = Texinfo::Common::get_label_element($current);
  if (defined($element_label) and $element_label ne '') {
    Texinfo::ManipulateTree::protect_first_parenthesis($element_label);
  }
  return undef;
}

# Used in Pod::Simple::Texinfo
# TODO document
sub protect_first_parenthesis_in_targets($) {
  my $tree = shift;

  Texinfo::ManipulateTree::modify_tree($tree,
                           \&_protect_first_parenthesis_in_targets);
}

# Has an XS override. Defined to be able to test Perl and XS. Undocumented
# on purpose.
sub protect_first_parenthesis_in_targets_in_document($) {
  my $document = shift;

  protect_first_parenthesis_in_targets($document->tree());
  return;
}

1;

__END__

=head1 NAME

Texinfo::Transformations - transformations of Texinfo tree

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

Includes miscellaneous methods such as as
C<insert_nodes_for_sectioning_commands> that adds nodes for sectioning commands
without nodes and C<complete_tree_nodes_menus_in_document> and
C<complete_tree_nodes_missing_menu> that completes the node menus based on the
sectioning tree.

Methods for copying and modifying the Texinfo tree used for default
conversion to output formats are in L<Texinfo::ManipulateTree>.

=head1 METHODS

No method is exported in the default case.

=over

=item complete_tree_nodes_menus_in_document($document, $add_section_names_in_entries)
X<C<complete_tree_nodes_menus_in_document>>

Add menu entries or whole menus for nodes associated with sections,
based on the sectioning tree.  If the optional
C<$add_section_names_in_entries> argument is set, a menu entry
name is added using the section name.  This function should be
called after L<sectioning_structure|Texinfo::Structuring/sectioning_structure($document)>.

=item complete_tree_nodes_missing_menu($document, $use_section_names_in_entries)
X<C<complete_tree_nodes_missing_menu>>

Add whole menus for nodes associated with sections and without menu,
based on the I<$document> sectioning tree.
If the optional I<$add_section_names_in_entries> argument is set, a menu entry
name is added using the section name.  This function should be
called after L<sectioning_structure|Texinfo::Structuring/sectioning_structure($document)>.

=item fill_gaps_in_sectioning_in_document($document, $commands_heading_tree)
X<C<fill_gaps_in_sectioning_in_document>>

This function adds empty C<@unnumbered> and similar commands in a
I<$document> tree to fill gaps in sectioning.  This may be used, for example,
when converting from a format that can handle gaps in sectioning.

In the default case, the added sectioning commands headings are empty.  It is
possible to use instead the I<$commands_heading_tree> Texinfo tree element.

If the sectioning commands are lowered or raised (with C<@raisesections>,
C<@lowersection>) the tree may be modified with C<@raisesections> or
C<@lowersection> added to some tree elements.

=item insert_nodes_for_sectioning_commands($document)
X<C<insert_nodes_for_sectioning_commands>>

Insert nodes for sectioning commands without node in C<$document>
tree.

=item menu_to_simple_menu($menu)
X<C<menu_to_simple_menu>>

C<menu_to_simple_menu> transforms the tree of a menu tree element.

A simple menu has no I<menu_comment>, I<menu_entry> or I<menu_entry_description>
container anymore, their content are merged directly in the menu in
I<preformatted> container.

Note that this kind of tree is not supported by other codes, so this
transformation should be avoided unless one knows exactly what to expect.

=item protect_hashchar_at_line_beginning($tree, $document)
X<C<protect_hashchar_at_line_beginning>>

Protect hash (#) character at the beginning of line such that they would not be
considered as lines to be processed by the CPP processor.  The I<$document>
argument is optional.  If defined, the I<$document> is used for error reporting
in case an hash character could not be protected because it appeared in a raw
formatted environment (C<@tex>, C<@html>...).

=item $modified_tree = reference_to_arg_in_tree($tree, $document)
X<C<reference_to_arg_in_tree>>

Modify I<$tree> by converting reference @-commands to simple text using one of
the arguments.  This transformation can be used, for example, to remove
reference @-command from constructed node names trees, as node names cannot
contain reference @-command while there could be some in the tree used in input
for the node name tree.  The I<$document> argument is optional.  If given,
the converted reference @-command is removed from the I<$document> internal
references list.

A I<$modified_tree> is not systematically returned, if the I<$tree> in argument
is not replaced, undef may also be returned.

=item regenerate_master_menu($document, $use_sections)
X<C<regenerate_master_menu>>

Regenerate the I<$document> Top node master menu, replacing the first
detailmenu in Top node menus or appending at the end of the Top node menu.

I<$use_sections> is an optional argument.  If set, sections associated with
nodes are used as labels in the generated master menu.

=back

=head1 SEE ALSO

L<Texinfo manual|http://www.gnu.org/s/texinfo/manual/texinfo/>,
L<Texinfo::Parser>, L<Texinfo::ManipulateTree>.

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
