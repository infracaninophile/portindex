# @(#) $Id: Makefile.PL,v 1.4 2009-05-03 09:36:30 matthew Exp $
use inc::Module::Install;

name			'FreeBSD-Portindex';
all_from		'lib/FreeBSD/Portindex/Tree.pm';

abstract		'Incremental FreeBSD ports INDEX file generation';
author			'Matthew Seaman <m.seaman@infracaninophile.co.uk>';
install_script  'bin/cache-init';
install_script  'bin/cache-update';
install_script  'bin/find-updated';
install_script  'bin/portindex';

requires		'BerkeleyDB' => '0.25';

WriteAll;
