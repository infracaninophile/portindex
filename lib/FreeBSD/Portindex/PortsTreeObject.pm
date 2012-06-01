# Copyright (c) 2012 Matthew Seaman. All rights reserved.
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
# Base class for Port and Category objects, which are specifically
# composite parts part of the Ports Tree.  Here ORIGIN is relative to
# ${PORTSDIR}
#

package FreeBSD::Portindex::PortsTreeObject;

require 5.10.1;

use strict;
use warnings;
use Carp;

use FreeBSD::Portindex::ListVal;
use FreeBSD::Portindex::TreeObject;

our $VERSION = '2.9';                                # Release
our @ISA     = ('FreeBSD::Portindex::TreeObject');

#
# PortsTreeObjects are users of Makefiles and PkgDescr files
#
sub new ($@)
{
    my $class = shift;
    my %args  = @_;
    my $self;

    croak "$0: error instantiating $class object -- MAKEFILE_LIST missing",
      " or empty\n"
      unless ref $args{MAKEFILE_LIST} eq 'ARRAY'
          && @{ $args{MAKEFILE_LIST} } > 0;

    $self = $class->SUPER::new(%args);

    $self->{MAKEFILE_LIST} =
      FreeBSD::Portindex::ListVal->new( @{ $args{MAKEFILE_LIST} } );

    return $self;
}

#
# Generate a README.html for this ports tree object.  By the time we
# get here, all the required substitutions have been done, so all we
# need to do is print out the result.
#
sub make_readme($$)
{
    my $self = shift;
    my $file = shift;
    my $text = shift;

    open( README, ">$file" )
      or croak "$0: Fatal -- can't open file \"$file\" -- $!\n";
    print README $text;
    close README;

    return $self;
}

#
# Accessor method
#
for my $slot ('MAKEFILE_LIST') {
    no strict qw(refs);

    *$slot = __PACKAGE__->list_val_accessor($slot);
}

1;

#
# That's All Folks!
#
