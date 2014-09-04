package Alien::Base;

use strict;
use warnings;

use Alien::Base::PkgConfig;

our $VERSION = '0.004_01';
$VERSION = eval $VERSION;

use Carp;
use DynaLoader ();

use File::ShareDir ();
use File::Spec;
use Scalar::Util qw/blessed/;
use Capture::Tiny 0.17 qw/capture_merged/;
use Text::ParseWords qw/shellwords/;
use Perl::OSType qw/os_type/;

sub import {
  my $class = shift;

  return if $class->install_type('system');

  # get a reference to %Alien::MyLibrary::AlienLoaded
  # which contains names of already loaded libraries
  # this logic may be replaced by investigating the DynaLoader arrays
  my $loaded = do {
    no strict 'refs';
    no warnings 'once';
    \%{ $class . "::AlienLoaded" };
  };

  my @libs = $class->split_flags( $class->libs );

  my @L = grep { s/^-L// } @libs;
  my @l = grep { /^-l/ } @libs;

  unshift @DynaLoader::dl_library_path, @L;

  my @libpaths;
  foreach my $l (@l) {
    next if $loaded->{$l};

    my $path = DynaLoader::dl_findfile( $l );
    unless ($path) {
      carp "Could not resolve $l";
      next;
    }

    push @libpaths, $path;
    $loaded->{$l} = $path;
  }

  push @DynaLoader::dl_resolve_using, @libpaths;

  my @librefs = map { DynaLoader::dl_load_file( $_, 0x01 ) } @libpaths;
  push @DynaLoader::dl_librefs, @librefs;

}

sub dist_dir {
  my $class = shift;

  my $dist = blessed $class || $class;
  $dist =~ s/::/-/g;


  my $dist_dir = 
    $class->config('finished_installing') 
      ? File::ShareDir::dist_dir($dist) 
      : $class->config('working_directory');

  return $dist_dir;
}

sub new { return bless {}, $_[0] }

sub cflags {
  my $self = shift;
  return $self->_keyword('Cflags', @_);
}

sub libs {
  my $self = shift;
  return $self->_keyword('Libs', @_);
}

sub install_type {
  my $self = shift;
  my $type = $self->config('install_type');
  return @_ ? $type eq $_[0] : $type;
}

sub _keyword {
  my $self = shift;
  my $keyword = shift;

  # use pkg-config if installed system-wide
  if ($self->install_type('system')) {
    my $name = $self->config('name');
    my $command = Alien::Base::PkgConfig->pkg_config_command . " --\L$keyword\E $name";

    chomp ( my $pcdata = capture_merged { system( $command ) } );
    croak "Could not call pkg-config: $!" if $!;

    $pcdata =~ s/\s*$//;

    return $pcdata;
  }

  # use parsed info from build .pc file
  my $dist_dir = $self->dist_dir;
  my @pc = $self->pkgconfig(@_);
  my @strings = 
    map { $_->keyword($keyword, 
      #{ pcfiledir => $dist_dir }
    ) }
    @pc;

  return join( ' ', @strings );
}

sub pkgconfig {
  my $self = shift;
  my %all = %{ $self->config('pkgconfig') };

  # merge in found pc files
  require File::Find;
  my $wanted = sub {
    return if ( -d or not /\.pc$/ );
    my $pkg = Alien::Base::PkgConfig->new($_);
    $all{$pkg->{package}} = $pkg;
  };
  File::Find::find( $wanted, $self->dist_dir );
    
  croak "No Alien::Base::PkgConfig objects are stored!"
    unless keys %all;
  
  # Run through all pkgconfig objects and ensure that their modules are loaded:
  for my $pkg_obj (values %all) {
    my $perl_module_name = blessed $pkg_obj;
    eval "require $perl_module_name"; 
  }

  return @all{@_} if @_;

  my $manual = delete $all{_manual};

  if (keys %all) {
    return values %all;
  } else {
    return $manual;
  }
}

# helper method to call Alien::MyLib::ConfigData->config(@_)
sub config {
  my $class = shift;
  $class = blessed $class || $class;
  
  my $config = $class . '::ConfigData';
  eval "require $config";
  warn $@ if $@;

  return $config->config(@_);
}

# helper method to split flags based on the OS
sub split_flags {
  my ($class, $line) = @_;
  my $os = os_type();
  if( $os eq 'Windows' ) {
    $class->split_flags_windows($line);
  } else {
    # $os eq 'Unix'
    $class->split_flags_unix($line);
  }
}

sub split_flags_unix {
  my ($class, $line) = @_;
  shellwords($line);
}

sub split_flags_windows {
  # NOTE a better approach would be to write a function that understands cmd.exe metacharacters.
  my ($class, $line) = @_;

  # Double the backslashes so that when they are unescaped by shellwords(),
  # they become a single backslash. This should be fine on Windows since
  # backslashes are not used to escape metacharacters in cmd.exe.
  $line =~ s,\\,\\\\,g;
  shellwords($line);
}

sub dynamic_libs {
  my ($class) = @_;
  my $dir = File::Spec->catfile($class->dist_dir, 'dynamic');
  return unless -d $dir;
  opendir(my $dh, $dir);
  my @dlls = grep { /\.so/ || /\.(dylib|dll)$/ } grep !/^\./, readdir $dh;
  closedir $dh;
  grep { ! -l $_ } map { File::Spec->catfile($dir, $_) } @dlls;
}

1;

__END__
__POD__

=head1 NAME

Alien::Base - Base classes for Alien:: modules

=head1 SYNOPSIS

 package Alien::MyLibrary;

 use strict;
 use warnings;

 use parent 'Alien::Base';

 1;

=head1 DESCRIPTION

L<Alien::Base> comprises base classes to help in the construction of C<Alien::> modules. Modules in the L<Alien> namespace are used to locate and install (if necessary) external libraries needed by other Perl modules.

This is the documentation for the L<Alien::Base> module itself. To learn more about the system as a whole please see L<Alien::Base::Authoring>.

=head1 SEE ALSO

=over 

=item * 

L<Module::Build>

=item *

L<Alien>

=back

=head1 SOURCE REPOSITORY

L<http://github.com/jberger/Alien-Base>

=head1 AUTHOR

Joel Berger, E<lt>joel.a.berger@gmail.comE<gt>

=head1 CONTRIBUTORS

=over 

=item David Mertens (run4flat)

=item Mark Nunberg (mordy, mnunberg)

=item Christian Walde (Mithaldu)

=item Brian Wightman (MidLifeXis)

=item Graham Ollis (plicease)

=item Zaki Mughal (zmughal)

=item mohawk2

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012-2014 by Joel Berger

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

