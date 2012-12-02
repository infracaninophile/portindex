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
# Makefile objects.  Correspond to a single file.  These type of
# objects have an ORIGIN (the fully qualified path) and an MTIME (last
# modified time of the file as returned by stat(2)).
#
package FreeBSD::Portindex::Makefile;
use parent qw(FreeBSD::Portindex::FileObject);

require 5.10.1;

use strict;
use warnings;
use Carp;

use FreeBSD::Portindex::Config qw(%Config);
use FreeBSD::Portindex::ListVal;

#
# All TreeObjects have an ORIGIN -- the key used to look up the object
# in the Tree, the filesystem path of the underlying file.  In
# addition FileObjects also have an MTIME and a USED_BY list of ports
# that include them.  USED_BY is created empty.
#
# MTIME is the last modification time of the underlying file.  MTIME
# is determined automatically.  If the referenced file doesn't exist,
# then MTIME is set to zero.
#
# Makefile objects additionally have two flag values that affect their
# behaviour:
#
#  IS_ENDEMIC -- modification of this file is assumed to make no
#                difference to the generated INDEX, so don't use this
#                Makefile as a basis for updating work lists.
#
#  IS_UBIQUITOUS -- every port or category uses this Makefile.
#                   Therefore, save space by not storing an explicit
#                   USED_BY list.  Also, suggest 'cache-init' if one
#                   of these files is modified.
#
sub new ($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;

    $self = $class->SUPER::new(%args);

    $self->{IS_ENDEMIC} = 1
      if ( $Config{EndemicMakefiles}->contains( $self->ORIGIN() ) );

    $self->{IS_UBIQUITOUS} = 1
      if ( $Config{UbiquitousMakefiles}->contains( $self->ORIGIN() ) );

    return $self;
}

# Acknowledge $self is a Makefile
sub is_makefile($) { return 1; }

sub is_endemic($)
{
    my $self = shift;

    return defined( $self->{IS_ENDEMIC} );
}

sub is_ubiquitous($)
{
    my $self = shift;

    return defined( $self->{IS_UBIQUITOUS} );
}

#
# Insert a list of port ORIGINs into the USED_BY list, unless this is
# a ubiquitous or endemc Makefile.
#
sub used_by($;@)
{
    my $self = shift;

    if ( @_ && !$self->is_ubiquitous() && !$self->is_endemic() ) {
        $self->{_needs_flush} = 1;
        $self->{USED_BY}->insert(@_);
    }
    return $self;
}

#
# Remove values from the USED_BY list, unless this is a ubiquitous or
# endemic Makefile.
#
sub mark_unused_by($;@)
{
    my $self = shift;

    if ( @_ && !$self->is_ubiquitous() && !$self->is_endemic() ) {
        $self->{_needs_flush} = 1;
        $self->{USED_BY}->delete(@_);
    }
    return $self;
}

1;

#
# That's All Folks!
#
