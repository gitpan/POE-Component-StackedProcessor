#!perl
# $Id: 01-sanity.t 6 2005-01-01 11:40:50Z daisuke $
#
# Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

use strict;
use Test::More qw(no_plan);
BEGIN { use_ok("POE::Component::StackedProcessor"); }

package NoX;
use strict;
sub new { bless {}, shift }
sub process {
    my $self  = shift;
    my $input = shift;
    $input->{text} =~s/x//ig;
    return 1;
}

package EightChars;
use strict;
sub new { bless {}, shift }
sub process {
    my $self  = shift;
    my $input = shift;

    return length($input->{text}) <= 8;
}
        

package main;
use strict;
use POE;

my @inputs = (
    { ok_to_fail => 1, text => 'axbxcxdxexfxgxhxixjxk', fail_index => 1 },
    { ok_to_fail => 0, text => 'axxb' }
);
my $nox  = NoX->new;
my $chr  = EightChars->new;

my $p    = POE::Component::StackedProcessor->new(
    Alias => "sp",
    InlineStates => {
        success => \&success,
        failure => \&failure,
    }
);

$p->add(NOX => $nox);
$p->add(CHR => $chr);

sub success
{
    my($response) = @_[ARG1];
    my $input = $response->[0];
    ok(!$input->{ok_to_fail}, "Processed input (success)");
    ok($input->{text} !~ /x/, "No X's");
    ok(length($input->{text}) <= 8, "Less than 8 chars");
}

sub failure
{
    my($response) = @_[ARG1];
    my($pr, $prdata, $input) = @$response;
    ok($input->{ok_to_fail}, "Processed input (failure)");

    ok($input->{ok_to_fail} &&
        $prdata->{index} == $input->{fail_index}, "Failure index match");
}

foreach my $input (@inputs) {
    POE::Kernel->post('sp', 'process', 'success', 'failure', $input);
}

POE::Kernel->run();
