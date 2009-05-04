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
# @(#) $Id: TreeObject.pm,v 1.1 2009-05-04 14:44:06 matthew Exp $
#

#
# Base class for Port, Category, Makefile objects that can be stored
# in the Tree.  This just abstracts the common code used for all of
# these objects, which are representations of files or directories
# involved in the FreeBSD ports.
#
package FreeBSD::Portindex::TreeObject;

require 5.8.3;

use strict;
use warnings;
use Exporter qw(import);

our $VERSION = '2.2';              # Release
our @EXPORT  = qw(_sort_unique);

#
# All TreeObjects have an ORIGIN -- the filesystem path of the
# underlying item, and the key used to look up the object from the
# Tree.  They also have a MTIME -- the last time the object was
# modified.
#
sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;

    die "$0: error instantiating $class object -- ORIGIN missing\n"
      unless defined $args{ORIGIN};

    $self = {
        ORIGIN => $args{ORIGIN},
        MTIME  => defined( $args{MTIME} ) ? $args{MTIME} : time(),
    };
    return bless $self, $class;
}

#
# Accessor methods
#
sub ORIGIN ($;$)
{
    my $self = shift;

    if (@_) {
        $self->{ORIGIN} = shift;
        $self->MTIME(1);
    }
    return $self->{ORIGIN};
}

#
# MTIME can only be read or set to the current time. Any method
# argument that evaluates to true will cause the value to be updated.
#
sub MTIME ($;$)
{
    my $self = shift;
    $self->{MTIME} = time() if ( @_ && $_[0] );
    return $self->{MTIME};
}

#
# Create a stringified version of an object -- assumed to be a blessed
# hash ref, whose values are either scalars or arrays.  The format is
# __CLASS\nobjectclass\nTAG1\n[DATA1a DATA1b DATA1c]\n...TAGn\nDATAn\n
# Where data represents an array it is transformed into a space
# separated list enclosed in [square brackets].  Implicit assumption:
# filenames do not contains any of the following characters: space \n.
#
sub freeze ($)
{
    my $self = shift;
    my $string;

    $string = "__CLASS\n" . ref($self) . "\n";

    for my $k ( keys %{$self} ) {
        if ( ref( $self->{$k} ) eq 'ARRAY' ) {

            # Array valued item
            $string .= "$k\n" . join( ' ', @{ $self->{$k} } ) . "\n";
        } else {

            # Scalar valued item
            $string .= "$k\n$self->{$k}\n";
        }
    }
    return $string;
}

#
# Take a stringified object and turn it back into a full object
#
sub thaw ($)
{
    my $caller = shift;    # Unused
    my $string = shift;
    my $class;
    my $self;

    $self = { split( /\n/, $string ) };

    if ( !defined $self->{__CLASS} ) {
        warn "$0: Error. Cannot regenerate object from stringified data\n";
        return undef;
    }

    $class = $self->{__CLASS};
    delete $self->{__CLASS};

    for my $k ( keys %{$self} ) {
        next unless $self->{$k} =~ m/ /;

        $self->{$k} = [ split( ' ', $self->{$k} ) ];
    }
    return bless $self, $class;
}

#
# Not a method call. Utility function to sort and unique the array
# referenced by the argument
#
sub _sort_unique ($)
{
    my %seen;

    return [ sort grep { !$seen{$_}++ } @{shift} ];
}

#
# Modify an array valued item so that entries are sorted and unique.
#
sub sort_unique ($$)
{
    my $self = shift;
    my $slot = shift;
    my %seen;

    if ( $self->{$slot} && ref( $self->{$slot} ) eq 'ARRAY' ) {
        $self->{$slot} = _sort_unique $self->{$slot};
    }
    return $self;
}

#
# Compare this TreeObject with that one: return true if they are
# equal, false if not.  Equal means exactly the same ORIGIN, class and
# data, but not necessarily the same MTIME.
#
sub compare($$)
{
    my $self  = shift;
    my $other = shift;

    # Eliminate the easy cases
    return 0
      unless $self->{ORIGIN} eq $other->{ORIGIN};
    return 0
      unless ref($self) eq ref($other);
    return 0
      unless @{$self} == @{$other};    # Same number of top-level items

    # Medium level: Are the same fields present?
    for my $k ( keys %{$self} ) {
        return 0
          unless exists $other->{$k};
    }

    # The hard way: need to do an in-depth comparison of the object
    # contents
    for my $k ( keys %{$self} ) {
        next
          if ( $k eq 'ORIGIN' || $k eq 'MTIME' );

        return 0
          unless ( ref( $self->{$k} ) eq ref( $other->{$k} ) );

        if ( ref( $self->{$k} ) eq 'ARRAY' ) {

            # element by element comparison.  Lists are guaranteed
            # sorted and uniqued
            for ( my $i = 0 ; $i < @{ $self->{$k} } ; $i++ ) {
                return 0
                  unless $self->{$k}->[$i] eq $other->{$k}->[$i];
            }
        } else {
            return 0
              unless $self->{$k} eq $other->{$k};
        }
    }

    return 1;    # They are the same...
}

1;

#
# That's All Folks!
#
