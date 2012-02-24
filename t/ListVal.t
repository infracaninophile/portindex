# @(#) $Id$

use Test::More tests => 68;

BEGIN {
    use_ok('FreeBSD::Portindex::ListVal');
}

# 1

# ListVal -- basic operations

my $lv = FreeBSD::Portindex::ListVal->new();

ok( defined $lv,                             'new() returns defined value' );
ok( $lv->isa('FreeBSD::Portindex::ListVal'), 'object of the expected class' );
is( $lv->length(), 0, 'starts empty' );
$lv->insert( 'a', 'b', 'c' );
is( $lv->length(), 3, 'add content' );

# 5

ok( $lv->contains('a'),  'can retrieve single value' );
ok( $lv->contains('b'),  'can retrieve single value' );
ok( $lv->contains('c'),  'can retrieve single value' );
ok( !$lv->contains('d'), 'can\'t retrieve what wasn\'t inserted' );
$lv->insert('a');
is( $lv->length(), 3, 'duplicate value suppressed' );
$lv->insert('d');
is( $lv->length(), 4, 'non-duplicate value added' );
ok( $lv->contains('d'), 'can retrieve the added value' );
is( $lv->item(0), 'a',   'can retrieve by index(0)' );
is( $lv->item(1), 'b',   'can retrieve by index(1)' );
is( $lv->item(2), 'c',   'can retrieve by index(2)' );
is( $lv->item(3), 'd',   'can retrieve by index(3)' );
is( $lv->item(4), undef, 'retrieve index(4) out-of-bounds returns undef' );

# 17

my $x = $lv->get();
is( ref($x), 'ARRAY',       'returns array ref in scalar context' );
is( @{$x},   $lv->length(), 'all contents recovered' );
for ( 0 .. 3 ) {
    ok( $lv->contains( $x->[$_] ), "retrieved value->[$_] exists in list" );
}

# 23

my @x = $lv->get();
is( @x, $lv->length(), 'returns array of correct size in array context' );
for ( 0 .. 3 ) {
    ok( $lv->contains( $x[$_] ), "retrieved value[$_] exists in list" );
}

# 28

$x = $lv->get_sorted();
is( ref($x), 'ARRAY',       'returns sorted array ref in scalar context' );
is( @{$x},   $lv->length(), 'all contents recovered' );
for ( 0 .. 3 ) {
    ok( $lv->contains( $x->[$_] ), "retrieved value->[$_] exists in list" );
    is( $lv->item($_), $x->[$_], "retrieved value->[$_] same order as list" );
}

# 38

@x = $lv->get_sorted();
is( @x, $lv->length(),
    'returns sorted array of correct size in array context' );
for ( 0 .. 3 ) {
    ok( $lv->contains( $x[$_] ), "retrieved value[$_] exists in list" );
    is( $lv->item($_), $x[$_], "retrieved value[$_] same order as list" );
}

# 47

my @y = ( 'e', 'f', 'g', 'h' );
$lv->set(@y);

for $x (@x) {
    ok( !$lv->contains($x), "set() has replaced original value '$x'" );
}
for my $y (@y) {
    ok( $lv->contains($y), "set() has inserted new value '$y'" );
}

# 55

is( $lv->freeze(), "e\000f\000g\000h\000",
    "freeze() produces expected output" );

# 56

my $lv2 = FreeBSD::Portindex::ListVal->thaw("i\000j\000k\000l\000");
ok( defined($lv2),                            'thaw returns defined value' );
ok( $lv2->isa('FreeBSD::Portindex::ListVal'), 'object of expected class' );

ok( $lv2->contains('i'), 'can retrieve single value' );
ok( $lv2->contains('j'), 'can retrieve single value' );
ok( $lv2->contains('k'), 'can retrieve single value' );
ok( $lv2->contains('l'), 'can retrieve single value' );
ok( !$lv->contains('m'), 'can\'t retrieve what wasn\'t inserted' );

# 63

$x = [ 'a', 'b' ];
$y = [ 'b', 'd' ];

$lv = FreeBSD::Portindex::ListVal->difference( $x, $y );
ok( defined($lv), 'difference returns defined value' );
ok( $lv->isa('FreeBSD::Portindex::ListVal'), 'object of expected class' );

ok( $lv->contains('a'),  'value only in first list' );
ok( $lv->contains('d'),  'value only in second list' );
ok( !$lv->contains('b'), 'value in both lists' );

# 68

#
# That's All Folks!
#

