# $Id: StackedProcessor.pm,v 1.7 2004/12/10 22:48:04 daisuke Exp $
#
# Daisuke Maki <daisuke@cpan.org>
# All rights reserved.

package POE::Component::StackedProcessor;
use strict;
our $VERSION = '0.01';
use base qw(Class::Data::Inheritable);
use Class::MethodMaker
    new_with_init  => 'new',
    new_hash_init  => 'hash_init',
    list           => [ qw(Processors) ],
    get_set        => [ qw(OnSuccess OnFailure) ],
;
use Params::Validate qw(validate validate_with ARRAYREF CODEREF SCALAR);
use POE;

__PACKAGE__->mk_classdata(qw(callback_name));
__PACKAGE__->callback_name('process');

my %InitValidate = (
    Alias         => { type => SCALAR,   default => 'SP' },
    Processors    => { type => ARRAYREF, default => [] },
    ProcessorArgs => { type => ARRAYREF, default => [] },
    OnSuccess     => { type => CODEREF,  default => \&noop_success },
    OnFailure     => { type => CODEREF,  default => \&noop_fail    },
);
sub init
{
    my $self = shift;
    my %args  = validate(@_, \%InitValidate);

    if (scalar @{$args{Processors}}) {
        validate_with(
            params => $args{Processors},
            spec   => [ ({ can => $self->callback_name }) x scalar @{$args{Processors}} ],
            called => ref($self) . "::new"
        );
    }

    my $alias   = delete $args{Alias};
    my $pr_args = delete $args{ProcessorArgs};

    $self->hash_init(%args);
        
    POE::Session->create(
        object_states => [
            $self, [ qw(_start _stop next_processor) ]
        ],
        heap => { args => $pr_args },
        args => [ $alias ],
    );
}

sub _start
{
    my ($kernel, $alias) = @_[KERNEL, ARG0];
    $kernel->alias_set($alias);
    $kernel->yield('next_processor', 0);
}

sub _stop
{
    my ($kernel) = @_[KERNEL];
    $kernel->alias_remove();
}

sub next_processor
{
    my($self, $pr_idx, $heap) = @_[OBJECT, ARG0, HEAP];

    my $pr    = $self->Processors_index($pr_idx);
    my $cb    = $self->callback_name();
    my $ret   = eval {
        # XXX - need to figure out what to pass to this guy
        $pr->$cb(@{ $heap->{args} }); 
    };
    warn if $@;

    if ($@ || !$ret) {
        warn if $@;
        $self->OnFailure();
    } else {
        my $next = $pr_idx + 1;
        if ($self->Processors_count() > $next) {
            return POE::Kernel->yield('next_processor', $next);
        } else {
            $self->OnSuccess();
        }
    }
    POE::Kernel->yield();
}

sub noop_success { warn "Success" }
sub noop_fail    { warn "Fail"    }

1;

__END__

=head1 NAME

POE::Component::StackedProcessor - Stack Processors In POE

=head1 SYNOPSIS

  use POE::Component::StackedProcessor;
  POE::Component::StackedProcessor->new(
    Alias      => $alias,
    Processors => [ $proc1, $proc2, $proc3 ],
    OnSuccess  => \&callback,
    OnFailure  => \&callback,
    ProcessorArgs => [ $foo, $bar, $baz ],
  );
  POE::Kernel->run();

=head1 DESCRIPTION

POE::Component::StackedProcessor allows you to build a chain of processors
whose dispatching depends on the successful completion of the previous
processor.

For example, suppose you have an HTML document that requires you to verify
whethere it meats certain criteria such as proper markup, valid links, etc.

All you need to do is to create objects that have a method "process", and
then you can invoke this from the stacked processor.

  package CheckMarkup;
  sub new { ... }
  sub process { ... }

  package ValidateLinks;
  sub new { ... }
  sub process { ... }

  package main;
  my $cm = CheckMarkup->new;
  my $vl = ValidateLink->new;
  POE::Component::StackedProcessor->new(
    Processors => [ $cm, $vl ],
  );

Normally this would be done in one pass for the sake of efficiency, but
sometimes you want to break these steps up into several components such that
you can mix and match the differnt processors as required.

=head1 METHOD

=head2 new ARGS

=over 4

=item Processors

An arrayref of processor objects. Each of these object must have a method
denoted by "callback_name" (which is by default "process")

=item ProcessArgs

An arrayref of arguments that should be passed to the processors. 

=item OnSuccess / OnFailure

Specify a callback to be executed on completion of processing. You must pass
a reference to a code ref.

If you want events to be posted to a session or such, pass a postback code

  POE::Component::StackedProcessor->new(
    OnSuccess => $session->postback('my event')
  );

=back

=head2 callback_name

This is a class-method to specify at run time what method name should be
called on the processor objects. The default is "process".

=head1 SEE ALSO

L<POE>

=head1 AUTHOR

Daisuke Maki E<lt>daisuke@cpan.orgE<gt>

=cut