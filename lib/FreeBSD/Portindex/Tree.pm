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
# @(#) $Id: Tree.pm,v 1.48 2006-05-14 20:03:35 matthew Exp $
#

#
# Container for FreeBSD::Portindex::Ports objects which models the
# entire ports tree -- indexed by port directories.  Persistence is
# supplied by using BerkeleyDB Btree for backing stores.
#
package FreeBSD::Portindex::Tree;
our $VERSION = '1.6';    # Release

use strict;
use warnings;
use Carp;
use BerkeleyDB;          # BDB version 2, 3, 4, 41, 42, 43, 44
use Storable qw(freeze thaw);

use FreeBSD::Portindex::Port;
use FreeBSD::Portindex::Config qw{counter};

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;
    my $portscachefile = $::Config{CacheFilename};

    # Make sure that the certain defaults are set.

    if ( defined $args{-CacheFilename} ) {
        $portscachefile = $args{-CacheFilename};
        delete $args{-CacheFilename};
    }

    $args{-Mode} = 0640
      unless defined $args{-Mode};
    $args{-Flags} = 0
      unless defined $args{-Flags};

    $self = { PORTS => {}, };

    # Must turn on the DB locking system if we're storing more than
    # one DB per file.

    $self->{ENV} = new BerkeleyDB::Env
      -Flags => DB_CREATE | DB_INIT_MPOOL | DB_INIT_LOCK,
      -Home  => $::Config{CacheDir},
      %{ $args{-Env} };
    delete $args{-Env};

    # Tie the PORTS hashes to our cache file -- a DB btree file.  Keep
    # two DBs in this cache -- the PORTS data, plus the data about
    # master/slave relationships and the MAKEFILE_LIST stuff.

    tie %{ $self->{PORTS} }, 'BerkeleyDB::Btree',
      -Env => $self->{ENV},
      %args,
      -Filename => $portscachefile
      or croak __PACKAGE__,
      "::new(): Can't access $portscachefile -- $! $BerkeleyDB::Error";

    # Save some regex definitions for use in the various
    # make_describe() methods.

    # Directories where ports-specific Makefiles are found.  Ignore
    # the effect of any Makefile not matching these locations.
    # Although other locations do contain Makefiles that will affect
    # the result, those generally do not change that often, and tend
    # to have minimal material effect on the final result.

    $self->{MAKEFILE_LOCATIONS} = qr{
        \A
            (
             /var/db/ports
             |
             \Q$::Config{PortsDir}\E
             )           
        }x;

    # Makefiles for which we ignore changes when producing the list of
    # ports needing updating, and which aren't recorded as included
    # Makefiles in the cache.  Either because changes to that file
    # tend to have no effect on the final INDEX, or because changes to
    # the file trigger update checks on too many (generally /all/)
    # ports -- in which case a cache-init run is indicated

    my $me = '\A('
      . join( '|',
        map { quotemeta } @{ $::Config{UbiquitousMakefiles} },
        @{ $::Config{EndemicMakefiles} } )
      . ')\Z';
    $self->{MAKEFILE_EXCEPTIONS} = qr{$me};

    return bless $self, $class;
}

sub DESTROY
{
    my $self = shift;

    untie $self->{PORTS};
    undef $self;
}

# Insert FreeBSD::Portindex::Port object (ie. from 'make describe'
# output) into ports tree structure according to the ORIGIN -- freeze
# the object for external storage.
sub insert ($$$)
{
    my $self   = shift;
    my $origin = shift;
    my $port   = shift;

    $self->{PORTS}->{$origin} = freeze($port);

    return $self;
}

# Return the cached FreeBSD::Portindex::Port object for a given origin
# path, deleting the frozen version from the tree hash.  Return undef
# if port not found in tree
sub delete ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;

    $port = $self->{PORTS}->{$origin};
    if ( defined $port ) {
        delete $self->{PORTS}->{$origin};
        $port = thaw($port);
    }
    return $port;
}

# Return the cached port description for a given origin path.  Return
# undef if port not found in tree.
sub get ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;

    $port = $self->{PORTS}->{$origin};
    $port = thaw($port)
      if ( defined $port );
    return $port;
}

# Build the tree structure by scanning through the Makefiles of the
# ports tree.  This is equivalent to the first part of 'make index' #
# Recurse through all of the Makefiles -- expand the SUBDIR argument
# from each Makefile, and all of the Makefiles in the referenced
# directories.  If no SUBDIRs are found, but various other make
# variable are set, then this is a leaf directory, in which case use
# 'make describe' and cache that output for later processing.
sub scan_makefiles($@)
{
    my $self    = shift;
    my @paths   = @_;
    my $counter = 0;

    print STDERR "Processing make describe output",
      @paths == 1 ? " for path \"$paths[0]\": " : ": "
      if ( $::Config{Verbose} );
    for my $path (@paths) {
        $self->_scan_makefiles( $path, \$counter );
    }
    print STDERR "<$counter>\n"
      if ( $::Config{Verbose} );
    return $self;
}

sub _scan_makefiles($$;$)
{
    my $self    = shift;
    my $path    = shift;
    my $counter = shift;
    my $isPort  = 0;
    my @subdirs;

    # Hmmm... Using make(1) to print out the value of the variable
    # (make -V SUBDIRS) takes about 200 times as long as just scanning
    # the Makefiles for definitions of the SUBDIR variable.  Be picky
    # about the format of the SUBDIR assignment lines: SUBDIR is used
    # in some of the leaf Makefiles, but in a different style.

    open( MAKEFILE, '<', "${path}/Makefile" )
      or do {

        # If $path does not exist, or if there's no Makefile there,
        # then make sure anything corresponding to $path is deleted
        # from the cache.

        if ( $self->delete($path) ) {
            warn __PACKAGE__, "::_scan_makefiles():$path: deleted from cache\n";
        } else {
            warn __PACKAGE__,
              "::_scan_makefiles(): Can't open Makefile in $path -- $!\n";
        }
        return $self;    # Leave out this directory.
      };
    while (<MAKEFILE>) {
        if (m/(PORTNAME|MASTERDIR|MASTER_PORT)/) {

            # Ooops.  This directory actually contains a port rather than
            # structural stuff.

            $isPort = 1;
            last;
        }
        push @subdirs, "${path}/${1}"
          if (m/^\s*SUBDIR\s\+=\s(\S+)\s*(#.*)?$/);
    }
    close MAKEFILE
      or do {

        # Even if the close() errors out, we've got this far, so
        # might as well carry on and try and process any output.

        warn __PACKAGE__,
          "::_scan_makefiles():$path/Makefile: close failed -- $!\n";
      };

    # bsd.ports.subdir.mk will automatically include Makefile.local
    # if it exists, which permits locally added ports or categories
    # Just append any SUBDIR settings onto the ones read from the
    # standard Makefile

    if ( !$isPort && -e "${path}/Makefile.local" ) {
      MAKEFILE_LOCAL: {
            open( MAKEFILE, '<', "${path}/Makefile.local" )
              or do {

                # We can't read Makefile.local.  So just ignore it
                warn __PACKAGE__,
"::_scan_makefiles():$path: Makefile.local unreadable -- $!\n";
                last MAKEFILE_LOCAL;
              };
            while (<MAKEFILE>) {
                push @subdirs, "${path}/${1}"
                  if (m/^\s*SUBDIR\s*\+=\s*(\S+)\s*(#.*)?$/);
            }
            close MAKEFILE
              or do {

                # Even if the close() errors out, we've got this far, so
                # might as well carry on and try and process any output.

                warn __PACKAGE__,
"::_scan_makefiles():$path/Makefile.local: close failed -- $!\n";
              };
        }
    }

    if ( !$isPort && @subdirs ) {
        for my $subdir (@subdirs) {
            $self->_scan_makefiles( $subdir, $counter );
        }
    } elsif ($isPort) {

        # This is a real port directory, not a subdir.
        $self->make_describe_newstyle( $path, $counter );
    }
    return $self;
}

# Run 'make describe' -- takes the port directory as an argument, and
# runs make describe in it.  Changes current working directory of the
# process: bails out without updating tree if no such directory or
# other problems. Deal gracefully with the case where the Makefile
# without SUBDIR entries is a new category (non-leaf) Makefile,
# without any ports in that category yet -- in which case, 'make
# describe' will succeed but return no output.
sub make_describe_oldstyle($$;$)
{
    my $self    = shift;
    my $path    = shift;
    my $counter = shift;
    my $desc;
    my $masterdir;
    my $makefile_list;
    my $port;

    chdir $path
      or do {

        # Make sure old cruft is deleted
        if ( $self->delete($path) ) {
            warn __PACKAGE__, "::make_describe():$path -- deleted from cache\n";
        } else {
            warn __PACKAGE__, "::make_describe():$path: can't chdir() -- $!\n";
        }
        return $self;
      };
    open MAKE, '/usr/bin/make describe|'
      or do {
        warn __PACKAGE__, "::make_describe():$path: can't run make -- $!\n";
        return $self;
      };
    $desc = <MAKE>;
    close MAKE
      or do {

        # There's a Makefile, but it's not a valid port.
        if ( $? && $self->delete($path) ) {
            warn __PACKAGE__, "::make_describe():$path -- deleted from cache\n";
        } else {
            warn __PACKAGE__, "::make_describe():$path: ",
              ( $! ? "close failed -- $!\n" : "make: bad exit status -- $?\n" );
        }
        return $self;
      };

    return $self
      unless ( defined $desc && $desc !~ m/\A\s*\Z/ );

    counter( \%::Config, $counter );

    $port = FreeBSD::Portindex::Port->new_from_description($desc)
      or die __PACKAGE__,
      "::make_describe():$path -- couldn't parse description $desc\n";

    # Now do almost the same again, to extract the MASTERDIR value (so
    # we can tell if this is a slave port or not) and the .MAKEFILE_LIST value
    # so we can trigger an update if an included Makefile is modified.

    open MAKE, '/usr/bin/make -V MASTERDIR -V .MAKEFILE_LIST|'
      or do {
        warn __PACKAGE__,
          "::make_describe():$path: can't run make again -- $!\n";
        return $self;
      };
    $masterdir     = <MAKE>;
    $makefile_list = <MAKE>;
    close MAKE
      or do {
        warn __PACKAGE__, "::make_describe():$path: ",
          ( $! ? "close failed -- $!\n" : "make: bad exit status -- $?\n" );
      };

    $port->masterdir($masterdir);
    $port->makefile_list(
        $makefile_list,
        $self->{MAKEFILE_LOCATIONS},
        $self->{MAKEFILE_EXCEPTIONS}
    );
    $self->insert( $path, $port );

    return $self;
}

# Generate the port description without actually running 'make
# describe'.  Instead, extract the values of a series of variables
# that are processed during 'make describe', and perform equivalent
# processing ourselves.  Changes current working directory of the
# process: bails out without updating tree if no such directory or
# other problems. Deal gracefully with the case where the Makefile
# without SUBDIR entries is a new category (non-leaf) Makefile,
# without any ports in that category yet -- in which case, 'make
# describe' will succeed but return no output.
sub make_describe_newstyle($$;$)
{
    my $self    = shift;
    my $path    = shift;
    my $counter = shift;
    my $make_command;
    my $port;

    my @make_var_list = qw{
      PKGNAME
      .CURDIR
      PREFIX
      COMMENT
      DESCR
      MAINTAINER
      CATEGORIES
      EXTRACT_DEPENDS
      PATCH_DEPENDS
      FETCH_DEPENDS
      BUILD_DEPENDS
      RUN_DEPENDS
      DEPENDS
      LIB_DEPENDS
      MASTERDIR
      .MAKEFILE_LIST
    };
    my %make_vars;

    chdir $path
      or do {

        # Make sure old cruft is deleted
        if ( $self->delete($path) ) {
            warn __PACKAGE__, "::make_describe():$path -- deleted from cache\n";
        } else {
            warn __PACKAGE__, "::make_describe():$path: can't chdir() -- $!\n";
        }
        return $self;
      };

    # Run make, extracting the values of our list of variables into a
    # hash.  The values will be printed out one per line in the same
    # order they are given on the command line.

    $make_command = '/usr/bin/make -V' . join( ' -V ', @make_var_list ) . '|';

    open MAKE, $make_command
      or do {
        warn __PACKAGE__, "::make_describe():$path: can't run make -- $!\n";
        return $self;
      };
    foreach my $mv (@make_var_list) {
        chomp($make_vars{$mv} = <MAKE>);
    }
    close MAKE
      or do {

        # There's a Makefile, but it's not a valid port.
        if ( $? && $self->delete($path) ) {
            warn __PACKAGE__, "::make_describe():$path -- deleted from cache\n";
        } else {
            warn __PACKAGE__, "::make_describe():$path: ",
              ( $! ? "close failed -- $!\n" : "make: bad exit status -- $?\n" );
        }
        return $self;
      };

    counter( \%::Config, $counter );

    $port = FreeBSD::Portindex::Port->new_from_make_vars(%make_vars)
      or die __PACKAGE__,
      "::make_describe():$path -- error parsing make output -- $!\n";

    $port->masterdir( $make_vars{MASTERDIR} );
    $port->makefile_list(
        $make_vars{'.MAKEFILE_LIST'},
        $self->{MAKEFILE_LOCATIONS},
        $self->{MAKEFILE_EXCEPTIONS}
    );
    $self->insert( $path, $port );

    return $self;
}

# Unpack all of the frozen FreeBSD::Portindex::Ports objects from the
# btree storage.  Return a reference to a hash containing refs to all
# port objects. (Note: 'each' passes values by reference (implicitly)
# -- modifying the returned value will affect the underlying hash)
sub springtime($$)
{
    my $self     = shift;
    my $allports = shift;

    while ( my ( $origin, $port ) = each %{ $self->{PORTS} } ) {
        $allports->{$origin} = thaw($port);
    }
    return $allports;
}

# Fill in the referenced hash with a list of all known ports (as keys)
# and zero as values.
sub port_origins($$)
{
    my $self     = shift;
    my $allports = shift;

    while ( my ( $origin, $port ) = each %{ $self->{PORTS} } ) {
        $allports->{$origin} = 0;
    }
    return $allports;
}

# Invert all of the slave => master hash relationships, returning a
# reference to a hash whose keys are the master port origins, and
# whose values are refs to arrays of slave port origins.
sub masterslave($$)
{
    my $self        = shift;
    my $masterslave = shift;

    while ( my ( $origin, $port ) = each %{ $self->{PORTS} } ) {
        $port = thaw($port);

        next unless $port->MASTERDIR();

        #print STDERR "Slave: $slave  Master: $master\n"
        #    if $::Config{Verbose};

        $masterslave->{ $port->MASTERDIR() } = []
          unless defined $masterslave->{ $port->MASTERDIR() };
        push @{ $masterslave->{ $port->MASTERDIR() } }, $origin;
    }
    return $masterslave;
}

# Another form of inversion: invert the .MAKEFILE_LIST data, returning
# a hash with keys being the various Makefiles and targets being an
# array of port origins depending on those Makefiles.
sub makefile_list ($$)
{
    my $self          = shift;
    my $makefile_list = shift;

    while ( my ( $origin, $port ) = each %{ $self->{PORTS} } ) {
        $port = thaw($port);

        for my $makefile ( @{ $port->MAKEFILE_LIST() } ) {
            $makefile_list->{$makefile} = []
              unless defined $makefile_list->{$makefile};
            push @{ $makefile_list->{$makefile} }, $origin;
        }
    }
    return $makefile_list;
}

# For all of the known ports, accumulate the various dependencies as
# required for the INDEX file.  See
# FreeBSD::Portindex::Port::accumulate_dependencies() for details.
sub accumulate_dependencies($$)
{
    my $self     = shift;
    my $allports = shift;
    my $counter  = 0;

    print STDERR "Accumulating dependency information: "
      if ( $::Config{Verbose} );
    for my $port ( values %{$allports} ) {
        $port->accumulate_dependencies( $allports, 0, \$counter );
    }
    print STDERR "<${counter}>\n" if ( $::Config{Verbose} );

    return $self;
}

# Print out whole INDEX file sorted by ORIGIN using $tree hash: since
# this is stored as a BerkeleyDB Btree, it comes out already sorted
sub print_index($$*)
{
    my $self     = shift;
    my $allports = shift;
    my $fh       = shift;
    my $counter  = 0;

    print STDERR "Writing INDEX file: " if ( $::Config{Verbose} );

    while ( my ( $origin, $port ) = each %{ $self->{PORTS} } ) {
        $allports->{$origin}->print( $fh, $allports, \$counter );
    }
    print STDERR "<${counter}>\n" if ( $::Config{Verbose} );

    return $self;
}

1;

#
# That's All Folks!
#
