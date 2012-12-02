# Copyright (c) 2012 Matthew Seaman. All rights reserved.
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
# @(#) $Id$
#

#
# Lists of Values -- conceptually ListVals are uniqued lists used by
# many of the other objects. They can be empty.  Internally, they are
# stored as hashes, with the hash keys being the values of interest.
# This makes adding and removing elements fast, but can require
# calling sort() on access.  Use wantarray to avoid unnecessary
# sorting when methods are called in void context.
#

package FreeBSD::Portindex::ListVal;

require 5.10.1;

use strict;
use warnings;

#
# Factory methods
#

sub new ($;@)
{
    my $class = shift;
    my $self  = {};

    if (@_) {
        %{$self} = map { ( $_ => 1 ) } @_;
    }
    return bless $self, $class;
}

# Generate the list of items only in one of the argument arrays, but
# not both.
sub difference($$$)
{
    my $class = shift;
    my $left  = shift;    # Array ref
    my $right = shift;    # Array ref

    my $self = $class->new();

    $self->insert( @{$left} );

    for my $i ( @{$right} ) {
        if ( exists $self->{$i} ) {
            delete $self->{$i};
        } else {
            $self->{$i} = 1;
        }
    }
    return $self;
}

# FFR -- union, intersection factories

# is the arg present in the list? Compare elements as strings.
sub contains($$)
{
    my $self = shift;
    my $item = shift;

    return exists( $self->{$item} );
}

# How many items contained in the list?
sub length($)
{
    return scalar keys %{ +shift };
}

# Retrieve an item from the list by index.  (This is pretty pessimal,
# calling sort every time...)
sub item($$)
{
    my $self  = shift;
    my $index = shift;

    return ( sort keys %{$self} )[$index];
}

# Return list of contents in array context, array_ref otherwise.
# Results are unsorted.
sub get ($)
{
    my @vals = keys %{ +shift };

    return wantarray ? @vals : \@vals;
}

# Return list of contents in array context, array_ref
# otherwise. Results are sorted.
sub get_sorted ($)
{
    my @vals = sort keys %{ +shift };

    return wantarray ? @vals : \@vals;
}

sub set ($@)
{
    my $self = shift;

    %{$self} = map { ( $_ => 1 ) } @_;

    return $self;
}

# Merge the values from the arg list into the list.
sub insert ($@)
{
    my $self = shift;

    for my $v (@_) {
        $self->{$v} = 1;
    }
    return $self;
}

# Delete any values matching anything in the arglist
sub delete ($@)
{
    my $self = shift;

    for my $v (@_) {
        delete $self->{$v};
    }
    return $self;
}

# Serialization.  Adds trailing NULL as a marker.
sub freeze($)
{
    return join( "\000", sort keys %{ +shift } ) . "\000";
}

# Unserialization. split throws away trailing null fields.
sub thaw($$)
{
    my $class = shift;

    return $class->new( split( /\000/, +shift ) );
}

1;

#
# That's All Folks!
#
