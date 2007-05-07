# Copyright (c) 2004-2006 Matthew Seaman. All rights reserved.
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
# @(#) $Id: Category.pm,v 1.11 2007-05-07 10:04:20 matthew Exp $
#

#
# An object for holding the lists of SUBDIRS from the per category
# or top level Makefiles.  These are used to detect certain types
# of update to the ports tree that may otherwise be missed between
# running 'cache-init' and a subsequent 'cache-update'
#
package FreeBSD::Portindex::Category;
our $VERSION = '1.9';    # Release

use strict;
use warnings;
use Carp;

#
# The data held by this object are the ORIGIN -- where in the ports
# tree the Makefile being processed resides -- and SUBDIRS -- the list
# of categories or portnames extracted from that Makefile.  Also contains
# the equivalent data extracted from any Makefile.local additions to the
# tree.
#
sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;

    croak __PACKAGE__, "::new() -- ORIGIN missing\n"
      unless defined $args{ORIGIN};

    # SUBDIRS should be an array ref, but can be empty or absent
    $args{SUBDIRS} = []
      unless ( defined $args{SUBDIRS} );
    croak __PACKAGE__, "::new() -- SUBDIRS not an array ref\n"
      unless ref $args{SUBDIRS} eq 'ARRAY';

    $self = {
        ORIGIN  => $args{ORIGIN},
        SUBDIRS => $args{SUBDIRS},
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
      unless @{ $self->SUBDIRS() } == @{ $self->SUBDIRS() };

    map { $seen{$_}++ } @{ $self->SUBDIRS() };
    map { $seen{$_}++ } @{ $other->SUBDIRS() };

    for my $k ( keys %seen ) {
        return 0
          unless $seen{$k} == 2;
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
            $comm{$sd}--;
        }
        for my $sd ( @{ $other->SUBDIRS() } ) {
            $comm{$sd}++;
        }
        for my $sd ( keys %comm ) {
            push @{ $result->[ $comm{$sd} + 1 ] }, $sd;
        }
    }
    return $result;
}

1;

#
# That's All Folks!
#
