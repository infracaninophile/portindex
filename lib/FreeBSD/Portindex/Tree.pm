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
# @(#) $Id: Tree.pm,v 1.18 2004-10-17 09:57:13 matthew Exp $
#

#
# Container for FreeBSD::Ports objects which models the entire ports
# tree -- indexed by port directories.  Persistence is supplied by
# using BerkeleyDB Btree for backing stores.
#
package FreeBSD::Ports::Tree;
our $VERSION = 0.01;

use strict;
use warnings;
use Carp;
use BerkeleyDB;    # BDB version 2, 3, 4, 41, 42
use Storable qw(freeze thaw);

use FreeBSD::Port;

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;
    my $portscachefile  = $::Config{CacheFilename};
    my $masterslavefile = $::Config{MasterSlaveFilename};

    # Make sure that the certain defaults are set.

    if ( defined $args{-CacheFilename} ) {
        $portscachefile = $args{-CacheFilename};
        delete $args{-CacheFilename};
    }

    if ( defined $args{-MasterSlaveFilename} ) {
        $masterslavefile = $args{-MasterSlaveFilename};
        delete $args{-MasterSlaveFilename};
    }

    $args{-Mode} = 0640
      unless defined $args{-Mode};
    $args{-Flags} = 0
      unless defined $args{-Flags};

    $self = {
        PORTS        => {},
        MASTER_SLAVE => {},
    };

    # Must turn on the DB locking system if we're storing more than
    # one DB per file.

    $self->{ENV} = new BerkeleyDB::Env
      -Flags      => DB_CREATE | DB_INIT_LOCK | DB_INIT_MPOOL,
      -LockDetect => DB_LOCK_DEFAULT,
      %{ $args{-Env} };
    delete $args{-Env};

    # Tie the PORTS and MASTER_SLAVE hashes to our cache file -- a DB
    # btree file.  Keep to DBs in this cache -- the PORTS data, plus
    # the data about master/slave relationships.

    tie %{ $self->{PORTS} }, 'BerkeleyDB::Btree',
      -Env => $self->{ENV},
      %args,
      -Filename => $portscachefile
      or croak __PACKAGE__,
      "::new(): Can't access $portscachefile -- $!";

    tie %{ $self->{MASTERSLAVE} }, 'BerkeleyDB::Btree',
      -Env => $self->{ENV},
      %args,
      -Filename => $masterslavefile
      or croak __PACKAGE__,
      "::new(): Can't access $masterslavefile -- $!";

    return bless $self, $class;
}

sub DESTROY
{
    my $self = shift;

    untie $self->{PORTS};
    untie $self->{MASTERSLAVE};
    undef $self;
}

# Insert FreeBSD::Port object (ie. from 'make describe' output) into
# ports tree structure according to the ORIGIN -- freeze the object
# for external storage.
sub insert ($$$)
{
    my $self   = shift;
    my $origin = shift;
    my $port   = shift;

    $self->{PORTS}->{$origin} = freeze($port);

    return $self;
}

# Return the cached FreeBSD::Port object for a given origin path,
# deleting the frozen version from the tree hash.  Return undef if
# port not found in tree
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

# Declare that $slave origin uses $master as it's MASTERDIR.  Just an
# assignment to a hash; hardly worth wrapping in a function really.
sub enslave ($$$)
{
    my $self   = shift;
    my $master = shift;
    my $slave  = shift;

    $self->{MASTERSLAVE}->{$slave} = $master;
    return $self;
}

# Remove the given $slave origin as a slave of any MASTERDIR.  Again,
# just deleting an entry from a hash; hardly worth wrapping in a
# function really.
sub manumit ($$)
{
    my $self  = shift;
    my $slave = shift;

    delete $self->{MASTERSLAVE}->{$slave};
    return $self;
}

# Build the tree structure by scanning through the Makefiles of the
# ports tree.  This is equivalent to the first part of 'make index' #
# Recurse through all of the Makefiles -- expand the SUBDIR argument
# from each Makefile, and all of the Makefiles in the referenced
# directories.  If no SUBDIRs are found, this is a leaf directory, in
# which case use 'make describe' and cache that output for later
# processing
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
    my @subdirs;

    # Hmmm... Using make(1) to print out the value of the variable
    # (make -V SUBDIRS) takes about 200 times as long as just scanning
    # the Makefiles for definitions of the SUBDIR variable.  Be picky
    # about the format of the SUBDIR assignment lines: SUBDIR is used
    # in some of the leaf Makefiles, but in a different style.

    open( MAKEFILE, '<', "${path}/Makefile" )
      or do {
        carp __PACKAGE__,
          "::_scan_makefiles(): Can't open Makefile in $path -- $!";

        # If $path does not exist, or if there's no Makefile there,
        # then make sure anything corresponding to $path is deleted
        # from the cache.

        if ( $self->manumit($path)->delete($path) ) {
            carp __PACKAGE__, "::_scan_makefiles():$path: deleted from cache";
        }
        return $self;    # Leave out this directory.
      };
    while (<MAKEFILE>) {
        push @subdirs, "${path}/${1}"
          if (m/^\s*SUBDIR\s+\+=\s+(\S+)\s*$/);
    }
    close MAKEFILE
      or do {

        # Even if the close() errors out, we've got this far, so
        # might as well carry on and try and process any output.

        carp __PACKAGE__, "::_scan_makefiles():$path: ",
          $! ? "close failed -- $!" : "make: bad exit status -- $?";
      };

    if (@subdirs) {
        for my $subdir (@subdirs) {
            $self->_scan_makefiles( $subdir, $counter );
        }
    } else {

        # This is a real port directory, not a subdir.
        $self->make_describe( $path, $counter );
    }
    return $self;
}

# Run 'make describe' -- takes the port directory as an argument, and
# runs make describe in it.  Changes current working directory of the
# process: bails out without updating tree if no such directory or
# other problems.
sub make_describe($$;$)
{
    my $self    = shift;
    my $path    = shift;
    my $counter = shift;
    my $desc;
    my $masterdir;

    chdir $path
      or do {
        carp __PACKAGE__, "::make_describe():$path: can't chdir() -- $!";

        # Make sure old cruft is deleted
        if ( $self->manumit($path)->delete($path) ) {
            carp __PACKAGE__, "::make_describe():$path -- deleted from cache";
        }
        return $self;
      };
    open MAKE, '/usr/bin/make describe|'
      or do {
        carp __PACKAGE__, "::make_describe():$path: can't run make -- $!";
        return $self;
      };
    $desc = <MAKE>;
    close MAKE
      or do {
        carp __PACKAGE__, "::make_describe():$path: ",
          ( $! ? "close failed -- $!" : "make: bad exit status -- $?" );

        # There's a Makefile, but it's not a valid port.
        if ( $? && $self->manumit($path)->delete($path) ) {
            carp __PACKAGE__, "::make_describe():$path -- deleted from cache";
        }
        return $self;
      };

    if ( $::Config{Verbose} && ref $counter ) {
        $$counter++;
        if ( $$counter % 1000 == 0 ) {
            print STDERR "[$$counter]";
        } elsif ( $$counter % 100 == 0 ) {
            print STDERR '.';
        }
    }

    $self->insert( $path, FreeBSD::Port->new_from_description($desc) );

    # Now do almost the same again, to extract the MASTERDIR value so
    # we can tell if this is a slave port or not.

    open MAKE, '/usr/bin/make -V MASTERDIR|'
      or do {
        carp __PACKAGE__, "::make_describe():$path: can't run make again -- $!";
        return $self;
      };
    $masterdir = <MAKE>;
    close MAKE
      or do {
        carp __PACKAGE__, "::make_describe():$path: ",
          ( $! ? "close failed -- $!" : "make: bad exit status -- $?" );
      };

    # Clean up various objectionable constructs -- see
    # FreeBSD::Port::_clean_depends() where the same thing is done to
    # port dependencies as well.

    chomp($masterdir);
    $masterdir =~ s@/\w[^/]+/\w[^/]+/\.\./\.\./@/@g;
    $masterdir =~ s@/\w[^/]+/\.\./@/@g;
    $masterdir =~ s@/\Z@@g;

    if ( $masterdir ne $path ) {
        $self->enslave( $masterdir, $path );
    } else {
        $self->manumit($path);
    }
    return $self;
}

# Unpack all of the frozen FreeBSD::Ports objects from the btree
# storage.  Return a reference to a hash containing refs to all port
# objects. (Note: 'each' passes values by reference (implicitly) --
# modifying the returned value will affect the underlying hash)
sub springtime($$)
{
    my $self     = shift;
    my $allports = shift;

    while ( my ( $origin, $port ) = each %{ $self->{PORTS} } ) {
        $allports->{$origin} = thaw($port);
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

    while ( my ( $slave, $master ) = each %{ $self->{MASTERSLAVE} } ) {

        #print STDERR "Slave: $slave  Master: $master\n"
        #    if $::Config{Verbose};

        $masterslave->{$master} = []
          unless defined $masterslave->{$master};
        push @{ $masterslave->{$master} }, $slave;
    }
    return $masterslave;
}

# For all of the known ports, accumulate the various dependencies as
# required for the INDEX file.  See
# FreeBSD::Port::accumulate_dependencies() for details.
sub accumulate_dependencies($$)
{
    my $self     = shift;
    my $allports = shift;
    my $counter  = 0;

    print STDERR "Accumulating dependency information: "
      if ( $::Config{Verbose} );
    for my $port ( values %{$allports} ) {
        $port->accumulate_dependencies( $allports, \$counter );
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
