# Copyright (c) 2004-2009 Matthew Seaman. All rights reserved.
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
# @(#) $Id: Category.pm,v 1.22 2009-05-04 14:44:06 matthew Exp $
#

#
# An object for holding the lists of SUBDIRS from the per category
# or top level Makefiles.  These are used to detect certain types
# of update to the ports tree that may otherwise be missed between
# running 'cache-init' and a subsequent 'cache-update'
#
package FreeBSD::Portindex::Category;

use strict;
use warnings;

use FreeBSD::Portindex::TreeObject;

our $VERSION = '2.2';                                # Release
our @ISA     = ('FreeBSD::Portindex::TreeObject');

#
# In addition to ORIGIN and MTIME provided by the base class, the data
# held by this object are the list of SUBDIRS -- the list of other
# categories or portnames extracted from the Makefile.  Also contains
# the equivalent data extracted from any Makefile.local additions to
# the tree.
#
sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;

    $self = $class->SUPER::new(%args);

    # SUBDIRS should be an array ref, but can be empty or absent
    $args{SUBDIRS} = []
      unless ( defined $args{SUBDIRS} );
    die "$0: error instantiating $class object -- SUBDIRS not an array ref\n"
      unless ref $args{SUBDIRS} eq 'ARRAY';

    $self->{SUBDIRS} = $args{SUBDIRS}, $self->sort_unique('SUBDIRS');

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

    my $origin;
    my @subdirs;

    $origin = $args->{'.CURDIR'};
    @subdirs = map { "$origin/$_" } split ' ', $args->{SUBDIR};

    return $caller->new( ORIGIN => $origin, SUBDIRS => \@subdirs );
}

# Accessor methods: Only SUBDIRS to deal with
sub SUBDIRS ($;@)
{
    my $self = shift;

    if (@_) {
        $self->{SUBDIRS} = _sort_unique [@_];
        $self->MTIME(1);
    }
    return $self->{SUBDIRS};
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
        for my $sd ( @{ $self->{SUBDIRS} } ) {
            $comm{$sd}--;
        }
        for my $sd ( @{ $other->{SUBDIRS} } ) {
            $comm{$sd}++;
        }
        for my $sd ( sort keys %comm ) {
            push @{ $result->[ $comm{$sd} + 1 ] }, $sd;
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

    for my $sd ( @{ $self->{SUBDIRS} } ) {
        return 1
          if ( $sd eq $origin );    # Found it
    }
    return 0;                       # Unknown
}

1;

#
# That's All Folks!
#
