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
# @(#) $Id: Port.pm,v 1.9 2004-10-10 20:37:18 matthew Exp $
#

#
# An object for holding various data used in creating a port -- mostly
# this is used for generating the ports INDEX.
#
package FreeBSD::Port;
$VERSION = 0.01;    # Extremely alpha.

use strict;
use warnings;
use Carp;

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %self   = @_;

    croak __PACKAGE__, "::new() -- PKGNAME missing"
      unless defined $self{PKGNAME};
    croak __PACKAGE__, "::new() -- ORIGIN missing"
      unless defined $self{ORIGIN};

    return bless \%self, $class;
}

# Process the output from 'make describe' into a FreeBSD::Port object.
# The 'make describe' format is very similar to an index line, except
# that the fields are in a different (more sendsible) order, and the
# dependencies are given using the port ORIGIN, rather than PKGNAME.
# Only the immediate dependencies of any port are given, not the
# cumulative dependencies of the port and all of its dependencies,
# etc.  Transforming the ORIGIN lines into the PKGNAME form has to
# wait until all the port objects have been created, ie. on output of
# the INDEX file.
sub new_from_description($$)
{
    my $caller = shift;
    my $desc   = shift;
    my $self;

    my $pkgname;
    my $origin;
    my $stuff;
    my $build_depends;
    my $run_depends;
    my $extract_depends;
    my $patch_depends;
    my $fetch_depends;
    my $www;

    chomp($desc);

    (
        $pkgname,         $origin,        $stuff,
        $extract_depends, $patch_depends, $fetch_depends,
        $build_depends,   $run_depends,   $www
      )
      = (
        $desc =~ m{
             ^([^|]+)\|          # PKGNAME
              ([^|]+)\|          # ORIGIN
              ((?:[^|]*\|){4}[^|]*)\|
                                 # PREFIX,COMMENT,DESCR,MAINTAINER,CATEGORIES
              ([^|]*)\|          # EXTRACT_DEPENDS
              ([^|]*)\|          # PATCH_DEPENDS
              ([^|]*)\|          # FETCH_DEPENDS
              ([^|]*)\|          # BUILD_DEPENDS
              ([^|]*)\|          # RUN_DEPENDS
              ([^|]*)$           # WWW
          }x
      )
      or croak __PACKAGE__,
      "::new_from_description(): -- incorrect format: $desc";

    $extract_depends = [ split ' ', $extract_depends ];
    $patch_depends   = [ split ' ', $patch_depends ];
    $fetch_depends   = [ split ' ', $fetch_depends ];
    $build_depends   = [ split ' ', $build_depends ];
    $run_depends     = [ split ' ', $run_depends ];

    $self = $caller->new(
        PKGNAME         => $pkgname,
        ORIGIN          => $origin,
        STUFF           => $stuff,
        EXTRACT_DEPENDS => $extract_depends,
        PATCH_DEPENDS   => $patch_depends,
        FETCH_DEPENDS   => $fetch_depends,
        BUILD_DEPENDS   => $build_depends,
        RUN_DEPENDS     => $run_depends,
        WWW             => $www,
    );

    return $self;
}

# Bulk creation of accessor methods.
for my $slot (
    qw(PKGNAME ORIGIN STUFF BUILD_DEPENDS RUN_DEPENDS WWW
    EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS BUILD_INVERSE
    RUN_INVERSE EXTRACT_INVERSE PATCH_INVERSE FETCH_INVERSE )
  )
{
    no strict qw(refs);

    *$slot = sub {
        my $self = shift;

        $self->{$slot} = shift if @_;
        return $self->{$slot};
    };
}

# Print out one line of the INDEX file
sub print ($*;$)
{
    my $self    = shift;
    my $fh      = shift;
    my $o2pn    = shift;
    my $counter = shift;

    print $fh $self->PKGNAME(), '|';
    print $fh $self->ORIGIN(),  '|';
    print $fh $self->STUFF(),   '|';
    print $fh $self->_chase_deps( $o2pn, 'BUILD_DEPENDS' ), '|';
    print $fh $self->_chase_deps( $o2pn, 'RUN_DEPENDS' ),   '|';
    print $fh $self->WWW(), '|';
    print $fh $self->_chase_deps( $o2pn, 'EXTRACT_DEPENDS' ), '|';
    print $fh $self->_chase_deps( $o2pn, 'PATCH_DEPENDS' ),   '|';
    print $fh $self->_chase_deps( $o2pn, 'FETCH_DEPENDS' ),   "\n";

    if ( $::verbose && defined $counter ) {
        if ( $$counter % 1000 == 0 ) {
            print STDERR "[$$counter]";
        } elsif ( $$counter % 100 == 0 ) {
            print STDERR '.';
        }
        $$counter++;
    }
    return $self;
}

# Currently, just turns the dependency array into a space separated
# list.  Translate from ORIGINs into PKGNAMEs
sub _chase_deps($$$)
{
    my $self = shift;
    my $o2pn = shift;
    my $dep  = shift;
    my @dependencies;

    for my $origin ( @{ $self ->${dep}() } ) {
        if ( defined $o2pn->{$origin} ) {
            push @dependencies, $o2pn->{$origin};
        } else {
            carp __PACKAGE__, "::_chase_deps(): No PKGNAME found for $origin";
        }
    }
    return join ' ', sort @dependencies;
}

1;

#
# That's All Folks!
#
