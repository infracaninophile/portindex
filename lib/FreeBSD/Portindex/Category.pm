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
# An object for holding the lists of SUBDIR from the per category
# or top level Makefiles.  These are used to detect certain types
# of update to the ports tree that may otherwise be missed between
# running 'cache-init' and a subsequent 'cache-update'
#
package FreeBSD::Portindex::Category;
use parent qw(FreeBSD::Portindex::PortsTreeObject);

use strict;
use warnings;
use Carp;

use FreeBSD::Portindex::Config qw(%Config _clean);
use FreeBSD::Portindex::ListVal;

#
# In addition to ORIGIN and MTIME provided by the base class, the data
# held by this object are the list of SUBDIR -- the list of other
# categories or portnames extracted from the Makefile.  Also contains
# the equivalent data extracted from any Makefile.local additions to
# the tree.
#
sub new ($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;

    # SUBDIR should be an array ref, but can be empty
    croak "$0: error instantiating $class object -- SUBDIR not an array ref\n"
      unless ref $args{SUBDIR} eq 'ARRAY';

    $self = $class->SUPER::new(%args);

    $self->{SUBDIR} = FreeBSD::Portindex::ListVal->new( @{ $args{SUBDIR} } );
    $self->{COMMENT} = $args{COMMENT};    # Can be undef

    return $self;
}

# Acknowledge that $self is a category
sub is_category($) { return 1; }

#
# Create a Category object from the value of certain variables
# extracted from one of the ports category Makefiles.  The top level
# node is thus "", corresponding to data read from
# /usr/ports/Makefile.
#
sub new_from_make_vars ($$)
{
    my $class = shift;
    my $args  = shift;
    my @subdir;
    my @makefile_list;
    my $origin;

    ( $origin = $args->{'.CURDIR'} ) =~ s,^$Config{PortsDir}/?,,;

    @subdir = split ' ', $args->{SUBDIR};

    # Paths in .MAKEFILE_LIST are either absolute or relative to
    # .CURDIR Get rid of all the '..' entries.

    @makefile_list = _clean(
        map { s@^(?!/)@$args->{'.CURDIR'}/@; $_ }
          grep { !m/^\.\.$/ } split ' ',
        $args->{'.MAKEFILE_LIST'}
    );

    return $class->new(
        ORIGIN        => $origin,
        SUBDIR        => \@subdir,
        COMMENT       => $args->{COMMENT},
        MAKEFILE_LIST => \@makefile_list
    );
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

    return $self->{SUBDIR}->contains($origin);
}

sub make_readme ($$$)
{
    my $self     = shift;
    my $file     = shift;
    my $template = shift;
    my $subdir   = shift;

    # %%SUBDIR%%  (top, category)

    $template =~ s/%%SUBDIR%%/$subdir/g;

    # %%CATEGORY%% (category)

    $template =~ s/%%CATEGORY%%/$self->ORIGIN()/ge;

    # %%COMMENT%% (category)

    $template =~ s/%%COMMENT%%/$self->COMMENT()/ge;

    # Template also includes %%DESCR%%, but only ports have that.

    $template =~ s/%%DESCR%%//g;

    return $self->SUPER::make_readme( $file, $template );
}

# Accessor methods (ARRAYS): Only SUBDIR to deal with
for my $slot ('SUBDIR') {
    no strict qw(refs);

    *$slot = __PACKAGE__->list_val_accessor($slot);
}

# Accessor methods (SCALARS): Only COMMENT to deal with
for my $slot ('COMMENT') {
    no strict qw(refs);

    *$slot = __PACKAGE__->scalar_accessor($slot);
}

1;

#
# That's All Folks!
#
