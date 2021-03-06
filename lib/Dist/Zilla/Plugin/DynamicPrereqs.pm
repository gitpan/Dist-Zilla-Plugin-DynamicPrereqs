use strict;
use warnings;
package Dist::Zilla::Plugin::DynamicPrereqs;
# git description: v0.008-2-g5c8595d
$Dist::Zilla::Plugin::DynamicPrereqs::VERSION = '0.009';
# ABSTRACT: Specify dynamic (user-side) prerequisites for your distribution
# KEYWORDS: plugin distribution metadata MYMETA prerequisites Makefile.PL dynamic
# vim: set ts=8 sw=4 tw=78 et :

use Moose;
with
    'Dist::Zilla::Role::InstallTool',
    'Dist::Zilla::Role::MetaProvider',
    'Dist::Zilla::Role::AfterBuild',
;
use MooseX::SlurpyConstructor 1.2;
use List::Util 'first';
use Module::Runtime 'module_notional_filename';
use namespace::autoclean;

has raw => (
    isa => 'ArrayRef[Str]',
    traits => ['Array'],
    handles => { raw => 'elements' },
    lazy => 1,
    default => sub { [] },
);

has _extra_args => (
    isa => 'HashRef[Str]',
    init_arg => undef,
    lazy => 1,
    default => sub { {} },
    traits => ['Hash'],
    handles => { _extra_keys => 'keys', _extra_args => 'elements' },
    slurpy => 1,
);

sub mvp_multivalue_args { qw(raw) }

sub mvp_aliases { +{ '-raw' => 'raw', '-delimiter' => 'delimiter' } }

around BUILDARGS => sub
{
    my $orig = shift;
    my $class = shift;

    my $args = $class->$orig(@_);

    my $delimiter = delete $args->{delimiter};
    if (defined $delimiter and length($delimiter))
    {
        s/^\Q$delimiter\E// foreach @{$args->{raw}};
    }

    return $args;
};

sub metadata { return +{ dynamic_config => 1 } }

sub after_build
{
    my $self = shift;
    $self->log_fatal('Build.PL detected - dynamic prereqs will not be added to it!')
        if first { $_->name eq 'Build.PL' } @{ $self->zilla->files };
}

sub setup_installer
{
    my $self = shift;

    $self->log_fatal('[MakeMaker::Awesome] must be at least version 0.19 to be used with [DynamicPrereqs]')
        if $INC{module_notional_filename('Dist::Zilla::Plugin::MakeMaker::Awesome')}
            and not eval { Dist::Zilla::Plugin::MakeMaker::Awesome->VERSION('0.19') };

    if (my @extra_keys = $self->_extra_keys)
    {
        # this should be done in BUILD instead, but MooseX::SlurpyConstructor is lame.
        $self->log('Warning: unrecognized argument' . (@extra_keys > 1 ? 's' : '')
                . ' (' . join(', ', @extra_keys) . ') passed. Perhaps you need to upgrade?');
    }

    my $file = first { $_->name eq 'Makefile.PL' } @{$self->zilla->files};
    $self->log_fatal('No Makefile.PL found!') if not $file;

    my $content = $file->content;

    $self->log_debug('Inserting dynamic prereq into Makefile.PL...');

    # insert after declarations for BOTH %WriteMakefileArgs, %FallbackPrereqs.
    # TODO: if marker cannot be found, fall back to looking for just
    # %WriteMakefileArgs -- this requires modifying the content too.
    $self->log_fatal('failed to find position in Makefile.PL to munge!')
        if $content !~ m'^my %FallbackPrereqs = \((?:\n[^;]+^)?\);$'mg;

    my $pos = pos($content);
    my $version = $self->VERSION || '<self>';

    $content = substr($content, 0, $pos)
        . "\n\n"
        . "# inserted by " . blessed($self) . ' ' . ($self->VERSION || '<self>') . "\n"
        . join("\n", $self->raw)
        . "\n" . substr($content, $pos);

    $file->content($content);
    return;
}

__PACKAGE__->meta->make_immutable;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::DynamicPrereqs - Specify dynamic (user-side) prerequisites for your distribution

=head1 VERSION

version 0.009

=head1 SYNOPSIS

In your F<dist.ini>:

    [DynamicPrereqs]
    -raw = $WriteMakefileArgs{PREREQ_PM}{'Role::Tiny'} = $FallbackPrereqs{'Role::Tiny'} = '1.003000'
    -raw = if eval { require Role::Tiny; 1 };

or:

    [DynamicPrereqs]
    -delimiter = |
    -raw = |$WriteMakefileArgs{TEST_REQUIRES}{'Devel::Cover'} = $FallbackPrereqs{'Devel::Cover'} = '0'
    -raw = |    if $ENV{EXTENDED_TESTING};

=head1 DESCRIPTION

This is a L<Dist::Zilla> plugin that inserts code into your F<Makefile.PL> to
indicate dynamic (installer-side) prerequisites.

Code is inserted immediately after the declarations for C<%WriteMakefileArgs>
and C<%FallbackPrereqs>, before they are conditionally modified (when an older
L<ExtUtils::MakeMaker> is installed).  This gives you an opportunity to add to
the C<WriteMakefile> arguments: C<PREREQ_PM>, C<BUILD_REQUIRES>, and
C<TEST_REQUIRES>, and therefore modify the prerequisites in the user's
F<MYMETA.yml> and F<MYMETA.json> based on conditions found on the user's system.

The C<dynamic_config> field in L<metadata|CPAN::Meta::Spec/dynamic_config> is
already set for you.

=for stopwords usecase

You could potentially use this plugin for performing other modifications in
F<Makefile.PL> other than user-side prerequisite modifications, but I can't
think of a situation where this makes sense. Contact me if you have any ideas!

Only F<Makefile.PL> modification is supported at this time. This author
considers the use of L<Module::Build> to be questionable in all circumstances,
and L<Module::Build::Tiny> does not (yet?) support dynamic configuration.

=head1 CONFIGURATION OPTIONS

=head2 C<-raw>

The code to be inserted; must be valid and complete perl statements. You can
reference and modify the already-declared C<%WriteMakefileArgs> and
C<%FallbackPrereqs> variables, as inserted into F<Makefile.PL> by
L<Dist::Zilla::Plugin::MakeMaker> and subclasses (e.g.
L<Dist::Zilla::Plugin::MakeMaker::Awesome> since L<Dist::Zilla> C<5.001>.

This option can be used more than once; lines are added in the order in which they are provided.

This option is pretty low-level; I anticipate its use to be deprecated when
better options are added (see below). In particular, the user should not have
to be aware of existing code in F<Makefile.PL> nor the exact code required to
add prerequisites of various types.

If you use external libraries in the code you are inserting, you B<must> add
these modules to C<configure_requires> prereqs in metadata (e.g. via
C<[Prereqs / ConfigureRequires]> in your F<dist.ini>).

=for Pod::Coverage mvp_multivalue_args mvp_aliases metadata after_build setup_installer

=head2 C<-delimiter>

(Available since version 0.007)

A string, usually a single character, which is stripped from the beginning of
all C<-raw> lines. This is because the INI file format strips all leading
whitespace from option values, so including this character at the front allows
you to use leading whitespace in an option string, so you can indent blocks of
code properly.

=head1 WARNING: UNSTABLE API!

=for stopwords DarkPAN

This plugin is still undergoing active development, and the interfaces B<will>
change and grow as I work through the proper way to do various things.  As I
make changes, I will be using L<http://grep.cpan.me> to find and fix any
upstream users, but I obviously cannot do this for DarkPAN users. Regardless,
please contact me (see below) and I will keep you directly advised of
interface changes.

Future options may include:

=over 4

=item *

C<-condition> a Perl expression that is tested before additional prereqs are added

=item *

C<-phase> the phase in which subsequently-specified module/version pairs will be added

=item *

C<-runtime> a module and version that is added to runtime prereqs should the C<-condition> be satisfied

=item *

C<-test> a module and version that is added to test prereqs should the C<-condition> be satisfied

=item *

C<-build> a module and version that is added to build prereqs should the C<-condition> be satisfied

=back

It is also quite possible that there will be customized condition options,
e.g. C<-can_xs>, that will automatically provide common subroutines for use in
condition expressions.

=head1 SUPPORT

=for stopwords irc

Bugs may be submitted through L<the RT bug tracker|https://rt.cpan.org/Public/Dist/Display.html?Name=Dist-Zilla-Plugin-DynamicPrereqs>
(or L<bug-Dist-Zilla-Plugin-DynamicPrereqs@rt.cpan.org|mailto:bug-Dist-Zilla-Plugin-DynamicPrereqs@rt.cpan.org>).
I am also usually active on irc, as 'ether' at C<irc.perl.org>.

=head1 SEE ALSO

=over 4

=item *

L<Dist::Zilla::Plugin::MakeMaker>

=item *

L<ExtUtils::MakeMaker/Using Attributes and Parameters>

=item *

L<Dist::Zilla::Plugin::OSPrereqs>

=item *

L<Dist::Zilla::Plugin::PerlVersionPrereqs>

=back

=head1 AUTHOR

Karen Etheridge <ether@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Karen Etheridge.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
