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
# @(#) $Id: Tree.pm,v 1.10 2004-10-11 08:03:39 matthew Exp $
#

#
# Container for FreeBSD::Ports objects which models the entire ports
# tree -- mapping port directories '/usr/ports/www/apache2', or any
# subdirectory thereof.
#
package FreeBSD::Ports::Tree;
$VERSION = 0.01;

use strict;
use warnings;
use Carp;
use BerkeleyDB;    # BDB version 2, 3, 4, 41, 42

use FreeBSD::Port;

our @ISA = qw(BerkeleyDB::Btree);

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %args   = @_;
    my $self;

    # Make sure that the certain defaults are set.

    $args{-Filename} = "/var/tmp/portindex-cache.db"
      unless defined $args{-Filename};
    $args{-Mode} = 0640
      unless defined $args{-Mode};
    $args{-Flags} = DB_CREATE
      unless defined $args{-Flags};

    # Tie the hash to our cache file -- a DB btree file.
    $self = $class->SUPER::new(%args);

    return $self;
}

# Insert port description (ie. 'make describe' output) into ports tree
# structure according to the ORIGIN --
sub insert ($$$)
{
    my $self   = shift;
    my $origin = shift;
    my $desc   = shift;

    $self->db_put( $origin, $desc );

    return $self;
}

# Return the cached port description for a given origin path, deleting
# the version from the tree hash.  Return undef if port not found in
# tree
sub delete ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $desc;

    $self->db_get( $origin, $desc );
    if ( defined $desc ) {
        $self->db_del($origin);
    }
    return $desc;
}

# Return the cached port description for a given origin path.  Return
# undef if port not found in tree.
sub get ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $desc;

    $self->db_get( $origin, $desc );

    return $desc;
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
    my $self  = shift;
    my @paths = @_;
    my $count = 1;

    foreach my $path (@paths) {
        print STDERR "Processing 'make describe' output for path \"$path\": ";
        $self->_scan_makefiles( $path, \$count );
        print STDERR "<$count>\n";

    }
    return $self;
}

sub _scan_makefiles($$;$)
{
    my $self  = shift;
    my $path  = shift;
    my $count = shift;
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
        return $self;    # Leave out this directory.
      };
    while (<MAKEFILE>) {
        push @subdirs, "${path}/${1}"
          if (m/^\s*SUBDIR\s+\+=\s+(\S+)\s*$/);
    }
    close MAKEFILE;

    if (@subdirs) {
        for my $subdir (@subdirs) {
            $self->_scan_makefiles( $subdir, $count );
        }
    } else {

        # This is a real port directory, not a subdir.
        $self->make_describe( $path, $count );
    }
    return $self;
}

# Run 'make describe' -- takes the port directory as an argument, and
# runs make describe in it.  Changes current working directory of the
# process: bails out without updating tree if no such directory or
# other problems.
sub make_describe($$;$)
{
    my $self  = shift;
    my $path  = shift;
    my $count = shift;
    my $desc;

    chdir $path
		or do {
			carp __PACKAGE__,
			"::make_describe():$path: can't chdir() -- $!";
			return $self;
		};
    open MAKE, '/usr/bin/make describe|'
		or do {
			carp __PACKAGE__,
			"::make_describe():$path: can't run make -- $!";
			return $self;
		};
    $desc = <MAKE>;
    close MAKE
		or do {
			carp __PACKAGE__, "::make_describe():$path: ",
			( $! ? "close failed -- $!" : "make: bad exit status -- $?" );
			return $self;
		};

    if ( $::verbose && ref $count ) {
        if ( $$count % 1000 == 0 ) {
            print STDERR "[$$count]";
        } elsif ( $$count % 100 == 0 ) {
            print STDERR '.';
        }
    }
    $$count++;

    # The make describe line may contain several undesirable
    # constructs in the list of dependency origins.  Strip these
    # out as follows:
    #
    #  Newline at EOS.
    #  /usr/ports/foo/bar/../../baz/blurfl -> /usr/ports/baz/blurfl
    #  /usr/ports/foo/bar/../quux -> /usr/ports/foo/quux
    #  /usr/ports/foo/bar/ -> /usr/ports/foo/bar

    chomp($desc);
    if ( $desc =~ m@\.\.|/( |\|)@ ) {
        my @desc = split '\|', $desc, -1;    # Don't eat trailing null fields
        for my $i ( 7 .. 11 ) {
            if ( $desc[$i] ) {
                $desc[$i] =~ s@/\w[^/]+/\w[^/]+/\.\./\.\./@/@g;
                $desc[$i] =~ s@/\w[^/]+/\.\./@/@g;
                $desc[$i] =~ s@/( |\Z)@$1@g;
            }
        }
        $desc = join '|', @desc;
    }
    $self->insert( $path, $desc );

    return $self;
}

# Print out whole INDEX file sorted by ORIGIN using $tree hash: since
# this is stored as a BerkeleyDB Btree, it comes out already sorted
sub print_index($*)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = 1;

    my $cursor;
    my $origin = "";
    my $desc   = "";
    my $port;
    my %o2pn;    # ORIGIN to PKGNAME translation

    $cursor = $self->db_cursor();
    while ( $cursor->c_get( $origin, $desc, DB_NEXT ) == 0 ) {
        ( $o2pn{$origin} ) = ( $desc =~ m@^([^|]+)\|@ );
    }

    print STDERR "Writing INDEX file: " if ($::verbose);

    $cursor = $self->db_cursor();
    while ( $cursor->c_get( $origin, $desc, DB_NEXT ) == 0 ) {
        $port = FreeBSD::Port->new_from_description($desc);

        $port->print( $fh, \%o2pn, \$counter );
    }
    print STDERR "<${counter}>\n" if ($::verbose);

    return $self;
}

1;

#
# That's All Folks!
#
