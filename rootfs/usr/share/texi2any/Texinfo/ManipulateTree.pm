# ManipulateTree.pm: common Texinfo tree manipulation
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

# functions useful for Texinfo tree transformations
# and some tree transformations functions, mostly those
# used in conversion to main output formats.  In general,
# tree transformations functions are documented in the POD section.

# Some helper functions defined here are used in other
# modules but are not generally useful in converters
# and therefore not public.

# ALTIMP XSTexinfo/parser_document/StructuringTransfoXS.xs
# ALTIMP C/main/manipulate_tree.c

package Texinfo::ManipulateTree;

use 5.006;

# stop \s from matching non-ASCII spaces, etc.  \p{...} can still be
# used to match Unicode character classes.
use if $] >= 5.014, re => '/a';

use strict;

# To check if there is no erroneous autovivification
#no autovivification qw(fetch delete exists store strict);

# debugging
use Carp qw(cluck confess);

# Do not used Devel::Peek, instead implement SvREFCNT as Devel::Peek
# cannot be loaded in an eval
#use Devel::Peek;
# SvREFCNT counts are wrong if loaded through eval?
#eval { require Devel::Peek; Devel::Peek->import(); };

# Next two only needed for debugging, if customization variable TEST
# is set > 2 (which never happens automatically).
eval { require Devel::Refcount; Devel::Refcount->import(); };
eval { require Devel::FindRef; Devel::FindRef->import(); };

my $devel_findref_loading_error = $@;

# for fileparse
use File::Basename;

use Texinfo::StructTransfXS;

use Texinfo::XSLoader;

use Texinfo::TreeElement;

use Texinfo::Common;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw(
move_index_entries_after_items_in_document
relate_index_entries_to_table_items_in_document
protect_colon_in_tree
protect_comma_in_tree
protect_first_parenthesis
protect_node_after_label_in_tree
normalized_entry_associated_internal_node
);

our $VERSION = '7.3';

my $XS_structuring = Texinfo::XSLoader::XS_structuring_enabled();

my %XS_overrides = (
  "Texinfo::ManipulateTree::copy_tree"
    => "Texinfo::StructTransfXS::copy_tree",
  "Texinfo::ManipulateTree::relate_index_entries_to_table_items_in_document"
    => "Texinfo::StructTransfXS::relate_index_entries_to_table_items_in_document",
  "Texinfo::ManipulateTree::move_index_entries_after_items_in_document"
    => "Texinfo::StructTransfXS::move_index_entries_after_items_in_document",
  "Texinfo::ManipulateTree::protect_colon_in_document"
    => "Texinfo::StructTransfXS::protect_colon_in_document",
  "Texinfo::ManipulateTree::protect_comma_in_document"
    => "Texinfo::StructTransfXS::protect_comma_in_document",
  "Texinfo::ManipulateTree::protect_node_after_label_in_document"
    => "Texinfo::StructTransfXS::protect_node_after_label_in_document",
  "Texinfo::ManipulateTree::tree_print_details"
    => "Texinfo::StructTransfXS::tree_print_details",

  # Devel::Peek is not present on all the platforms, and we cannot load it
  # in an eval, so we reimplement trivially SvREFCNT
  "Texinfo::ManipulateTree::SvREFCNT"
    => "Texinfo::StructTransfXS::SvREFCNT",
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



# copy a Texinfo tree.

# To do the copy, we do two pass.  First with _copy_tree, the tree is
# copied and a reference to the copy is put in all the elements,
# taking care that each element is processed once only.
# Then, remove_element_copy_info goes through the tree again and remove
# the references to the copies.

# the *_directions extra items are not elements, they contain
# up, next and prev that point to elements.
# it could also have been possible to determine that it is
# an extra_directions if the keys are only up, next and prev
# NOTE these are not in tree but in relations information.  The code is kept
# nevertheless in case some directions are put back in extra in the tree.
my %extra_directions;
foreach my $type ('node', 'section', 'toplevel') {
  $extra_directions{$type.'_directions'} = 1;
}

# $OTHER_TREES sould be used to put subtree roots, for instance to make sure
# that all the references are within one tree.  For now, if undef, the extra
# references to elements are not followed, except for elements that are not
# in other parts of the tree.
sub _copy_tree($;$);
sub _copy_tree($;$) {
  my ($current, $other_trees) = @_;

  # either a duplicate in a tree (should be rare/avoided) or an
  # element referred to in extra/info, either directly or
  # (probably rare) in the extra element tree that has already
  # been seen in the tree
  if (exists($current->{'_copy'})) {
    #print STDERR "RCT $current ".debug_print_element($current)
    # .": $current->{'_counter'}\n";
    return $current->{'_copy'};
  }

  my $new = Texinfo::TreeElement::new({});
  foreach my $key ('type', 'text') {
    $new->{$key} = $current->{$key} if (exists($current->{$key}));
  }

  $current->{'_copy'} = $new;

  if (exists($current->{'text'})) {
    if (exists($current->{'info'})
        and exists($current->{'info'}->{'inserted'})) {
      $new->{'info'} = {'inserted' => $current->{'info'}->{'inserted'}};
    }
    return $new;
  }

  my $command_or_type = '';
  if (exists($current->{'cmdname'})) {
    $new->{'cmdname'} = $current->{'cmdname'};
    $command_or_type = '@'.$current->{'cmdname'};
  } elsif (exists($current->{'type'})) {
    $command_or_type = $current->{'type'};
  }

  #print STDERR "CTNEW $current ".debug_print_element($current)." $new\n";

  if (exists($current->{'contents'})) {
    if (!defined($current->{'contents'})) {
      print STDERR "BUG: contents not defined ".Texinfo::Common::debug_print_element($current)."\n";
      cluck();
    }
    if (ref($current->{'contents'}) ne 'ARRAY') {
      print STDERR "BUG: Not an array [$command_or_type] $current->{'contents'} 'contents' ".
                                           ref($current->{'contents'})."\n";
    }
    $new->{'contents'} = [];
    foreach my $child (@{$current->{'contents'}}) {
      my $added = _copy_tree($child, $other_trees);
      $added->{'parent'} = $new unless(exists($added->{'text'}));
      push @{$new->{'contents'}}, $added;
    }
  }

  foreach my $info_type ('info', 'extra') {
    next if (!exists($current->{$info_type}));
    $new->{$info_type} = {};
    foreach my $key (sort(keys(%{$current->{$info_type}}))) {
      my $value = $current->{$info_type}->{$key};
      if (ref($value) eq '') {
        $new->{$info_type}->{$key} = $value;
      } elsif (ref($value) eq 'ARRAY') {
        # formerly menus, now in node relations
        if (ref($value->[0]) eq 'HASH'
            or ref($value->[0]) eq 'Texinfo::TreeElement') {
          #print STDERR "II ARRAY $key $value\n";
          if ($other_trees) {
            $new->{$info_type}->{$key} = [];
            foreach my $target (@{$value}) {
              push @{$new->{$info_type}->{$key}},
                   _copy_tree($target, $other_trees);
            }
          }
        } elsif (ref($value->[0]) eq '') {
        # misc_args index_entry
          $new->{$info_type}->{$key} = [@$value];
        } else {
          print STDERR "Unexpected array $info_type [$command_or_type]{$key}: "
                                                     .ref($value->[0])."\n";
        }
      } elsif (ref($value) eq 'HASH' or ref($value) eq 'Texinfo::TreeElement') {
        #print STDERR "II HASH $key $value\n";
        if (not $other_trees
            and ($info_type eq 'extra'
                 # elements that do not point to other parts of the tree,
                 # point to associated element
                 and $key ne 'node_content'
                 and $key ne 'node_manual'
                 # point to element only in extra, not in the document tree
                 and $key ne 'def_index_element'
                 and $key ne 'def_index_ref_element')) {
          next;
        }
        if ($extra_directions{$key}) {
          $new->{$info_type}->{$key} = {};
          foreach my $direction (sort(keys(%$value))) {
            my $target = $value->{$direction};
            $new->{$info_type}->{$key}->{$direction}
              = _copy_tree($target, $other_trees);
          }
        } else {
          if (not exists($value->{'cmdname'}) and not exists($value->{'type'})
              and not exists($value->{'text'}) and not exists($value->{'extra'})
              and not exists($value->{'contents'})
              and scalar(keys(%$value))) {
            print STDERR "HASH NOT ELEMENT $info_type [$command_or_type]{$key}\n";
          }
          $new->{$info_type}->{$key} = _copy_tree($value, $other_trees);
        }
      } else {
        print STDERR "Unexpected $info_type [$command_or_type]{$key}: "
                                                          .ref($value)."\n";
      }
    }
  }
  return $new;
}

sub _remove_element_copy_info($;$$);
sub _remove_element_copy_info($;$$) {
  my ($current, $level, $added_root_elements) = @_;

  my $command_or_type = '';
  if (exists($current->{'cmdname'})) {
    $command_or_type = '@'.$current->{'cmdname'};
  } elsif (exists($current->{'type'})) {
    $command_or_type = $current->{'type'};
  }

  $level = 0 if (!defined($level));

  if (!exists($current->{'_copy'})) {
    #print STDERR "DONE $current ".debug_print_element($current)."\n";
    return;
  }

  if (!exists($current->{'text'})
      and !exists($current->{'_copy'}->{'parent'})) {
    if ($added_root_elements) {
      push @$added_root_elements, $current->{'_copy'};
    }
  }

  delete $current->{'_copy'};

  $level++;
  #print STDERR (' ' x $level)
  #   .Texinfo::Common::debug_print_element($current).": $current\n";

  if (exists($current->{'contents'})) {
    my $index = 0;
    foreach my $child (@{$current->{'contents'}}) {
      _remove_element_copy_info($child, $level, $added_root_elements);
      $index++;
    }
  }

  foreach my $info_type ('info', 'extra') {
    next if (!exists($current->{$info_type}));
    foreach my $key (sort(keys(%{$current->{$info_type}}))) {
      my $value = $current->{$info_type}->{$key};
      #print STDERR (' ' x $level) . "K $info_type $key |$value\n";
      if (ref($value) eq 'ARRAY') {
        if (ref($value->[0]) eq 'HASH'
            or ref($value->[0]) eq 'Texinfo::TreeElement') {
        #print STDERR (' ' x $level) .
        #           "Array $command_or_type $info_type -> $key\n";
          # manual_content menus node_content
          for (my $index = 0; $index < scalar(@{$value}); $index++) {
            #my $context = "$info_type [$command_or_type]{$key} [$index]";
            _remove_element_copy_info($value->[$index], $level,
                                      $added_root_elements);
          }
        }
      } elsif (ref($value) eq 'HASH'
               or ref($value) eq 'Texinfo::TreeElement') {
        #print STDERR (' ' x $level)
        #         . "Hash $command_or_type $info_type -> $key\n";
        if ($extra_directions{$key}) {
          foreach my $direction (sort(keys(%$value))) {
            #my $context = "$info_type [$command_or_type]{$key} {$direction}";
            _remove_element_copy_info($value->{$direction}, $level,
                                      $added_root_elements);
          }
        } else {
          if (not exists($value->{'cmdname'}) and not exists($value->{'type'})
              and not exists($value->{'text'}) and not exists($value->{'extra'})
              and not exists($value->{'contents'})
              and scalar(keys(%$value))) {
            print STDERR "HASH NOT ELEMENT $info_type [$command_or_type]{$key}\n";
          }
          _remove_element_copy_info($value, $level, $added_root_elements);
        }
      }
    }
  }
}

# The functions called in Perl code outside of tests are the copy_*NonXS
# functions.
# TODO document?
# If $ADDED_ROOT_ELEMENTS is set, links in extra to other subtrees are
# followed and subtree roots should be put in there.
# NOTE right now there are no extra types that points to other parts
# of the tree used in any code.  See comment in C code for more information.
sub copy_tree($;$)
{
  my ($current, $added_root_elements) = @_;

  my $other_trees;
  if (defined($added_root_elements)) {
    $other_trees = {};
  }

  my $copy = _copy_tree($current, $other_trees);
  _remove_element_copy_info($current, $copy, $added_root_elements);

  if (defined($added_root_elements)) {
    $added_root_elements = [ grep {$_ ne $current} @$added_root_elements ];
  }

  return $copy;
}

# Never overriden by XS version
sub copy_treeNonXS($;$) {
  my ($current, $added_root_elements) = @_;

  my $other_trees;
  if (defined($added_root_elements)) {
    $other_trees = {};
  }

  my $copy = _copy_tree($current, $other_trees);
  _remove_element_copy_info($current, $copy, $added_root_elements);

  if (defined($added_root_elements)) {
    $added_root_elements = [ grep {$_ ne $current} @$added_root_elements ];
  }

  return $copy;
}

sub copy_contents($;$) {
  my ($element, $type) = @_;

  my $copy;
  if (!exists($element->{'contents'})) {
    $copy = Texinfo::TreeElement::new({});
  } else {
    # Done for consistency, but not sure that it is needed
    my $tmp = Texinfo::TreeElement::new({'contents' => $element->{'contents'}});
    $copy = copy_tree($tmp);
  }
  if (defined($type)) {
    $copy->{'type'} = $type;
  }
  return $copy;
}

sub copy_contentsNonXS($;$) {
  my ($element, $type) = @_;

  my $copy;
  if (!exists($element->{'contents'})) {
    $copy = Texinfo::TreeElement::new({});
  } else {
    # Done for consistency, but not sure that it is needed
    my $tmp = Texinfo::TreeElement::new({'contents' => $element->{'contents'}});
    $copy = copy_treeNonXS($tmp);
  }
  if (defined($type)) {
    $copy->{'type'} = $type;
  }
  return $copy;
}



# The XS override returns the SvREFCNT value.
#   $EXPECTED_COUNT should be set to the reference count expected, for
#   instance the reference count expected in a test that follows the
#   call to SvREFCNT.
sub SvREFCNT($;$) {
  # If there is no XS, return the expected count instead of showing the
  # true reference count.
  my ($variable, $expected_count) = @_;

  return $expected_count;
}

# for debugging
sub _print_tree_elements_ref($$);
sub _print_tree_elements_ref($$)
{
  my ($element, $level) = @_;

  my $parent;
  if (exists($element->{'parent'})) {
    $parent = ' (p)';
  } else {
    $parent = '';
  }

  my $reference_count = SvREFCNT($element, -1);
  my $object_count = Devel::Refcount::refcount($element);

  print STDERR "". (' ' x $level) . $element
     . Texinfo::Common::debug_print_element($element)
       . "${parent}{$reference_count;$object_count}\n";

  if (exists($element->{'source_marks'})) {
    foreach my $source_mark (@{$element->{'source_marks'}}) {
      if (exists($source_mark->{'element'})) {
        _print_tree_elements_ref($source_mark->{'element'}, $level+3);
      }
    }
  }

  return if (exists($element->{'text'}));

  if (exists($element->{'info'})) {
    foreach my $info_elt_key ('comment_at_end', 'spaces_before_argument',
                              'spaces_after_cmd_before_arg',
                              'spaces_after_argument') {
      if (exists($element->{'info'}->{$info_elt_key})) {
        _print_tree_elements_ref($element->{'info'}->{$info_elt_key}, $level+2);
      }
    }
  }

  if (exists($element->{'contents'})) {
    for (my $i = 0; $i < scalar(@{$element->{'contents'}}); $i++) {
      _print_tree_elements_ref($element->{'contents'}->[$i], $level+1);
    }
  }
}

sub tree_remove_parents($);

# TODO add documentation?
# remove parent key in tree, which allows to remove the cycle going
# through contents and parents.
sub tree_remove_parents($) {
  my $element = shift;

  confess() if (!defined($element));
  #print STDERR "TREE t_r_p $element: "
  #     .Devel::Refcount::refcount($element)."\n";
  #   .Texinfo::ManipulateTree::element_print_details($element)."\n";

  if (exists($element->{'source_marks'})) {
    foreach my $source_mark (@{$element->{'source_marks'}}) {
      if (exists($source_mark->{'element'})) {
        tree_remove_parents($source_mark->{'element'});
      }
    }
  }

  return if (exists($element->{'text'}));

  delete $element->{'parent'};

  if (exists($element->{'info'})) {
    foreach my $info_elt_key ('comment_at_end', 'spaces_before_argument',
                              'spaces_after_cmd_before_arg',
                              'spaces_after_argument') {
      # for spaces_* parents can only be in source marks
      if (exists($element->{'info'}->{$info_elt_key})) {
        tree_remove_parents($element->{'info'}->{$info_elt_key});
      }
    }
  }

  if (exists($element->{'contents'})) {
    foreach my $content (@{$element->{'contents'}}) {
      tree_remove_parents($content);
    }
    if (exists($element->{'extra'})) {
      if (exists($element->{'extra'}->{'def_index_element'})) {
        tree_remove_parents($element->{'extra'}->{'def_index_element'});
        if (exists($element->{'extra'}->{'def_index_ref_element'})) {
          tree_remove_parents($element->{'extra'}->{'def_index_ref_element'});
        }
      }
      # elements also in $element->{'contents'} (without parent when added).
      #foreach my $key ('node_content', 'manual_content') {
      #  if (exists($element->{'extra'}->{$key})) {
      #    tree_remove_parents($element->{'extra'}->{$key});
      #  }
      #}
    }
  }
}

# expected number of references to the object
# The $element variable owns one count to reference and to object.
# The parent contents or the extra key or the info key or the
# source mark element key also holds a count to the object.
# plus possibly one count owned by the C code
my $destroyed_objects_refcount;
# used in messages
my $destroyed_objects_refcount_text;
# expected number of references to the object if created in Perl without
# any reference owned by the C code.  Only possible with XS parser, and
# with structure without XS.
my $no_XS_objects_refcount;

# expected number of references to the element SV
my $element_SV_target_count = 1;

sub _element_remove_references($;$$);

# recursively remove references to element.  In general should not be
# called on the tree root element, as it has different number of references.
# If $CHECK_REFCOUNT is set (to a Document), verify that the reference count for
# elements correspond to the count after removing reference to tree elements
# as much as possible while still being able to process the tree.
sub _element_remove_references($;$$) {
  my ($element, $check_refcount, $silent_refcount) = @_;

  # We do not set variables to hash values in this code, as this adds a
  # refcount, we do everything with the hash key values directly.

  if (exists($element->{'source_marks'})) {
    foreach my $source_mark (@{$element->{'source_marks'}}) {
      if (exists($source_mark->{'element'})) {
        _element_remove_references($source_mark->{'element'},
                                   $check_refcount, $silent_refcount);
      }
      delete $source_mark->{'element'};
    }
  }

  if (!exists($element->{'text'})) {
    if (exists($element->{'info'})) {
      foreach my $info_elt_key ('comment_at_end', 'spaces_before_argument',
                                'spaces_after_cmd_before_arg',
                                'spaces_after_argument') {
        if (exists($element->{'info'}->{$info_elt_key})) {
          _element_remove_references($element->{'info'}->{$info_elt_key},
                                 $check_refcount, $silent_refcount);
          delete $element->{'info'}->{$info_elt_key};
        }
      }
    }

    if (exists($element->{'contents'})) {
      if (exists($element->{'extra'})) {
        if (exists($element->{'extra'}->{'def_index_element'})) {
          _element_remove_references($element->{'extra'}->{'def_index_element'},
                                 $check_refcount, $silent_refcount);
          delete $element->{'extra'}->{'def_index_element'};
          if (exists($element->{'extra'}->{'def_index_ref_element'})) {
            _element_remove_references(
              $element->{'extra'}->{'def_index_ref_element'},
                                   $check_refcount, $silent_refcount);
            delete $element->{'extra'}->{'def_index_ref_element'};
          }
        }
        # hold duplicates of the element label contents
        foreach my $key ('node_content', 'manual_content') {
          if (exists($element->{'extra'}->{$key})) {
            delete $element->{'extra'}->{$key}->{'contents'};
          }
        }
      }
      for (my $i = 0; $i < scalar(@{$element->{'contents'}}); $i++) {
        _element_remove_references($element->{'contents'}->[$i],
                               $check_refcount, $silent_refcount);
      }
      delete $element->{'contents'};
    }
  }

  #print STDERR "T RREF $element ".
  #   Texinfo::ManipulateTree::element_print_details($element)."\n";

  if (defined($check_refcount) and not $silent_refcount) {
    my $reference_count = SvREFCNT($element, $element_SV_target_count);
    my $object_count = Devel::Refcount::refcount($element);
    #if (1) {
    #Devel::Peek::Dump($element);
    if ($reference_count != $element_SV_target_count
        or ($object_count != $destroyed_objects_refcount
            and !(defined($no_XS_objects_refcount)
                  and $object_count == $no_XS_objects_refcount))) {
      my $findref_info;
      if ($devel_findref_loading_error) {
        $findref_info = '';
      } else {
        $findref_info = Devel::FindRef::track($element)."\n";
      }
      my $message = "Element refcount ($reference_count, $object_count) != ".
             "($element_SV_target_count, $destroyed_objects_refcount_text)";
      warn "You found a bug: $message for $element\n\n".
      Texinfo::ManipulateTree::element_print_details($element)."\n".
       $findref_info;
      # pass as warning to have t/*.t tests fail
      $check_refcount->document_line_warn("$message for "
           . Texinfo::Common::debug_print_element($element), {});
    }
  }
}

# Remove all the references to elements in tree.  The main objective
# here is not to release memory, as Perl can release memory if there are
# no cycles, but to be able to check that the reference counting in C/XS is done
# correctly.  No specific reason to use in code outside of the Texinfo modules,
# not documented on purpose.
sub tree_remove_references($;$$) {
  my ($tree, $check_refcount, $silent_refcount) = @_;

  if (defined($check_refcount)) {
    # Setup the expected reference counts.  Better do it dynamically
    # and not out of any function to be sure that the the parser module have been
    # setup and XS_parser_loaded return is correct.
    $destroyed_objects_refcount = 2;
    $destroyed_objects_refcount_text = $destroyed_objects_refcount;
    # Do not use XS_parser_enabled, as the loading of the parser may have failed
    # even if it was enabled.
    if (Texinfo::XSLoader::XS_parser_loaded()) {
      # a reference in C too
      $destroyed_objects_refcount++;

      if (!$XS_structuring) {
        # transformations may create elements in pure Perl only when
        # structuring is not done with XS extensions.
        $no_XS_objects_refcount = $destroyed_objects_refcount -1;
        $destroyed_objects_refcount_text
          = "$destroyed_objects_refcount or $no_XS_objects_refcount";
      } else {
        $destroyed_objects_refcount_text = $destroyed_objects_refcount;
      }
    }
  }

  if (exists($tree->{'contents'})) {
   foreach my $content (@{$tree->{'contents'}}) {
     _element_remove_references($content, $check_refcount, $silent_refcount);
   }

    delete $tree->{'contents'};
  }
}



sub set_element_tree_numbers($$);

# does nothing as there are no reference to tree elements
# in the tree extra information currently, consistently no command
# is selected, so this function has no effect.
sub set_element_tree_numbers($$) {
  my ($element, $current_nr) = @_;

  if (exists($element->{'text'})) {
    return $current_nr;
  }

  my $type = $element->{'type'};
  my $cmdname = $element->{'cmdname'};

  my $builtin_cmdname;

  if (defined($type) and $type eq 'definfoenclose_command') {
    $builtin_cmdname = 'definfoenclose_command';
  } elsif (defined($cmdname)) {
    $builtin_cmdname = $cmdname;
  }

  if ($builtin_cmdname
      # no reference to other commands in tree for now
      and (0)
      #and ($builtin_cmdname eq 'node'
      #  or $Texinfo::Commands::sectioning_heading_commands{$builtin_cmdname})
    # no reason for this to happen, but if it does, avoid clobbering
      and not exists($element->{'_number'})) {
    $element->{'_number'} = $current_nr;
    $current_nr++;
  }

  if (exists($element->{'contents'})) {
    foreach my $content (@{$element->{'contents'}}) {
      $current_nr = set_element_tree_numbers($content, $current_nr);
    }
  }
  return $current_nr;
}

my $SOURCE_MARK_PREPEND = '>';

sub print_tree_details($$$$;$$);

sub _print_source_marks($$$$;$$) {
  my ($element, $level, $prepended, $current_nr, $fname_encoding,
      $use_filename) = @_;

  return ($current_nr, '') if (!exists($element->{'source_marks'}));

  my $s_mark_prepended;
  if (defined($prepended)) {
    $s_mark_prepended = $prepended . $SOURCE_MARK_PREPEND;
  } else {
    $s_mark_prepended = $SOURCE_MARK_PREPEND;
  }

  my $result = (' ' x $level) . $s_mark_prepended . "SOURCEMARKS\n";
  my @source_marks = @{$element->{'source_marks'}};
  foreach my $s_mark (@source_marks) {
    $result .= (' ' x $level) . $s_mark_prepended
               . $s_mark->{'sourcemark_type'}.'<';
    if ($s_mark->{'status'}) {
      $result .= "$s_mark->{'status'};";
    }
    $result .= "$s_mark->{'counter'}>";
    if (exists($s_mark->{'position'})) {
      $result .= "<p:$s_mark->{'position'}>";
    }
    if (exists($s_mark->{'line'})) {
      $result .= '{'._debug_protect_eol($s_mark->{'line'}).'}';
    }
    $result .= "\n";

    if (exists($s_mark->{'element'})) {
      my $element_result;
      ($current_nr, $element_result)
       = print_tree_details($s_mark->{'element'}, $level+1,
                         $s_mark_prepended, $current_nr, $fname_encoding,
                         $use_filename);
      $result .= $element_result;
    }
  }

  return ($current_nr, $result);
}

sub _print_text_element($$$;$$) {
  my ($element, $level, $prepended, $fname_encoding, $use_filename) = @_;

  my $result = '';
  if (exists($element->{'info'}) and $element->{'info'}->{'inserted'}) {
    $result .= '(i)';
  }

  my $element_text = _debug_protect_eol($element->{'text'});

  if (exists($element->{'type'})) {
    $result .= "{$element->{'type'}:${element_text}}";
  } else {
    $result .= "{${element_text}}";
  }
  # this is for debug, text element should not have parent
  if (exists($element->{'parent'})) {
    $result .= "p";
  }
  $result .= "\n";

  return $result;
}

my $ADDITIONAL_INFO_PREPEND = '|';

sub _print_element_add_prepend_info($$$$;$$) {
  my ($element, $level, $prepended, $current_nr, $fname_encoding,
      $use_filename) = @_;

  my $info_prepended;
  if (defined($prepended)) {
    $info_prepended = $prepended . $ADDITIONAL_INFO_PREPEND;
  } else {
    $info_prepended = $ADDITIONAL_INFO_PREPEND;
  }

  return print_tree_details($element, $level, $info_prepended, $current_nr,
                               $fname_encoding, $use_filename);
}

# extra elements out of tree.  Corresponds to C AI_KEYS_LIST element_oot
my @extra_out_of_tree = ('def_index_element', 'def_index_ref_element');

# keep in sync with elt_info_names in C/main/tree.c
my @elt_info_names = ('spaces_before_argument', 'spaces_after_cmd_before_arg',
                      'spaces_after_argument', 'comment_at_end');

my %out_of_tree_element_name;
foreach my $name (@extra_out_of_tree, @elt_info_names) {
  $out_of_tree_element_name{$name} = 1;
}

# from Texinfo::Structuring
my @node_directions_names = ('next', 'prev', 'up');

# not called for now, see _print_element_associated_info
sub element_number_or_error($) {
  my $element = shift;

  if (ref($element) eq ''
      or (ref($element) ne 'HASH'
          and ref($element) ne 'Texinfo::TreeElement')) {
    cluck("element_number_or_error: not an hash: $element\n");
  }

  if (exists($element->{'_number'})) {
    return "E$element->{'_number'}";
  } else {
    return "MISSING: ".Texinfo::Common::debug_print_element($element);
  }
}

sub _print_root_command($) {
  my $element = shift;

  if (!defined($element) or !exists($element->{'contents'})) {
    confess("_print_root_command: unexpected element");
  }

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

sub root_command_element_string($) {
  my $element = shift;

  my $root_command_texi = _print_root_command($element);

  if (exists($element->{'cmdname'}) and $element->{'cmdname'} ne 'node') {
    if (exists($element->{'extra'})
        and exists($element->{'extra'}->{'section_heading_number'})
        and $element->{'extra'}->{'section_heading_number'} ne '') {
      my $result = $element->{'extra'}->{'section_heading_number'};
      if (defined($root_command_texi)) {
        $result .= ' '.$root_command_texi;
      }
      return $result;
    }
  }

  return $root_command_texi;
}

sub _debug_protect_eol($) {
  my $line = shift;

  $line =~ s/\n/\\n/g;
  $line =~ s/\t/\\t/g;
  $line =~ s/\f/\\f/g;
  return $line;
}

# currently no ARRAY, and for HASH only 'node_content' 'manual_content'
# and out_of_tree_element_name, therefore no call to element_number_or_error
sub _print_element_associated_info($$$$$;$$) {
  my ($associated_info, $header, $level, $prepended, $current_nr,
      $fname_encoding, $use_filename) = @_;

  my @keys = sort(keys(%$associated_info));

  return ($current_nr, '') if (!scalar(@keys));

  my $info_prepended;
  if (defined($prepended)) {
    $info_prepended = $prepended . $ADDITIONAL_INFO_PREPEND;
  } else {
    $info_prepended = $ADDITIONAL_INFO_PREPEND;
  }

  my $result = (' ' x $level) . $info_prepended . "$header\n";

  foreach my $key (@keys) {
    my $had_eol = 0;
    my $value = $associated_info->{$key};
    my $ref = ref($value);
    $result .= (' ' x $level) . $info_prepended . "$key:";
    if ($ref eq '') {
      if (!defined(${value})) {
        $result .= ' UNDEF';
      } else {
        $result .= "{${value}}";
      }
    } elsif (($ref eq 'HASH' or $ref eq 'Texinfo::TreeElement')
              and $out_of_tree_element_name{$key}) {
      my $info_e_text;
      ($current_nr, $info_e_text)
        = _print_element_add_prepend_info($value, $level+1, $prepended,
                                          $current_nr,
                                          $fname_encoding, $use_filename);
      $result .= "\n$info_e_text";
      $had_eol = 1;
    } elsif ($ref eq 'HASH' or $ref eq 'Texinfo::TreeElement') {
      if ($extra_directions{$key}) {
        my @directions_strings;
        foreach my $d_key (@node_directions_names) {
          if (exists($value->{$d_key})) {
            my $e = $value->{$d_key};
            my $element_str = element_number_or_error($e);
            push @directions_strings, "${d_key}->$element_str";
          }
        }
        $result .= 'D['.join('|', @directions_strings).']';
      } elsif ($key eq 'node_content' or $key eq 'manual_content') {
        my $container_value
          = Texinfo::Convert::Texinfo::convert_to_texinfo($value);
        $container_value = _debug_protect_eol($container_value);
        $result .= "{$container_value}";
      } else {
        my $element_value = element_number_or_error($value);
        $result .= "[$element_value]";
      }
    } elsif ($key eq 'misc_args') {
      $result .= 'A{'.join('|', @{$value}).'}';
    } elsif ($key eq 'index_entry' or $key eq 'associated_index_entry') {
      my ($index_name, $number) = @{$value};
      $result .= "I{${index_name},${number}}";
    } elsif ($ref eq 'ARRAY') {
      my @elts_list;
      foreach my $e (@$value) {
        push @elts_list, element_number_or_error($e);
      }
      $result .= 'EC['.join('|', @elts_list).']';
    }
    if (!$had_eol) {
      $result .= "\n";
    }
  }

  #'misc_args' array of strings
  #'node_content' 'node_manual' special
  #'index_entry'} = [$index_name, $number]
  return ($current_nr, $result);
}

sub print_element_base($$$;$$) {
  my ($element, $level, $prepended, $fname_encoding, $use_filename) = @_;

  my $result = ' ' x $level;

  if (defined($prepended)) {
    $result .= $prepended;
  }

  if (exists($element->{'text'})) {
    my $text_result
      = _print_text_element($element, $level, $prepended,
                            $fname_encoding, $use_filename);
    $result .= $text_result;
    return $result;
  }

  $result .= '*';
  #$result .= "$element:".refcount($element).": ";

  if (exists($element->{'_number'})) {
    $result .= "$element->{'_number'} ";
  }

  if (exists($element->{'type'})) {
    $result .= $element->{'type'};
  }

  my $cmdname = $element->{'cmdname'};
  if (defined($cmdname)) {
    $result .= '@'.Texinfo::Common::debug_command_name($cmdname);
  }

  my $contents_nr = 0;
  if (exists($element->{'contents'})) {
    $contents_nr = scalar(@{$element->{'contents'}});
  }
  if ($contents_nr) {
    $result .= " C$contents_nr";
  }

  my $source_info = $element->{'source_info'};

  if (defined($source_info)) {
    $result .= ' '.Texinfo::Report::print_source_info_details($source_info,
                                            $fname_encoding, $use_filename);
  }

  if (defined($cmdname) and $Texinfo::Commands::root_commands{$cmdname}
      and exists($element->{'contents'})) {
    my $argument_line = $element->{'contents'}->[0];
    if (exists($argument_line->{'contents'})
        and exists($argument_line->{'contents'}->[0]->{'contents'})) {
      my $root_command_texi
        = Texinfo::Convert::Texinfo::convert_to_texinfo(
            Texinfo::TreeElement::new(
              {'contents' => $argument_line->{'contents'}->[0]->{'contents'}}));
      $result .= " {${root_command_texi}}";
    }
  }

  $result .= "\n";

  return $result;
}

sub print_element_details($$$$;$$) {
  my ($element, $level, $prepended, $current_nr, $fname_encoding,
      $use_filename) = @_;

  my $result
      = print_element_base($element, $level, $prepended,
                           $fname_encoding, $use_filename);

  if (exists($element->{'text'})) {
    my $source_marks_result;
    ($current_nr, $source_marks_result)
      = _print_source_marks($element, $level, $prepended, $current_nr,
                            $fname_encoding, $use_filename);

    $result .= $source_marks_result;
    return ($current_nr, $result);
  }

  if (exists($element->{'info'})) {
    my $info = $element->{'info'};
    my $result_info;
    foreach my $info_oot (@elt_info_names) {
      if (exists($info->{$info_oot})) {
        $current_nr = set_element_tree_numbers($info->{$info_oot},
                                               $current_nr);
      }
    }
    ($current_nr, $result_info)
      = _print_element_associated_info($info, 'INFO', $level,
                                       $prepended, $current_nr,
                                       $fname_encoding, $use_filename);
    $result .= $result_info;
  }

  if (exists($element->{'extra'})) {
    my $result_info;
    my $extra = $element->{'extra'};

    foreach my $extra_oot (@extra_out_of_tree) {
      if (exists($extra->{$extra_oot})) {
        $current_nr = set_element_tree_numbers($extra->{$extra_oot},
                                               $current_nr);
      }
    }

    ($current_nr, $result_info)
      = _print_element_associated_info($extra, "EXTRA", $level,
                                       $prepended, $current_nr,
                                       $fname_encoding, $use_filename);
    $result .= $result_info;
  }

  my $source_marks_result;
  ($current_nr, $source_marks_result)
    = _print_source_marks($element, $level, $prepended, $current_nr,
                          $fname_encoding, $use_filename);
  $result .= $source_marks_result;

  return ($current_nr, $result);
}

# only used for debugging
sub element_print_details($;$$) {
  my ($element, $fname_encoding, $use_filename) = @_;

  return print_element_details($element, 0, 0, 0, $fname_encoding,
                               $use_filename);
}

sub print_tree_details($$$$;$$) {
  my ($element, $level, $prepended, $current_nr, $fname_encoding,
      $use_filename) = @_;

  my $result;
  ($current_nr, $result) = print_element_details($element, $level, $prepended,
                                  $current_nr, $fname_encoding, $use_filename);

  if (exists($element->{'contents'})) {
    foreach my $content (@{$element->{'contents'}}) {
      my $content_result;
      ($current_nr, $content_result)
        = print_tree_details($content, $level+1, $prepended,
                                $current_nr, $fname_encoding, $use_filename);
      $result .= $content_result;
    }
  }
  return ($current_nr, $result);
}

sub remove_element_tree_numbers($);

sub remove_element_tree_numbers($) {
  my $element = shift;

  if (exists($element->{'text'})) {
    return;
  }

  delete $element->{'_number'};

  if (exists($element->{'extra'})) {
    foreach my $extra_oot (@extra_out_of_tree) {
      if (exists($element->{'extra'}->{$extra_oot})) {
        remove_element_tree_numbers($element->{'extra'}->{$extra_oot});
      }
    }
  }

  if (exists($element->{'contents'})) {
    foreach my $content (@{$element->{'contents'}}) {
      remove_element_tree_numbers($content);
    }
  }
}

# no reference to other elements in extra information currently
# (no extra element, content, direction), therefore no need for
# element numbers to refer to.
# The calls to set_element_tree_numbers and remove_element_tree_numbers
# are thus commented out.
sub tree_print_details($;$$) {
  my ($tree, $fname_encoding, $use_filename) = @_;

  my $result;

  my $current_nr = 0;
  #$current_nr = set_element_tree_numbers($tree, 0);

  ($current_nr, $result) = print_tree_details($tree, 0, undef, $current_nr,
                                             $fname_encoding, $use_filename);

  #remove_element_tree_numbers($tree);

  return $result;
}



# Texinfo tree transformations used in main output formats conversion.

# NOTE for now, if there is a need to recurse, for instance in elements_oot
# extra information or in modified elements, it should be done in
# &OPERATION.  If it becomes common, it could be done in modify_tree instead.
sub modify_tree($$;$);
sub modify_tree($$;$) {
  my ($tree, $operation, $argument) = @_;

  #print STDERR "modify_tree tree: $tree\n";

  if (!defined($tree)
      or (ref($tree) ne 'HASH' and ref($tree) ne 'Texinfo::TreeElement')) {
      #or (ref($tree) ne 'Texinfo::TreeElement')) {
    cluck "tree ".(!defined($tree) ? 'UNDEF' : "not a hash: $tree");
    return undef;
  }

  if (exists($tree->{'contents'})) {
    my $contents_nr = scalar(@{$tree->{'contents'}});
    for (my $i = 0; $i < $contents_nr; $i++) {
      my $new_contents = &$operation('content',
                                     $tree->{'contents'}->[$i], $argument);
      if ($new_contents) {
        # replace by new content
        splice(@{$tree->{'contents'}}, $i, 1, @$new_contents);
        $i += scalar(@$new_contents) -1;
        $contents_nr += scalar(@$new_contents) -1;
      } else {
        modify_tree($tree->{'contents'}->[$i], $operation, $argument);
      }
    }
  }
  # This is probably unneeded, the call on each element of the
  # tree just above allows to modify source marks already.
  #if ($tree->{'source_marks'}) {
  #  my @source_marks = @{$tree->{'source_marks'}};
  #  for (my $i = 0; $i <= $#source_marks; $i++) {
  #    if ($source_marks[$i]->{'element'}) {
  #      # Return a reference array for consistency with call for contents
  #      my $new_element
  #        = &$operation('source_mark', $source_marks[$i]->{'element'},
  #                      $argument);
  #      if ($new_element) {
  #        $source_marks[$i]->{'element'} = $new_element->[0];
  #      }
  #    }
  #  }
  #}
  return $tree;
}

sub _protect_comma($$) {
  my $type = shift;
  my $current = shift;

  return _protect_text($current, quotemeta(','));
}

sub protect_comma_in_tree($) {
  my $tree = shift;

  return modify_tree($tree, \&_protect_comma);
}

# Has an XS override. Defined to be able to test Perl and XS. Undocumented
# on purpose.
sub protect_comma_in_document($) {
  my $document = shift;

  protect_comma_in_tree($document->tree());
  return;
}

sub _new_asis_command_with_text($$;$) {
  my ($text, $parent, $text_type) = @_;

  my $new_command = Texinfo::TreeElement::new({'cmdname' => 'asis'});

  if (defined($parent)) {
    $new_command->{'parent'} = $parent;
  }

  push @{$new_command->{'contents'}},
        Texinfo::TreeElement::new({'type' => 'brace_container',
                                   'parent' => $new_command});
  push @{$new_command->{'contents'}->[0]->{'contents'}},
    Texinfo::TreeElement::new({'text' => $text,});
  if (defined($text_type)) {
    $new_command->{'contents'}->[0]->{'contents'}->[0]->{'type'} = $text_type;
  }
  return $new_command;
}

sub _protect_text($$) {
  my ($current, $to_protect) = @_;

  #print STDERR "_protect_text: $to_protect: $current "
  #                         .debug_print_element($current, 1)."\n";
  if (exists($current->{'text'}) and $current->{'text'} =~ /$to_protect/
      and !(exists($current->{'type'})
            and ($current->{'type'} eq 'raw'
                 or $current->{'type'} eq 'rawline_text'))) {
    my @result = ();
    my $remaining_text = $current->{'text'};

    my $current_position = 0;
    while ($remaining_text) {
      if ($remaining_text =~ s/^(.*?)(($to_protect)+)//) {
        # Note that it includes for completeness the case of $1 eq ''
        # although it is unclear that source marks may happen in that case
        # as they are rather associated to the previous element.
        my $e = Texinfo::TreeElement::new({'text' => $1,});
        $e->{'type'} = $current->{'type'} if (exists($current->{'type'}));
        $current_position = Texinfo::Common::relocate_source_marks(
                                        $current->{'source_marks'}, $e,
                                        $current_position, length($1));
        if ($e->{'text'} ne '' or exists($e->{'source_marks'})) {
          push @result, $e;
        }
        if ($to_protect eq quotemeta(',')) {
          for (my $i = 0; $i < length($2); $i++) {
            my $e = Texinfo::TreeElement::new({'cmdname' => 'comma'});
            my $brace_container
              = Texinfo::TreeElement::new({'type' => 'brace_container',
                                           'parent' => $e});
            $e->{'contents'} = [$brace_container];
            $current_position = Texinfo::Common::relocate_source_marks(
                                          $current->{'source_marks'}, $e,
                                          $current_position, 1);
            push @result, $e;
          }
        } else {
          my $new_asis = _new_asis_command_with_text($2, undef,
                                                    $current->{'type'});
          my $e = $new_asis->{'contents'}->[0]->{'contents'}->[0];
          $current_position = Texinfo::Common::relocate_source_marks(
                                          $current->{'source_marks'}, $e,
                                          $current_position, length($2));
          push @result, $new_asis;
        }
      } else {
        my $e = Texinfo::TreeElement::new({'text' => $remaining_text,});
        $e->{'type'} = $current->{'type'} if (exists($current->{'type'}));
        $current_position = Texinfo::Common::relocate_source_marks(
                                      $current->{'source_marks'}, $e,
                                      $current_position, length($remaining_text));
        push @result, $e;
        last;
      }
    }
    $current = undef;
    #print STDERR "_protect_text: Result: @result\n";
    return \@result;
  } else {
    #print STDERR "_protect_text: No change\n";
    return undef;
  }
}

sub _protect_colon($$) {
  my ($type, $current) = @_;

  return _protect_text($current, quotemeta(':'));
}

sub protect_colon_in_tree($) {
  my $tree = shift;

  return modify_tree($tree, \&_protect_colon);
}

# Has an XS override. Defined to be able to test Perl and XS. Undocumented
# on purpose.
sub protect_colon_in_document($) {
  my $document = shift;

  protect_colon_in_tree($document->tree());
  return;
}

sub _protect_node_after_label($$) {
  my ($type, $current) = @_;

  return _protect_text($current, '['. quotemeta(".\t,") .']');
}

sub protect_node_after_label_in_tree($) {
  my $tree = shift;

  return modify_tree($tree, \&_protect_node_after_label);
}

# Has an XS override. Defined to be able to test Perl and XS. Undocumented
# on purpose.
sub protect_node_after_label_in_document($) {
  my $document = shift;

  protect_node_after_label_in_tree($document->tree());
  return;
}

sub protect_first_parenthesis($) {
  my $element = shift;

  confess("BUG: protect_first_parenthesis element undef")
    if (!defined($element));
  confess("BUG: protect_first_parenthesis not a hash")
    if (ref($element) ne 'HASH' and ref($element) ne 'Texinfo::TreeElement');
  #print STDERR "protect_first_parenthesis: $element->{'contents'}\n";

  return if (!exists($element->{'contents'}));

  my $current_position = 0;
  my $nr_contents = scalar(@{$element->{'contents'}});
  for (my $i = 0; $i < $nr_contents; $i++) {
    my $content = $element->{'contents'}->[$i];
    return if (!exists($content->{'text'}));
    if ($content->{'text'} eq '') {
      next;
    }
    if ($content->{'text'} =~ /^\(/) {
      my $current_position = 0;
      my $new_asis = _new_asis_command_with_text('(', $element,
                                                 $content->{'type'});
      my $e = $new_asis->{'contents'}->[0]->{'contents'}->[0];
      $current_position = Texinfo::Common::relocate_source_marks(
                                       $content->{'source_marks'}, $e,
                                       $current_position, length('('));

      if ($content->{'text'} !~ /^\($/) {
        $content->{'text'} =~ s/^\(//;
        if (exists($content->{'source_marks'})) {
          if (scalar(@{$content->{'source_marks'}})) {
            foreach my $source_mark (@{$content->{'source_marks'}}) {
              $source_mark->{'position'} -= length('(');
            }
          } else {
            delete $content->{'source_marks'};
          }
        }
      } else {
        # remove the $content element, everything is in the @asis text now.
        splice (@{$element->{'contents'}}, $i, 1);
        $content = undef;
      }
      splice (@{$element->{'contents'}}, $i, 0, $new_asis);
    }
    return;
  }
}

sub move_index_entries_after_items($) {
  # enumerate or itemize
  my $current = shift;

  return unless (exists($current->{'contents'}));

  my $previous;
  foreach my $item (@{$current->{'contents'}}) {
    #print STDERR "Before proceeding: $previous $item->{'cmdname'} (@{$previous->{'contents'}})\n" if ($previous and $previous->{'contents'});
    if (defined($previous) and exists($item->{'cmdname'})
        and $item->{'cmdname'} eq 'item'
        and exists($previous->{'contents'})) {

      my $previous_ending_container;
      if (exists($previous->{'contents'}->[-1]->{'type'})
          and ($previous->{'contents'}->[-1]->{'type'} eq 'paragraph'
               or $previous->{'contents'}->[-1]->{'type'} eq 'preformatted')) {
        # for preformatted, happens if in @itemize/enumerate in @example
        # or similar.
        # for paragraph happens if there is a paragraph at the end
        # of the previous item, and it could be possible for this
        # paragraph to end with an inline index command.
        # TODO check that there are all the cases in tests, with
        # paragraph or preformatted, and with an idex entry+comment
        # to gather or not.
        $previous_ending_container = $previous->{'contents'}->[-1];
      } else {
        # possible index commands out of paragraph
        $previous_ending_container = $previous;
      }

      my $contents_nr = scalar(@{$previous_ending_container->{'contents'}});

      # find the last index entry, with possibly comments after
      my $last_entry_idx = -1;
      for (my $i = $contents_nr -1; $i >= 0; $i--) {
        my $content = $previous_ending_container->{'contents'}->[$i];
        if (exists($content->{'type'})
            and $content->{'type'} eq 'index_entry_command') {
          $last_entry_idx = $i;
        } elsif (not (exists($content->{'cmdname'})
                      and ($content->{'cmdname'} eq 'c'
                           or $content->{'cmdname'} eq 'comment'
                     # subentry is not within the index entry in the tree
                           or $content->{'cmdname'} eq 'subentry'))) {
          last;
        }
      }

      if ($last_entry_idx >= 0) {
        my $item_container;
        if (exists($item->{'contents'})
            and exists($item->{'contents'}->[0]->{'type'})
            and $item->{'contents'}->[0]->{'type'} eq 'preformatted') {
          $item_container = $item->{'contents'}->[0];
        } else {
          $item_container = $item;
        }

        for (my $i = $last_entry_idx; $i < $contents_nr; $i++) {
          # can only be index_entry_command or comment as gathered just above
          my $content = $previous_ending_container->{'contents'}->[$i];
          $content->{'parent'} = $item_container;
        }

        my $insertion_idx = 0;
        if (exists($item_container->{'contents'})
            and exists($item_container->{'contents'}->[0]->{'type'})
            and $item_container->{'contents'}->[0]->{'type'}
                                eq 'ignorable_spaces_after_command') {
          # insert after leading spaces, and add an end of line if there
          # is none
          $insertion_idx = 1;
          $item_container->{'contents'}->[0]->{'text'} .= "\n"
            if ($item_container->{'contents'}->[0]->{'text'} !~ /\n$/);
        }
        # first part of the splice is the insertion in $item_container
        splice (@{$item_container->{'contents'}},
                $insertion_idx, 0,
                    # this splice removes from the previous container starting
                    # at $last_entry_idx and returns the contents to be inserted
                    splice (@{$previous_ending_container->{'contents'}},
                            $last_entry_idx, $contents_nr - $last_entry_idx));
        delete $previous_ending_container->{'contents'}
          if (!scalar(@{$previous_ending_container->{'contents'}}));
      }
    }
    $previous = $item;
  }
}

sub _move_index_entries_after_items($$) {
  my ($type, $current) = @_;

  if (exists($current->{'cmdname'})
      and ($current->{'cmdname'} eq 'enumerate'
           or $current->{'cmdname'} eq 'itemize')) {
    move_index_entries_after_items($current);
  }
  return undef;
}

# Not documented, should not be generally useful, this is a transformation
# that makes more sense for a whole document.
sub move_index_entries_after_items_in_tree($) {
  my $tree = shift;

  modify_tree($tree, \&_move_index_entries_after_items);
}

# For @itemize/@enumerate
sub move_index_entries_after_items_in_document($) {
  my $document = shift;

  move_index_entries_after_items_in_tree($document->tree());
}

sub _relate_index_entries_to_table_items_in($$) {
  my ($table, $indices_information) = @_;

  return unless(exists($table->{'contents'}));

  foreach my $table_entry (@{$table->{'contents'}}) {
    next unless(exists($table_entry->{'contents'})
                and exists($table_entry->{'type'})
                and $table_entry->{'type'} eq 'table_entry');

    my $term = $table_entry->{'contents'}->[0];
    my $definition;
    my $item;

    # Move any index entries from the start of a 'table_definition' to
    # the 'table_term'.
    if (defined($table_entry->{'contents'}->[1])
        and exists($table_entry->{'contents'}->[1]->{'type'})
        and $table_entry->{'contents'}->[1]->{'type'} eq 'table_definition') {
      $definition = $table_entry->{'contents'}->[1];
      my $nr_index_entry_command = 0;
      foreach my $child (@{$definition->{'contents'}}) {
        if (exists($child->{'type'})
            and $child->{'type'} eq 'index_entry_command') {
          $child->{'parent'} = $term;
          $nr_index_entry_command++;
        } else {
          last;
        }
      }
      if ($nr_index_entry_command > 0) {
        unshift @{$term->{'contents'}},
          splice (@{$definition->{'contents'}}, 0, $nr_index_entry_command);
      }
    }

    if (exists($term->{'type'}) and $term->{'type'} eq 'table_term') {
      # Relate the first index_entry_command in the 'table_term' to
      # the term itself.

      my $index_entry;
      my $index_element;
      foreach my $content (@{$term->{'contents'}}) {
        if (exists($content->{'type'})
            and $content->{'type'} eq 'index_entry_command') {
          if (!$index_entry) {
            my $index_info;
            $index_element = $content;
            ($index_entry, $index_info)
              = Texinfo::Common::lookup_index_entry(
                              $content->{'extra'}->{'index_entry'},
                              $indices_information);
          }
        } elsif (exists($content->{'cmdname'})
                 and $content->{'cmdname'} eq 'item') {
          $item = $content unless $item;
        }
        if ($item and $index_entry) {
          # This is better than overwriting 'entry_element', which
          # holds important information.
          $index_entry->{'entry_associated_element'} = $item;
          # also add a reference from element to index entry in index
          $item->{'extra'} = {} if (!exists($item->{'extra'}));
          $item->{'extra'}->{'associated_index_entry'}
             = [@{$index_element->{'extra'}->{'index_entry'}}];
          last;
        }
      }
    }
  }
}

# Locate all @tables in the tree, and relate index entries to
# the @item that immediately follows or precedes them.
sub _relate_index_entries_to_table_items($$$) {
  my ($type, $current, $indices_information) = @_;

  if (exists($current->{'cmdname'}) and $current->{'cmdname'} eq 'table') {
    _relate_index_entries_to_table_items_in($current, $indices_information);
  }
  return undef;
}

sub relate_index_entries_to_table_items_in_document($) {
  my $document = shift;

  my $tree = $document->tree();
  my $indices_information = $document->indices_information();

  modify_tree($tree, \&_relate_index_entries_to_table_items,
              $indices_information);
}



# Methods used to get information on menu entries and nodes.  Used in
# structuring and transformation codes, here because this module is
# used by all the structuring and transformation modules.
# Not documented in POD because they are considered to be internal functions.

# return $NORMALIZED_ENTRY_NODE, the identifier corresponding to
# the internal node referred to by menu entry $ENTRY
sub normalized_menu_entry_internal_node($) {
  my $entry = shift;

  foreach my $content (@{$entry->{'contents'}}) {
    if ($content->{'type'} eq 'menu_entry_node') {
      if (exists($content->{'extra'})) {
        if (! $content->{'extra'}->{'manual_content'}) {
          return $content->{'extra'}->{'normalized'};
        }
      }
      return undef;
    }
  }
  return undef;
}

# Return $NODE where $NODE is the node referred to by menu entry $ENTRY.
sub normalized_entry_associated_internal_node($$) {
  my ($entry, $identifier_target) = @_;

  my $normalized_entry_node = normalized_menu_entry_internal_node($entry);

  if (defined($normalized_entry_node)) {
    return $identifier_target->{$normalized_entry_node};
  }
  return undef;
}

# In $NODE, find the first menu entry in the first menu.  If the node
# in the menu refers to a target element in the document, return that
# element.  Otherwise, return the 'menu_entry_node' element.
sub first_menu_node($$) {
  my ($node_relations, $identifier_target) = @_;

  if (exists($node_relations->{'menus'})) {
    foreach my $menu (@{$node_relations->{'menus'}}) {
      foreach my $menu_content (@{$menu->{'contents'}}) {
        if (exists($menu_content->{'type'})
            and $menu_content->{'type'} eq 'menu_entry') {
          my $menu_node
            = normalized_entry_associated_internal_node($menu_content,
                                                        $identifier_target);
          # an internal node
          return $menu_node if ($menu_node);
          foreach my $content (@{$menu_content->{'contents'}}) {
            if ($content->{'type'} eq 'menu_entry_node') {
              # a reference to an external manual
              if (exists($content->{'extra'})
                  and $content->{'extra'}->{'manual_content'}) {
                return $content
              }
              last;
            }
          }
        }
      }
    }
  }
  return undef;
}



# Print listoffloats information for tests

# ALTIMP tta/C/main/floats.c
# no equivalent in Perl, so in this module.

sub _print_caption_shortcaption($$$$$) {
  my ($element, $float, $caption_type, $type, $float_number) = @_;

  my $caption_texi = "";
  if (exists($element->{'contents'})) {
    $caption_texi = Texinfo::Convert::Texinfo::convert_to_texinfo(
                                                $element->{'contents'}->[0]);
  }

  my $caption_float;
  if (!exists($element->{'parent'}) or $element->{'parent'} ne $float) {
    $float_number = 'UNDEF' unless(defined($float_number));
    print STDERR "BUG: \@".${element}->{'cmdname'}." $type; $float_number: "
       . "caption_float != float_e: $caption_texi\n";
  }

  my $result;
  # important to have the -1 last argument to keep the traling new lines
  my @caption_lines = split /\n/, $caption_texi, -1;
  my $lines_nr = scalar(@caption_lines);
  if ($lines_nr > 0) {
    $result = "  ${caption_type}: ";
    my $first_line = shift @caption_lines;
    $result .= $first_line ."\n";
    if ($lines_nr > 1) {
      # remove empty string after the last end of line
      pop(@caption_lines) if ($caption_lines[-1] eq '');
      foreach my $line (@caption_lines) {
        $result .= "   $line\n";
      }
    }
  } else {
    $result = "  ${caption_type}(E)\n";
  }
  return $result;
}

sub print_listoffloats_types($) {
  my $listoffloats_list = shift;

  return undef if (scalar(keys(%$listoffloats_list)) == 0);

  my $result = '';
  foreach my $type (sort(keys(%$listoffloats_list))) {
    my $listoffloats = $listoffloats_list->{$type};
    $result .= "$type: ".scalar(@$listoffloats)."\n";
    foreach my $float_and_section (@$listoffloats) {
      my ($float, $float_section) = @$float_and_section;
      if (!$float->{'extra'}) {
         print STDERR "BUG: $type: float without extra: $float\n";
         next;
      }
      my $float_type = $float->{'extra'}->{'float_type'};
      my $float_normalized = $float->{'extra'}->{'normalized'};
      my $float_number = $float->{'extra'}->{'float_number'};
      if (!defined($float_type) or $float_type ne $type) {
        $float_normalized = 'UNDEF' unless(defined($float_normalized));
        $float_number = 'UNDEF' unless(defined($float_number));
        $float_type = 'UNDEF' unless(defined($float_type));
        print STDERR "BUG: $type: listoffloats != float type "
            ."'$float_type' ($float_normalized;$float_number)\n";
        next;
      }
      my ($caption, $shortcaption)
        = Texinfo::Common::find_float_caption_shortcaption($float);

      $result .= ' F';
      $result .= "${float_number}:" if (defined($float_number));
      $result .= " {${float_normalized}}" if (defined($float_normalized));
      $result .= "\n";
      if ($shortcaption) {
        my $shortcaption_text
          = _print_caption_shortcaption ($shortcaption, $float, "S",
                                         $type, $float_number);
        $result .= $shortcaption_text;
      }
      if ($caption) {
        my $caption_text
          = _print_caption_shortcaption ($caption, $float, "C",
                                         $type, $float_number);
        $result .= $caption_text;
      }
    }
  }
  return $result;
}

1;

__END__

=head1 NAME

Texinfo::ManipulateTree - Texinfo modules common tree manipulation functions

=head1 SYNOPSIS

  use Texinfo::ManipulateTree;

=head1 NOTES

The Texinfo Perl module main purpose is to be used in C<texi2any> to convert
Texinfo to other formats.  There is no promise of API stability.

=head1 DESCRIPTION

C<Texinfo::ManipulateTree> contains methods for copying and modifying the
Texinfo tree used for default conversion to output formats.

For optional tree transformation, see L<Texinfo::Transformations>.

=head1 METHODS

The Texinfo tree and Texinfo tree elements used in argument of some functions
are documented in L<Texinfo::Parser/TEXINFO TREE>.  When customization
information is needed, an object that defines C<get_conf> is
expected, normally a L<Texinfo::Document/Getting customization
options values registered in document> object.

=over

=item move_index_entries_after_items_in_document($document)
X<C<move_index_entries_after_items_in_document>>

In C<@enumerate> and C<@itemize> from the I<$document> tree, move index
entries appearing just before C<@item> after the C<@item>.  Comment lines
between index entries are moved too.

=item protect_colon_in_tree($tree)

=item protect_node_after_label_in_tree($tree)
X<C<protect_colon_in_tree>>
X<C<protect_node_after_label_in_tree>>

Protect colon with C<protect_colon_in_tree> and characters that
are special in node names after a label in menu entries (tab
dot and comma) with C<protect_node_after_label_in_tree>.
The protection is achieved by putting protected characters
in C<@asis{}>.

=item protect_comma_in_tree($tree)
X<C<protect_comma_in_tree>>

Protect comma characters, replacing C<,> with @comma{} in tree.

=item protect_first_parenthesis($element)
X<C<protect_first_parenthesis>>

Modify I<$element> contents by protecting the first parenthesis.
If I<$element> is undef a fatal error with a backtrace will be emitted.

=item relate_index_entries_to_table_items_in_document($document)
X<C<relate_index_entries_to_table_items_in_document>>

In tables, relate index entries preceding and following an
entry with said item.  Reference one of them in the entry's
C<entry_associated_element>.

=back

=head1 SEE ALSO

L<Texinfo::Document>, L<Texinfo::Structuring>, L<Texinfo::Transformations>.

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
