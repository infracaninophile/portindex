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
# Base class for Makefile and File (pkg-descr) objects.  Corresponds
# to a single file.  These type of objects have an ORIGIN (the fully
# qualified path) and an MTIME (last modified time of the file as
# returned by stat(2)).
#
package FreeBSD::Portindex::FileObject;

require 5.10.1;

use strict;
use warnings;
use Carp;

use FreeBSD::Portindex::ListVal;
use FreeBSD::Portindex::TreeObject;

our $VERSION = '2.8';                                # Release
our @ISA     = ('FreeBSD::Portindex::TreeObject');

#
# All FileObjects have an ORIGIN -- the key used to look up the object
# in the Tree, the filesystem path of the underlying file.  In
# addition FileObjects also have an MTIME and a USED_BY list of ports
# that include them.  USED_BY is created empty.
#
# MTIME is the last modification time of the underlying file. MTIME is
# determined automatically.  If the underlying file doesn't actually
# exist, set MTIME to zero.
#
# USED_BY tracks which ports are affected by this file -- on creation,
# it is always empty.  See the MAKEFILE_LIST and DESCR properties of
# the FreeBSD::Portindex::PortsTreeObject class, which show the
# inverse relationship: port uses file.
#
sub new ($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;

    $self = $class->SUPER::new(%args);

    $self->{MTIME} = ( stat $self->ORIGIN() )[9] || 0;
    $self->{USED_BY} = FreeBSD::Portindex::ListVal->new();

    return $self;
}

# Acknowledge $self is a file
sub is_file($) { return 1; }

# Stub methods: these properly apply to Makefiles only: for any other
# File objects just return undef (ie. neither endemic, nor ubiquitous)
sub is_endemic($)    { return undef; }
sub is_ubiquitous($) { return undef; }

#
# Did the mtime of the file change since the last update?  Returns -1
# if the file is now /older/ than it was, 0 if the same age or 1 if
# the file is newer.  Use MTIME==0 for un-stat'able files.
#
sub has_been_modified($)
{
    my $self = shift;
    my $mtime;

    $mtime = ( stat $self->ORIGIN() )[9] or $mtime = 0;

    return $mtime <=> $self->MTIME();
}

#
# Record the current mtime of the file
#
sub update_mtime($)
{
    my $self = shift;
    my $mtime;

    $mtime = ( stat $self->ORIGIN() )[9] || 0;

    $self->MTIME($mtime);

    return $self;
}

#
# Insert a list of port ORIGINs into the USED_BY list,
# and return the result.
#
sub mark_used_by($;@)
{
    my $self = shift;

    if (@_) {
        $self->{_needs_flush} = 1;
        $self->{USED_BY}->insert(@_);
    }
    return $self;
}

#
# Remove values from the USED_BY list, returning the
# result.
#
sub mark_unused_by($;@)
{
    my $self = shift;

    if (@_) {
        $self->{_needs_flush} = 1;
        $self->{USED_BY}->delete(@_);
    }
    return $self;
}

#
# Is anything still using this FileObject?  Returns 1 for 'yes', undef
# for 'no'
#
sub is_unused($)
{
    my $self = shift;

    return $self->{USED_BY}->length() == 0 ? 1 : undef;
}

#
# MTIME is the unixtime (seconds since the epoch) of the last change
# to the underlying file (ie. Makefile or PkgDescr objects.)
#
for my $slot ('MTIME') {
    no strict qw(refs);

    *$slot = __PACKAGE__->scalar_accessor($slot);
}

#
# USED_BY -- cross reference
#
for my $slot ('USED_BY') {
    no strict qw(refs);

    *$slot = __PACKAGE__->list_val_accessor($slot);
}

1;

#
# That's All Folks!
#
