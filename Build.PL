#!perl
# $Id: Build.PL 4 2004-12-24 04:06:08Z daisuke $
#
# Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

use strict;
use Module::Build; 

my $build = Module::Build->new(
    module_name => 'POE::Component::StackedProcessor',
    dist_author => 'Daisuke Maki <dmaki@cpan.org>',
    sign        => 1,
    license     => 'perl',
    create_makefile_pl => 'traditional',
    build_requires => {
        'Test::More'               => 0,
    },
    requires    => {
        'Class::Data::Inheritable' => 0,
        'Class::MethodMaker'       => 0,
        'Params::Validate'         => 0,
        'POE'                      => 0,
    },
);

$build->create_build_script();