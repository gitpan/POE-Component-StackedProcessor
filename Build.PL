#!perl
# $Id: Build.PL,v 1.5 2004/12/10 22:47:58 daisuke Exp $
#
# Daisuke Maki <daisuke@cpan.org>

use strict;
use Module::Build; 

my $build = Module::Build->new(
    module_name => 'POE::Component::StackedProcessor',
    dist_author => 'Daisuke Maki <daisuke@cpan.org>',
    sign        => 1,
    license     => 'perl',
    create_makefile_pl => 'traditional',
    build_requires => {
        'Test::More'               => 0,
    },
    requires    => {
        'Class::Data::Inheritable' => 0,
        'Params::Validate'         => 0,
        'POE'                      => 0,
    },
);

$build->create_build_script();