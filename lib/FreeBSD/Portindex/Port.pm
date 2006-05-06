# Copyright (c) 2004-2006 Matthew Seaman. All rights reserved.
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
# @(#) $Id: Port.pm,v 1.32 2006-05-06 22:43:26 matthew Exp $
#

#
# An object for holding various data used in creating a port -- mostly
# this is used for generating the ports INDEX.
#
package FreeBSD::Portindex::Port;
our $VERSION = '1.5';    # Release

use strict;
use warnings;
use Carp;

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %self   = @_;

    croak __PACKAGE__, "::new() -- PKGNAME missing\n"
      unless defined $self{PKGNAME};
    croak __PACKAGE__, "::new() -- ORIGIN missing\n"
      unless defined $self{ORIGIN};

    return bless \%self, $class;
}

# Process the output from 'make describe' into a
# FreeBSD::Portindex::Port object.  The 'make describe' format is very
# similar to an index line, except that the fields are in a different
# (more sendsible) order, and the dependencies are given using the
# port ORIGIN, rather than PKGNAME.  Only the immediate dependencies
# of any port are given, not the cumulative dependencies of the port
# and all of its dependencies, etc.  Transforming the ORIGIN lines
# into the PKGNAME form has to wait until all the port objects have
# been created, ie. on output of the INDEX file.
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
      or do {
        warn __PACKAGE__,
          "::new_from_description(): -- incorrect format: $desc\n";
        return undef;
      };

    $extract_depends = _clean_depends($extract_depends);
    $patch_depends   = _clean_depends($patch_depends);
    $fetch_depends   = _clean_depends($fetch_depends);
    $build_depends   = _clean_depends($build_depends);
    $run_depends     = _clean_depends($run_depends);

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

# This is a regular sub, not a method call.  Convert the space
# separated dependency list into an array, plus clean up various
# undesirable features.
sub _clean_depends ($)
{
    my $deps = shift;
    my @deps;

    # The make describe line may contain several undesirable
    # constructs in the list of dependency origins.  Strip these
    # out as follows:
    #
    #  /usr/ports/foo/bar/../../baz/blurfl -> /usr/ports/baz/blurfl
    #  /usr/ports/foo/bar/../quux -> /usr/ports/foo/quux
    #  /usr/ports/foo/bar/ -> /usr/ports/foo/bar

    for my $dep ( split ' ', $deps ) {
        $dep =~ s@/\w[^/]+/\w[^/]+/\.\./\.\./@/@g;
        $dep =~ s@/\w[^/]+/\.\./@/@g;
        $dep =~ s@/\Z@@g;

        push @deps, $dep;
    }
    return \@deps;
}

# Bulk creation of accessor methods.
for my $slot (
    qw(PKGNAME ORIGIN STUFF BUILD_DEPENDS RUN_DEPENDS WWW
    EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS DEPENDENCIES_ACCUMULATED
    MASTERDIR MAKEFILE_LIST)
  )
{
    no strict qw(refs);

    *$slot = sub {
        my $self = shift;

        $self->{$slot} = shift if @_;
        return $self->{$slot};
    };
}

# Accumulate all of the various dependencies for this port.  If a port
# has a FOO_DEPENDS entry for /usr/ports/foo/bar, then the FOO_DEPENDS
# entry should have all of the RUN_DEPENDS items for the foo/bar port
# added to it.  Recursively.  Note: don't store
# FreeBSD::Portindex::Port objects with accumulated dependencies in
# the FreeBSD::Portindex::Tree structure.
sub accumulate_dependencies ($$$;$)
{
    my $self     = shift;
    my $allports = shift;
    my $recdepth = shift;
    my $counter  = shift;

    print STDERR ' ' x $recdepth, $self->ORIGIN(),
      ( $self->DEPENDENCIES_ACCUMULATED() ? '+' : '' ), "\n"
      if ( $::Config{Debug} );

    unless ( $self->DEPENDENCIES_ACCUMULATED() ) {
        $self->DEPENDENCIES_ACCUMULATED(1);    # Accumulation in progress

      DEPEND: for my $whatdep (
            qw( EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS
            BUILD_DEPENDS RUN_DEPENDS )
          )
        {
            my %seen = ();

            for my $dep ( @{ $self->$whatdep() } ) {
                if ( defined $allports->{$dep} ) {
                    $allports->{$dep}
                      ->accumulate_dependencies( $allports, $recdepth + 1 );
                } else {
                    warn "\n", __PACKAGE__, "::accumulate_dependencies: ",
                      $self->PKGNAME(), " (", $self->ORIGIN(),
                      ") claims to have a $whatdep dependency on $dep,",
                      " but no such port is known\n";
                    next DEPEND;
                }
            }

            grep { $seen{$_}++ } @{ $self->$whatdep() };
            for my $dep ( @{ $self->$whatdep() } ) {
                grep { $seen{$_}++ } @{ $allports->{$dep}->RUN_DEPENDS() };
            }
            $self->$whatdep( [ keys %seen ] );
        }
        $self->DEPENDENCIES_ACCUMULATED(2);    # Accumulation done
    } elsif ( $self->DEPENDENCIES_ACCUMULATED() == 1 ) {

        # We've got a dependency loop
        warn __PACKAGE__, "::accumulate_dependencies(): ",
          "dependency loop detected while processing ", $self->ORIGIN(), "\n";
    }
    counter( \$::Config, $counter );
    return $self;
}

# Print out one line of the INDEX file
sub print ($*;$)
{
    my $self     = shift;
    my $fh       = shift;
    my $allports = shift;
    my $counter  = shift;

    print $fh $self->PKGNAME(), '|';
    print $fh $self->ORIGIN(),  '|';
    print $fh $self->STUFF(),   '|';
    print $fh $self->_chase_deps( $allports, 'BUILD_DEPENDS' ), '|';
    print $fh $self->_chase_deps( $allports, 'RUN_DEPENDS' ),   '|';
    print $fh $self->WWW(), '|';
    print $fh $self->_chase_deps( $allports, 'EXTRACT_DEPENDS' ), '|';
    print $fh $self->_chase_deps( $allports, 'PATCH_DEPENDS' ),   '|';
    print $fh $self->_chase_deps( $allports, 'FETCH_DEPENDS' ),   "\n";

    counter( \$::Config, $counter );
    return $self;
}

# Currently, just turns the dependency array into a space separated
# list.  Translate from ORIGINs into PKGNAMEs
sub _chase_deps($$$)
{
    my $self     = shift;
    my $allports = shift;
    my $dep      = shift;
    my @dependencies;

    for my $origin ( @{ $self ->${dep}() } ) {
        if ( defined $allports->{$origin} ) {
            push @dependencies, $allports->{$origin}->PKGNAME();
        } else {
            warn "\n", __PACKAGE__, "::_chase_deps():", $self->PKGNAME(),
              " No PKGNAME found for ($dep) $origin\n";
        }
    }
    return join ' ', sort @dependencies;
}

1;

#
# That's All Folks!
#
