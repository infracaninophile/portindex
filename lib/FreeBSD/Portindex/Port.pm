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
# @(#) $Id: Port.pm,v 1.6 2004-10-07 09:56:26 matthew Exp $
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

# Ports should be uniquely identified by pkgname
our (%index);

sub new ($@)
{
    my $caller = shift;
    my $class = ref($caller) || $caller;
    my $self;
    my %args = @_;

    croak __PACKAGE__, "::new() -- PKGNAME missing"
      unless defined $args{PKGNAME};

    if ( defined $index{ $args{PKGNAME} } ) {
        $self = $index{ $args{PKGNAME} };
        %{$self} = ( %{$self}, %args );
    } else {
        $self = $index{ $args{PKGNAME} } = \%args;
    }

    bless $self, $class;

    $self->{ORIGIN} = [ split '/', $self->{ORIGIN} ]
      if defined $self->{ORIGIN} && !ref $self->{ORIGIN};

    for my $dep (
        qw( EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS BUILD_DEPENDS
        RUN_DEPENDS )
      )
    {
        $self->{$dep} = [ split / /, $self->{$dep} ]
          if defined $self->{$dep} && !ref $self->{$dep};
    }
    return $self;
}

sub DESTROY ($)
{
    my $self = shift;

    delete $index{ $self->PKGNAME() };
    undef $self;
    return;
}

# Take the string returned by 'make describe' or read as one line out
# of INDEX and use it to populate a pkg object
sub new_from_indexline($$)
{
    my $caller = shift;
    my $desc   = shift;
    my $self;

    my $pkgname;
    my $origin;
    my $stuff;
    my $build_depends;
    my $run_depends;
    my $www;
    my $extract_depends;
    my $patch_depends;
    my $fetch_depends;

    chomp($desc);

    (
        $pkgname,         $origin,        $stuff,
        $build_depends,   $run_depends,   $www,
        $extract_depends, $patch_depends, $fetch_depends
      )
      = (
        $desc =~ m{
			 ^([^|]+)\|          # PKGNAME
	          ([^|]+)\|          # ORIGIN
	          ((?:[^|]*\|){4}[^|]*)\|
			                     # PREFIX,COMMENT,DESCR,MAINTAINER,CATEGORIES
	          ([^|]*)\|          # BUILD_DEPENDS
	          ([^|]*)\|          # RUN_DEPENDS
	          ([^|]*)\|          # WWW
	          ([^|]*)\|          # EXTRACT_DEPENDS
	          ([^|]*)\|          # PATCH_DEPENDS
	          ([^|]*)$           # FETCH_DEPENDS
		  }x
      )
      or croak __PACKAGE__, "::new_from_indexline():$.: -- incorrect format";

    $self = $caller->new(
        PKGNAME         => $pkgname,
        ORIGIN          => $origin,
        STUFF           => $stuff,
        EXTRACT_DEPENDS => $extract_depends,
        PATCH_DEPENDS   => $patch_depends,
        FETCH_DEPENDS   => $fetch_depends,
        BUILD_DEPENDS   => $build_depends,
        RUN_DEPENDS     => $run_depends,
        WWW             => $www,
    );

    # Chase the dependency linkages

    for my $dep (
        qw( EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS BUILD_DEPENDS
        RUN_DEPENDS )
      )
    {
        $self->_get_index_links($dep);
    }

    return $self;
}

# Take a list of pkgnames (separated by spaces) as seen in
# /usr/ports/INDEX, and convert it into a list of hash references to
# entries in the temporary %index hash -- creating empty entries as
# required.
sub _get_index_links ($$)
{
    my $self = shift;
    my $dep  = shift;

    # Don't re-process entry if it's already a ref
    @{ $self->{$dep} } =
      map { $self->new( PKGNAME => $_ ) unless ref $_; } @{ $self->{$dep} };
    return $self;
}

# This is very similar to new_from_indexline, except it uses the
# output from 'make describe'.  Format is very similar to an index
# line, except that the fields are in a different (more sendsible)
# order, and the dependencies are given using the port ORIGIN, rather
# than PKGNAME.  Only the immediate dependencies of any port are
# given, not the cumulative dependencies of the port and all of its
# dependencies, etc.  Transforming the ORIGIN lines into the usual form
# has to wait until all the port objects have been created.
sub new_from_makedescribe($$)
{
    my $caller = shift;
    my $desc   = shift;
    my $self;

    my $pkgname;
    my $origin;
    my $stuff;
    my $build_depends;
    my $run_depends;
    my $extract_depends;
    my $patch_depends;
    my $fetch_depends;
    my $www;

    chomp($desc);

    (
        $pkgname,         $origin,        $stuff,
        $extract_depends, $patch_depends, $fetch_depends,
        $build_depends,   $run_depends,   $www
      )
      = (
        $desc =~ m{
             ^([^|]+)\|          # PKGNAME
              ([^|]+)\|          # ORIGIN
              ((?:[^|]*\|){4}[^|]*)\|
                                 # PREFIX,COMMENT,DESCR,MAINTAINER,CATEGORIES
              ([^|]*)\|          # EXTRACT_DEPENDS
              ([^|]*)\|          # PATCH_DEPENDS
              ([^|]*)\|          # FETCH_DEPENDS
              ([^|]*)\|          # BUILD_DEPENDS
              ([^|]*)\|          # RUN_DEPENDS
              ([^|]*)$           # WWW
          }x
      )
      or croak __PACKAGE__, "::new_from_makedescribe: -- incorrect format";

    $self = $caller->new(
        PKGNAME         => $pkgname,
        ORIGIN          => $origin,
        STUFF           => $stuff,
        EXTRACT_DEPENDS => $extract_depends,
        PATCH_DEPENDS   => $patch_depends,
        FETCH_DEPENDS   => $fetch_depends,
        BUILD_DEPENDS   => $build_depends,
        RUN_DEPENDS     => $run_depends,
        WWW             => $www,
    );

    return $self;
}

# Take a list of port origins (separated by spaces) as seen in 'make
# describe' output, and convert it into a list of hash references to
# entries in the %tree hash-of-hashes.  Missing entries are an error:
# there should always be corresponding directories in the ports tree.
sub _get_describe_links ($$$)
{
    my $self = shift;
    my $tree = shift;
    my $dep  = shift;

    @{ $self->{$dep} } =
      map { $tree->get($_) unless ref $_; } @{ $self->{$dep} };
    return $self;
}

# Bulk creation of accessor methods.
for my $slot (
    qw(PKGNAME ORIGIN STUFF BUILD_DEPENDS RUN_DEPENDS WWW
    EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS BUILD_INVERSE
    RUN_INVERSE EXTRACT_INVERSE PATCH_INVERSE FETCH_INVERSE )
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
sub print ($$;$)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = shift;

    print $fh $self->PKGNAME(), '|';
    print $fh join( '/', @{ $self->ORIGIN() } ), '|';
    print $fh $self->STUFF(), '|';
    print $fh join( ' ', $self->_chase_links('BUILD_DEPENDS') ), '|';
    print $fh join( ' ', $self->_chase_links('RUN_DEPENDS') ),   '|';
    print $fh $self->WWW(), '|';
    print $fh join( ' ', $self->_chase_links('EXTRACT_DEPENDS') ), '|';
    print $fh join( ' ', $self->_chase_links('PATCH_DEPENDS') ),   '|';
    print $fh join( ' ', $self->_chase_links('FETCH_DEPENDS') ),   "\n";

    if ( $::verbose && defined $counter ) {
        if ( $$counter % 1000 == 0 ) {
            print STDERR "[$$counter]";
        } elsif ( $$counter % 100 == 0 ) {
            print STDERR '.';
        }
        $$counter++;
    }
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
# dependency on it.  $dep is a hash key -- one of BUILD_DEPENDS,
# RUN_DEPENDS, EXTRACT_DEPENDS, PATCH_DEPENDS, FETCH_DEPENDS -- which
# we invert to create links from the dependencies' FOO_INVERSE entry
# to $self.  Ie. FOO_INVERSE is a list of the ports which have a FOO
# dependency on this one.
sub invert_dependencies($$)
{
    my $self = shift;
    my $dep  = shift;

    my $inverse_dep;
    my $i;

    ( $inverse_dep = $dep ) =~ s/DEPENDSS/INVERSE/;

    foreach my $dependency ( @{ $self ->${dep}() } ) {
        if ( defined $dependency ->${inverse_dep}() ) {

            # Insert the upreference into the
            # $dependency->{$inverse_dep} list so that the list
            # remains sorted by $pkgname

            $i = 0;    # Index at which to make insertion
            foreach my $dependent ( @{ $dependency ->${inverse_dep}() } ) {
                if ( $dependent->PKGNAME() eq $self->PKGNAME() ) {

                    # Already in the list
                    last;
                }
                if ( $dependent->PKGNAME() gt $self->PKGNAME() ) {

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
    carp "Inverse $dep dependencies of ", $self->PKGNAME(), "\n"
      if $::verbose;
    return $self;
}

1;

#
# That's All Folks!
#
