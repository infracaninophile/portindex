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
# @(#) $Id: Tree.pm,v 1.3 2004-10-01 11:58:24 matthew Exp $
#

#
# Container for FreeBSD::Ports objects which models the entire ports
# tree -- mapping port directories 'www/apache2'
#
package FreeBSD::Ports::Tree;
$VERSION = 0.01;

use strict;
use warnings;
use Carp;

our ($verbose);

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %self   = @_;

    return bless \%self, $class;
}

sub insert ($$;$)
{
    my $self   = shift;
    my $origin = shift;
    my $port   = shift;
    my $s      = $self;

    $origin = [ split '/' . $origin ]
      unless ref $origin eq 'ARRAY';
    $port = {}
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

1;

#
# That's All Folks!
#
