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
# @(#) $Id: Config.pm,v 1.13 2004-10-23 11:01:09 matthew Exp $
#

# Utility functions used by the various portindex programs.

package FreeBSD::Portindex;
require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(read_config);
our $VERSION   = 0.2;               # Beta

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
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
        CacheDir            => "/var/tmp/$::pkgname",
        CacheFilename       => "$::pkgname-cache.db",
        Input               => '-',
        Format              => 'cvsup-output',
        MasterSlaveFilename => "$::pkgname-masterslave.db",
        Output              => '-',
        PortsDir            => '/usr/ports',
        PropagationDelay    => 3600,                          # 1 hour
        Verbose             => 1,
    );
    @optargs = (
        'cache-dir|c=s'         => \$config->{CacheDir},
        'cache-file|C=s'        => \$config->{CacheFilename},
        'help|?'                => \$help,
        'master-slave-file|M=s' => \$config->{MasterSlaveFilename},
        'quiet'                 => sub { $config->{Verbose} = 0 },
        'verbose!'              => \$config->{Verbose},
    );
    push @optargs, ( 'output=s' => \$config->{Output} )
      if ( $0 eq 'portindex' );
    push @optargs, (
        'input|i=s'  => \$config->{Input},
        'format|f=s' => sub {
            my $optname  = shift;
            my $optvalue = shift;

            die "$0: Option --$optname unrecognised argument: $optvalue\n"
              unless $optvalue =~ m@^plain|cvsup-(output|checkouts)\Z@;

            $config->{Format} = $optvalue;
        },
        'propagation-delay=i' => \$config->{PropagationDelay},
      )
      if ( $0 eq 'cache-update' );
    push @optargs, ( 'ports-dir=s' => \$config->{PortsDir}, )
      if ( $0 eq 'cache-init' );

    for my $cf (
        "/usr/local/etc/${main::pkgname}.cfg",
        "$ENV{HOME}/.${main::pkgname}rc",
        "./.${main::pkgname}rc"
      )
    {
        do $cf;
    }
    GetOptions(@optargs) or pod2usage(2);
    if ($help) {
        pod2usage( -exitval => 'NOEXIT', -verbose => 1 );
        show_config($config);
        exit(1);
    }
    return $config;
}

# Print out the current configuration settings after config file and
# command line have been processed.
sub show_config ($)
{
    my $config = shift;

    print <<"E_O_CONFIG";

Current Configuration:

    Settings after reading all configuration files and parsing the
    command line.  They apply to all programs, except as marked.

    PortsDir (cache-init) ............. $config->{PortsDir}
    CacheDir .......................... $config->{CacheDir}
    CacheFilename ..................... $config->{CacheFilename}
    MasterSlaveFilename ............... $config->{MasterSlaveFilename}
    Input (cache-update) .............. $config->{Input}
    Format (cache-update) ............. $config->{Format}
    PropagationDelay (cache-update) ... $config->{PropagationDelay}
    Output (portindex) ................ $config->{Output}
    Verbose ........................... $config->{Verbose}

E_O_CONFIG
    return;
}

1;

#
# That's All Folks!
#
