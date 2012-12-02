# Copyright (c) 2011-2012 Matthew Seaman. All rights reserved.
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
# Severely cut-down and bastardized implementation of something almost
# but not quite like the excellent GraphViz module interface by Leon
# Brocard.  All this does is generate the canonical 'dot' file
# corresponding to a graph.  Unlike the GraphViz module, this has no
# other dependencies (not even GraphViz).
#

package FreeBSD::Portindex::GraphViz;
use fields qw(NODES NODE_ORIGINS EDGES);

require 5.008_003;

use strict;
use warnings;
use Carp;

#
# Graphs are essentially a list of nodes, and a list of edges
# connecting the nodes.
#
sub new($)
{
    my $class = shift;
    my $self  = fields::new($class);

    %{$self} = (
        NODES        => [],
        NODE_ORIGINS => {},
        EDGES        => [],
    );
    return $self;
}

sub add_node($$@)
{
    my $self   = shift;
    my $origin = shift;
    my %args   = @_;
    my $node   = {};

    if ( $args{label} ) {
        if ( $args{label} =~ m/\W/ ) {
            $args{label} = "\"$args{label}\"";
            $args{label} =~ s/\n/\\n/gs;
        }
        $node->{label} = $args{label};
    } else {
        croak "add_node missing mandatory label";
    }

    $node->{name} = 'node' . ( scalar( @{ $self->{NODES} } ) + 1 );

    $self->{NODE_ORIGINS}->{$origin} = $node;
    push @{ $self->{NODES} }, $node;

    return $self;
}

sub add_edge($$$@)
{
    my $self = shift;
    my $from = shift;
    my $to   = shift;
    my %args = @_;
    my $edge = {};

    # $from and $to nodes may not exist yet... Resolve all these from
    # origin directories to node names at print()-time.

    $edge->{from} = $from;
    $edge->{to}   = $to;

    # We need a label and a colour -- actually a series of colours.
    # Add "quote" marks if either contains more than just alphanumeric
    # characters.  Replace some characters with escape sequences.

    if ( $args{label} ) {
        if ( $args{label} =~ m/\W/ ) {
            $args{label} = "\"$args{label}\"";
            $args{label} =~ s/\n/\\n/gs;
        }
        $edge->{label} = $args{label};
    } else {
        croak "add_edge missing mandatory label";
    }

    if ( $args{color} ) {
        if ( $args{color} =~ m/\W/ ) {
            $args{color} = "\"$args{color}\"";
        }
        $edge->{color} = $args{color};
    } else {
        croak "add_edge missing mandatory color";
    }

    push @{ $self->{EDGES} }, $edge;

    return $self;
}

sub print($)
{
    my $self = shift;

    # Header: Standard boilerplate

    print <<'E_O_HEADER';
digraph test {
        graph [ratio=fill, fontname=arial, fontsize=8];
        node [label="\N"];
        edge [color=Navy];
E_O_HEADER

    # Node List:
    for my $n ( @{ $self->{NODES} } ) {
        print ' ' x 8, $n->{name}, ' [label=', $n->{label}, "];\n";
    }

    # Edge List:

    for my $e ( @{ $self->{EDGES} } ) {
        croak "Edge from non-existent node ", $e->{from}
          unless defined $self->{NODE_ORIGINS}->{ $e->{from} };

        $e->{from} = $self->{NODE_ORIGINS}->{ $e->{from} }->{name};

        croak "Edge to non-existent node ", $e->{to}
          unless defined $self->{NODE_ORIGINS}->{ $e->{to} };

        $e->{to} = $self->{NODE_ORIGINS}->{ $e->{to} }->{name};

        print ' ' x 8, $e->{from},
          ' -> ',     $e->{to},
          ' [color=', $e->{color},
          ', label=', $e->{label},
          "];\n";
    }

    # Trailer:
    print "}\n";

    return;
}

#
# That's All Folks!
#
