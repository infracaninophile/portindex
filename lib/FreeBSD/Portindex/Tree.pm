# Copyright (c) 2004 Matthew Seaman. All rights reserved.
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
# @(#) $Id: Tree.pm,v 1.4 2004-10-01 19:11:37 matthew Exp $
#

#
# Container for FreeBSD::Ports objects which models the entire ports
# tree -- mapping port directories 'www/apache2'.
#
package FreeBSD::Ports::Tree;
$VERSION = 0.01;

use strict;
use warnings;
use Carp;

use FreeBSD::Port;

our ($verbose);

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %self   = @_;

    return bless \%self, $class;
}

# Insert port into ports tree structure according to the ORIGIN --
# either as a string or an array of directories.  Specifying a $port
# is optional -- leaving it out just creates a "directory" structure.
sub insert ($$;$)
{
    my $self   = shift;
    my $origin = shift;
    my $port   = shift;
    my $s      = $self;

    $origin = [ split '/' . $origin ]
      unless ref $origin eq 'ARRAY';
    $port = undef
      unless defined $port && $port->isa("FreeBSD::Port");

    while ( @{$origin} > 1 ) {
        my $d = shift @{$origin};

        $s->{$d} = {}
          unless defined $s->{$d};
        $s = $s->{$d};
    }
    $s->{ $origin->[0] } = $port;

    return $self;
}

# Return the port object for a given origin path, deleting the
# reference to it from the tree structure.  Return undef if port not
# found in tree
sub delete ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;
    my $xport;

    $origin = [ split '/', $origin ]
      unless ref $origin eq 'ARRAY';

    $port = $self;
    for my $d ( @{$origin} ) {
        if ( $port->{$d} ) {
            $xport = $port;
            $port  = $port->{$d};
        } else {
            undef $port;
            last;
        }
    }
    delete $xport->{ $origin->[-1] }
      if defined $port;
    return $port;
}

# Return the port object for a given origin path -- note that this can
# return entries corresponding to a port subdirectory as well.  Return
# undef if port not found in tree.
sub get ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;

    $origin = [ split '/', $origin ]
      unless ref $origin eq 'ARRAY';

    $port = $self;
    for my $d ( @{$origin} ) {
        if ( $port->{$d} ) {
            $port = $port->{$d};
        } else {
            undef $port;
            last;
        }
    }
    return $port;
}

# Read in the /usr/ports/INDEX file from STDIN converting to an array
# of hashes with links to the entries for dependencies.
sub read_index($)
{
    my $self  = shift;
    my $index = {};
    my $port;

    while (<>) {
        $port = FreeBSD::Port->new_from_description( $index, $_ );
        $self->insert( $port->ORIGIN(), $port );
    }

    # Only construct the inverse dependency links once the whole
    # structure has been initialised

    foreach $port ( values %{$index} ) {

        # Construct the inverse links -- from the dependency to us
        $port->invert_dependencies('B_DEPS');
        $port->invert_dependencies('R_DEPS');
        $port->invert_dependencies('E_DEPS');
        $port->invert_dependencies('P_DEPS');
        $port->invert_dependencies('F_DEPS');
    }
    return $self;
}

# Print out whole INDEX file sorted by origin using %ports hash:
# recurse through directory levels.
sub print($)
{
    my $self = shift;

    sub _do_print ($)
    {
        my $self = shift;

        unless ( $self->isa("FreeBSD::Port") ) {
            for my $q ( sort keys %{$self} ) {
                &_do_print( $self->{$q} );
            }
        } else {
            $self->print();
        }
    }

    _do_print($self);

    return $self;
}

1;

#
# That's All Folks!
#
