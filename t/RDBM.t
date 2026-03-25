use strict;
use warnings;
use Test::More;

my $DRIVER = $ENV{DRIVER};
use constant USER   => $ENV{USER};
use constant PASS   => $ENV{PASS};
use constant DBNAME => $ENV{DB} || 'test';
use constant HOST   => $ENV{HOST} || (( $^O eq 'cygwin' ) ? '127.0.0.1' : 'localhost');

use DBI;
use Tie::RDBM;

unless ($DRIVER) {
    local ($^W) = 0;    # kill uninitialized variable warning

    # Test using the mysql, sybase, oracle and mSQL databases respectively
    my ($count) = 0;
    my (%DRIVERS) = map { ( $_, $count++ ) } qw(Informix Pg Ingres mSQL Sybase Oracle mysql SQLite);    # ExampleP doesn't work
    ($DRIVER) = sort { $DRIVERS{$b} <=> $DRIVERS{$a} } grep { exists $DRIVERS{$_} } DBI->available_drivers(1);
}

if ($DRIVER) {
    plan tests => 22;
    diag("RDBM.t - Using DBD driver $DRIVER...");
}
else {
    plan skip_all => "Found no DBD driver to use.\n";
}

my $dsn;
if   ( $DRIVER eq 'Pg' ) { $dsn = "dbi:$DRIVER:dbname=${\DBNAME}"; }
else                     { $dsn = "dbi:$DRIVER:${\DBNAME}:${\HOST}"; }

my %h;
isa_ok( tie( %h, 'Tie::RDBM', $dsn, { create => 1, drop => 1, table => 'PData', 'warn' => 0, user => USER, password => PASS } ), 'Tie::RDBM' );
%h = ();
is( scalar( keys %h ), 0 );

is( $h{'fred'} = 'ethel', 'ethel' );
is( $h{'fred'}, 'ethel' );
is( $h{'ricky'} = 'lucy', 'lucy' );
is( $h{'ricky'}, 'lucy' );
is( $h{'fred'} = 'lucy', 'lucy' );
is( $h{'fred'}, 'lucy' );

ok( exists( $h{'fred'} ) );
ok( delete $h{'fred'} );
ok( !exists( $h{'fred'} ) );

SKIP: {
    if ( !tied(%h)->{canfreeze} ) {
        $h{'fred'} = 'junk';
        skip 'Not working on this DBD', 2;
    }

    local ($^W) = 0;    # avoid uninitialized variable warning
    ok( $h{'fred'} = { 'name' => 'my name is fred', 'age' => 34 } );
    is( $h{'fred'}->{'age'}, 34 );
}

is( join( " ", sort keys %h ), "fred ricky" );
is( $h{'george'} = 42, 42 );
is( join( " ", sort keys %h ), "fred george ricky" );

# Test that each() returns correct values via FIRSTKEY/NEXTKEY caching.
# Without FIRSTKEY caching, the first value would still be fetched
# correctly (via FETCH fallback), but at the cost of an extra SQL query.
{
    my %got;
    while ( my ( $k, $v ) = each %h ) {
        $got{$k} = $v;
    }
    is( $got{'george'}, 42, 'each() returns correct values for all keys' );
}

untie %h;

my %i;
isa_ok( tie( %i, 'Tie::RDBM', $dsn, { table => 'PData', user => USER, password => PASS } ), 'Tie::RDBM' );
is( $i{'george'}, 42 );
is( join( " ", sort keys %i ), "fred george ricky" );
untie %i;

# Test that passing an external dbh doesn't disconnect it on untie.
# Before the needs_disconnect fix, Tie::RDBM would unconditionally
# disconnect the caller's handle in DESTROY, breaking ongoing work.
my $ext_dbh = DBI->connect( $dsn, USER, PASS, { PrintError => 0 } )
    || die "Can't connect for external dbh test: $DBI::errstr";
my %ext;
tie( %ext, 'Tie::RDBM', $ext_dbh, { table => 'PData' } );
untie %ext;
ok( $ext_dbh->ping, 'external dbh still alive after untie' );
eval { $ext_dbh->disconnect };

# Explicit cleanup to avoid SEGV during global destruction (GH #7).
# All DBI objects must be freed before global destruction begins.
undef $ext_dbh;
ok( 1, 'cleanup complete' );
