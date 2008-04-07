# Copyright (c) 2004-2008 Matthew Seaman. All rights reserved.
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
# @(#) $Id: Category.pm,v 1.18 2008-04-07 20:06:38 matthew Exp $
#

#
# An object for holding the lists of SUBDIRS from the per category
# or top level Makefiles.  These are used to detect certain types
# of update to the ports tree that may otherwise be missed between
# running 'cache-init' and a subsequent 'cache-update'
#
package FreeBSD::Portindex::Category;
our $VERSION = '2.1';    # Release

use strict;
use warnings;

#
# The data held by this object are the ORIGIN -- where in the ports
# tree the Makefile being processed resides -- and SUBDIRS -- the list
# of categories or portnames extracted from that Makefile.  Also
# contains the equivalent data extracted from any Makefile.local
# additions to the tree.  MTIME is the unix time that this object was
# created or that a modified object was committed to the cache.
#
sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;

    die "$0: error instantiating Category object -- ORIGIN missing\n"
      unless defined $args{ORIGIN};

    # SUBDIRS should be an array ref, but can be empty or absent
    $args{SUBDIRS} = []
      unless ( defined $args{SUBDIRS} );
    die
      "$0: error instantiating Category object -- SUBDIRS not an array ref\n"
      unless ref $args{SUBDIRS} eq 'ARRAY';

    $self = {
        ORIGIN  => $args{ORIGIN},
        SUBDIRS => $args{SUBDIRS},
        MTIME   => defined( $args{MTIME} ) ? $args{MTIME} : time(),
    };

    return bless $self, $class;
}

#
# Create a Category object from the value of certain variables
# extracted from one of the ports category Makefiles.
#
sub new_from_make_vars ($$)
{
    my $caller = shift;
    my $args   = shift;
    my $self;

    my $origin;
    my @subdirs;

    $origin = $args->{'.CURDIR'};
    @subdirs = map { "$origin/$_" } split ' ', $args->{SUBDIR};

    $self = $caller->new( ORIGIN => $origin, SUBDIRS => \@subdirs );
    return $self;
}

#
# Accessor methods
#
for my $slot (qw(ORIGIN SUBDIRS)) {
    no strict qw(refs);

    *$slot = sub {
        my $self = shift;

        $self->{$slot} = shift if @_;
        return $self->{$slot};
    };
}

#
# MTIME can only be read or set to the current time. Any method
# argument that evaluates to true will cause the value to be updated.
#
sub MTIME ($$)
{
    my $self = shift;
    $self->{MTIME} = time() if ( @_ && $_[0] );
    return $self->{MTIME};
}

#
# Compare this Category object with that one: return true if
# they are equal, false if not.  Equal means exactly the
# same entries in the SUBDIRS list, but not necessarily in
# the same order.
#
sub compare($$)
{
    my $self  = shift;
    my $other = shift;
    my %seen;

    # Eliminate the easy cases
    return 0
      unless $self->ORIGIN() eq $other->ORIGIN();
    return 0
      unless @{ $self->SUBDIRS() } == @{ $other->SUBDIRS() };

    # The SUBDIRS list should not contain any repeated entries, but
    # that isn't enforced so deal reasonably with repeated elements.

    map { $seen{$_}++ } @{ $self->SUBDIRS() };
    map { $seen{$_}-- } @{ $other->SUBDIRS() };

    for my $k ( keys %seen ) {
        return 0
          unless $seen{$k} == 0;
    }
    return 1;    # They are the same...
}

#
# Sort the SUBDIRS entries from two Category objects into three
# classes: those present only in the first, those present in both
# and those present only in the second.  Similar to the comm(1)
# program.  Return the results as a reference to a 3xN array
#
sub comm($$)
{
    my $self   = shift;
    my $other  = shift;
    my $result = [ [], [], [] ];
    my %comm;

    if ( defined $other && $other->can("SUBDIRS") ) {
        for my $sd ( @{ $self->SUBDIRS() } ) {
            $comm{$sd}++;
        }
        for my $sd ( @{ $other->SUBDIRS() } ) {
            $comm{$sd}--;
        }
        for my $sd ( sort keys %comm ) {

            # The SUBDIRS list should not contain any repeated
            # entries, but that isn't enforced so deal reasonably with
            # repeated elements.
            if ( $comm{$sd} >= 1 ) {
                push @{ $result->[0] }, $sd;
            } elsif ( $comm{$sd} == 0 ) {
                push @{ $result->[1] }, $sd;
            } else {
                push @{ $result->[2] }, $sd;
            }
        }
    }
    return $result;
}

#
# Given a port origin, is it referenced in this category Makefile?
# Unless a port is listed in the SUBDIR variable in its category
# Makefile, it's disconnected from the ports and shouldn't be indexed
#
sub is_known_subdir($$)
{
    my $self   = shift;
    my $origin = shift;

    for my $sd ( @{ $self->SUBDIRS() } ) {
        return 1
          if ( $sd eq $origin );    # Found it
    }
    return 0;                       # Unknown
}

1;

#
# That's All Folks!
#
