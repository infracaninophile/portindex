# Copyright (c) 2004 Matthew Seaman. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#    1.  Redistributions of source code must retain the above
#        copyright notice, this list of conditions and the following
#        disclaimer.
#
#    2.  Redistributions in binary form must reproduce the above
#        copyright notice, this list of conditions and the following
#        disclaimer in the documentation and/or other materials
#        provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS''
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
# TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
# PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF
# USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
# OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

#
# @(#) $Id: Port.pm,v 1.3 2004-10-01 19:11:37 matthew Exp $
#

#
# An object for holding various data used in creating a port -- mostly
# this is used for generating the ports INDEX.
#
package FreeBSD::Port;
$VERSION = 0.01;    # Extremely alpha.

use strict;
use warnings;
use Carp;

our ($base);

$base = '/usr/ports';

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %self   = @_;

    return bless \%self, $class;
}

# Take the string returned by 'make describe' or read as one line out
# of INDEX and use it to populate a pkg object
sub new_from_description($$)
{
	my $caller = shift;
	my $class  = ref($caller) || $caller;
    my $index  = shift;
    my $desc   = shift;

    my $pkg;
    my $pkgname;
    my $origin;
    my $installdir;
    my $comment;
    my $pkg_descr;
    my $maintainer;
    my $categories;
    my $b_deps;
    my $r_deps;
    my $www;
    my $e_deps;
    my $p_deps;
    my $f_deps;

    # Take a list of pkgnames (separated by spaces), and convert it into a
    # list of hash references to entries in the temporary %index hash --
    # creating empty entries as required.
    sub _get_index_links($)
    {
        my $list   = shift;
        my @return = ();
    
        foreach my $entry ( split( / /, $list ) ) {
    
            # Create only if doesn't already exist...
            $index->{$entry} = FreeBSD::Port->new()
              unless defined( $index->{$entry} );
    
            push @return, $index->{$entry};
        }
        return \@return;
    }
    
    chomp($desc);
    (
        $pkgname,    $origin,     $installdir, $comment, $pkg_descr,
        $maintainer, $categories, $b_deps,     $r_deps,  $www,
        $e_deps,     $p_deps,     $f_deps,
      )
      = split '\|', $desc;

    # Strip the common prefix from the port origins and pkg_descr
    # items

    $origin    =~ s,^$::base/,,o;
    $pkg_descr =~ s,^$::base/,,o;

    # Create the reference only if it doesn't already exist.  This
    # may be present, but empty if port has already been seen as a
    # *_dep of another port.

    $index->{$pkgname} = $caller->new()
      unless defined( $index->{$pkgname} );
    $pkg = $index->{$pkgname};

    $pkg->PKGNAME($pkgname);
    $pkg->ORIGIN( [ split( '/', $origin ) ] );
    $pkg->INSTALLDIR($installdir);
    $pkg->COMMENT($comment);
    $pkg->PKG_DESCR($pkg_descr);
    $pkg->MAINTAINER($maintainer);
    $pkg->CATEGORIES($categories);
    $pkg->B_DEPS( _get_index_links( $b_deps ) );
    $pkg->R_DEPS( _get_index_links( $r_deps ) );
    $pkg->WWW($www);
    $pkg->E_DEPS( _get_index_links( $e_deps ) );
    $pkg->P_DEPS( _get_index_links( $p_deps ) );
    $pkg->F_DEPS( _get_index_links( $f_deps ) );

    return $pkg;
}

# Bulk creation of accessor methods.
for my $slot (
    qw(PKGNAME ORIGIN PREFIX COMMENT DESCR MAINTAINER
    CATEGORIES E_DEPS P_DEPS F_DEPS B_DEPS F_DEPS
    E_UPD P_UPD F_UPD B_UPD F_UPD )
  )
{
    no strict qw(refs);

    *$slot = sub {
        my $self = shift;

        $self->{$slot} = shift if @_;
        return $self->{$slot};
    };
}

# Print out one line of the INDEX file
sub print ($)
{
    my $self = shift;

    print $self->PKGNAME(), '|';
    print "$base/", join( '/', @{ $self->ORIGIN() } ), '|';
    print $self->PREFIX(),  '|';
    print $self->COMMENT(), '|';
    print "$base/", $self->DESCR(), '|';
    print $self->MAINTAINER(), '|';
    print $self->CATEGORIES(), '|';
    print join( ' ', $self->_chase_links('B_DEPS') ), '|';
    print join( ' ', $self->_chase_links('R_DEPS') ), '|';
    print $self->WWW(), '|';
    print join( ' ', $self->_chase_links('E_DEPS') ), '|';
    print join( ' ', $self->_chase_links('P_DEPS') ), '|';
    print join( ' ', $self->_chase_links('F_DEPS') ), "\n";

    return $self;
}

# Turn the list of references to hashes, which are the dependencies
# (of the specified type) for this package into a list of package
# names.
sub _chase_links($$)
{
    my $self = shift;
    my $dep  = shift;

    return sort map { $_->PKGNAME() } @{ $self ->${dep}() };
}

# Create references from each package to the packages that have a
# dependency on it.  $dep is a hash key -- either B_DEPS for build
# dependencies, R_DEPS for runtime dependencies, E_DEPS for extract
# dependencies, P_DEPS for patch dependencies and F_DEPS for fetch
# dependencies. B_UPD, R_UPD, E_UPD, P_UPD and F_UPD are the keys for
# the corresponding inverse arrays.
sub invert_dependencies($$)
{
    my $self = shift;
    my $dep  = shift;

    my $inverse_dep;
    my $i;

    ( $inverse_dep = $dep ) =~ s/DEPS/UPD/;

    foreach my $dependency ( @{ $self ->${dep}() } ) {
        if ( defined $dependency ->${inverse_dep}() ) {

            # Insert the upreference into the
            # $dependency->{$inverse_dep} list so that the list
            # remains sorted by $pkgname

            $i = 0;    # Index at which to make insertion
            foreach my $dependent_pkg ( @{ $dependency ->${inverse_dep}() } ) {
                if ( $dependent_pkg->PKGNAME() eq $self->PKGNAME() ) {

                    # Already in the list
                    last;
                }
                if ( $dependent_pkg->PKGNAME() gt $self->PKGNAME() ) {

                    # Add before this entry...
                    splice( @{ $dependency ->${inverse_dep}() }, $i, 0, $self );
                    last;
                }
                $i++;
            }
        } else {

            # It's easy to order a list of one thing...
            $dependency ->${inverse_dep}( [$self] );
        }
    }
    print STDERR "Inverse $dep dependencies of ", $self->PKGNAME(), "\n"
      if $::verbose;
    return $self;
}

1;

#
# That's All Folks!
#
