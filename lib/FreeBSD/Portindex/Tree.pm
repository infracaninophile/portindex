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
# Container for FreeBSD::Portindex::Ports objects which models the
# entire ports tree -- indexed by port directories.  Persistence is
# supplied by using BerkeleyDB Btree for backing stores.
#
package FreeBSD::Portindex::Tree;

use strict;
use warnings;
use BerkeleyDB;
use Scalar::Util qw(blessed);
use Carp;

use FreeBSD::Portindex::Category;
use FreeBSD::Portindex::Config qw{%Config counter htmlencode};
use FreeBSD::Portindex::FileObject;
use FreeBSD::Portindex::Makefile;
use FreeBSD::Portindex::Port;
use FreeBSD::Portindex::TreeObject;

our $VERSION       = '2.8';    # Release
our $CACHE_VERSION = '2.8';    # Earliest binary compat version

sub new ($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;
    my $portscachefile  = $Config{CacheFilename};
    my $cachewascreated = 0;

    # Make sure that the certain defaults are set.

    if ( defined $args{-CacheFilename} ) {
        $portscachefile = "$Config{CacheDir}/$args{-CacheFilename}";
        delete $args{-CacheFilename};
    }

    $args{-Mode} = 0640
      unless defined $args{-Mode};
    $args{-Flags} = 0
      unless defined $args{-Flags};

    $self = { CACHE => {}, };

    # Test if the cache file name already exists.  If there is
    # already a file there, then after we tie to it, check for
    # a __CACHE_VERSION entry.  If this is a new file, insert
    # the __CACHE_VERSION.

    $cachewascreated = 1 unless ( -e "$portscachefile" );

    # Must turn on the DB locking system if we're storing more than
    # one DB per file.

    $self->{ENV} = new BerkeleyDB::Env
      -Flags => DB_CREATE | DB_INIT_MPOOL | DB_INIT_CDB,
      -Home  => $Config{CacheDir},
      %{ $args{-Env} };
    delete $args{-Env};

    # Tie the CACHE hashes to our cache file -- a DB btree file.  Keep
    # various FreeBSD::Portindex::TreeObject objects in this cache --
    # primarily the PORT data, plus the CATEGORY.  Also contains data
    # data about dependencies on files -- Makefiles and pkg-descr files.

    tie %{ $self->{CACHE} }, 'BerkeleyDB::Btree',
      -Env => $self->{ENV},
      %args, -Filename => $portscachefile
      or die "$0: Can\'t access $portscachefile -- $! $BerkeleyDB::Error";

    # Set the cache version number on creation.  Test the cache
    # version number if we're re-opening a pre-existing cache, and
    # make sure it's compatible.

    if ($cachewascreated) {
        $self->{CACHE}->{__CACHE_VERSION} = $VERSION;
    } else {
        unless ( exists $self->{CACHE}->{__CACHE_VERSION}
            && $self->{CACHE}->{__CACHE_VERSION} >= $CACHE_VERSION )
        {
            die "$0: The cache in $portscachefile contains an incompatible ",
              "data format -- please re-run cache-init\n";
        }
    }

    # Area for holding any copy of any tree object unfrozen from the
    # cache.

    $self->{LIVE} = {};

    return bless $self, $class;
}

sub DESTROY
{
    my $self = shift;

    untie $self->{CACHE};
    undef $self;
}

#
# Insert FreeBSD::Portindex::TreeObject object (eg. a Port or Category
# from 'make describe' output, or a Makefile or pkg-descr file) into
# ports Tree structure according to the ORIGIN -- do this in a lazy
# way: don't immediately freeze the object for persistent storage.
#
sub insert ($$)
{
    my $self        = shift;
    my $tree_object = shift;
    my $origin;

    return undef
      unless blessed($tree_object)
          && $tree_object->isa('FreeBSD::Portindex::TreeObject');

    $origin = $tree_object->ORIGIN();
    $self->{LIVE}->{$origin} = $tree_object;

    return $self;
}

#
# Commit an update of an object in the live cache to the frozen copy
# in the disk cache.  Works on any FreeBSD::Portindex::TreeObject
# object.
#
sub commit ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $tree_object;

    return undef if ( $origin eq '__CACHE_VERSION' );

    return undef
      unless exists $self->{LIVE}->{$origin};

    $tree_object = $self->{LIVE}->{$origin};

    if ( $tree_object->is_dirty() ) {
        $self->{CACHE}->{$origin} = $tree_object->freeze();
        $tree_object->was_flushed();
    }
    return $self;
}

#
# Commit any dirty TreeObjects to persistent storage in the cache.
#
sub flush ($)
{
    my $self = shift;

    for my $origin ( keys %{ $self->{LIVE} } ) {
        $self->commit($origin);
    }
    return $self;
}

#
# Return the cached FreeBSD::Portindex::PortsTreeObject for a given
# origin path, deleting the frozen version from both the cache and the
# live collection.  Return undef if port not found in tree
#
sub delete ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $tree_object;

    return undef if ( $origin eq '__CACHE_VERSION' );

    if ( exists $self->{CACHE}->{$origin} ) {
        $tree_object =
          FreeBSD::Portindex::TreeObject->thaw( $self->{CACHE}->{$origin} );
        delete $self->{CACHE}->{$origin};
    }
    if ( exists $self->{LIVE}->{$origin} ) {
        $tree_object = delete $self->{LIVE}->{$origin};
    }
    return $tree_object;
}

#
# Return the FreeBSD::Portindex::TreeObject for a given origin path,
# thawing from cache if needed.  Return undef if port not found in
# tree.  Stash a copy of the live TreeObject for later use.
#
sub get ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $tree_object;

    return undef if ( $origin eq '__CACHE_VERSION' );

    if ( exists $self->{LIVE}->{$origin} ) {
        $tree_object = $self->{LIVE}->{$origin};
    } elsif ( exists $self->{CACHE}->{$origin} ) {
        $tree_object =
          FreeBSD::Portindex::TreeObject->thaw( $self->{CACHE}->{$origin} );
        $self->{LIVE}->{$origin} = $tree_object;
    }
    return $tree_object;
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
sub scan_makefiles($$)
{
    my $self    = shift;
    my @paths   = @_;
    my $counter = 0;

    print STDERR "Processing make describe output",
      @paths == 1 ? " for path \"$paths[0]\": " : ": "
      if ( $Config{Verbose} );
    for my $path (@paths) {
        $self->_scan_makefiles( $path, \$counter );
    }
    $self->flush();    # Ensure everything is in persistent storage
    print STDERR "<$counter>\n"
      if ( $Config{Verbose} );
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
    if ($port) {
        if ( $port->isa("FreeBSD::Portindex::Port") ) {

            # This is a port makefile, not a category one.
            counter($counter);

        } else {

            # A category -- process the subdirs, recursively
            for my $subdir ( $port->SUBDIR() ) {
                $self->_scan_makefiles( "$path/$subdir", $counter );
            }
        }
    }
    return $self;
}

#
# Generate the port description or category subdir listing without
# actually running 'make describe'.  Instead, extract the values of a
# series of variables that are processed during 'make describe', and
# perform equivalent processing ourselves.  Returns a reference to the
# port or category object generated and placed into the cache.
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
      .CURDIR
      .MAKEFILE_LIST
      BUILD_DEPENDS
      CATEGORIES
      COMMENT
      DESCR
      EXTRACT_DEPENDS
      FETCH_DEPENDS
      LIB_DEPENDS
      MAINTAINER
      OPTIONS
      OPTIONSFILE
      PATCH_DEPENDS
      PKGNAME
      PREFIX
      RUN_DEPENDS
      SUBDIR
    };
    my %make_vars;

    chdir $path
      or do {
        $port = $self->delete($path);    # Make sure old cruft is deleted

        if ($port) {
            $self->update_files_unused_by($port);

            warn "$0: $path -- deleted from cache\n"
              if $Config{Warnings};
        } else {
            warn "$0: can't change directory to \'$path\' -- $!\n"
              if $Config{Warnings};
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
        $port = $self->delete($path);    # There's a Makefile, but not valid.

        if ( $? && $port ) {
            $self->update_files_unused_by($port);

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

        $port = FreeBSD::Portindex::Port->new_from_make_vars( \%make_vars )
          or do {
            warn "$0: $path Error.  Can\'t parse make output\n";
            return undef;
          };

        # If the port uses OPTIONS, force a Makefile entry to be made
        # for the options file even though it doesn't exist yet.  (It
        # will set mtime to 0 in this case) This will trigger a cache
        # update if OPTIONS are set at a later date.

        if ( $make_vars{OPTIONS} ) {
            my $makefile = $self->get( $make_vars{OPTIONSFILE} );

            if ( !$makefile ) {
                $makefile =
                  FreeBSD::Portindex::Makefile->new(
                    ORIGIN => $make_vars{OPTIONSFILE}, );
                $self->insert($makefile);
            }
            $makefile->mark_used_by( $port->ORIGIN() );
        }
    } else {

        # A category Makefile
        $port = FreeBSD::Portindex::Category->new_from_make_vars( \%make_vars );
    }
    $self->insert($port);

    # Create any new Makefile or FileObject (pkg-descr) objects
    # for anything we haven't seen before, then update the USED_BY
    # fields of every referenced file object.

    $self->update_files_used_by($port);

    return $port;
}

#
# Update the File (Makefile, pkg-descr) objects referenced from a port
# or category -- add $tree_object as using the file, even if it is
# marked as doing so already.  Create new FileObjects as required.
#
sub update_files_used_by($$)
{
    my $self        = shift;
    my $tree_object = shift;
    my $origin;
    my $file_object;

    $origin = $tree_object->ORIGIN();

    if ( $tree_object->can('MAKEFILE_LIST') ) {
        for my $makefile ( $tree_object->MAKEFILE_LIST() ) {
            eval {
                $file_object = $self->get($makefile);

                if ( !defined $file_object ) {
                    $file_object =
                      FreeBSD::Portindex::Makefile->new( ORIGIN => $makefile );
                    $self->insert($file_object);
                }
                $file_object->mark_used_by($origin);
            };
            if ($@) {

                # File not found... turn the error into a warning.
                carp $@;
            }
        }
    }
    if ( $tree_object->can('DESCR') ) {
        my $descr = $tree_object->DESCR();

        eval {
            $file_object = $self->get($descr);

            if ( !defined $file_object ) {
                $file_object =
                  FreeBSD::Portindex::FileObject->new( ORIGIN => $descr );
                $self->insert($file_object);
            }
            $file_object->mark_used_by($origin);
        };
        if ($@) {

            # File not found... turn the error into a warning.
            carp $@;
        }
    }
    return $self;
}

#
# Update the File (Makefile, pkg-descr) objects no-longer referenced
# from a port or category -- delete $tree_object as using the file,
# even if it is not marked as doing so already.  If the FileObject
# doesn't already exist, that's OK.  Deleting USED_BY links could
# leave the FileObject unused by anything, but that's OK too.
#
sub update_files_unused_by($$)
{
    my $self        = shift;
    my $tree_object = shift;
    my $origin;
    my $file_object;

    $origin = $tree_object->ORIGIN();

    if ( $tree_object->can('MAKEFILE_LIST') ) {
        for my $makefile ( $tree_object->MAKEFILE_LIST() ) {
            $file_object = $self->get($makefile);

            if ( defined $file_object ) {
                $file_object->mark_unused_by($origin);
            }
        }
    }
    if ( $tree_object->can('DESCR') ) {
        my $descr = $tree_object->DESCR();

        $file_object = $self->get($descr);

        if ( defined $file_object ) {
            $file_object->mark_unused_by($origin);
        }
    }
    return $self;
}

#
# Return an array or array_ref of all of the Port names, in sorted
# order.  Relies on the underlying btree file to provide the sorting.
# Port ORIGINS are matched by pattern.
#
sub allports($;$)
{
    my $self = shift;
    my $filter = shift || qr@^[^/]+/[^/]+$@;
    my @allports;

    @allports = grep { m/$filter/ } keys %{ $self->{CACHE} };

    return wantarray ? @allports : \@allports;
}

#
# Return an array or array_ref of all of the Port objects, in sorted
# order. Relies on the underlying btree file to provide the sorting.
# Port ORIGINS are matched by pattern.
#
sub allports_data($;$)
{
    my $self = shift;
    my $filter = shift || qr@^[^/]+/[^/]+$@;
    my @allports;

    @allports = map { $self->{LIVE}->{$_} }
      grep { m/$filter/ } keys %{ $self->{CACHE} };

    return wantarray ? @allports : \@allports;
}

#
# Unpack all of the frozen FreeBSD::Portindex::Port objects from the
# btree storage and stash in an internal hash for use when printing
# out the index.
#
sub springtime($)
{
    my $self = shift;

    foreach my $origin ( $self->allports() ) {
        $self->get($origin);
    }
    return $self;
}

#
# Test whether a given filename matches a known category type of
# thing.  Updates to a category Makefile mean we should compare the
# new and old list of SUBDIRs carefully, as this can indicate a new
# port being hooked up to the tree, or various other changes.
#
sub category_match ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;

    $origin =~ s@^$Config{PortsDir}/@@;

    $port = $self->get($origin);

    return defined $port ? $port->is_category() : undef;
}

#
# As a category Makefile has changed, regenerate the corresponding
# category object, and compare it to the one from the cache.  Add any
# differences to the list of ports to update, and replace the category
# object in the cache. XXX -- sanity? does this still matter in the
# new regime?
#
sub category_check ($$$$)
{
    my $self             = shift;
    my $origin           = shift;
    my $category_updates = shift;
    my $port_updates     = shift;

    my $newcat;
    my $oldcat;

    $oldcat = $self->get($origin)->SUBDIR();
    $self->make_describe("$Config{PortsDir}/$origin");
    $newcat = $self->get($origin)->SUBDIR();

    $category_updates->delete($origin);

    for my $path (
        FreeBSD::Portindex::ListVal->difference( $oldcat, $newcat )->get() )
    {
        if ( $origin ne '' ) {
            $path = "$origin/$path";
        }
        if ( $self->category_match($path) ) {
            $category_updates->insert($path);
        } else {
            $port_updates->insert($path);
        }
    }
    return $self;
}

#
# Check file object or makefile for updates to mtime and add any ports
# that use it to the $updaters ListVal.
#
sub add_to_updates_if_modified($$$)
{
    my $self    = shift;
    my $updates = shift;
    my $name    = shift;
    my $makefile;

    $makefile = $self->get($name);

    return undef
      unless ($makefile);

    if (   $makefile->is_file()
        && !$makefile->is_endemic()
        && $makefile->has_been_modified() )
    {
        if ( $makefile->is_ubiquitous() ) {
            warn "$0: WARNING: $name modified since last update ",
              "-- time for cache-init again?\n";
        } else {
            $updates->insert( $makefile->USED_BY() );
        }
        $makefile->update_mtime();
    }
    return $self;
}

#
# Scan through all Makefile or other files that don't sit under PORTSDIR
# or PORT_DBDIR, and check them for updates
#
sub check_other_makefiles($$)
{
    my $self    = shift;
    my $updates = shift;
    my $makefile;

    for my $name ( keys %{ $self->{CACHE} } ) {

        # Skip ports etc. where the origin doesn't start with '/'
        next
          unless ( $name =~ m@^/@ );

        # Skip anything under PORTSDIR or PORT_DBDIR
        next
          if ( $name =~ m@^(?:$Config{PortsDir}|$Config{PortDBDir})@ );

        $self->add_to_updates_if_modified( $updates, $name );
    }
    return $self;
}

#
# Scan through the PORT_DBDIR looking for 'options' files.  Compare
# the mtime of the file with the last update timestamp from the cache
# -- add the port to the list to be checked if the options have been
# modified more recently.
#
sub check_port_options ($$)
{
    my $self    = shift;
    my $updates = shift;
    my $options;
    my $makefile;

    opendir PORT_DBDIR, $Config{PortDBDir}
      or do {
        warn "$0: Error. Cannot read directory \'$Config{PortDBDir}\' -- $!\n";
        return $updates;
      };
    while ( my $dir = readdir PORT_DBDIR ) {
        next
          unless $dir =~ m/[\w-]+/;    # Skip things with dots in the name

        # The Makefile generated by and included due to OPTIONS
        # processing
        $options = "$Config{PortDBDir}/$dir/options";

        next
          unless ( -f $options );      # $dir may be empty

        if ( !$self->add_to_updates_if_modified( $updates, $options ) ) {

            # It looks like an options file, but since we load the
            # cache with all posible names of the known options files,
            # it must be something else.
            warn "$0: WARNING unknown options file \"$options\" -- ignored\n"
              if $Config{Verbose};
        }
    }
    closedir PORT_DBDIR
      or warn "$0: Error. Closing directory \'$Config{PortDBDir}\' -- $!\n";

    return $self;
}

#
# For all of the known ports (but not the categories), accumulate the
# various dependencies as required for the INDEX or SHLIB file.  Assumes
# 'springtime' has been called to populate the LIVE hash.  See
# FreeBSD::Portindex::Port::accumulate_dependencies() for details.
#
# **Note** This alters the contents of LIVE without flushing the
# same changes into the on-disk CACHE.
#
sub accumulate_dependencies($)
{
    my $self    = shift;
    my $counter = 0;
    my $whatdeps;
    my $accumulate_deps;

    # If printing INDEX:
    # On output -- all converted to pkg name:
    # EXTRACT_DEPENDS <-- RUN_DEPENDS
    # PATCH_DEPENDS   <-- RUN_DEPENDS
    # FETCH_DEPENDS   <-- RUN_DEPENDS
    # BUILD_DEPENDS   <-- RUN_DEPENDS (Includes LIB_DEPENDS already)
    # RUN_DEPENDS     <-- RUN_DEPENDS (Includes LIB_DEPENDS already)

    my $index_deps = {
        EXTRACT_DEPENDS => 1,
        PATCH_DEPENDS   => 1,
        FETCH_DEPENDS   => 1,
        BUILD_DEPENDS   => 1,
        RUN_DEPENDS     => 1,
    };

    # If printing SHLIBS:
    # On output
    # LIB_DEPENDS  <--- LIB_DEPENDS (as port origins)
    my $shlib_deps = { LIB_DEPENDS => 0 };

    if ( $Config{ShLibs} == 0 ) {

        # Printing INDEX
        $whatdeps        = $index_deps;
        $accumulate_deps = "RUN_DEPENDS";
    } else {

        # Printing SHLIBS
        $whatdeps        = $shlib_deps;
        $accumulate_deps = "LIB_DEPENDS";
    }

    print STDERR "Accumulating dependency information: "
      if ( $Config{Verbose} );
    for my $port ( $self->allports_data() ) {
        $port->accumulate_dependencies( $self->{LIVE}, $whatdeps,
            $accumulate_deps, 0, \$counter );
    }
    print STDERR "<${counter}>\n" if ( $Config{Verbose} );

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

    print STDERR "Writing INDEX file: "
      if ( $Config{Verbose} );

    foreach my $port ( $self->allports_data() ) {
        $port->print_index( $fh, \$counter );
    }
    print STDERR "<${counter}>\n"
      if ( $Config{Verbose} );

    return $self;
}

#
# Print out SHLIBS file sorted by ORIGIN using $tree hash: uses the
# ordering implicit in the BerkelyDB Btree as above.
#
sub print_shlibs($*)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = 0;

    print STDERR "Writing SHLIBS file: "
      if ( $Config{Verbose} );

    foreach my $port ( $self->allports_data() ) {
        $port->print_shlibs( $fh, \$counter );
    }
    print STDERR "<$counter}>\n"
      if ( $Config{Verbose} );

    return $self;
}

#
# Generate README.html files, recursing via SUBDIRS values
#
sub make_readmes($$$$$;$);    #  Prototype aids recursion

sub make_readmes($$$$$;$)
{
    my $self      = shift;
    my $dir       = shift;
    my $origin    = shift;
    my $templates = shift;
    my $depth     = shift;
    my $counter   = shift;
    my $port;
    my $subdirs;
    my $comment;

    my %t = (
        1 => 'top',
        2 => 'category',
        3 => 'port',
    );

    # Retrieve data from cache

    $port = $self->get($origin)
      or croak "$0: FATAL: data for \"$origin\" not found in cache.\n";

    # Create directory --

    eval {
        use autodie;

        mkdir $dir;
    };
    if ( $@ && $@ !~ m/File exists/ ) {
        croak "$0: FATAL -- $@\n";
    }

    # Recurse through subdirs (top and categories only)

    if ( $depth == 1 ) {
        for my $subdir ( sort $port->SUBDIR() ) {
            my ( $p, $c ) =
              $self->make_readmes( "$dir/$subdir", $subdir, $templates, 2,
                $counter );
            $subdirs .= "<a href=\"$subdir/README.html\">$subdir</a>: $c\n";
        }
    } elsif ( $depth == 2 ) {
        for my $subdir ( sort $port->SUBDIR() ) {
            my ( $p, $c ) =
              $self->make_readmes( "$dir/$subdir", "$origin/$subdir",
                $templates, 3, $counter );
            $subdirs .= "<a href=\"$subdir/README.html\">$p</a>: $c\n";
        }
    }

    # Process template and write to $dir/README.html
    $port->make_readme( "$dir/README.html", $templates->{ $t{$depth} },
        $subdirs );

    $comment = htmlencode( $port->COMMENT() );

    # Show progress
    counter($counter);

    return ( $port->can('PKGNAME') ? $port->PKGNAME() : '', $comment );
}

1;

#
# That's All Folks!
#
