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
# @(#) $Id: Tree.pm,v 1.8 2004-10-08 21:17:03 matthew Exp $
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

use FreeBSD::Port;

sub new ($@)
{
    my $caller = shift;
    my $class  = ref($caller) || $caller;
    my %self   = @_;

    return bless \%self, $class;
}

# Insert port into ports tree structure according to the ORIGIN --
# This is just a mapping from port origin to package name.
sub insert ($$$)
{
    my $self   = shift;
    my $origin = shift;
    my $port   = shift;

    $self->{$origin} = $port;

    return $self;
}

# Return the port object for a given origin path, deleting the
# reference to it from the tree structure.  Return undef if port not
# found in tree
sub delete ($$)
{
    my $self   = shift;
    my $origin = shift;
    my $port;

    if ( defined $self->{$origin} ) {
        $port = $self->{$origin};
        delete $self->{$origin};
    } else {
        $port = undef;
    }
    return $port;
}

# Return the port object for a given origin path.  Return
# undef if port not found in tree.
sub get ($$)
{
    my $self   = shift;
    my $origin = shift;

    return defined $self->{$origin} ? $self->{$origin} : undef;
}

# Read in the /usr/ports/INDEX file from STDIN converting to an array
# of hashes with links to the entries for dependencies.
sub read_index($*)
{
    my $self       = shift;
    my $filehandle = shift;
    my $port;

    print STDERR "Reading INDEX file: " if ($::verbose);
    while (<$filehandle>) {
        $port = FreeBSD::Port->new_from_indexline($_);
        $self->insert( $port->ORIGIN(), $port );

        if ($::verbose) {
            if ( $. % 1000 == 0 ) {
                print STDERR "[$.]";
            } elsif ( $. % 100 == 0 ) {
                print STDERR '.';
            }
        }
    }
    print STDERR "<$.>\n" if ($::verbose);

    return $self;
}

#----------------------------------------------------------------

# Build the tree structure by scanning through the Makefiles of the
# ports tree.  This is equivalent to the first part of 'make index'
#
# Recurse through all of the Makefiles -- expand the SUBDIR argument
# from each Makefile, and all of the Makefiles in the referenced
# directories.  If no SUBDIRs are found, this is a leaf directory, in
# which case use 'make describe' to instantiate a new FreeBSD::Port
# object.

sub scan_makefiles($@)
{
    my $self  = shift;
    my @paths = @_;
    my $count = 1;

    print STDERR "Processing 'make describe' output: ";

    foreach my $path (@paths) {
        $self->_scan_makefiles( $path, \$count );
    }

    print STDERR "<$count>\n";

    $self->origin_to_pkgname(
        qw( EXTRACT_DEPENDS PATCH_DEPENDS FETCH_DEPENDS
          BUILD_DEPENDS RUN_DEPENDS )
    );
    return $self;
}

sub _scan_makefiles($$$)
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

        # Return the path relative to $::base
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
        my $port = FreeBSD::Port->new_from_make_describe($path);

        if ($::verbose) {
            if ( $$count % 1000 == 0 ) {
                print "[$$count]";
            } elsif ( $$count % 100 == 0 ) {
                print '.';
            }
        }
        $$count++;

        $self->insert( $path, $port );
    }
    return $self;
}

# Scan through the whole tree converting the port ORIGINs in each
# dependency list into PKGNAMEs.
sub origin_to_pkgname ($@)
{
    my $self = shift;
    my @deps = @_;

    for my $origin ( keys %{$self} ) {
        $self->{$origin}->origin_to_pkgname( $self, @deps );
    }
    return $self;
}

# Print out whole INDEX file sorted by ORIGIN using $tree hash:
sub print($*)
{
    my $self    = shift;
    my $fh      = shift;
    my $counter = 1;

    print STDERR "Writing INDEX file: " if ($::verbose);

    for my $origin ( sort keys %{$self} ) {
        $self->{$origin}->print( $fh, \$counter );
    }
    print STDERR "<${counter}>\n" if ($::verbose);

    return $self;
}

1;

#
# That's All Folks!
#
