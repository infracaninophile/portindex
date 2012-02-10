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

# Utility functions used by the various portindex programs.

package FreeBSD::Portindex::Config;

require 5.008_003;

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case);
use Pod::Usage;
use POSIX qw(strftime);
use Exporter qw(import);

our @EXPORT_OK = qw(%Config read_config update_timestamp get_timestamp
  compare_timestamps scrub_environment counter _clean);
our $VERSION = '2.8';    # Release

# The ultimate defaults...
our %Config;

# Config file and command line option handling.  The config data is
# loaded from (in order): defaults built into this function, the
# system etc dir: /usr/local/etc/${pkgname}.cfg the users' home dir
# $ENV{HOME}/.${pkgname}rc or the current directory ./.${pkgname}rc --
# entries in the later files on that list override the earlier ones.
# Config files consist of live perl code to populate the %Config hash,
# which is the return value of this function.  Then any command line
# arguments are parsed, which can override any of the config file
# settings.
sub read_config ($)
{
    my $pkgname = shift;

    my $help;
    my @optargs;
    my $ubiquitous_makefiles_seen = 0;
    my $endemic_makefiles_seen    = 0;

    %Config = (
        CacheDir         => "/var/db/$pkgname",
        CacheFilename    => "$pkgname-cache.db",
        CrunchWhitespace => 0,
        EndemicMakefiles => [
            qw(
              /usr/ports/Mk/bsd.commands.mk
              /usr/ports/Mk/bsd.licenses.db.mk
              /usr/ports/Mk/bsd.licenses.mk
              /usr/ports/Mk/bsd.sites.mk
              /usr/share/mk/bsd.compat.mk
              /usr/share/mk/bsd.cpu.mk
              /usr/share/mk/bsd.own.mk
              /usr/share/mk/bsd.port.mk
              /usr/share/mk/bsd.port.options.mk
              /usr/share/mk/bsd.port.post.mk
              /usr/share/mk/bsd.port.pre.mk
              /usr/share/mk/sys.mk
              )
        ],
        Format              => 'cvsup-output,options',
        Input               => '-',
        Output              => '-',
        OutputStyle         => 'default',
        PortDBDir           => $ENV{PORT_DBDIR} || '/var/db/ports',
        PortsDir            => $ENV{PORTSDIR} || '/usr/ports',
        PropagationDelay    => 3600,                                  # 1 hour
        ScrubEnvironment    => 0,
        ShLibs              => 0,
        Strict              => 1,
        TimestampFilename   => "$pkgname-timestamp",
        UbiquitousMakefiles => [
            qw(
              /etc/make.conf
              /usr/ports/Mk/bsd.commands.mk
              /usr/ports/Mk/bsd.licenses.mk
              /usr/ports/Mk/bsd.perl.mk
              /usr/ports/Mk/bsd.port.mk
              /usr/ports/Mk/bsd.sites.mk
              /usr/share/mk/bsd.compat.mk
              /usr/share/mk/bsd.cpu.mk
              /usr/share/mk/bsd.own.mk
              /usr/share/mk/bsd.port.mk
              /usr/share/mk/sys.mk
              )
        ],
        Verbose  => 1,
        Warnings => 0,
    );

    @optargs = (
        'cache-dir|c=s'      => \$Config{CacheDir},
        'cache-file|C=s'     => \$Config{CacheFilename},
        'help|?'             => \$help,
        'timestamp-file|T=s' => \$Config{TimestampFilename},
        'quiet'              => sub { $Config{Verbose} = 0 },
        'verbose!'           => \$Config{Verbose},
        'warnings!'          => \$Config{Warnings},
    );
    push @optargs, (
        'output=s'  => \$Config{Output},
        'style|s=s' => sub {
            my $optname  = shift;
            my $optvalue = shift;

            if ( $optvalue =~ m/^(g|graph)\Z/ ) {
                $Config{OutputStyle} = 'graph';
            } elsif ( $optvalue =~ m/^(s|short)\Z/ ) {
                $Config{OutputStyle} = 'short';
            } else {
                $Config{OutputStyle} = 'default';
            }
        },
    ) if ( $0 eq 'portdepends' );
    push @optargs,
      (
        'output=s'        => \$Config{Output},
        'crunch-white|W!' => \$Config{CrunchWhitespace},
        'shlibs|L!'       => \$Config{ShLibs},
        'strict!'         => \$Config{Strict},
      ) if ( $0 eq 'portindex' );
    push @optargs, (
        'input|i=s'  => \$Config{Input},
        'format|f=s' => sub {
            my $optname  = shift;
            my $optvalue = shift;

            die "$0: Option --$optname unrecognised argument: $optvalue\n"
              unless $optvalue =~ m@
                  ^(
                     (
                      plain|cvsup-(output|checkouts)
                     )
                     (,options)?
                   )
                  |
                   options
                  \Z
                  @x;

            $Config{Format} = $optvalue;
        },
        'propagation-delay|P=i' => \$Config{PropagationDelay},
        'port-dbdir|d=s'        => \$Config{PortDBDir},
    ) if ( $0 eq 'cache-update' );
    push @optargs, (
        'ports-dir=s'              => \$Config{PortsDir},
        'scrub-environment|s!'     => \$Config{ScrubEnvironment},
    ) if ( $0 eq 'cache-init' || $0 eq 'cache-update' );
    push @optargs, (
        'ubiquitous-makefile|M=s@' => sub {
            my $optname  = shift;
            my $optvalue = shift;

            # Discard built-in defaults for this list of Makefiles if
            # any are given on the command-line

            $Config{UbiquitousMakefiles} = []
              unless $ubiquitous_makefiles_seen++;

            push @{ $Config{UbiquitousMakefiles} }, $optvalue;
        },
        'endemic-makefile|m=s@' => sub {
            my $optname  = shift;
            my $optvalue = shift;

            # Discard built-in defaults for this list of Makefiles if
            # any are given on the command-line

            $Config{EndemicMakefiles} = []
              unless $endemic_makefiles_seen++;

            push @{ $Config{EndemicMakefiles} }, $optvalue;
        },
    ) if ( $0 eq 'cache-init' );
    push @optargs, (
        'ports-dir=s' => \$Config{PortsDir},
        '<>'          => sub {
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

            $Config{ReferenceTime} = strftime '%s', @date;    # Localtime
        },
    ) if ( $0 eq 'find-updated' );

    for my $cf (
        "/usr/local/etc/${pkgname}.cfg",
        (
            $> == 0    # Don't let root be trojanned
            ? ()
            : ( "$ENV{HOME}/.${pkgname}rc", "./.${pkgname}rc" )
        )
      )
    {
        do $cf;
    }
    GetOptions(@optargs) or pod2usage(2);
    map { $_ = "$Config{PortsDir}/$_" unless m@^/@ }
      @{ $Config{UbiquitousMakefiles} }, @{ $Config{EndemicMakefiles} };
    if ($help) {
        pod2usage( -exitval => 'NOEXIT', -verbose => 1 );
        show_config();
        exit(1);
    }
    if ( $0 eq 'find-updated' && !exists $Config{ReferenceTime} ) {
        pod2usage(2);
    }
    return;
}

# Print out the current configuration settings after config file and
# command line have been processed.
sub show_config ()
{
    my $um_fmt = "  UbiquitousMakefiles (cache-init) ............ ";
    my $em_fmt = "  EndemicMakefiles (cache-init) ............... ";

    print <<"E_O_CONFIG";

Current Configuration:

  Settings after reading all configuration files and parsing the
  command line.  They apply to all programs, except as marked.

  CacheDir .................................... $Config{CacheDir}
  CacheFilename ............................... $Config{CacheFilename}
  CrunchWhitespace (portindex)................. $Config{CrunchWhitespace}
  Format (cache-update) ....................... $Config{Format}
  Input (cache-update) ........................ $Config{Input}
  Output (portindex, portdepends, find-updated) $Config{Output}
  OutputStyle (portdepends) ................... $Config{OutputStyle}
  PortDBDir (cache-update) .................... $Config{PortDBDir}
  PortsDir .................................... $Config{PortsDir}
  PropagationDelay (cache-update) ............. $Config{PropagationDelay}
  ScrubEnvironment (cache-init, cache-update) . $Config{ScrubEnvironment}
  ShLibs (portindex) .......................... $Config{ShLibs}
  Strict (portindex) .......................... $Config{Strict}
  TimestampFilename ........................... $Config{TimestampFilename}
  Verbose ..................................... $Config{Verbose}
  Warnings .................................... $Config{Warnings} 
E_O_CONFIG
    for my $um ( @{ $Config{UbiquitousMakefiles} } ) {
        print $um_fmt, $um, "\n";
        $um_fmt = ' ' x length $um_fmt
          unless $um_fmt =~ m/^ +$/;
    }
    for my $em ( @{ $Config{EndemicMakefiles} } ) {
        print $em_fmt, $em, "\n";
        $em_fmt = ' ' x length $em_fmt
          unless $em_fmt =~ m/^ +$/;
    }
    return;
}

# Update the timestamp file -- write the current time into the
# TimeStamp file.  This is the time of the start of any session when
# data is written to the cache.  Only needed because a read-only
# access to the cache updates the mtimes of all of the files.
sub update_timestamp ()
{
    open TSTMP, '>', "$Config{CacheDir}/$Config{TimestampFilename}"
      or die "$0: Can't update timestamp $Config{TimestampFilename} -- $!\n";
    print TSTMP scalar localtime(), "\n";
    close TSTMP;
    return;
}

# Return the mtime of the timestamp file
sub get_timestamp ()
{
    return ( stat "$Config{CacheDir}/$Config{TimestampFilename}" )[9]
      or die "$0: can't stat $Config{TimestampFilename} -- $!\n";
}

# Return true if the portindex timestamp is *newer* than the file
# timestamp, false otherwise -- in which case, it's probably time to
# re-run cache-init.
sub compare_timestamps ()
{
    my $p_mtime;
    my $f_mtime;
    my $was_updated = 0;

    $p_mtime = get_timestamp();

    for my $file ( @{ $Config{UbiquitousMakefiles} } ) {
        $f_mtime = ( stat $file )[9]
          or do {
            warn "$0: can't stat $file -- $!\n";
            next;
          };
        warn "$0: WARNING: $file more recently modified than last ",
          "cache update -- time for cache-init again?\n"
          if ( $Config{Verbose}
            && ( !defined $f_mtime || $f_mtime > $p_mtime ) );
        $was_updated += ( $p_mtime > $f_mtime );
    }
    return $was_updated;
}

# Clear everything out of the environment except for some standard
# variables.
sub scrub_environment ()
{
    my $allowed_env = qr{^(USER|HOME|PATH|SHELL|TERM|TERMCAP)\Z};

    for my $var ( keys %ENV ) {
        delete $ENV{$var}
          unless $var =~ m/$allowed_env/;
    }
    return;
}

# Print numbers and dots to show progress
sub counter ($)
{
    my $counter = shift;

    if ( $Config{Verbose} && ref $counter ) {
        $$counter++;
        if ( $$counter % 1000 == 0 ) {
            print STDERR "[$$counter]";
        } elsif ( $$counter % 100 == 0 ) {
            print STDERR '.';
        }
    }
}

#
# The make describe data may contain several undesirable constructs
# where ports or files are referred to by path.  Strip these out as
# follows:
#
#  /usr/ports/foo/bar/../../baz/blurfl -> /usr/ports/baz/blurfl
#  /usr/ports/foo/bar/../quux -> /usr/ports/foo/quux
#  /usr/ports/foo/bar/ -> /usr/ports/foo/bar
#
sub _clean(@)
{
    return map {
        s@/[^/]+/[^/]+/\.\./\.\./@/@g;
        s@/[^/]+/\.\./@/@g;
        s@/\Z@@;
        $_
    } @_;
}

1;

#
# That's All Folks!
#
