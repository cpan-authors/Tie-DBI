use strict;
use warnings;
use Test::More;

my $DRIVER = $ENV{DRIVER};
use constant USER   => $ENV{USER} || $ENV{DBI_USER};
use constant PASS   => $ENV{PASS} || $ENV{DBI_PASS};
use constant DBNAME => $ENV{DB}   || 'test';
use constant HOST   => $ENV{HOST} || ( ( $^O eq 'cygwin' ) ? '127.0.0.1' : 'localhost' );

use DBI;
use Tie::DBI;

######################### End of black magic.

if ( $ENV{DBI_DSN} && !$DRIVER ) {
    ( $DRIVER = $ENV{DBI_DSN} ) =~ s/^dbi:([^:]+):.*$/$1/i;
}

unless ($DRIVER) {
    local ($^W) = 0;    # kill uninitialized variable warning
                        # I like mysql best, followed by Oracle and Sybase
    my ($count) = 0;
    my (%DRIVERS) = map { ( $_, $count++ ) } qw(Informix Pg Ingres mSQL Sybase Oracle mysql SQLite);    # ExampleP doesn't work;
    ($DRIVER) = sort { $DRIVERS{$b} <=> $DRIVERS{$a} } grep { exists $DRIVERS{$_} } DBI->available_drivers(1);
}

if ($DRIVER) {
    plan tests => 34;
    diag("DBI.t - Using DBD driver $DRIVER...");
}
else {
    plan skip_all => "Found no DBD driver to use.\n";
}

my %TABLES = (
    'CSV' => <<END,
CREATE TABLE testTie (
produce_id       char(15),
price            real,
quantity         int,
description      char(30)
)
END
    'mSQL' => <<END,
CREATE TABLE testTie (
produce_id       char(15),
price            real,
quantity         int,
description      char(30)
)
;
CREATE UNIQUE INDEX idx1 ON testTie (produce_id)
END
    'Pg' => <<END,
CREATE TABLE testTie (
produce_id       varchar(15) primary key,
price            real,
quantity         int,
description      varchar(30)
)
END
);

use constant DEFAULT_TABLE => <<END;
CREATE TABLE testTie (
produce_id       char(15) primary key,
price            real,
quantity         int,
description      char(30)
)
END

my @fields    = qw(produce_id     price quantity description);
my @test_data = (
    [ 'strawberries', 1.20, 8,  'Fresh Maine strawberries' ],
    [ 'apricots',     0.85, 2,  'Ripe Norwegian apricots' ],
    [ 'bananas',      1.30, 28, 'Sweet Alaskan bananas' ],
    [ 'kiwis',        1.50, 9,  'Juicy New York kiwi fruits' ],
    [ 'eggs',         1.00, 12, 'Farm-fresh Atlantic eggs' ]
);

sub initialize_database {
    local ($^W) = 0;
    my $dsn;
    if    ( $ENV{DBI_DSN} )   { $dsn = $ENV{DBI_DSN}; }
    elsif ( $DRIVER eq 'Pg' ) { $dsn = "dbi:$DRIVER:dbname=${\DBNAME}"; }
    else                      { $dsn = "dbi:$DRIVER:${\DBNAME}:${\HOST}"; }
    my $dbh = DBI->connect( $dsn, USER, PASS, { PrintError => 0 } ) || return undef;
    $dbh->do("DROP TABLE testTie");
    return $dbh if $DRIVER eq 'ExampleP';
    my $table = $TABLES{$DRIVER} || DEFAULT_TABLE;

    foreach ( split( ';', $table ) ) {
        $dbh->do($_) || warn $DBI::errstr;
    }
    $dbh;
}

sub insert_data {
    my $h = shift;
    my ( $record, $count );
    foreach $record (@test_data) {
        my %record = map { $fields[$_] => $record->[$_] } ( 0 .. $#fields );
        $h->{ $record{produce_id} } = \%record;
        $count++;
    }
    return $count == @test_data;
}

sub chopBlanks {
    my $a = shift;
    $a =~ s/\s+$//;
    $a;
}

my %h;
my $dbh = initialize_database;
{
    local ($^W) = 0;
    ok( $dbh, "DBH returned from init_db" ) or die("Couldn't create test table: $DBI::errstr");
}
isa_ok( tie( %h, 'Tie::DBI', { db => $dbh, table => 'testTie', key => 'produce_id', CLOBBER => 3, WARN => 0 } ), 'Tie::DBI' );

%h = () unless $DRIVER eq 'ExampleP';
is( scalar( keys %h ), 0, '%h is empty' );

# Test SCALAR on empty table: scalar %h should return 0 (falsy)
is( scalar %h, 0, 'scalar %h returns 0 for empty table' );

{
    local $^W = 0;
    ok( insert_data( \%h ), "Insert data into db" );
}

# Test SCALAR on non-empty table: scalar %h should return the row count
is( scalar %h, 5, 'scalar %h returns row count' );
ok( %h, 'non-empty table is truthy in boolean context' );
ok( exists( $h{strawberries} ) );
ok( defined( $h{strawberries} ) );
is( join( " ", map { chopBlanks($_) } sort keys %h ), "apricots bananas eggs kiwis strawberries" );
is( $h{eggs}->{quantity}, 12 );
$h{eggs}->{quantity} *= 2;
is( $h{eggs}->{quantity}, 24 );

my $total_price = 0;
my $count       = 0;
my ( $key, $value );
while ( ( $key, $value ) = each %h ) {
    $total_price += $value->{price} * $value->{quantity};
    $count++;
}
is( $count, 5 );
cmp_ok( abs( $total_price - 85.2 ), '<', 0.01 );

$h{'cherries'} = { description => 'Vine-ripened cherries', price => 2.50, quantity => 200 };
is( $h{'cherries'}{quantity}, 200 );

$h{'cherries'} = { price => 2.75 };
is( $h{'cherries'}{quantity}, 200 );
is( $h{'cherries'}{price},    2.75 );
is( join( " ", map { chopBlanks($_) } sort keys %h ), "apricots bananas cherries eggs kiwis strawberries" );

ok( delete $h{'cherries'} );
is( exists $h{'cherries'}, '' );

my $array = $h{ 'eggs', 'strawberries' };
is( $array->[1]->{'description'}, 'Fresh Maine strawberries' );

my $another_array = $array->[1]->{ 'produce_id', 'quantity' };
is( "@{$another_array}", 'strawberries 8' );

is( @fields = tied(%h)->select_where('quantity > 10'), 2 );
is( join( " ", sort @fields ), 'bananas eggs' );

SKIP: {
    skip "Skipping test for CSV driver...", 1 if ( $DRIVER eq 'CSV' );

    delete $h{strawberries}->{quantity};
    ok( !defined $h{strawberries}->{quantity}, 'Quantity was deleted' );
}

ok( $h{strawberries}->{quantity} = 42 );
ok( $h{strawberries}->{quantity} = 42 );    # make sure update statement works when nothing changes
is( $h{strawberries}->{quantity}, 42 );

# RT 19833 - Trailing space inappropriatley stripped.
use constant TEST_STRING => '  extra spaces  ';
my $before = TEST_STRING;
$h{strawberries}->{description} = $before;
my $after = $h{strawberries}->{description};
is( $after, $before, "blanks aren't chopped" );

# RT 104338 - prepare fails with a question mark in a text field
use constant TEST_STRING_WITH_QUESTION_MARK => 'will this work? I hope so';
$before                         = TEST_STRING_WITH_QUESTION_MARK;
$h{strawberries}->{description} = $before;
$after                          = $h{strawberries}->{description};
is( $after, $before, 'question marks can appear in text fields' );

# Test Record CLEAR: clearing a record should null all non-key fields
# but preserve the key column. Bug: CLEAR used the record's key VALUE
# (e.g. 'strawberries') instead of the key COLUMN NAME (e.g. 'produce_id')
# when excluding the key field, so the key column was incorrectly included
# in the update and the exclusion was a no-op.
SKIP: {
    skip "Skipping CLEAR test for CSV driver...", 2 if ( $DRIVER eq 'CSV' );

    # Set known values first
    $h{eggs}->{price}       = 1.00;
    $h{eggs}->{quantity}    = 12;
    $h{eggs}->{description} = 'Farm-fresh Atlantic eggs';

    # CLEAR the record — should null all non-key fields
    my $record = $h{eggs};
    %$record = ();

    # The key should still exist in the table
    ok( exists $h{eggs}, 'Record still exists after CLEAR' );

    # Non-key fields should be undef/null
    ok( !defined $h{eggs}->{quantity}, 'Non-key field is null after Record CLEAR' );
}

# Record CLEAR should not attempt to set the key field at all.
# Bug: CLEAR built a hash with ALL fields (including key) set to undef, then
# relied on STORE to silently skip it.  With WARN enabled, this produced a
# spurious "Ignored attempt to change value of key field" warning.
SKIP: {
    skip "Skipping CLEAR-warn test for CSV driver...", 1 if ( $DRIVER eq 'CSV' );

    my %warn_hash;
    tie( %warn_hash, 'Tie::DBI', { db => $dbh, table => 'testTie', key => 'produce_id', CLOBBER => 3, WARN => 1 } );
    my $record = $warn_hash{eggs};
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, $_[0] };
    %$record = ();
    my @key_warnings = grep { /key field/ } @warnings;
    is( scalar @key_warnings, 0, 'Record CLEAR does not warn about key field' );
    untie %warn_hash;
}

# Test that DESTROY disconnects when Tie::DBI owns the connection.
# The SEGV-fix loop in DESTROY must not delete the dbh before
# the disconnect call, or connections created via DSN will leak.
{
    my $dsn;
    if    ( $ENV{DBI_DSN} )   { $dsn = $ENV{DBI_DSN}; }
    elsif ( $DRIVER eq 'Pg' ) { $dsn = "dbi:$DRIVER:dbname=${\DBNAME}"; }
    else                      { $dsn = "dbi:$DRIVER:${\DBNAME}:${\HOST}"; }

    my %dsn_hash;
    tie( %dsn_hash, 'Tie::DBI', $dsn, 'testTie', 'produce_id',
        { CLOBBER => 0, WARN => 0, user => USER, password => PASS } );
    my $internal_dbh = tied(%dsn_hash)->dbh;
    untie %dsn_hash;
    ok( !$internal_dbh->ping, 'DSN-created dbh is disconnected after untie' );
    undef $internal_dbh;
}

# Explicit cleanup to avoid SEGV during global destruction (GH #7).
# All DBI objects must be freed before global destruction begins,
# otherwise hash teardown order may free the dbh before cached
# statement handles, causing SEGV in sqlite3_finalize.
undef $value;
undef $array;
undef $another_array;
untie %h;
eval { $dbh->disconnect } if $dbh;
undef $dbh;
