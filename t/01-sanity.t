#!perl
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
    { ok_to_fail => 1, text => 'axbxcxdxexfxgxhxixjxk' },
    { ok_to_fail => 0, text => ' axxb' }
);
my $nox  = NoX->new;
my $chr  = EightChars->new;

POE::Component::StackedProcessor->new(
    Alias => "sp",
    Processors => [ $nox, $chr ],
    InlineStates => {
        success => \&success,
        failure => \&failure,
    }
);

sub success
{
    my($response) = @_[ARG1];
    my $input = $response->[0];
    ok(!$input->{ok_to_fail}, "Processed input");
    ok($input->{text} !~ /x/, "No X's");
    ok(length($input->{text}) <= 8, "Less than 8 chars");
}

sub failure
{
    my($response) = @_[ARG1];
    my $input = $response->[0];
    ok($input->{ok_to_fail}, "Processed input");
}

foreach my $input (@inputs) {
    POE::Kernel->post('sp', 'process', 'success', 'failure', $input);
}

POE::Kernel->run();
