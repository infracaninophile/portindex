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
# An object for holding various data used in creating a port -- mostly
# this is used for generating the ports INDEX.  In addition to the
# ORIGIN and MAKEFILE_LIST fields provided by the superclasses, this
# must at least have a defined PKGNAME field, and may have numerous
# other fields.
#
package FreeBSD::Portindex::Port;
use parent qw(FreeBSD::Portindex::PortsTreeObject);

use strict;
use warnings;
use Carp;
use Scalar::Util qw{blessed};

use FreeBSD::Portindex::Config qw{%Config counter _clean htmlencode};
use FreeBSD::Portindex::ListVal;

our %directorycache;    # Remember all the directories we've ever seen
our %pkgnamecache;      # Remember all of the package names we've output

sub new($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;

    croak "$0: error instantiating $class object -- PKGNAME missing\n"
      unless defined $args{PKGNAME};

    $self = $class->SUPER::new(%args);

    $self->{PKGNAME}    = $args{PKGNAME};
    $self->{PREFIX}     = $args{PREFIX};
    $self->{COMMENT}    = $args{COMMENT};
    $self->{DESCR}      = $args{DESCR};
    $self->{MAINTAINER} = $args{MAINTAINER};
    $self->{CATEGORIES} = $args{CATEGORIES};
    $self->{EXTRACT_DEPENDS} =
      FreeBSD::Portindex::ListVal->new( @{ $args{EXTRACT_DEPENDS} } );
    $self->{PATCH_DEPENDS} =
      FreeBSD::Portindex::ListVal->new( @{ $args{PATCH_DEPENDS} } );
    $self->{FETCH_DEPENDS} =
      FreeBSD::Portindex::ListVal->new( @{ $args{FETCH_DEPENDS} } );
    $self->{BUILD_DEPENDS} =
      FreeBSD::Portindex::ListVal->new( @{ $args{BUILD_DEPENDS} } );
    $self->{RUN_DEPENDS} =
      FreeBSD::Portindex::ListVal->new( @{ $args{RUN_DEPENDS} } );
    $self->{LIB_DEPENDS} =
      FreeBSD::Portindex::ListVal->new( @{ $args{LIB_DEPENDS} } );
    $self->{WWW} = $args{WWW};

    return $self;
}

# Acknowledge that $self is a port.
sub is_port($) { return 1; }

#
# Generate the same result using the values of a number of variables
# extracted from the port Makefile.  This effectively duplicates the
# code in /usr/ports/Mk/bsd.ports.mk used to produce the 'make
# describe' output. Instead of invoking perl repeatedly for all
# 22,000+ ports, we just invoke it once, plus we cache all the results
# of testing that referenced port directories exist -- so this should
# be a bit more efficient.
#
sub new_from_make_vars($$$$)
{
    my $class = shift;
    my $args  = shift;
    my $self;

    my $origin;
    my $pkgname;
    my $build_depends;
    my $run_depends;
    my $extract_depends;
    my $patch_depends;
    my $fetch_depends;
    my $lib_depends;
    my $descr;
    my $www;
    my $makefile_list;

    # %{$args} should contain the value of the following port variables:
    # PKGNAME, .CURDIR, PREFIX, COMMENT[*], DESCR, MAINTAINER,
    # CATEGORIES, EXTRACT_DEPENDS, PATCH_DEPENDS, FETCH_DEPENDS,
    # BUILD_DEPENDS, RUN_DEPENDS, LIB_DEPENDS.
    # Additionally, the file referenced by DESCR should be grepped to find
    # the WWW value.
    #
    # To the usual ports index stuff we add the extra make variable:
    # .MAKEFILE_LIST which, together with DESCR is used to control
    # incremental updating.

    ( $origin = $args->{'.CURDIR'} ) =~
      s,^($Config{RealPortsDir}|$Config{PortsDir})/?,,;
    $pkgname = $args->{PKGNAME};

    ( $descr, $www ) = _www_descr( $args->{DESCR} );

    $makefile_list =
      _makefile_list( $args->{'.MAKEFILE_LIST'}, $args->{'.CURDIR'} );

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
        PREFIX          => $args->{PREFIX},
        COMMENT         => $args->{COMMENT},
        DESCR           => $descr,
        MAINTAINER      => $args->{MAINTAINER},
        CATEGORIES      => $args->{CATEGORIES},
        EXTRACT_DEPENDS => $extract_depends,
        PATCH_DEPENDS   => $patch_depends,
        FETCH_DEPENDS   => $fetch_depends,
        BUILD_DEPENDS   => $build_depends,
        RUN_DEPENDS     => $run_depends,
        LIB_DEPENDS     => $lib_depends,
        WWW             => $www,
        MAKEFILE_LIST   => $makefile_list,
    );

    return $self;
}

#
# Clean up the path and test if the file referenced by DESCR exists --
# otherwise return /dev/null instead.  If it does exist, grep through
# it to find the WWW: reference.
#
sub _www_descr($)
{
    my $descr = shift;
    my $www   = '';

    ($descr) = _clean($descr);
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

#
# Another non-method sub: grep through the list of makefiles given in
# .MAKEFILE_LIST and strip out what it does not make sense to try and
# process.  Return a ref to the list of interesting Makefiles
#
sub _makefile_list($$$)
{
    my $makefile_list = shift;
    my $origin        = shift;

    # List all of the makefiles which affect the compilation of a
    # port.  Strip out bogus bits like '..', and make sure all path
    # names are fully qualified.  Don't bother uniquing here as that
    # will be done when this Port object is instantiated.

    return [
        map {
            s@^(?!/)@$origin/@;
            s@/[^/]+/[^/]+/\.\./\.\./@/@g;
            s@/[^/]+/\.\./@/@g;
            $_
          }
          grep {
            !m/^\.\.$/
          }
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

    foreach my $arg (
        _clean( map { ( split( /:/, $_ ) )[1] } split( /\s+/, $deplist ) ) )
    {
        next
          unless $arg;    # Leading whitespace causes a null element

        if ( !$directorycache{$arg}++ ) {
            if ( -d $arg ) {

                # Sanity check -- is the dependency on what appears to
                # be a port, rather than anything else?  The target
                # may not be in the cache yet, so guess based on the
                # file path.

                if ( $arg !~
                    m@^($Config{RealPortsDir}|$Config{PortsDir})/[^/]+/[^/]+\Z@
                  )
                {
                    warn "$0:${origin} ($pkgname) Error. $whatdep $arg ",
                      "-- dependency is not a port\n";
                    $errorflag++;
                    last;
                }
            } else {
                warn "$0:${origin} ($pkgname) Error. $whatdep $arg ",
                  "-- dependency not found\n";
                $errorflag++;
                last;
            }
        }
        $arg =~ s@^($Config{RealPortsDir}|$Config{PortsDir})/@@;
        push @deps, $arg;
    }
    return $errorflag ? undef : \@deps;
}

#
# Generic dependency accessor -- return array or array_ref of the
# named type of dependency.  If the named type doesn't exist, return
# an empty array, or a reference to such.
#
sub depends($$;$)
{
    my $self = shift;
    my $slot = shift;

    if (@_) {
        $self->{$slot}->set(@_);
    }
    return $self->{$slot}->get();
}

#
# Generic dependency modifier -- insert values into the list for the
# named dependency type.
#
sub insert($$;@)
{
    my $self = shift;
    my $slot = shift;

    if (@_) {
        $self->{$slot}->insert(@_);
    }
    return $self;
}

#
# For the given dependency, convert all of the port origins in the
# dependency list to pkgnames.
#
sub convert_to_pkgnames($$$)
{
    my $self     = shift;
    my $allports = shift;
    my $slot     = shift;

    eval {
        $self->{$slot}
          ->set( map { $allports->{$_}->PKGNAME() } $self->{$slot}->get() );
    };
    if ($@) {
        carp "Missing $slot dependency $_ for ", $self->ORIGIN(), " (",
          $self->PKGNAME(), ") -- $@\n";
    }
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
sub accumulate_dependencies($$$$$;$)
{
    my $self           = shift;
    my $allports       = shift;
    my $whatdeps       = shift;
    my $accumulate_dep = shift;
    my $recdepth       = shift;
    my $counter        = shift;

    unless ( $self->{DEPENDENCIES_ACCUMULATED} ) {
        $self->{DEPENDENCIES_ACCUMULATED} = 1;    # Accumulation in progress

        for my $thisdep ( keys %{$whatdeps} ) {
            my $seen = FreeBSD::Portindex::ListVal->new();

            # Recurse through the tree -- find the ends of any
            # dependency chains and accumulate upwards from there.
            for my $dep ( $self->depends($thisdep) ) {
                if ( defined $allports->{$dep} ) {
                    $allports->{$dep}->accumulate_dependencies(
                        $allports,       $whatdeps,
                        $accumulate_dep, $recdepth + 1
                    );

                    $seen->insert($dep);
                } else {
                    warn "$0:", $self->ORIGIN(), " (", $self->PKGNAME(),
                      ") $thisdep on \'$dep\' not recognised as a port\n"
                      if $Config{Warnings};
                }
            }

            # Convert port origins to pkg names if required.
            if ( $whatdeps->{$thisdep} ) {
                $self->convert_to_pkgnames( $allports, $thisdep );
            }

            if ( $seen->length() ) {
                for my $dep ( $seen->get() ) {
                    for my $d ( $allports->{$dep}->depends($accumulate_dep) ) {
                        $self->insert( $thisdep, $d );
                    }
                }
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
sub print_index($*$)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = shift;
    my $comment;

    # Duplicate package names are an error to 'make index'.
    if ( defined $pkgnamecache{ $self->PKGNAME() } ) {
        warn "$0: warning duplicate package name ", $self->PKGNAME(), " (",
          $self->ORIGIN(), " and ", $pkgnamecache{ $self->PKGNAME() }, ")\n"
          if $Config{Warnings};
    } else {
        $pkgnamecache{ $self->PKGNAME() } = $self->ORIGIN();
    }

    $comment = $self->COMMENT();
    $comment =~ s@\s+@ @g if ( $Config{CrunchWhitespace} );

    print $fh $self->PKGNAME(), '|';
    print $fh $Config{PortsDir}, '/', $self->ORIGIN(), '|';
    print $fh $self->PREFIX(), '|';
    print $fh $comment, '|';
    print $fh $self->DESCR(),      '|';
    print $fh $self->MAINTAINER(), '|';
    print $fh $self->CATEGORIES(), '|';
    print $fh join( ' ', $self->{BUILD_DEPENDS}->get_sorted() ), '|';
    print $fh join( ' ', $self->{RUN_DEPENDS}->get_sorted() ),   '|';
    print $fh $self->WWW(), '|';
    print $fh join( ' ', $self->{EXTRACT_DEPENDS}->get_sorted() ), '|';
    print $fh join( ' ', $self->{PATCH_DEPENDS}->get_sorted() ),   '|';
    print $fh join( ' ', $self->{FETCH_DEPENDS}->get_sorted() ),   "\n";

    counter($counter);
    return $self;
}

#
# Print out one line of the SHLIBS file
#
sub print_shlibs($*$)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = shift;

    print $fh $self->PKGNAME(), '|';
    print $fh $self->ORIGIN(),  '|';
    print $fh join( ' ', $self->{LIB_DEPENDS}->get_sorted() ), "\n";

    counter($counter);
    return $self;
}

#
# Get rid of everything except the last three parts of $descr.
# Compare the first two of these to $self->ORIGIN -- if the same,
# strip the value, otherwise prepend as many '..' elements as
# required. (Not a class method)
#
sub _make_relative ($$)
{
    my @descr  = split( m@/@, shift );
    my @origin = split( m@/@, shift );

    @descr = splice @descr, -3, 3;

    while ( @origin && $descr[0] eq $origin[0] ) {
        shift(@descr);
        shift(@origin);
    }
    for (@origin) {
        unshift( @descr, '..' );
    }
    return join( '/', @descr );
}

#
# Fill out README.html template
#
sub make_readme ($$$$)
{
    my $self     = shift;
    my $file     = shift;
    my $template = shift;
    my $subdir   = shift;    # Not used
    my $comment;
    my $descr;
    my $www;
    my $build_depends;
    my $run_depends;

    # %%PORT%%

    $template =~ s/%%PORT%%/$self->ORIGIN()/ge;

    # %%COMMENT%% -- needs HTML escapes.

    $comment = htmlencode( $self->COMMENT() );
    $template =~ s/%%COMMENT%%/$comment/ge;

    # %%PKG%%

    $template =~ s/%%PKG%%/$self->PKGNAME()/ge;

    # %%DESCR%% -- make relative to current directory.

    $descr = _make_relative( $self->DESCR(), $self->ORIGIN() );
    $template =~ s/%%DESCR%%/$descr/g;

    # %%WEBSITE%%

    $www = $self->WWW();
    if ( length($www) > 0 ) {
        $www = " and/or visit the <a href=\"$www\">web site</a>\n"
          . "     for further information.";
    }

    $template =~ s/%%WEBSITE%%/$www/ge;

    # %%EMAIL%%

    $template =~ s/%%EMAIL%%/$self->MAINTAINER()/ge;

    # %%BUILD_DEPENDS%% -- as pkgnames

    $build_depends = join( ' ', $self->{BUILD_DEPENDS}->get_sorted() );
    if ( length($build_depends) > 0 ) {
        $build_depends =
          "This port requires package(s) \"$build_depends\" to build.\n";
    }
    $template =~ s/%%BUILD_DEPENDS%%/$build_depends/g;

    # %%RUN_DEPENDS%% -- as pkgnames

    $run_depends = join( ' ', $self->{RUN_DEPENDS}->get_sorted() );
    if ( length($run_depends) > 0 ) {
        $run_depends =
          "This port requires package(s) \"$run_depends\" to run.\n";
    }
    $template =~ s/%%RUN_DEPENDS%%/$run_depends/g;

    # %%TOP%% -- PORTSDIR relative to here (why is this a template
    # variable?)

    $template =~ s@%%TOP%%@../..@g;

    return $self->SUPER::make_readme( $file, $template );
}

#
# Bulk creation of accessor methods -- SCALARs.
#
for my $slot (
    qw(PKGNAME PREFIX COMMENT DESCR MAINTAINER CATEGORIES
    WWW DEPENDENCIES_ACCUMULATED )
  )
{
    no strict qw(refs);

    *$slot = __PACKAGE__->scalar_accessor($slot);
}

#
# Bulk creation of accessor methods -- ARRAYs.  These are all
# instantiated as FreeBSD::Portindex::ListVal objects.
#
for my $slot (
    qw(BUILD_DEPENDS RUN_DEPENDS EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS
    LIB_DEPENDS)
  )
{
    no strict qw(refs);

    *$slot = __PACKAGE__->list_val_accessor($slot);
}

1;

#
# That's All Folks!
#
