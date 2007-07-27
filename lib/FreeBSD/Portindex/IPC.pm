# Copyright (c) 2007 Matthew Seaman. All rights reserved.
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
# @(#) $Id: IPC.pm,v 1.2 2007-07-27 15:41:47 matthew Exp $
#

#
# An object for generating worker sub-processes and managing the IPC
# between the master process and the workers.  Calling 'new()' will
# fork the process the specified number of times: in the parent process
# the result will be a FreeBSD::Portindex::IPC::Master object, in the
# children a FreeBSD::Portindex::IPC::Worker object.
#
package FreeBSD::Portindex::IPC;
our $VERSION = '2.0';    # Release

use strict;
use warnings;
use Carp;
use Socket;
use IO::Handle;

use FreeBSD::Portindex::Config;

# Fork off the required number of worker processes.  Set up SIGCHILD
# handler in parent.  The master process creates a socket pair, which
# is inherited across the fork().  The master process writes the names
# of ports to update into the WRITER end, which the worker processes
# read line by line from the READER end of the handle, serializing
# access by gaining a write lock on a filehandle.
sub new ($$)
{
    my $caller  = shift;
    my $class   = ref($caller) || $caller;
    my $workers = shift;
    my $self    = {};
    my @pid;
    my $child_count;

    socketpair( READER, WRITER, AF_UNIX, SOCK_STREAM, PF_UNSPEC )
      or die "$0: Could not create socket pairs -- $!\n";
    READER->autoflush(1);
    WRITER->autoflush(1);

    # Use an anonymous temporary file for locking
    open( LOCK, "+>", undef )
      or die "$0: Could not open lock-file -- $!\n";

    for ( 1 .. $workers ) {
        if ( $pid[$_] = fork() ) {

            # In parent
            $child_count++;

        } else {

            # In child
            die "$0: Cannot fork -- $!\n"
              unless defined $pid[$_];

            $self->{READER} = *READER;
            close WRITER;
            $self->{LOCK} = *LOCK;

            return bless $self, "${class}::Worker";
        }
    }

    $self->{pid}         = \@pid;
    $self->{child_count} = $child_count;

    close READER;
    $self->{WRITER} = *WRITER;
    close LOCK;

    return bless $self, "${class}::Master";
}

#
# Methods applicable to Master objects
#
package FreeBSD::Portindex::IPC::Master;
use vars qw(@ISA);
@ISA = qw(FreeBSD::Portindex::IPC);

use POSIX qw(:sys_wait_h);

# Use the parent's new() method which will return either a Master or a
# Worker object.
sub new ($$)
{
    my $caller = shift;
    my $class = ref($caller) || $caller;

    return $class->SUPER::new(@_);
}

# Handler for SIGCHLD
sub reaper ($)
{
    my $self = shift;

    $self->{child_count}-- until ( waitpid( -1, WNOHANG ) == -1 );
}

#
# Methods applicable to Worker objects
#
package FreeBSD::Portindex::IPC::Worker;
use vars qw(@ISA);
@ISA = qw(FreeBSD::Portindex::IPC);

use IO::Handle;
use Fcntl qw(:flock);

# Use the parent's new() method which will return either a Master or a
# Worker object.
sub new ($$)
{
    my $caller = shift;
    my $class = ref($caller) || $caller;

    return $class->SUPER::new(@_);
}

sub getline ()
{
    my $self = shift;
    my $line;

    # Grab an exclusive lock on the lock file, read a line from the
    # socket pair, then release the lock.  Blocks until lock
    # established.

    flock $self->{LOCK}, LOCK_EX
      or do {
        warn "$0: Cannot lock -- $!\n";
        return undef;
      };
    $line = $self->{READER}->getline();
    flock $self->{LOCK}, LOCK_UN;

    return $line;
}

1;

#
# That's All Folks!
#
