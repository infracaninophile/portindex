# Copyright (c) 2004-2011 Matthew Seaman. All rights reserved.
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
# An object for holding various data used in creating a port -- mostly
# this is used for generating the ports INDEX.  In addition to the
# ORIGIN and MTIME fields provided by the superclass, this must at
# least have a defined PKGNAME field.
#
package FreeBSD::Portindex::Port;

use strict;
use warnings;

use FreeBSD::Portindex::TreeObject;
use FreeBSD::Portindex::Config qw{%Config counter};

our @ISA     = ('FreeBSD::Portindex::TreeObject');
our $VERSION = '2.6';                                # Release

our %directorycache;    # Remember all the directories we've ever seen
our %pkgnamecache;      # Remember all of the package names we've output

sub new ($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;

    $self = $class->SUPER::new(%args);

    die "$0: error instantiating $class object -- PKGNAME missing\n"
      unless defined $args{PKGNAME};

    $self->PKGNAME( $args{PKGNAME} );
    $self->STUFF( $args{STUFF} );
    $self->EXTRACT_DEPENDS( $args{EXTRACT_DEPENDS} );
    $self->PATCH_DEPENDS( $args{PATCH_DEPENDS} );
    $self->FETCH_DEPENDS( $args{FETCH_DEPENDS} );
    $self->BUILD_DEPENDS( $args{BUILD_DEPENDS} );
    $self->RUN_DEPENDS( $args{RUN_DEPENDS} );
    $self->LIB_DEPENDS( $args{LIB_DEPENDS} );
    $self->WWW( $args{WWW} );
    $self->MASTER_PORT( $args{MASTER_PORT} );
    $self->MAKEFILE_LIST( $args{MAKEFILE_LIST} );

    return $self;
}

#
# Generate the same result using the values of a number of variables
# extracted from the port Makefile.  This effectively duplicates the
# code in /usr/ports/Mk/bsd.ports.mk used to produce the 'make
# describe' output. Instead of invoking perl repeatedly for all
# 22,000+ ports, we just invoke it once, plus we cache all the results
# of testing that referenced port directories exist -- so this should
# be a bit more efficient.
#
sub new_from_make_vars ($$$$)
{
    my $class               = shift;
    my $args                = shift;
    my $makefile_locations  = shift;
    my $makefile_exceptions = shift;
    my $self;

    my $origin;
    my $pkgname;
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
    my $makefile_list;

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

    $origin  = $args->{'.CURDIR'};
    $pkgname = $args->{PKGNAME};

    ( $descr, $www ) = _www_descr( $args->{DESCR} );

    # [*] COMMENT doesn't need quoting to get it through several
    # layers of shell.

    $stuff = join( '|',
        $args->{PREFIX}, $args->{COMMENT}, $descr, $args->{MAINTAINER},
        $args->{CATEGORIES} );

    $master_port = _master_port( $args->{MASTER_PORT}, $origin, $pkgname );

    $makefile_list = _makefile_list( $args->{'.MAKEFILE_LIST'},
        $makefile_locations, $makefile_exceptions );

    # If any of the dependencies aren't there, then don't generate
    # a Port object.

    # Of all the FOO_DEPENDS variables, one is not like all the
    # others.  EXTRACT, PATCH, BUILD, RUN all list the dependencies
    # needed at various phases of port building.  LIB lists
    # dependencies that happen to be shlibs.  It's an annoying
    # inconsistency.  As a consequence, the LIB_DEPENDS list needs to
    # be added to the RUN_DEPENDS and BUILD_DEPEND lists.

    $extract_depends =
      _depends_list( $origin, $pkgname, 'EXTRACT_DEPENDS',
        $args->{EXTRACT_DEPENDS} );
    return undef unless defined $extract_depends;

    $patch_depends =
      _depends_list( $origin, $pkgname, 'PATCH_DEPENDS',
        $args->{PATCH_DEPENDS} );
    return undef unless defined $patch_depends;

    $fetch_depends =
      _depends_list( $origin, $pkgname, 'FETCH_DEPENDS',
        $args->{FETCH_DEPENDS} );
    return undef unless defined $fetch_depends;

    $lib_depends =
      _depends_list( $origin, $pkgname, 'LIB_DEPENDS', $args->{LIB_DEPENDS} );
    return undef unless defined $lib_depends;

    $build_depends =
      _depends_list( $origin, $pkgname, 'BUILD_DEPENDS',
        $args->{BUILD_DEPENDS} . " " . $args->{LIB_DEPENDS} );
    return undef unless defined $build_depends;

    $run_depends =
      _depends_list( $origin, $pkgname, 'RUN_DEPENDS',
        $args->{RUN_DEPENDS} . " " . $args->{LIB_DEPENDS} );
    return undef unless defined $run_depends;

    $self = $class->new(
        PKGNAME         => $pkgname,
        ORIGIN          => $origin,
        STUFF           => $stuff,
        EXTRACT_DEPENDS => $extract_depends,
        PATCH_DEPENDS   => $patch_depends,
        FETCH_DEPENDS   => $fetch_depends,
        BUILD_DEPENDS   => $build_depends,
        RUN_DEPENDS     => $run_depends,
        LIB_DEPENDS     => $lib_depends,
        WWW             => $www,
        MASTER_PORT     => $master_port,
        MAKEFILE_LIST   => $makefile_list,
    );

    return $self;
}

#
# The make describe line may contain several undesirable constructs in
# the list of dependency origins.  Strip these out as follows:
#
#  /usr/ports/foo/bar/../../baz/blurfl -> /usr/ports/baz/blurfl
#  /usr/ports/foo/bar/../quux -> /usr/ports/foo/quux
#  /usr/ports/foo/bar/ -> /usr/ports/foo/bar
#
sub _clean ($)
{
    my $d = shift;

    chomp $d;
    $d =~ s@/\w[^/]+/\w[^/]+/\.\./\.\./@/@g;
    $d =~ s@/\w[^/]+/\.\./@/@g;
    $d =~ s@/\Z@@;

    return $d;
}

#
# Clean up the path and test if the file referenced by DESCR exists --
# otherwise return /dev/null instead.  If it does exist, grep through
# it to find the WWW: reference.
#
sub _www_descr ($)
{
    my $descr = shift;
    my $www   = '';

    $descr = _clean($descr);
    if ( -f $descr ) {
        open( DESCR, '<', $descr ) and do {
            while (<DESCR>) {
                if (m/^\s*WWW:\s+(\S+)/) {
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

# We're only interested in MASTER_PORT if it is set.  It can be the same
# as ORIGIN, but that's OK.
sub _master_port($$$)
{
    my $master_port = shift;
    my $origin      = shift;
    my $pkgname     = shift;

    if ($master_port) {
        if ( $master_port =~ m@^[a-zA-Z0-9._+-]+/[a-zA-Z0-9._+-]+$@ ) {
            $master_port = "$Config{PortsDir}/$master_port";
        } else {

            # This is probably caused by a trailing '/' character
            # on a MASTERDIR setting. In which case the result is
            # '/usr/ports/foo/bar/' rather than 'foo/bar'
            $master_port =~ s@/?$@@;

            warn "$0:$origin($pkgname) warning -- ",
              "\'MASTER_PORT=$master_port\' extraneous trailing /\n"
              if $Config{Warnings};
        }
    }
    return $master_port;
}

#
# Another non-method sub: grep through the list of
# makefiles given in .MAKEFILE_LIST and strip out what it does
# not make sense to try and process.  Return the list of interesting
# Makefiles an array
#
sub _makefile_list ($$$)
{
    my $makefile_list = shift;
    my $keepers       = shift;    # MAKEFILE_LOCATIONS
    my $discards      = shift;    # MAKEFILE_EXCEPTIONS
    my %seen;

    # List all of the makefiles under ${PORTSDIR} or /var/db/ports
    # which affect the compilation of a port.  Don't include
    # ${PORTSDIR}/Mk/bsd.port.mk, because that affects *everything*,
    # nor include ${PORTSDIR}/Mk/bsd.sites.mk since that has no
    # material effect on the resulting port/package.

    return [
        grep { !$seen{$_}++ && m/$keepers/ && !m/$discards/ }
          map { _clean $_ }
          split( ' ', $makefile_list )
    ];
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
sub _depends_list($$$$)
{
    my $origin    = shift;
    my $pkgname   = shift;
    my $whatdep   = shift;
    my $deplist   = shift;
    my $errorflag = 0;
    my @deps;

    # Extract the port directories from the list of tuples emitted by
    # make for (EXTRACT|FETCH|BUILD|RUN|LIB)_DEPENDS.  These are space
    # separated lists of the form path:dir[:target] -- the 'dir' is
    # what we want.  Note: some of these fields can be empty.  See
    # math/asymptote BUILD_DEPENDS for example.

    foreach my $arg ( split /\s+/, $deplist ) {
        next
          unless $arg;    # Leading whitespace causes a null element

        $arg =~ s/^[^:]*:([^\s:]+)(?::\S+)?$/$1/;
        $arg = _clean $arg;

        if ( $directorycache{$arg} ) {
            push @deps, $arg;
        } else {
            if ( -d $arg ) {

                # Sanity check -- is the dependency on what appears to
                # be a port, rather than anything else?  The target
                # may not be in the cache yet, so guess based on the
                # file path.
                if ( $arg =~ m@^$Config{PortsDir}(?:/[^/]+){2}\Z@ ) {
                    $directorycache{$arg}++;
                    push @deps, $arg;
                } else {
                    warn "$0:${origin} ($pkgname) Error. $whatdep $arg ",
                      "-- dependency is not a port\n";
                    $errorflag++;
                }
            } else {
                warn "$0:${origin} ($pkgname) Error. $whatdep $arg ",
                  "-- dependency not found\n";
                $errorflag++;
            }
        }
    }
    return $errorflag ? undef : \@deps;
}

#
# Bulk creation of accessor methods -- SCALARs.
#
for my $slot (qw(PKGNAME STUFF WWW DEPENDENCIES_ACCUMULATED MASTER_PORT)) {
    no strict qw(refs);

    *$slot = sub {
        my $self = shift;

        if (@_) {
            $self->{$slot} = shift;
        }
        return $self->{$slot};
    };
}

#
# Bulk creation of accessor methods -- ARRAYs.  These take references
# to arrays but return arrays rather than array references.
#
for my $slot (
    qw(BUILD_DEPENDS RUN_DEPENDS EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS
    LIB_DEPENDS MAKEFILE_LIST)
  )
{
    no strict qw(refs);

    *$slot = sub {
        my $self = shift;

        if (@_) {
            $self->{$slot} = [ _sort_unique +shift ];
        }
        return @{ $self->{$slot} };
    };
}

#
# Generic dependency accessor -- return array of the named type of
# dependency
#
sub depends($$;$)
{
    my $self = shift;
    my $slot = shift;

    if ( ref( $self->{$slot} ) eq 'ARRAY' ) {
        if (@_) {
            $self->{$slot} = [ _sort_unique +shift ];
        }
        return @{ $self->{$slot} };
    } else {
        return ();
    }
}

#
# Accumulate all of the various dependencies for this port.  If a port
# has a FOO_DEPENDS entry for /usr/ports/foo/bar, then the FOO_DEPENDS
# entry should have all of the RUN_DEPENDS items for the foo/bar port
# added to it.  Recursively.  Note: don't store
# FreeBSD::Portindex::Port objects with accumulated dependencies in
# the FreeBSD::Portindex::Tree structure.
#
sub accumulate_dependencies ($$$$$;$)
{
    my $self           = shift;
    my $allports       = shift;
    my $whatdeps       = shift;
    my $accumulate_dep = shift;
    my $recdepth       = shift;
    my $counter        = shift;

    unless ( $self->{DEPENDENCIES_ACCUMULATED} ) {
        $self->{DEPENDENCIES_ACCUMULATED} = 1;    # Accumulation in progress

        for my $whatdep ( @{$whatdeps} ) {
            my %seen = ();

            for my $dep ( $self->depends($whatdep) ) {
                if ( defined $allports->{$dep}
                    && $allports->{$dep}->can("accumulate_dependencies") )
                {
                    $allports->{$dep}->accumulate_dependencies(
                        $allports,       $whatdeps,
                        $accumulate_dep, $recdepth + 1
                    );

                    $seen{$dep}++;
                } else {
                    warn "$0:", $self->ORIGIN(), " (", $self->PKGNAME(),
                      ") $whatdep on \'$dep\' not recognised as a port\n"
                      if $Config{Warnings};
                }
            }

            if ( keys %seen ) {
                my @s;
                for my $dep ( keys %seen ) {
                    for my $d ( $allports->{$dep}->depends($accumulate_dep) ) {
                        $seen{$d}++;
                    }
                }
                @s = keys %seen;
                $self->depends( $whatdep, \@s );
            }
        }
        $self->{DEPENDENCIES_ACCUMULATED} = 2;    # Accumulation done
    } elsif ( $self->{DEPENDENCIES_ACCUMULATED} == 1 ) {

        # We've got a dependency loop
        warn "$0: Error. Dependency loop detected while processing ",
          $self->ORIGIN(), "\n";
    }
    counter($counter);
    return $self;
}

#
# Print out one line of the INDEX file
#
sub print_index ($*;$)
{
    my $self     = shift;
    my $fh       = shift;
    my $allports = shift;
    my $counter  = shift;
    my $stuff;

    # Duplicate package names are an error to 'make index'.
    if ( defined $pkgnamecache{ $self->{PKGNAME} } ) {
        warn "$0: warning duplicate package name ", $self->{PKGNAME}, " (",
          $self->{ORIGIN}, " and ", $pkgnamecache{ $self->{PKGNAME} }, ")\n"
          if $Config{Warnings};
    } else {
        $pkgnamecache{ $self->{PKGNAME} } = $self->{ORIGIN};
    }

    $stuff = $self->{STUFF};
    $stuff =~ s@\s+@ @g if ( $Config{CrunchWhitespace} );

    print $fh $self->PKGNAME(), '|';
    print $fh $self->ORIGIN(),  '|';
    print $fh $stuff, '|';
    print $fh $self->_chase_deps( $allports, 'BUILD_DEPENDS' ), '|';
    print $fh $self->_chase_deps( $allports, 'RUN_DEPENDS' ),   '|';
    print $fh $self->{WWW}, '|';
    print $fh $self->_chase_deps( $allports, 'EXTRACT_DEPENDS' ), '|';
    print $fh $self->_chase_deps( $allports, 'PATCH_DEPENDS' ),   '|';
    print $fh $self->_chase_deps( $allports, 'FETCH_DEPENDS' ),   "\n";

    counter($counter);
    return $self;
}

#
# Print out one line of the SHLIBS file
#
sub print_shlibs($*;$)
{
    my $self     = shift;
    my $fh       = shift;
    my $allports = shift;
    my $counter  = shift;

    print $fh $self->PKGNAME(), '|';
    print $fh $self->ORIGIN(),  '|';
    print $fh join( ' ', $self->LIB_DEPENDS() ), "\n";

    counter($counter);
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

    # This should be done earlier...
    for my $origin ( $self->depends( ${dep} ) ) {
        if ( defined $allports->{$origin}
            && $allports->{$origin}->can("PKGNAME") )
        {
            push @dependencies, $allports->{$origin}->PKGNAME();
        } else {
            warn "$0: ", $self->PKGNAME(),
              " No PKGNAME found for ($dep) $origin\n"
              if $Config{Warnings};
        }
    }
    return join ' ', sort @dependencies;
}

1;

#
# That's All Folks!
#
