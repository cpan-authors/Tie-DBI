use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my %test_requires = (
    'Test::More'  => 0,
    'DBD::SQLite' => 0,
);

WriteMakefile(
    'NAME'          => 'Tie::DBI',
    'AUTHOR'        => 'Lincoln D. Stein <lds@cpan.org>',
    'VERSION_FROM'  => 'lib/Tie/DBI.pm',                    # finds $VERSION
    'ABSTRACT_FROM' => 'lib/Tie/DBI.pm',
    'PREREQ_PM'     => {
        'DBI'         => 0,
        # On old EUMM (< 6.64), TEST_REQUIRES is not supported,
        # so test deps fall back into PREREQ_PM.
        ( $ExtUtils::MakeMaker::VERSION < 6.64 ? %test_requires : () ),
    },
    ( $ExtUtils::MakeMaker::VERSION >= 6.64 ? ( 'TEST_REQUIRES' => \%test_requires ) : () ),
    ( $ExtUtils::MakeMaker::VERSION >= 6.3002 ? ( 'LICENSE' => 'perl', ) : () ),
    'DISTNAME' => 'Tie-DBI',
    'MIN_PERL_VERSION' => 5.008,
    'dist'     => {
        'COMPRESS' => 'gzip -9f',     'SUFFIX'   => 'gz',
        'ZIP'      => '/usr/bin/zip', 'ZIPFLAGS' => '-rl'
    },
    'clean'      => { FILES => 'Tie-DBI-* test:* depth_test' },
    'META_MERGE' => {
        'meta-spec' => { version => 2 },
        prereqs => {
            test => {
                requires => \%test_requires,
            },
        },
        resources => {
            license    => ['https://dev.perl.org/licenses/'],
            homepage   => 'https://github.com/cpan-authors/Tie-DBI',
            bugtracker => {
                web => 'https://github.com/cpan-authors/Tie-DBI/issues',
            },
            repository => {
                type => 'git',
                url  => 'https://github.com/cpan-authors/Tie-DBI.git',
                web  => 'https://github.com/cpan-authors/Tie-DBI',
            },
        },
    },
  )
