# @(#) $Id: Makefile.PL,v 1.2 2004-11-01 13:34:02 matthew Exp $
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'FreeBSD::Portindex',
    VERSION_FROM => 'lib/FreeBSD/Portindex/Port.pm', # finds $VERSION
    PREREQ_PM    => { BerkeleyDB => 0.25 },          # e.g., Module::Name => 1.1
    EXE_FILES    => [
        'bin/cache-init',   'bin/cache-update',
        'bin/find-updated', 'bin/portindex'
    ],
    (
        $] >= 5.005
        ?    ## Add these new keywords supported since 5.005
          (

            # retrieve abstract from module
            ABSTRACT => 'Incremental FreeBSD ports INDEX file generation',
            AUTHOR   => 'Matthew Seaman <m.seaman@infracaninophile.co.uk>' )
        : ()
    ),
);
