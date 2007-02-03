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
# @(#) $Id: Port.pm,v 1.43 2007-02-03 15:06:08 matthew Exp $
#

#
# An object for holding various data used in creating a port -- mostly
# this is used for generating the ports INDEX.
#
package FreeBSD::Portindex::Port;
our $VERSION = '1.8';    # Release

our %directorycache;     # Remember all the directories we've ever seen

use strict;
use warnings;
use Carp;

use FreeBSD::Portindex::Config qw{counter};

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

#
# Generate the same result using the values of a number of variables
# extracted from the port Makefile.  This effectively duplicates the
# code in /usr/ports/Mk/bsd.ports.mk used to produce the 'make
# describe' output. Instead of invoking perl repeatedly for all
# 15,000+ ports, we just invoke it once, plus we cache all the results
# of testing that referenced port directories exist -- so this should
# be a bit more efficient.
#
sub new_from_make_vars ($$)
{
    my $caller = shift;
    my $args   = shift;
    my $self;

    my $pkgname;
    my $origin;
    my $stuff;
    my $build_depends;
    my $run_depends;
    my $extract_depends;
    my $patch_depends;
    my $fetch_depends;
    my $lib_depends;
    my $descr;
    my $www;
    my $master_port;

    # %{$args} should contain the value of the following port variables:
    # PKGNAME, .CURDIR, PREFIX, COMMENT[*], DESCR, MAINTAINER,
    # CATEGORIES, EXTRACT_DEPENDS, PATCH_DEPENDS, FETCH_DEPENDS,
    # BUILD_DEPENDS, RUN_DEPENDS, LIB_DEPENDS.
    # Additionally, the file referenced by DESCR should be grepped to find
    # the WWW value.
    #
    # To the usual ports index stuff we add the extra make variables:
    # MASTER_PORT and .MAKEFILE_LIST which are used to control
    # incremental updating.  MASTER_PORT is usually null, and where it
    # is set is given as a relative path to PORTSDIR

    $pkgname = $args->{PKGNAME};
    $origin  = $args->{'.CURDIR'};
    ( $descr, $www ) = _www_descr( $args->{DESCR} );
    $stuff = join( '|',
        $args->{PREFIX}, $args->{COMMENT}, $descr, $args->{MAINTAINER},
        $args->{CATEGORIES} );
    if ( $args->{MASTER_PORT} ) {
        if ( $args->{MASTER_PORT} =~ m@^[a-zA-Z0-9._+-]+/[a-zA-Z0-9._+-]+$@ ) {
            $master_port = "$::Config{PortsDir}/$args->{MASTER_PORT}";
        } else {

            # This is probably caused by a trailing '/' character
            # on a MASTERDIR setting. In which case the result is
            # '/usr/ports/foo/bar/' rather than 'foo/bar'
            ( $master_port = $args->{MASTER_PORT} ) =~ s@/?$@@;

            warn __PACKAGE__, ":new_from_make_vars():$origin($pkgname) ",
              "-- warning MASTER_PORT=$args->{MASTER_PORT} not in expected ",
              "format\n";
        }
    }

    # [*] COMMENT doesn't need quoting to get it through several
    # layers of shell.

    $extract_depends =
      _sanatize( $origin, $pkgname, 'EXTRACT_DEPENDS',
        _split_xxx_depends( $args->{EXTRACT_DEPENDS} ) );
    $patch_depends =
      _sanatize( $origin, $pkgname, 'PATCH_DEPENDS',
        _split_xxx_depends( $args->{PATCH_DEPENDS} ) );
    $fetch_depends =
      _sanatize( $origin, $pkgname, 'FETCH_DEPENDS',
        _split_xxx_depends( $args->{FETCH_DEPENDS} ) );
    $build_depends =
      _sanatize( $origin, $pkgname, 'BUILD_DEPENDS',
        _split_xxx_depends( $args->{BUILD_DEPENDS} ) );
    $run_depends =
      _sanatize( $origin, $pkgname, 'RUN_DEPENDS',
        _split_xxx_depends( $args->{RUN_DEPENDS} ) );
    $lib_depends =
      _sanatize( $origin, $pkgname, 'LIB_DEPENDS',
        _split_xxx_depends( $args->{LIB_DEPENDS} ) );

    # If any of the dependencies weren't there, then don't generate
    # a Port object.
    return undef
      unless ( defined $extract_depends
        && defined $patch_depends
        && defined $fetch_depends
        && defined $build_depends
        && defined $run_depends
        && defined $lib_depends );

    # On output:
    # $extract_depends = EXTRACT_DEPENDS
    # $patch_depends   = PATCH_DEPENDS
    # $fetch_depends   = FETCH_DEPENDS
    # $build_depends   = BUILD_DEPENDS + LIB_DEPENDS
    # $run_depends     = RUN_DEPENDS   + LIB_DEPENDS
    # The lists should be uniq'd -- sorting will happen later

    $extract_depends = _uniquify($extract_depends);
    $patch_depends   = _uniquify($patch_depends);
    $fetch_depends   = _uniquify($fetch_depends);
    $build_depends   = _uniquify( $build_depends, $lib_depends );
    $run_depends     = _uniquify( $run_depends, $lib_depends );

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
    $self->master_port($master_port);

    return $self;
}

#
# This is a regular sub, not a method call.  Convert the space
# separated dependency list into an array (unless it is one already),
# plus clean up various undesirable features.
#
sub _clean_depends ($)
{
    my $deps = shift;
    my @deps;

    @deps = ( ref $deps ) ? @{$deps} : split( ' ', $deps );

    _clean(@deps);
    return \@deps;
}

#
# The make describe line may contain several undesirable constructs in
# the list of dependency origins.  Strip these out as follows:
#
#  /usr/ports/foo/bar/../../baz/blurfl -> /usr/ports/baz/blurfl
#  /usr/ports/foo/bar/../quux -> /usr/ports/foo/quux
#  /usr/ports/foo/bar/ -> /usr/ports/foo/bar
#
# This alters the arg list directly, so don't pass unassignables
# to this sub.
#
sub _clean (@)
{
    for (@_) {
        chomp;
        s@/\w[^/]+/\w[^/]+/\.\./\.\./@/@g;
        s@/\w[^/]+/\.\./@/@g;
        s@/\Z@@;
    }
    return wantarray ? @_ : $_[0];
}

#
# Extract the port directories from the list of tuples emitted by make
# for (EXTRACT|FETCH|BUILD|RUN|LIB)_DEPENDS.  These are space
# separated lists of the form path:dir[:target] -- the 'dir' is what
# we want.  Note: some of these fields can be empty.  See
# math/asymptote BUILD_DEPENDS for example.
#
sub _split_xxx_depends ($)
{
    my $deps = shift;
    my @deps;

    @deps = ( $deps =~ m{\s*[^\s:]*:([^\s:]+)(?::\S+)?}g );

    return _clean_depends( \@deps );
}

#
# Test if the file referenced by DESCR exists -- otherwise return /dev/null
# instead.  If it does exist, grep through it to find the WWW: reference.
#
sub _www_descr ($)
{
    my $descr = shift;
    my $www   = '';

    if ( -f $descr ) {
        open( DESCR, '<', $descr ) and do {
            while (<DESCR>) {
                if (m/^WWW:\s+(\S+)/) {
                    $www = $1;
                    last;
                }
            }
            close DESCR;
          }
    } else {
        $descr = '/dev/null';
    }
    return ( $descr, $www );
}

#
# Take a list of array references, expand them into a single
# array. Strip out any duplicates entries in that array. Return
# a reference to the result.
#
sub _uniquify(@)
{
    my @args = @_;
    my %seen;

    # Expand the referenced arrays and strip out duplicates
    @args = grep { !$seen{$_}++ } map { @{$_} } @args;

    return \@args;
}

#
# Take the list of dependencies and ensure that all entries correspond
# to extant directories.  'make index' dies with an error in that case
# -- we don't die, but raise an error by returning undef to signal the
# caller that thigs have gone horribly wrong. (Must be careful --
# empty lists are fine) One important optimization: keep a cache of
# all the directories we've ever located, instead of stat()'ing them
# again.
#
sub _sanatize($$$$)
{
    my $origin    = shift;
    my $pkgname   = shift;
    my $whatdep   = shift;
    my $deplist   = shift;
    my $errorflag = 0;

    foreach my $arg ( @{$deplist} ) {
        unless ( $directorycache{$arg} ) {
            if ( -d $arg ) {
                $directorycache{$arg}++;
            } else {
                warn __PACKAGE__, "::new_from_make_vars(): ",
                  "${origin}($pkgname):$whatdep $arg -- dependency not found\n";
                $errorflag++;
            }
        }
    }
    if ($errorflag) {
        return undef;
    } else {
        return $deplist;
    }
}

#
# Bulk creation of accessor methods.
#
for my $slot (
    qw(PKGNAME ORIGIN STUFF BUILD_DEPENDS RUN_DEPENDS WWW
    EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS DEPENDENCIES_ACCUMULATED
    MASTER_PORT MAKEFILE_LIST)
  )
{
    no strict qw(refs);

    *$slot = sub {
        my $self = shift;

        $self->{$slot} = shift if @_;
        return $self->{$slot};
    };
}

#
# Accessor method with added foo: we're only interested in
# MASTER_PORT if it is set and different to ORIGIN
#
sub master_port ($$)
{
    my $self = shift;
    my $master_port;

    if (@_) {
        $master_port = shift;

        if ( $master_port && $master_port ne $self->ORIGIN() ) {
            $self->MASTER_PORT($master_port);
        } else {
            $self->MASTER_PORT(undef);
        }
    }
    return $self->MASTER_PORT();
}

#
# Accessor method with added foo: grep through the list of
# makefiles given in .MAKEFILE_LIST and strip out what it does
# not make sense to try and process.
#
sub makefile_list ($$$$)
{
    my $self          = shift;
    my $makefile_list = shift;
    my $keepers       = shift;    # MAKEFILE_LOCATIONS
    my $discards      = shift;    # MAKEFILE_EXCEPTIONS

    # List all of the makefiles under ${PORTSDIR} or /var/db/ports
    # which affect the compilation of a port.  Don't include
    # ${PORTSDIR}/Mk/bsd.port.mk, because that affects *everything*,
    # nor include ${PORTSDIR}/Mk/bsd.sites.mk since that has no
    # material effect on the resulting port/package.

    my %seen = ();

    $self->MAKEFILE_LIST(
        [
            _clean(
                grep { !$seen{$_}++ && m/$keepers/ && !m/$discards/ }
                  split( ' ', $makefile_list )
            )
        ]
    );
    return $self;
}

#
# Accumulate all of the various dependencies for this port.  If a port
# has a FOO_DEPENDS entry for /usr/ports/foo/bar, then the FOO_DEPENDS
# entry should have all of the RUN_DEPENDS items for the foo/bar port
# added to it.  Recursively.  Note: don't store
# FreeBSD::Portindex::Port objects with accumulated dependencies in
# the FreeBSD::Portindex::Tree structure.
#
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
                    if ( $allports->{$dep}->can("accumulate_dependencies") ) {
                        $allports->{$dep}
                          ->accumulate_dependencies( $allports, $recdepth + 1 );
                    } else {
                        warn "\n", __PACKAGE__, "::accumulate_dependencies: ",
                          $self->PKGNAME(), " (", $self->ORIGIN(),
") dependency on something ($dep) that is not a port\n";
                        next DEPEND;
                    }
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
    counter( \%::Config, $counter );
    return $self;
}

#
# Print out one line of the INDEX file
#
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

    counter( \%::Config, $counter );
    return $self;
}

#
# Currently, just turns the dependency array into a space separated
# list and translates from ORIGINs into PKGNAMEs
#
sub _chase_deps($$$)
{
    my $self     = shift;
    my $allports = shift;
    my $dep      = shift;
    my @dependencies;

    for my $origin ( @{ $self ->${dep}() } ) {
        if ( defined $allports->{$origin}
            && $allports->{$origin}->can("PKGNAME") )
        {
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
