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
# @(#) $Id: Tree.pm,v 1.6 2004-10-07 09:56:26 matthew Exp $
#

#
# Container for FreeBSD::Ports objects which models the entire ports
# tree -- mapping port directories '/usr/ports/www/apache2', or any
# subdirectory thereof.
#
package FreeBSD::Ports::Tree;
$VERSION = 0.01;

use strict;
use warnings;
use Carp;

use FreeBSD::Port;

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

    $origin = [ split '/', $origin ]
      unless ref $origin eq 'ARRAY';
    $port = undef
      unless defined $port && $port->isa("FreeBSD::Port");

    # Since $origin is (usually) passed by ref, mustn't alter its
    # contents.  How to loop over all but the last element of an array
    # given that limitation:

    for my $d ( @{$origin}[ 0 .. $#{$origin} - 1 ] ) {
        $s->{$d} = $s->new()
          unless defined $s->{$d};
        $s = $s->{$d};
    }
    $s->{ $origin->[-1] } = $port;

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
# return object corresponding to a port subdirectory as well.  Return
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
sub read_index($$)
{
    my $self       = shift;
    my $filehandle = shift;
    my $port;

    print STDERR "Reading INDEX file: " if ($::verbose);
    while (<$filehandle>) {
        $port = FreeBSD::Port->new_from_indexline($_);
        $self->insert( $port->ORIGIN(), $port );

        if ($::verbose) {
            if ( $. % 1000 == 0 ) {
                print STDERR "[$.]";
            } elsif ( $. % 100 == 0 ) {
                print STDERR '.';
            }
        }
    }
    print STDERR "<$.>\n" if ($::verbose);

    return $self;
}

# Print out whole INDEX file sorted by origin using %ports hash:
# recurse through directory levels.  Elements are either
# FreeBSD::Ports::Tree or FreeBSD::Port objects -- just call the print
# method for each object, sorting in order of port name.
sub print_index($$)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = 1;

    print STDERR "Writing INDEX file: " if ($::verbose);

    $self->print( $fh, \$counter );

    print STDERR "<${counter}>\n" if ($::verbose);

    return $self;
}

# The print method for a FreeBSD::Ports::Tree object just calls the
# print method for all of the objects it contains.
sub print($$;$)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = shift;

    for my $q ( sort keys %{$self} ) {
        $self->{$q}->print( $fh, $counter );
    }
    return $self;
}

1;

#
# That's All Folks!
#
