#!perl
use strict;
use Test::More qw(no_plan);
BEGIN { use_ok ("POE::Component::StackedProcessor") }

our %VISITED;

package P1;
use strict;
sub new { bless {}, shift }
sub process {
    $main::VISITED{P1}++;
    return 1;
}

package P2;
use strict;
sub new { bless {}, shift }
sub process {
    $main::VISITED{P2}++;
    return 1;
}

package P3;
use strict;
sub new { bless {}, shift }
sub process {
    $main::VISITED{P3}++;
    return 1;
}

package main;
use strict;
use POE;

my $p = POE::Component::StackedProcessor->new(
    InlineStates => {
        success => \&success
    }
);
$p->add(P1 => P1->new, sub { 'P3' });
$p->add(P2 => P2->new);
$p->add(P3 => P3->new);
sub success
{
    my($request, $response) = @_[ARG0, ARG1];
    $VISITED{SUCCESS}++;
}

POE::Kernel->post($p->alias, 'process', 'success', undef, 1);
POE::Kernel->run();

# should have only visited P1->P3
ok($VISITED{P1} == 1, "Visited P1");
ok($VISITED{P2} == 0, "NOT Visited P2");
ok($VISITED{P3} == 1, "Visited P3");
ok($VISITED{SUCCESS} == 1, "Visited SUCCESS");

