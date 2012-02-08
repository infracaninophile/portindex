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

our $VERSION = '2.8';                                # Release
our @ISA     = ('FreeBSD::Portindex::TreeObject');

#
# All FileObjects have an ORIGIN -- the key used to look up the object
# in the Tree, the filesystem path of the underlying file.  In
# addition FileObjects also have an MTIME and a USED_BY list of ports
# that include them.  USED_BY is created empty.
#
# MTIME is the last modification time of the underlying file.  Unless
# set explicitly in the %args, MTIME is determined automatically.
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

    if ( defined $args{mtime} ) {
        croak "$0: error instantiating $class object -- ",
          "MTIME=$args{mtime} is bogus\n"
          unless $args{mtime} =~ m/^\d+$/;

        $self->{MTIME} = $args{mtime};
    } else {
        my $mtime = ( stat $self->ORIGIN() )[9]
          or croak "$0: error instantiating $class object -- ",
          "cannot obtain mtime for ", $self->ORIGIN(), " -- $!\n";

        $self->{MTIME} = $mtime;
    }

    $self->{USED_BY} = FreeBSD::Portindex::ListVal->new();

    return $self;
}

#
# Did the mtime of the file change since the last update?  Returns
# -1 if the file is now /older/ than it was, 0 if the same age or
# 1 if the file is newer.
#
sub has_been_modified($)
{
    my $self = shift;
    my $mtime;

    $mtime = ( stat $self->ORIGIN() )[9]
      or croak "$0: Cannot determine mtime for ", $self->ORIGIN(), " -- $!\n";

    return $mtime <=> $self->mtime();
}

#
# Insert a list of port ORIGINs into the USED_BY list,
# and return the result.
#
sub used_by($;@)
{
    my $self = shift;

    if (@_) {
        $self->{_needs_to_flush_cache} = 1;
    }
    return $self->{USED_BY}->insert(@_);
}

#
# Remove values from the USED_BY list, returning the
# result.
#
sub unused_by($;@)
{
    my $self = shift;

    if (@_) {
        $self->{_needs_to_flush_cache} = 1;
    }
    return $self->{USED_BY}->delete(@_);
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

1;

#
# That's All Folks!
#
