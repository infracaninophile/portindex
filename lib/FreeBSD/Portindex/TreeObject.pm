# Copyright (c) 2004-2012 Matthew Seaman. All rights reserved.
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
# Base class for Port, Category, Makefile or PkgDescr objects that are
# part of the Tree.  This just abstracts the common code used for all
# of these objects, which are representations of files or directories
# involved in the FreeBSD ports.
#
package FreeBSD::Portindex::TreeObject;

require 5.10.1;

use strict;
use warnings;
use Carp;
use Scalar::Util qw(blessed);

use FreeBSD::Portindex::ListVal;

our $VERSION = '2.8';    # Release

#
# All TreeObjects have an ORIGIN -- the key used to look up the object
# in the Tree, frequently the filesystem path of the underlying item
# or the path relative to ${PORTSDIR}.
#
# _needs_flush tracks whether the object has been modified since
# the last flush or commit to the underlying persistent (disk)
# storage.
#
# Values in the $self hash are either scalars or blessed array refs
# which are FreeBSD::Portindex::ListVal objects -- values are sorted
# and uniqued
#
sub new ($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;

    croak "$0: error instantiating $class object -- ORIGIN missing\n"
      unless defined $args{ORIGIN};

    $self = {
        ORIGIN       => $args{ORIGIN},
        _needs_flush => 1,
    };
    return bless $self, $class;
}

#
# Utility functions to mark what sort of object this is There should
# be no instances of the generic TreeObject added to the Tree: only
# subclasses.  Override these methods in the appropriate subclasses.
#
sub is_port($)     { return undef; }
sub is_category($) { return undef; }
sub is_file($)     { return undef; }
sub is_makefile($) { return undef; }

#
# Function to generate accessor methods for Scalars
#

sub scalar_accessor($$)
{
    my $class  = shift;
    my $method = shift;

    return sub ($;$) {
        my $self = shift;

        if (@_) {
            $self->{_needs_flush} = 1;
            $self->{$method} = shift;
        }
        return $self->{$method};
    };
}

#
# Function to generate accessor methods for ListVals
#

sub list_val_accessor($$)
{
    my $class  = shift;
    my $method = shift;

    return sub ($;@) {
        my $self = shift;

        if (@_) {
            $self->{_needs_flush} = 1;
            $self->{$method}->set(@_);
        }
        return $self->{$method}->get();
    };
}

#
# Does this object need to be flushed to persistent storage?
#
sub is_dirty($)
{
    return +shift->{_needs_flush};
}

#
# Set object clean after flushing.
#
sub was_flushed($)
{
    my $self = shift;

    $self->{_needs_flush} = 0;

    return $self;
}

#
# Create a stringified version of an object -- assumed to be a blessed
# hash ref, whose values are either scalars or arrays.  The format is
# TAG1\0DATA1a\0DATA1b\0DATA1c\n...TAGn\nDATAn...__CLASS\nobjectclass
# Where data represents an array it is transformed into a null
# separated list.  Implicit assumption: filenames do not contain any
# of the following characters: \0 \n.
#
sub freeze ($)
{
    my $self   = shift;
    my $string = '';

    while ( my ( $k, $v ) = each %{$self} ) {
        next
          if ( $k eq '_needs_flush' );

        if ( blessed($v) && $v->isa('FreeBSD::Portindex::ListVal') ) {
            $string .= "$k\n" . $v->freeze();    # Array valued item
        } else {
            $string .= "$k\n$v";                 # Scalar valued item
        }
        $string .= "\n";
    }
    $string .= "__CLASS\n" . ref($self);    # Make sure last value is not null

    return $string;
}

#
# Take a stringified object and turn it back into a full object
#
sub thaw ($$)
{
    my $caller = shift;                     # Unused
    my $string = shift;
    my $class;
    my $self;

    $self = { split( /\n/, $string ) };

    if ( !defined $self->{__CLASS} ) {
        carp "$0: Error. Cannot regenerate object from stringified data\n";
        return undef;
    }

    $class = delete $self->{__CLASS};

    while ( my ( $k, $v ) = each %{$self} ) {
        next unless $v =~ m/\000/;
        $self->{$k} = FreeBSD::Portindex::ListVal->thaw($v);
    }
    $self->{_needs_flush} = 0;

    return bless $self, $class;
}

#
# Compare this TreeObject with that one: return true if they are
# equal, false if not.  Equal means exactly the same ORIGIN, class and
# other data.
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
          if ( $k eq 'ORIGIN' );       # Already checked

        return 0
          unless ( ref( $self->{$k} ) eq ref( $other->{$k} ) );

        if ( blessed( $self->{$k} ) eq 'FreeBSD::Portindex::ListVal' ) {

            # Are the two lists the same length?
            return 0
              unless $self->{$k}->length() == $other->{$k}->length();

            # element by element comparison.  ListVals are uniqued, so
            # we don't need to check the converse, that all items in
            # $self->{$k} exist in $other->{$k}.
            foreach my $item ( $other->{$k}->get() ) {
                return 0
                  unless $self->{$k}->contains($item);
            }
        } else {
            return 0
              unless $self->{$k} eq $other->{$k};
        }
    }

    return 1;    # They are the same...
}

#
# Accessor methods
#
for my $slot ('ORIGIN') {
    no strict qw(refs);

    *$slot = __PACKAGE__->scalar_accessor($slot);
}

1;

#
# That's All Folks!
#
