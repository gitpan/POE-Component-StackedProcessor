# $Id: StackedProcessor.pm 3 2004-12-24 03:59:51Z daisuke $
#
# Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package POE::Component::StackedProcessor;
use strict;
our $VERSION = '0.02';
use base qw(Class::Data::Inheritable);
use Class::MethodMaker
    new_with_init  => 'new',
    new_hash_init  => 'hash_init',
    list           => [ qw(alias processors) ],
    get_set        => [ qw(on_success on_failure) ],
;
use Params::Validate ();
use POE;

__PACKAGE__->mk_classdata(qw(callback_name));
__PACKAGE__->callback_name('process');

my %InitValidate = (
    Alias         => { type => Params::Validate::SCALAR(),   default => 'SP' },
    Processors    => { type => Params::Validate::ARRAYREF(), default => [] },
    InlineStates  => { type => Params::Validate::HASHREF(),  optional => 1 },
    PackageStates => { type => Params::Validate::HASHREF(),  optional => 1 },
    ObjectStates  => { type => Params::Validate::HASHREF(),  optional => 1 },
);

sub _InitArgNormalizer
{
    $_[0] =~ s/^([[:upper:]])/\L\1\E/;
    $_[0] =~ s/(?<=[[:lower:]])([[:upper:]])/_\L\1\E/g;
    $_[0];
}

sub init
{
    my $self = shift;
    my %args  = Params::Validate::validate_with(
        params => \@_,
        spec   => \%InitValidate,
        normalize_keys => \&_InitArgNormalizer
    );

    if (scalar @{$args{processors}}) {
        Params::Validate::validate_with(
            params => $args{processors},
            spec   => [ ({ can => $self->callback_name }) x scalar @{$args{processors}} ],
            called => ref($self) . "::new"
        );
    }

    my $alias   = delete $args{alias};
    my $pr_args = delete $args{processor_args};

    my %states = (
        inline_states => { _start => \&_start, _stop => \&_stop },
        object_states => [ $self, [ qw(process run_processor) ] ]
    );
    foreach my $state qw(inline_states package_states object_states) {
        if (exists $args{$state}) {
            my $user_supplied = delete $args{$state};
            if (my $value = $states{$state}) {
                $states{$state} = $state eq 'inline_states' ?
                    { %$value, %$user_supplied } :
                    [ @$user_supplied, @$value ];
            } else {
                $states{$state} = $user_supplied;
            }
        }
    }

    $self->hash_init(%args);

    POE::Session->create(
        heap  => { args => $pr_args },
        args  => [ $alias ],
        %states
    );
}

sub _start
{
    my($kernel, $alias) = @_[KERNEL, ARG0];
    $kernel->alias_set($alias);
}

sub _stop
{
    my ($kernel) = @_[KERNEL];
    $kernel->alias_remove();
}

sub process
{
    my($self, $kernel, $session, $success_evt, $failure_evt, $input) =
        @_[OBJECT, KERNEL, SESSION, ARG0, ARG1, ARG2];

    $kernel->yield(
        'run_processor',
        $session->postback($success_evt, $input), 
        $session->postback($failure_evt, $input),
        $input,
        0
    );
}

sub run_processor
{
    my($self, $kernel, $success_evt, $failure_evt, $input, $pr_idx) =
        @_[OBJECT, KERNEL, ARG0, ARG1, ARG2, ARG3, ARG4];
    my $pr    = $self->processors_index($pr_idx);
    my $cb    = $self->callback_name();
    my $ret   = eval {
        # XXX - need to figure out what to pass to this guy
        $pr->$cb($input); 
    };
    warn if $@;

    if ($@ || !$ret) {
        warn if $@;
        $failure_evt->($input);
    } else {
        my $next = $pr_idx + 1;
        if ($self->processors_count() > $next) {
            $kernel->yield('run_processor', $success_evt, $failure_evt, $input, $next);
        } else {
            $success_evt->($input);
        }
    }
}

1;

__END__

=head1 NAME

POE::Component::StackedProcessor - Stacked Processors In POE

=head1 SYNOPSIS

  use POE::Component::StackedProcessor;
  POE::Component::StackedProcessor->new(
    Alias      => $alias,
    Processors => [ $proc1, $proc2, $proc3 ],
    InlineStates => {  # or PackageStates/ObjectStates
      success => \&success_cb,
      failure => \&failure_cb
    }
  );
  POE::Kernel->run();

  # else where in the code...
  $kernel->post($alias, 'process', 'success', 'failure', $input);

=head1 DESCRIPTION

POE::Component::StackedProcessor allows you to build a chain of processors
whose dispatching depends on the successful completion of the previous
processor.

For example, suppose you have an HTML document that requires you to verify
whethere it meats certain criteria such as proper markup, valid links, etc.
Normally this would be done in one pass for the sake of efficiency, but
sometimes you want to break these steps up into several components such that
you can mix and match the differnt processors as required.

The basic steps to creating a stacked processor is as follows:

=over 4

=item 1. Create some processors

These are just simple objects that have a method called "process". The method
should take exactly one parameter, which is the "thing" being processed,
whatever it may be. It must return a true value upon successful execution.
If an exception is thrown or the method returns a false value, the processing
is terminated right there and then, and the failure event will be called.

Once you define these processors, pass them to the Processors argument to
new(), in the order that you want them executed:

  POE::Component::StackedProcessor->new(
    ...
    Processors => [ $p1, $p2, $p3 ... ]
  );

=item 2. Define success and failure events

You need to define success and failure events so that upon completion of
executing the processors, you can do some post processing. You specify
which states get called.

  # Calling from outside a POE session:
  sub success_cb { ... }
  sub failure_cb { ... }
  POE::Component::StackedProcessor->new(
    ...,
    InlineStates => {  # or PackageStates/ObjectStates
      success => \&success_cb,
      failure => \&failure_cb
    }
  );

Because the success/failure events are invoked via POE::Kernel's post() method,
they will receive the "request" and "response" arguments in ARG0 and ARG1,
which are arrayrefs:

  sub success_cb {
    my($response, $response) = @_[ARG0, ARG1];
    # whatever that got passed to process() is in $response-E<gt>[0];
    ...
  }

=item 3. Send some data to be processed

Once you've set up the processors and the success/failure states,
send some data to the StackedProcessor session via POE::Kernel->post()

  POE::Kernel->post(
    $alias_of_stacked_processor,
    'process', # this is always the same
    $success_event,
    $failure_event,
    $arg_to_process
  );

If all processors complete execution successfully, $success_event will be
called. Otherwise $failure_event gets called.

=back

=head1 METHODS

=head2 new ARGS

=over 4

=item Alias

Alias of the StackedProcessor session. (You probably want to set this, because
you will need to post() to this session to run the processors)

=item Processors

An arrayref of processor objects. Each of these object must have a method
denoted by "callback_name" (which is by default "process")

=item InlineStates/Packagestates/ObjectStates

Optional states to faciliate your method dispatching. You can, for example,
set success and failure states there that gets called upon successful
execution.

=back

=head2 callback_name

This is a class-method to specify at run time what method name should be
called on the processor objects. The default is "process".

=head1 SEE ALSO

L<POE>

=head1 AUTHOR

Daisuke Maki E<lt>dmaki@cpan.orgE<gt>

=cut