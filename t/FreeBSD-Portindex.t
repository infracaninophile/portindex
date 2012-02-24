# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl FreeBSD-Portindex.t'
# @(#) $Id$

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 9;

BEGIN {
    use_ok('FreeBSD::Portindex::Category');
    use_ok('FreeBSD::Portindex::Config');
    use_ok('FreeBSD::Portindex::FileObject');
    use_ok('FreeBSD::Portindex::GraphViz');
    use_ok('FreeBSD::Portindex::ListVal');
    use_ok('FreeBSD::Portindex::Port');
    use_ok('FreeBSD::Portindex::PortsTreeObject');
    use_ok('FreeBSD::Portindex::Tree');
    use_ok('FreeBSD::Portindex::TreeObject');
}

# 9

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

