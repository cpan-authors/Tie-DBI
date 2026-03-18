requires 'DBI';

on 'test' => sub {
    requires 'Test::More';
    requires 'DBD::SQLite';
    requires 'Test::Pod';
    requires 'Test::Pod::Coverage';
};
