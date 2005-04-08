# $Id: StackedProcessor.pm 9 2005-04-01 23:19:11Z daisuke $
#
# Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package POE::Component::StackedProcessor;
use strict;
our $VERSION = '0.05';
use base qw(Class::Data::Inheritable);
use Class::MethodMaker
    new_with_init  => 'new',
    new_hash_init  => 'hash_init',
    list           => [ qw(processor_list) ],
    hash           => [ qw(processors) ],
    get_set        => [ qw(alias) ],
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

sub _DefaultDecisionMaker
{
    my($sp, $value, $context, $pr) = @_;
    $value ? $pr->{index} + 1 : undef;
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

    my $alias   = $args{alias};
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
    my($self, $kernel, $heap, $session, $sender, $success_evt, $failure_evt, $input, $context) =
        @_[OBJECT, KERNEL, HEAP, SESSION, SENDER, ARG0, ARG1, ARG2];

    $context ||= {};
    if ($self->processor_list_count <= 0) {
        # Hmm, process was called without any processors being
        # added. Let this pass, but generate a warning
        if ($^W) {
            warn "No processors defined for stacked processor. Passing anyway";
        }
        return $_[SENDER]->postback($success_evt, $input, $context)->();
    }

    my($success_cb, $failure_cb);
    if (defined $sender && UNIVERSAL::isa($sender, 'POE::Kernel')) {
        # got to be a call to the current session
        $success_cb = $session->postback($success_evt, $input, $context);
        $failure_cb = $session->postback($failure_evt, $input, $context);
    } else {
        $success_cb = $sender->postback($success_evt, $input, $context);
        $failure_cb = $sender->postback($failure_evt, $input, $context);
    }

    my $internal_context = {
        success_cb => $success_cb,
        failure_cb => $failure_cb,
        input      => $input,
        context    => $context,
        processor  => $self->processor_list_index(0)
    };

    $kernel->yield('run_processor', $internal_context);
}

sub add
{
    my($self, $name, $processor, $dm) = @_;
    my $data = {
        name      => $name,
        processor => $processor,
        dm        => $dm || \&_DefaultDecisionMaker,
        index     => $self->processor_list_count,
    };
    $self->processor_list_push($data);
    $self->processors($name, $data);
}

sub run_processor
{
    my($self, $kernel, $heap, $internal_context) = @_[OBJECT, KERNEL, HEAP, ARG0];

    my $input   = $internal_context->{input};
    my $context = $internal_context->{context};
    my $prdata  = $internal_context->{processor};
    my $pr      = $prdata->{processor};
    my $dm      = $prdata->{dm};
    my $cb      = $self->callback_name();

    my $next = eval {
        my $ret     = $pr->$cb($input, $context); 
        return $dm->($self, $ret, $context, $prdata);
    };
    warn if $@;

    # failure_cb and success_cb has references to at least one session,
    # which will put this intance of POE::Kernel into an infinite loop,
    # unless we manually get rid of it.
    if ($@ || !defined $next) {
        warn if $@;

        my $failure_cb = $internal_context->{failure_cb};
        undef %$internal_context;
        $failure_cb->($input, $context, $prdata);
    } else {
        my $next_data = $next =~ /\D/ ?
            $self->processors($next) : $self->processor_list_index($next);

        if ($next_data) {
            $internal_context->{processor} = $next_data;
            $kernel->yield('run_processor', $internal_context);
        } else {
            my $success_cb = $internal_context->{success_cb};
            undef %$internal_context;
            $success_cb->($input, $context, $prdata);
        }
    }
}

1;

__END__

=head1 NAME

POE::Component::StackedProcessor - Stacked Processors In POE

=head1 SYNOPSIS

  use POE::Component::StackedProcessor;
  my $p = POE::Component::StackedProcessor->new(
    Alias      => $alias,
    InlineStates => {  # or PackageStates/ObjectStates
      success => \&success_cb,
      failure => \&failure_cb
    }
  );
  $p->add(state1 => $proc1);
  $p->add(state2 => $proc2, $decision);
  $p->add(state3 => $proc3);
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
you can mix and match the different processors as required.

In a very simple stacked processor where the processors are run in linear 
fashion, all you need to do is to create the processor, and then add the
states in the order that you want them to be executed:

  use POE::Component::StackedProcessor;
  sub success_state {
    my($response) = @_[ARG1];
    ...
  }

  sub failure_state {
    my($response) = @_[ARG1];
    ...
  }

  my $p = POE::Component::StackedProcessor->new(
    Alias        => $alias,
    InlineStates => {
      success => \&success_state,
      failure => \&failure_state,
    }
  );

  my $p1 = MyProcessor1->new();
  my $p2 = MyProcessor2->new();
  my $p3 = MyProcessor3->new();

  $p->add($name1, $p1);
  $p->add($name2, $p2);
  $p->add($name3, $p3);

  POE::Kernel->post($alias, 'process', 'success', 'failure', $input);
  POE::Kernel->run();

In the above example, C<$p1>, C<$p2>, C<$p3> are executed in order. If all
processors are run to completion, then the 'success' state (or whatever
you specified in the third argument to post()) is called. Otherwise,
the 'failure' state (the fourth argument to post()) is called.

However, sometimes you want to control the execution order. In such cases,
you can use add()'s third parameter, which is the "decision maker" parameter.
This argument can be a coderef or an object, and is responsible for returning
the key for next processor to be run.

  $p->add($name1, $p1, $dm);

For example, if you had stated P1, P2, P3, and you want to only run P2
if P1 succeeded, then you can do this:

  sub skip_if_p1_failed {
    my($p, $prdata, $result) = @_;

    # where $p      is the POE::Component::StackedProcessor
    #       $prdata is the current processor's information (as hashref)
    #       $result is the return value from the the current processor

    if (!defined $result) {
      return 'P3';
    } else {
      return 'P2';
    }
  }

  $p->add(P1 => $p1, \&skip_if_p1_failed);
  $p->add(P2 => $p2);
  $p->add(P3 => $p3);

Note, though, that you can use numerical indices to indicate the next
processor to be run. So instead of the last 5 lines of C<skip_if_p1_failed>,
you can say:

  if (!defined $result) {
     return 2;
  } else {
     return 1;
  }

The success/failure callbacks receive the arguments that a POE postback
state receives. Namely ARG0 maps to the "request" argument list and, and
ARG1 maps to the "response" argument list.

=head1 METHODS

=head2 new ARGS

=over 4

=item Alias

Alias of the StackedProcessor session. (You probably want to set this, because
you will need to post() to this session to run the processors)

=item InlineStates/Packagestates/ObjectStates

Optional states to faciliate your method dispatching. You can, for example,
set success and failure states there that gets called upon successful
execution.

=back

=head2 callback_name

This is a class-method to specify at run time what method name should be
called on the processor objects. The default is "process".

=head2 alias

Gets the alias given to the session for this stack processor

=head1 CAVEATS

The processor name must *not* look like a number. If it looks like a number,
then it will be taken as an index in the processor list, not a processor name.

=head1 SEE ALSO

L<POE>

=head1 AUTHOR

Daisuke Maki E<lt>dmaki@cpan.orgE<gt>

=cut