#!perl
use strict;
use Test::More qw(no_plan);
BEGIN { use_ok("POE::Component::StackedProcessor"); }

package NoX;
use strict;
sub new { bless {}, shift }
sub process {
    my $self = shift;
    my $text_ref = shift;
    $$text_ref =~ s/x/_/ig
}

package main;
use strict;

my $text = "axbxcxdxexfxgxhxixjxk";
my $nox  = NoX->new;
my $p = POE::Component::StackedProcessor->new(
    Processors => [ $nox ],
    ProcessorArgs => [ \$text ],
    OnSuccess     => \&success
);

sub success
{
    warn "foo";
}

POE::Kernel->run();
