# Copyright 2014-2026 Free Software Foundation, Inc.
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
# ALTIMP ParserNonXS.pm

package Texinfo::Parser;

use 5.006;
use strict;
use warnings;

our $VERSION = '7.3';

use Texinfo::XSLoader;

BEGIN {
  my $shared_library_name = "Parsetexi";
  if (!Texinfo::XSLoader::XS_parser_enabled()) {
    undef $shared_library_name;
  }

  my $nonXS_package = "Texinfo::ParserNonXS";
  my $loaded_package = Texinfo::XSLoader::init (
      "Texinfo::Parser",
      $nonXS_package,
      $shared_library_name,
      "XSTexinfo::Parsetexi",
      ['texinfo', 'texinfoxs'],
  );
  if (!defined($shared_library_name)
      or $loaded_package eq $nonXS_package) {
    Texinfo::XSLoader::set_XS_parser_loaded(0);
  } else {
    Texinfo::XSLoader::set_XS_parser_loaded(1);
  }
}


# NB Don't add more functions down here, because this can cause an error
# with some versions of Perl, connected with any typeglob assignments done
# above.  ("Can't call mro_method_changed_in() on anonymous symbol table").
#
# See http://perl5.git.perl.org/perl.git/commitdiff/03d9f026ae253e9e69212a3cf6f1944437e9f070?hp=ac73ea1ec401df889d312b067f78b618f7ffecc3
#
# (change to Perl interpreter on 22 Oct 2011)


1;
__END__

The POD documentation of Texinfo::Parser is in Texinfo::ParserNonXS.
