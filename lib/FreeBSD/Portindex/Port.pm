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
# @(#) $Id: Port.pm,v 1.8 2004-10-08 21:17:03 matthew Exp $
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

# Ports should be uniquely identified by pkgname
our (%index);

sub new ($@)
{
    my $caller = shift;
    my $class = ref($caller) || $caller;
    my $self;
    my %args = @_;

    croak __PACKAGE__, "::new() -- PKGNAME missing"
      unless defined $args{PKGNAME};

    if ( defined $index{ $args{PKGNAME} } ) {
        $self = $index{ $args{PKGNAME} };
        %{$self} = ( %{$self}, %args );
    } else {
        $self = $index{ $args{PKGNAME} } = \%args;
    }

    bless $self, $class;

    for my $dep (
        qw( EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS BUILD_DEPENDS
        RUN_DEPENDS )
      )
    {

        # If the hash key has not yet been created, don't do anything
        if ( exists $self->{$dep} ) {
            if ( !defined $self->{$dep} ) {
                $self->{$dep} = [];    # Empty list
            } elsif ( !ref $self->{$dep} ) {
                $self->{$dep} = [ split / /, $self->{$dep} ];
            }
        }
    }
    return $self;
}

sub DESTROY ($)
{
    my $self = shift;

    delete $index{ $self->PKGNAME() };
    undef $self;
    return;
}

# Take the string returned by 'make describe' or read as one line out
# of INDEX and use it to populate a pkg object
sub new_from_indexline($$)
{
    my $caller = shift;
    my $desc   = shift;
    my $self;

    my $pkgname;
    my $origin;
    my $stuff;
    my $build_depends;
    my $run_depends;
    my $www;
    my $extract_depends;
    my $patch_depends;
    my $fetch_depends;

    chomp($desc);

    (
        $pkgname,         $origin,        $stuff,
        $build_depends,   $run_depends,   $www,
        $extract_depends, $patch_depends, $fetch_depends
      )
      = (
        $desc =~ m{
			 ^([^|]+)\|          # PKGNAME
	          ([^|]+)\|          # ORIGIN
	          ((?:[^|]*\|){4}[^|]*)\|
			                     # PREFIX,COMMENT,DESCR,MAINTAINER,CATEGORIES
	          ([^|]*)\|          # BUILD_DEPENDS
	          ([^|]*)\|          # RUN_DEPENDS
	          ([^|]*)\|          # WWW
	          ([^|]*)\|          # EXTRACT_DEPENDS
	          ([^|]*)\|          # PATCH_DEPENDS
	          ([^|]*)$           # FETCH_DEPENDS
		  }x
      )
      or croak __PACKAGE__, "::new_from_indexline():$.: -- incorrect format";

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

# This is very similar to new_from_indexline, except it uses the
# output from 'make describe'.  Format is very similar to an index
# line, except that the fields are in a different (more sendsible)
# order, and the dependencies are given using the port ORIGIN, rather
# than PKGNAME.  Only the immediate dependencies of any port are
# given, not the cumulative dependencies of the port and all of its
# dependencies, etc.  Transforming the ORIGIN lines into the usual form
# has to wait until all the port objects have been created.
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
      or croak __PACKAGE__, "::new_from_makedescribe: -- incorrect format";

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

# Use the $tree hash to convert package dependency lists from ORIGINs
# to PKGNAMEs
sub origin_to_pkgname ($$@)
{
    my $self = shift;
    my $tree = shift;
    my @deps = @_;
    my $translated;

    for my $dep (@deps) {
        $translated = [];

        for my $origin ( @{ $self->$dep() } ) {
            my $p = $tree->get($origin);

            if ( defined $p ) {
                push @{$translated}, $p->PKGNAME();
            } else {
                carp __PACKAGE__, "::origin_to_pathname(): ",
                  "Can't find package with origin $origin";
            }
        }
        $self->$dep($translated);
    }
    return $self;
}

# Another variant using 'make describe' -- this one takes the port
# directory as an argument, and runs make sescribe in it.  Changes
# current working directory of the process: croaks if no such
# directory.
sub new_from_make_describe($$)
{
    my $caller = shift;
    my $path   = shift;
    my $self;
    my $desc;

    chdir $path
      or croak __PACKAGE__, "::new_from_make_describe(): can't chdir() -- $!";
    open MAKE, '/usr/bin/make describe|'
      or croak __PACKAGE__, "::new_from_make_describe(): can't run make -- $!";
    $desc = <MAKE>;
    close MAKE
      or croak __PACKAGE__, "::new_from_make_describe(): ",
      ( $! ? "close failed -- $!" : "make: bad exit status -- $?" );

    return $caller->new_from_description($desc);
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
    my $counter = shift;

    print $fh $self->PKGNAME(), '|';
    print $fh $self->ORIGIN(),  '|';
    print $fh $self->STUFF(),   '|';
    print $fh $self->_chase_deps('BUILD_DEPENDS'), '|';
    print $fh $self->_chase_deps('RUN_DEPENDS'),   '|';
    print $fh $self->WWW(), '|';
    print $fh $self->_chase_deps('EXTRACT_DEPENDS'), '|';
    print $fh $self->_chase_deps('PATCH_DEPENDS'),   '|';
    print $fh $self->_chase_deps('FETCH_DEPENDS'),   "\n";

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

# Turn the list of references to hashes, which are the dependencies
# (of the specified type) for this package into a list of package
# names.
sub _chase_deps($$)
{
    my $self = shift;
    my $dep  = shift;

    return join ' ', @{ $self ->${dep}() };
}

# Create the inverse dependency lists for each package: that is, the
# list of packages that depend on this one in order to build, run,
# etc.  dependency on it.  $dep is a hash key -- one of BUILD_DEPENDS,
# RUN_DEPENDS, EXTRACT_DEPENDS, PATCH_DEPENDS, FETCH_DEPENDS -- which
# we invert to create links from the dependencies' FOO_INVERSE entry
# to $self.  Ie. FOO_INVERSE is a list of the ports which have a FOO
# dependency on this one.
sub invert_dependencies($$)
{
    my $self    = shift;
    my $dep     = shift;
    my $pkgname = $self->PKGNAME();

    my $other;
    my $inverse_dep;
    my $i;

    ( $inverse_dep = $dep ) =~ s/DEPENDS/INVERSE/;

    foreach my $dependency ( @{ $self ->${dep}() } ) {
        unless ( defined $index{$dependency} ) {
            carp __PACKAGE__, "::invert_dependencies(): $pkgname claims ",
              "$dependency as a $dep, but $dependency is unknown";
        }
        $other = $index{$dependency};

        if ( $other ->${inverse_dep}() ) {

            # Insert the upreference into the
            # $dependency->{$inverse_dep} list so that the list
            # remains sorted by $pkgname

            $i = 0;    # Index at which to make insertion
            foreach my $dependent ( @{ $other ->${inverse_dep}() } ) {
                if ( $dependent eq $pkgname ) {

                    # Already in the list
                    last;
                }
                if ( $dependent gt $pkgname ) {

                    # Add before this entry...
                    splice( @{ $other ->${inverse_dep}() }, $i, 0, $pkgname );
                    last;
                }
                $i++;
            }
        } else {

            # It's easy to order a list of one thing...
            $other ->${inverse_dep}( [$pkgname] );
        }
    }
    print STDERR "Inverted $dep dependencies of $pkgname\n"
      if $::verbose;
    return $self;
}

1;

#
# That's All Folks!
#
