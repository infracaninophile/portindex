# @(#) $Id: Makefile.PL,v 1.7 2009-05-04 10:29:50 matthew Exp $
use inc::Module::Install;

name			'FreeBSD-Portindex';
version_from	'lib/FreeBSD/Portindex/Tree.pm';

abstract		'Incremental FreeBSD ports INDEX file generation';
author			'Matthew Seaman <m.seaman@infracaninophile.co.uk>';
license			'bsd';
perl_version	'5.008003';

requires		'BerkeleyDB' => '0.25';
install_script  'cache-init';
install_script  'cache-update';
install_script  'find-updated';
install_script  'portindex';

WriteAll;
