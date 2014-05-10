use strict;
use warnings FATAL => 'all';

use Test::More;
use if $ENV{AUTHOR_TESTING}, 'Test::Warnings';
use Test::DZil;
use Test::Fatal;
use Path::Tiny;
use Test::Deep;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaJSON => ],
                [ Prereqs => { 'strict' => '0', 'Test::More' => '0' } ],
                [ MakeMaker => ],
                [ DynamicPrereqs => {
                        raw => [
                            q|$WriteMakefileArgs{PREREQ_PM}{'Test::More'} = $FallbackPrereqs{'Test::More'} = '0.123'|,
                            q|if eval { require Test::More; 1 };|,
                        ],
                        unknown_arg => 'foo',
                    },
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
is(
    exception { $tzil->build },
    undef,
    'build proceeds normally',
) or diag "log messages:\n", join("\n", @{ $tzil->log_messages });

cmp_deeply(
    $tzil->log_messages,
    superbagof(
        re(qr/\QWarning: unrecognized argument (unknown_arg) passed. Perhaps you need to upgrade?\E/),
    ),
    'warning issued about unrecognized arguments',
) or diag "log messages:\n", join("\n", @{ $tzil->log_messages });

done_testing;
