# @(#) $Id: Makefile.PL,v 1.5 2009-05-03 18:10:22 matthew Exp $
use inc::Module::Install;

name			'FreeBSD-Portindex';
version_from	'lib/FreeBSD/Portindex/Tree.pm';

abstract		'Incremental FreeBSD ports INDEX file generation';
author			'Matthew Seaman <m.seaman@infracaninophile.co.uk>';
license			'bsd';
perl_version	'5.006';

requires		'BerkeleyDB' => '0.25';
install_script  'bin/cache-init';
install_script  'bin/cache-update';
install_script  'bin/find-updated';
install_script  'bin/portindex';

WriteAll;
