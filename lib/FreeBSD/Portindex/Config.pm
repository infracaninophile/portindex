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
# @(#) $Id: Config.pm,v 1.28 2004-11-03 21:59:53 matthew Exp $
#

# Utility functions used by the various portindex programs.

package FreeBSD::Portindex::Config;
require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK =
  qw(read_config update_timestamp get_timestamp compare_timestamp
  scrub_environment );
our $VERSION = '1.0';    # Release

use strict;
use warnings;
use Carp;
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;
use POSIX qw(strftime);

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
        CacheDir          => "/var/db/$::pkgname",
        CacheFilename     => "$::pkgname-cache.db",
        ScrubEnvironment  => 0,
        Input             => '-',
        Format            => 'cvsup-output',
        Output            => '-',
        PortsDir          => '/usr/ports',
        PropagationDelay  => 3600,                     # 1 hour
        TimestampFilename => "$::pkgname-timestamp",
        Verbose           => 1,
    );
    @optargs = (
        'cache-dir|c=s'      => \$config->{CacheDir},
        'cache-file|C=s'     => \$config->{CacheFilename},
        'help|?'             => \$help,
        'timestamp-file|T=s' => \$config->{TimestampFilename},
        'quiet'              => sub { $config->{Verbose} = 0 },
        'verbose!'           => \$config->{Verbose},
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
        'propagation-delay=i'  => \$config->{PropagationDelay},
        'scrub-environment|s!' => \$config->{ScrubEnvironment},
      )
      if ( $0 eq 'cache-update' );
    push @optargs,
      (
        'ports-dir=s'          => \$config->{PortsDir},
        'scrub-environment|s!' => \$config->{ScrubEnvironment},
      )
      if ( $0 eq 'cache-init' );
    push @optargs, (
        '<>' => sub {
            my $optval = shift;
            my @date;

            die "$0: Incorrect time specification $optval\n"
              unless $optval =~
              m@^(\d\d\d\d)\.(\d\d)\.(\d\d)\.(\d\d)\.(\d\d)\.(\d\d)\Z@;
            $date[5] = $1 - 1900;    # Year
            $date[4] = $2 - 1;       # Month
            $date[3] = $3;           # Day
            $date[2] = $4;           # Hour
            $date[1] = $5;           # Minute
            $date[0] = $6;           # Second

            $::Config{ReferenceTime} = strftime '%s', @date;    # Localtime
        },
      )
      if ( $0 eq 'find-updated' );

    for my $cf (
        "/usr/local/etc/${main::pkgname}.cfg",
        (
            $> == 0    # Don't let root be trojanned
            ? ()
            : ( "$ENV{HOME}/.${main::pkgname}rc", "./.${main::pkgname}rc" )
        )
      )
    {
        do $cf;
    }
    GetOptions(@optargs) or pod2usage(2);
    if ( $0 eq 'find-updated' && !exists $::Config{ReferenceTime} ) {
        pod2usage(2);
    }
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

    PortsDir (cache-init) ........................ $config->{PortsDir}
    CacheDir ..................................... $config->{CacheDir}
    CacheFilename ................................ $config->{CacheFilename}
    ScrubEnvironment (cache-init, cache-update) .. $config->{ScrubEnvironment}
    Input (cache-update) ......................... $config->{Input}
    Format (cache-update) ........................ $config->{Format}
    PropagationDelay (cache-update) .............. $config->{PropagationDelay}
    Output (portindex, find-updated) ............. $config->{Output}
    TimestampFilename ............................ $config->{TimestampFilename}
    Verbose ...................................... $config->{Verbose}

E_O_CONFIG
    return;
}

# Update the timestamp file -- write the current time into the
# TimeStamp file.  This is the time of the start of any session when
# data is written to the cache.  Only needed because a read-only
# access to the cache updates the mtimes of all of the files.
sub update_timestamp ($)
{
    my $config = shift;

    open TSTMP, '>', "$config->{CacheDir}/$config->{TimestampFilename}"
      or die "$0: Can't update timestamp $config->{TimestampFilename} -- $!\n";
    print TSTMP scalar localtime(), "\n";
    close TSTMP;
    return;
}

# Return the mtime of the timestamp file
sub get_timestamp ($)
{
    my $config = shift;

    return ( stat "$config->{CacheDir}/$config->{TimestampFilename}" )[9]
      or die "$0: can't stat $config->{TimestampFilename} -- $!\n";
}

# Return true if the portindex timestamp is *newer* than the file
# timestamp, false otherwise -- in which case, it's probably time to
# re-run cache-init.
sub compare_timestamp ($$)
{
    my $config = shift;
    my $file   = shift;

    my $p_mtime;
    my $f_mtime;

    $p_mtime = get_timestamp($config);
    $f_mtime = ( stat $file )[9]
      or warn "$0: can't stat $file -- $!\n";
    warn "$0: WARNING: $file more recently modified than last cache update",
      " -- time for cache-init again?\n"
      if ( !defined $f_mtime || $f_mtime > $p_mtime );
    return ( $p_mtime > $f_mtime );
}

# Clear everything out of the environment except for some standard
# variables.
sub scrub_environment ($)
{
    my $config      = shift;
    my $allowed_env = qr{^(USER|HOME|PATH|SHELL|TERM|TERMCAP)\Z};

    for my $var ( keys %ENV ) {
        delete $ENV{$var}
          unless $var =~ m/$allowed_env/;
    }
    return;
}

1;

#
# That's All Folks!
#
