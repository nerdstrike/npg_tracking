# $Id: 80-email-run_lane_annotation.t 14928 2012-01-17 13:57:20Z mg8 $
use strict;
use warnings;
use DateTime;
use DateTime::Format::MySQL;
use Perl6::Slurp;
use Test::More tests => 14;
use Test::Deep;
use Test::Exception::LessClever;
use Test::MockModule;

use t::dbic_util;
use t::util;

use Readonly; Readonly::Scalar our $VERSION => do { my ($r) = q$Revision: 14928 $ =~ /(\d+)/msx; $r; };


local $ENV{dev} = 'test';
my $schema    = t::dbic_util->new->test_schema();
my $util      = t::util->new();
$util->catch_email($util);

my $test;

BEGIN {
  use_ok( q{npg::email::event::annotation::run_lane} );
}

my $event_row = $schema->resultset('Event')->find(30);

my $batch_details = {
  lanes => [],
};

foreach my $position ( 1..8 ) {
  push @{ $batch_details->{lanes} }, {
    position => $position, library => q{human},
  };
}

lives_ok { 
  $test = npg::email::event::annotation::run_lane->new({
    event_row   => $event_row,
    schema_connection => $schema,
    batch_details => $batch_details,
  })
} q{Can create with event row object};

is( $test->template(), q{run_lane_annotation.tt2}, q{correct template name obtained} );

is( $test->user(), q{pipeline}, q{user returns username} );
is( $test->event_row->description(), q{This is a run lane annotation.}, q{annotation retrieved from description} );

my $email_template;
lives_ok { $email_template = $test->compose_email() } q{compose email runs ok};

my $email = q{This email was generated from a test as part of the development process of the NPD group. If you are reading this, the test failed as the email should not have 'escaped' and actually have been sent. (Or it was you that was running the test.)

Please ignore the contents below, and apologies for the inconvenience.


Run 1 lane 7 has had the following annotation added in NPG tracking.

This is a run lane annotation.

The database reports the following lanes on this run:

Lane - 1: Library - human
Lane - 2: Library - human
Lane - 3: Library - human
Lane - 4: Library - human
Lane - 5: Library - human
Lane - 6: Library - human
Lane - 7: Library - human
Lane - 8: Library - human


You can get more detail about the run through NPG:

http://npg.sanger.ac.uk/perl/npg/run/1

This email was automatically generated by New Pipeline Development monitoring system.

};

my @expected_lines = split /\n/xms, $email;
my @obtained_lines = split /\n/xms, $test->next_email();
is_deeply( \@obtained_lines, \@expected_lines, q{generated email is correct} );

my $watchers = $test->watchers();
is_deeply( $watchers, [ qw{full@address.already joe_engineer@sanger.ac.uk joe_results@sanger.ac.uk} ], q{watchers are is correct} );

lives_ok {
  $test->run();
} q{run method ok};

$email = $util->parse_email( $util->{emails}->[0] );
is( $email->{subject}, q{Run Lane 1_7 has been annotated by pipeline} . qq{\n}, q{subject is correct} );
is( $email->{to}, q{full@address.already, joe_engineer@sanger.ac.uk, joe_results@sanger.ac.uk} . qq{\n}, q{correct recipients} );
is( $email->{from}, q{srpipe@sanger.ac.uk} . qq{\n}, q{from is correct} );
@obtained_lines = split/\n/xms, $email->{annotation};
is_deeply( \@obtained_lines, \@expected_lines, q{email body is correct} );

ok( $event_row->notification_sent(), q{notification recorded} );

1;