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
# @(#) $Id: Config.pm,v 1.4 2004-10-17 09:57:13 matthew Exp $
#

# Utility functions used by the various portindex programs.

package FreeBSD::Portindex;
require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(read_config);
our $VERSION   = 0.01;              # Extremely alpha.

use strict;
use warnings;
use Carp;
use Getopt::Long;
use Pod::Usage;

# Config file and command line option handling.  The config data is
# loaded from (in order): defaults built into this function, the
# system etc dir: /usr/local/etc/$::{pkgname}.cfg the users' home dir
# $ENV{HOME}/.$::{pkgname}rc or the current directory
# ./.$::{pkgname}rc -- entries in the later files on that list
# override the earlier ones.  Config files consist of live perl code
# to populate the %Config hash, which is the return value of this
# function.  Then any command line arguments are parsed, which can
# override any of the config file settings.
sub read_config ($)
{
    my $config = shift;
    my $help;
    my @optargs;

    %{$config} = (
        PortsDir            => '/usr/ports',
        CacheDir            => '/var/tmp',
        CacheFilename       => "$::pkgname-cache.db",
        MasterSlaveFilename => "$::pkgname-masterslave.db",
        Verbose             => 1,
        Output              => '-',
    );
    @optargs = (
        'help|?'   => \$help,
        'verbose!' => \$config->{Verbose},
        'quiet'    => sub { $config->{Verbose} = 0 },
    );

    for my $cf (
        "/usr/local/etc/${main::pkgname}.cfg",
        "$ENV{HOME}/.${main::pkgname}rc",
        "./.${main::pkgname}rc"
      )
    {
        do $cf;
    }
    GetOptions(@optargs) or pod2usage(2);
    pod2usage(1)
      if $help;
    return $config;
}

1;

#
# That's All Folks!
#
