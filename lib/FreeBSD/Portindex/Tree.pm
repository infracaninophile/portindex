# Copyright (c) 2004-2008 Matthew Seaman. All rights reserved.
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
# @(#) $Id: Tree.pm,v 1.75 2009-04-26 19:13:53 matthew Exp $
#

#
# Container for FreeBSD::Portindex::Ports objects which models the
# entire ports tree -- indexed by port directories.  Persistence is
# supplied by using BerkeleyDB Btree for backing stores.
#
package FreeBSD::Portindex::Tree;
our $VERSION       = '2.1';    # Release
our $CACHE_VERSION = '2.0';    # Earliest binary compat version

use strict;
use warnings;
use BerkeleyDB;                # BDB version 2, 3, 4, 41, 42, 43, 44, 45, 46

use FreeBSD::Portindex::Port;
use FreeBSD::Portindex::Category;
use FreeBSD::Portindex::Config qw{counter freeze thaw};

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;
    my $portscachefile  = $::Config{CacheFilename};
    my $cachewascreated = 0;

    # Make sure that the certain defaults are set.

    if ( defined $args{-CacheFilename} ) {
        $portscachefile = "$::Config{CacheDir}/$args{-CacheFilename}";
        delete $args{-CacheFilename};
    }

    $args{-Mode} = 0640
      unless defined $args{-Mode};
    $args{-Flags} = 0
      unless defined $args{-Flags};

    $self = { PORTS => {}, };

    # Test if the cache file name already exists.  If there is
    # already a file there, then after we tie to it, check for
    # a __CACHE_VERSION entry.  If this is a new file, insert
    # the __CACHE_VERSION.

    $cachewascreated = 1 unless ( -e "$portscachefile" );

    # Must turn on the DB locking system if we're storing more than
    # one DB per file.

    $self->{ENV} = new BerkeleyDB::Env
      -Flags => DB_CREATE | DB_INIT_MPOOL | DB_INIT_CDB,
      -Home  => $::Config{CacheDir},
      %{ $args{-Env} };
    delete $args{-Env};

    # Tie the PORTS hashes to our cache file -- a DB btree file.  Keep
    # two sets of data in this objects in this cache -- the PORTS
    # data, plus the CATEGORY.  PORTS objects contain the data about
    # master/slave relationships (the MAKEFILE_LIST and the
    # MASTER_PORT stuff).

    tie %{ $self->{PORTS} }, 'BerkeleyDB::Btree',
      -Env => $self->{ENV},
      %args, -Filename => $portscachefile
      or die "$0: Can\'t access $portscachefile -- $! $BerkeleyDB::Error";

    # Set the cache version number on creation.  Test the cache
    # version number if we're re-opening a pre-existing cache, and
    # make sure it's compatible.

    if ($cachewascreated) {
        $self->{PORTS}->{__CACHE_VERSION} = $VERSION;
    } else {
        unless ( exists $self->{PORTS}->{__CACHE_VERSION}
            && $self->{PORTS}->{__CACHE_VERSION} >= $CACHE_VERSION )
        {
            die "$0: The cache in $portscachefile contains an incompatible ",
              "data format -- please re-run cache-init\n";
        }
    }

    # Save some regex definitions for use in the make_describe()
    # method.

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

    # Area for holding any copy of a live port or category object
    # unfrozen from the cache.

    $self->{LIVE_PORTS} = {};

    # Result of the last check on a port / category
    $self->{LAST_RESULT} = "none";

    return bless $self, $class;
}

sub DESTROY
{
    my $self = shift;

    untie $self->{PORTS};
    undef $self;
}

#
# Insert FreeBSD::Portindex::Port or FreeBSD::Portindex::Category
# object (ie. from 'make describe' output) into ports tree structure
# according to the ORIGIN -- freeze the object for external storage
# and keep the live copy handy too.
sub insert ($$$)
{
    my $self   = shift;
    my $origin = shift;
    my $port   = shift;

    return undef if ( $origin eq '__CACHE_VERSION' );

    $self->{LIVE_PORTS}->{$origin} = $port;
    $self->{PORTS}->{$origin}      = freeze($port);
    return $self;
}

#
# Return the cached FreeBSD::Portindex::Port or
# FreeBSD::Portindex::Category object for a given origin path,
# deleting the frozen version from the tree hash.  Return undef if
# port not found in tree
#
sub delete ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;
    my $thawedport;

    return undef if ( $origin eq '__CACHE_VERSION' );

    $thawedport = $self->{LIVE_PORTS}->{$origin};
    if ( defined $thawedport ) {
        delete $self->{LIVE_PORTS}->{$origin};
    }

    $port = $self->{PORTS}->{$origin};
    if ( defined $port ) {
        delete $self->{PORTS}->{$origin};
        $thawedport = thaw($port);
    }
    return $thawedport;
}

#
# Return the cached port description or category object for a given
# origin path.  Return undef if port not found in tree.  Stash a copy
# of the live port for later use.
#
sub get ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;
    my $thawedport;

    return undef if ( $origin eq '__CACHE_VERSION' );

    $thawedport = $self->{LIVE_PORTS}->{$origin};
    if ( !defined $thawedport ) {

        $port       = $self->{PORTS}->{$origin};
        $thawedport = thaw($port)
          if ( defined $port );
        $self->{LIVE_PORTS}->{$origin} = $thawedport
          if ( defined $thawedport );
    }
    return $thawedport;
}

#
# Set or get what the last result of a check on a port was
#
sub last_result($;$)
{
    my $self   = shift;
    my $result = shift;

    my %results = (
        none      => "none",
        new       => "new",
        deleted   => "deleted",
        unchanged => "unchanged",
        modified  => "modified",
        error     => "error"
    );
    if ( $result && $results{$result} eq $result ) {
        $self->{LAST_RESULT} = $result;
    }
    return $self->{LAST_RESULT};
}

#
# Build the tree structure by scanning through the Makefiles of the
# ports tree.  This is equivalent to the first part of 'make index'
# Recurse through all of the Makefiles -- extract the values of
# various make variables.  From that divine if this is a leaf
# directory -- ie. a port, or a category directory.  Store either sort
# of object in the cache, but for category objects, expand the SUBDIR
# argument from each Makefile, and any Makefile.local in the
# referenced directory and process each of those, recursively.
#
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
    my $port;

    # Read the Makefile to extract the settings of some interesting
    # variables.  Possible results are -- no such file or directory or
    # other IO error (undef); success (new object reference)

    $port = $self->make_describe($path);
    if ( defined $port ) {
        if ( $port->isa("FreeBSD::Portindex::Port") ) {

            # This is a port makefile, not a category one.
            counter( \%::Config, $counter );

        } else {

            # A category -- process the subdirs, recursively
            for my $subdir ( @{ $port->SUBDIRS() } ) {
                $self->_scan_makefiles( $subdir, $counter );
            }
        }
    }
    return $self;
}

#
# Generate the port description or category subdir listing without
# actually running 'make describe'.  Instead, extract the values of a
# series of variables that are processed during 'make describe', and
# perform equivalent processing ourselves.  Returns a reference to
# the port or category object generated and placed into the cache.
# Changes current working directory of the process: does nothing if
# 'no such directory'.  For that and other problems, returns undef to
# signal problems to upper layers in that case.  Deals gracefully with
# the case where the Makefile without SUBDIR entries is a new category
# (non-leaf) Makefile, without any ports in that category yet -- in
# which case, 'make describe' will succeed but return an empty SUBDIR
# list.
#
sub make_describe($$)
{
    my $self = shift;
    my $path = shift;
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
      LIB_DEPENDS
      MASTER_PORT
      .MAKEFILE_LIST
      SUBDIR
    };
    my %make_vars;

    chdir $path
      or do {

        # Make sure old cruft is deleted
        if ( $self->delete($path) ) {
            warn "$0: $path -- deleted from cache\n"
              if $::Config{Warnings};
        } else {
            warn "$0: can't change directory to \'$path\' -- $!\n"
              if $::Config{Warnings};
        }
        return undef;
      };

    # Run make, extracting the values of our list of variables into a
    # hash.  The values will be printed out one per line in the same
    # order they are given on the command line.

    $make_command = '/usr/bin/make -V' . join( ' -V ', @make_var_list ) . '|';

    open MAKE, $make_command
      or do {
        warn "$0: Error. Can\'t run make in \'$path\' -- $!\n";
        return undef;
      };
    foreach my $mv (@make_var_list) {
        $make_vars{$mv} = <MAKE>;
        last unless defined $make_vars{$mv};
        chomp( $make_vars{$mv} );
    }
    close MAKE
      or do {

        # There's a Makefile, but it's not a valid one.
        if ( $? && $self->delete($path) ) {
            warn "$0: $path Error. Invalid port deleted from cache\n";
        } else {
            warn "$0: $path Error. ",
              ( $! ? "close failed -- $!\n" : "make: bad exit status -- $?\n" );
        }
        return undef;
      };

    # Create the appropriate type of object (FreeBSD::Portindex::Port
    # or FreeBSD::Portindex::Category) depending on the results of
    # running the make command above.  Only real ports set PKGNAME

    if ( $make_vars{PKGNAME} ) {

        # Unlike 'make index' we can benefit by pressing on even if there
        # are errors.  Return undef to signal this to higher levels.

        $port = FreeBSD::Portindex::Port->new_from_make_vars(
            \%make_vars,
            $self->{MAKEFILE_LOCATIONS},
            $self->{MAKEFILE_EXCEPTIONS}
          )
          or do {
            warn "$0: $path Error.  Can\'t parse make output -- $!\n";
            return undef;
          };
    } else {

        # A category Makefile
        $port = FreeBSD::Portindex::Category->new_from_make_vars( \%make_vars );
    }
    $self->insert( $path, $port );
    return $port;
}

#
# Unpack all of the frozen FreeBSD::Portindex::Ports or
# FreeBSD::Portindex::Category objects from the btree storage and
# stash in an internal hash for later use.  Includes all of the
# categories too.
#
sub springtime($)
{
    my $self = shift;

    foreach my $origin ( keys %{ $self->{PORTS} } ) {
        next
          if ( $origin eq '__CACHE_VERSION' );

        $self->get($origin);
    }
    return $self;
}

#
# Fill in the referenced hash with a list of all known ports (as keys)
# and zero as values.  Includes all of the categories too.
#
sub port_origins($$)
{
    my $self     = shift;
    my $allports = shift;

    foreach my $origin ( keys %{ $self->{PORTS} } ) {
        next
          if ( $origin eq '__CACHE_VERSION' );

        $allports->{$origin} = 0;
    }
    return $allports;
}

#
# Invert all of the slave => master hash relationships, returning a
# reference to a hash whose keys are the master port origins, and
# whose values are refs to arrays of slave port origins.  Only
# initialise on the first call.
#
sub init_masterslave($)
{
    my $self = shift;
    my $port;

    if ( !defined $self->{MASTERSLAVE} ) {
        foreach my $origin ( keys %{ $self->{PORTS} } ) {
            next
              if ( $origin eq '__CACHE_VERSION' );

            $port = $self->get($origin);

            # This skips over all of the Category objects, as well as
            # ports that don't have MASTER_PORT set.
            next
              unless ( $port->can("MASTER_PORT") && $port->MASTER_PORT() );

            $self->{MASTERSLAVE}->{ $port->MASTER_PORT() } = []
              unless ( defined $self->{MASTERSLAVE}->{ $port->MASTER_PORT() } );
            push @{ $self->{MASTERSLAVE}->{ $port->MASTER_PORT() } }, $origin;
        }
    }
    return $self;
}

#
# Return array ref with list of slave ports of the master given in the
# arg -- or a ref to an empty array if no slave ports are known.
#
sub masterslave($$)
{
    my $self   = shift;
    my $origin = shift;

    return $self->{MASTERSLAVE}->{$origin} || [];
}

#
# Another form of inversion: invert the .MAKEFILE_LIST data, returning
# a hash with keys being the various Makefiles and targets being an
# array of port origins depending on those Makefiles.  Only initialise
# on the first call.
#
sub init_makefile_list ($)
{
    my $self = shift;
    my $port;

    if ( !defined $self->{MAKEFILE_LIST} ) {
        foreach my $origin ( keys %{ $self->{PORTS} } ) {
            next
              if ( $origin eq '__CACHE_VERSION' );

            $port = $self->get($origin);

            # This skips over all of the Category objects.
            next unless $port->can("MAKEFILE_LIST");

            for my $makefile ( @{ $port->MAKEFILE_LIST() } ) {
                $self->{MAKEFILE_LIST}->{$makefile} = []
                  unless defined $self->{MAKEFILE_LIST}->{$makefile};
                push @{ $self->{MAKEFILE_LIST}->{$makefile} }, $origin;
            }
        }
    }
    return $self;
}

#
# Accessor for .MAKEFILE_LIST data
#
sub makefile_list($$)
{
    my $self = shift;
    my $name = shift;

    return $self->{MAKEFILE_LIST}->{$name} || [];
}

#
# Test whether a given filename matches a known category type of thing.
# Updates to a category Makefile mean we should compare the new and
# old list of SUBDIRs carefully, as this can indicate a new port being
# hooked up to the tree, or various other changes.
#
sub category_match ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;

    $port = $self->get($origin);

    return ( defined $port && $port->isa("FreeBSD::Portindex::Category") );
}

#
# As a category Makefile has changed, regenerate the corresponding
# category object, and compare it to the one from the cache.  Add
# any differences to the list of ports to update, and replace the
# category object in the cache.
#
sub category_check ($$$)
{
    my $self     = shift;
    my $origin   = shift;
    my $updaters = shift;

    my $newcat;
    my $oldcat;
    my $comm;

    $newcat = $self->make_describe($origin);
    $oldcat = $self->get($origin);
    delete $updaters->{$origin};

    # Sometimes a deleted port may be mixed up with a category.
    # Filter out those cases.

    if ( defined $newcat && $newcat->isa("FreeBSD::Portindex::Category") ) {
        $comm = $oldcat->comm($newcat);

        if ( @{ $comm->[0] } || @{ $comm->[2] } ) {

            # This category was modified: better check the contents

            foreach my $o ( @{ $comm->[0] }, @{ $comm->[2] } ) {
                $updaters->{$o}++;
            }
        }
    }
    return $self;
}

#
# For all of the known ports (but not the categories), accumulate the
# various dependencies as required for the INDEX file.  Assumes
# 'springtime' has been called to populate the LIVE_PORTS hash.  See
# FreeBSD::Portindex::Port::accumulate_dependencies() for details.
#
# **Note** This alters the contents of LIVE_PORTS without pushing the
# same changes into the on-disk cache.
#
sub accumulate_dependencies($)
{
    my $self    = shift;
    my $counter = 0;

    print STDERR "Accumulating dependency information: "
      if ( $::Config{Verbose} );
    for my $port ( values %{ $self->{LIVE_PORTS} } ) {
        $port->accumulate_dependencies( $self->{LIVE_PORTS}, 0, \$counter )
          if ( ref($port)
            && $port->isa("FreeBSD::Portindex::Port") );
    }
    print STDERR "<${counter}>\n" if ( $::Config{Verbose} );

    return $self;
}

#
# Print out whole INDEX file sorted by ORIGIN using $tree hash: since
# this is stored as a BerkeleyDB Btree, it comes out already sorted
#
sub print_index($*)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = 0;
    my $parentorigin;

    print STDERR "Writing INDEX file: "
      if ( $::Config{Verbose} );

    foreach my $origin ( keys %{ $self->{PORTS} } ) {
        next
          if ( $origin eq '__CACHE_VERSION' );

        if (   $self->{LIVE_PORTS}->{$origin}
            && $self->{LIVE_PORTS}->{$origin}->isa("FreeBSD::Portindex::Port") )
        {

            if ( $::Config{Strict} ) {
                ( $parentorigin = $origin ) =~ s@/[^/]*$@@;

                if (   $self->{LIVE_PORTS}->{$parentorigin}
                    && $self->{LIVE_PORTS}->{$parentorigin}
                    ->isa("FreeBSD::Portindex::Category")
                    && $self->{LIVE_PORTS}->{$parentorigin}
                    ->is_known_subdir($origin) )
                {
                    $self->{LIVE_PORTS}->{$origin}
                      ->print( $fh, $self->{LIVE_PORTS}, \$counter );
                } else {
                    warn "$0: $origin is not referenced from the ",
                      "$parentorigin category -- not added to INDEX\n"
                      if $::Config{Warnings};
                }
            } else {

                # Not strict...
                $self->{LIVE_PORTS}->{$origin}
                  ->print( $fh, $self->{LIVE_PORTS}, \$counter );
            }
        }
    }
    print STDERR "<${counter}>\n"
      if ( $::Config{Verbose} );

    return $self;
}

1;

#
# That's All Folks!
#
