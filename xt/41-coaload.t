#!/usr/bin/env perl

use strict;
use warnings;

use Test2::V0;
use Test2::Tools::Spec;

use Capture::Tiny qw(capture);

use LedgerSMB::Database;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init($OFF);


my @missing = grep { ! $ENV{$_} } (qw(LSMB_NEW_DB COA_TESTING LSMB_TEST_DB));
skip_all((join ', ', @missing) . ' not set') if @missing;

use File::Find::Rule;

my $rule = File::Find::Rule->new;
$rule->or($rule->new
               ->directory
               ->name(qr(gifi|sic))
               ->prune
               ->discard,
          $rule->new);
my @files = sort $rule->name("*.sql")->file->in("sql/coa");

for my $sqlfile (@files) {
    tests $sqlfile => { async => 1 }, sub {
        # Generate test database name based on sql file name
        my ($db) = $sqlfile =~ m|^sql/(coa/.+)\.sql$|
            or die "failed to extract test_name from filename $sqlfile";
        $db =~ s|\W|_|g; # replace non-word characters with underscores
        $db = "lsmb_test_$db";

        my ($stdout, $stderr, $rv) = capture {
            system('dropdb', $db);
            (system('createdb', $db, '-T', $ENV{LSMB_NEW_DB}) >> 8 == 0)
                or die "Failed to create database $db: $!"; # sytem() returns 0 on success => 'and'
        };

        ok((system('psql', $db, '-f', $sqlfile) >> 8) == 0, "psql run file succeeded ($!)");

        my $lsmb_db = LedgerSMB::Database->new(
            connect_data => {
                dbname       => $db,
                user         => $ENV{PGUSER},
                password     => $ENV{PGPASSWORD},
            });
        my $dbh = $lsmb_db->connect;
        my $sth = $dbh->prepare(q{SELECT COUNT(*), 'TESTRESULT' from account});
        $sth->execute or die 'Failed to query test result: ' . $sth->errstr;
        my ($count) = $sth->fetchrow_array();
        ok($count, "Got rows back for account, for $sqlfile");
        $sth->finish;
        $dbh->disconnect;

        capture {
            system('dropdb', $db);
        };
    };
}

done_testing;
