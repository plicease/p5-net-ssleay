use 5.8.1;

use strict;
use warnings;
use ExtUtils::MakeMaker;
use Config;
use File::Spec;
use Env qw( @PKG_CONFIG_PATH );
use IPC::Cmd qw( can_run );
use Text::ParseWords qw( shellwords );

my $tests = prompt(
  "Do you want to run external tests?\n".
  "These tests *will* *fail* if you do not have network connectivity.",
  'n',
) =~ /^y/i ? 't/*/*.t t/*/*/*.t' : 't/local/*.t t/handle/local/*.t';

my %eumm_args = (
  NAME => 'Net::SSLeay',
  ABSTRACT => 'Perl extension for using OpenSSL',
  LICENSE => 'artistic_2',
  AUTHOR => [
    'Sampo Kellomäki <sampo@iki.fi>',
    'Florian Ragwitz <rafl@debian.org>',
    'Mike McCauley <mikem@airspayce.com>',
    'Chris Novakovic <chris@chrisn.me.uk>',
    'Tuure Vartiainen <vartiait@radiatorsoftware.com>',
    'Heikki Vatiainen <hvn@radiatorsoftware.com>'
  ],
  VERSION_FROM => 'lib/Net/SSLeay.pm',
  MIN_PERL_VERSION => '5.8.1',
  CONFIGURE_REQUIRES => {
    'ExtUtils::MakeMaker' => '0',
    'IPC::Cmd'            => '0',
  },
  TEST_REQUIRES => {
    'Test::More' => '0.60_01',
  },
  PREREQ_PM => {
    'MIME::Base64' => '0',
  },
  test => { TESTS => $tests },
  clean => { FILES => join ' ', map fixpath($_), qw(
      makecert.out
      makecert.err
      sslecho.log
      tcpecho.log
      t/local/ptr_cast_test
      examples/cert.pem
      examples/key.pem
      examples/key.pem.e
      examples/*.0
  ) },
  META_MERGE => {
    "meta-spec" => { version => 2 },
    dynamic_config => 1,
    resources => {
      repository => {
        type => 'git',
        url => 'git://github.com/radiator-software/p5-net-ssleay.git',
        web => 'https://github.com/radiator-software/p5-net-ssleay',
      },
      bugtracker  => {
        web => 'https://rt.cpan.org/Public/Dist/Display.html?Name=net-ssleay',
      },
    },
    no_index => { directory => [ qw(helper_script examples) ] },
    prereqs => {
      develop => {
        requires => {
          'Test::Pod::Coverage' => '1.00',
          'Test::Kwalitee' => '1.00',
        },
      },
    },
  },
  ssleay(),
);

# This can go when EU::MM older than 6.58 are gone
$eumm_args{AUTHOR} = join(', ', @{$eumm_args{AUTHOR}}) unless eval { ExtUtils::MakeMaker->VERSION(6.58); };

# This can go when EU::MM older than 6.64 are gone
delete $eumm_args{TEST_REQUIRES} unless eval { ExtUtils::MakeMaker->VERSION(6.64); };

WriteMakefile(%eumm_args);

sub MY::postamble {
my $regen_script = File::Spec->catfile('helper_script', 'regen_openssl_constants.pl');
my $constants_t = File::Spec->catfile('t', 'local', '21_constants.t');
<<"MAKE";
constants.c : $regen_script
	\$(ABSPERLRUN) $regen_script -gen-c constants.c

$constants_t : $regen_script
	\$(ABSPERLRUN) $regen_script -gen-t $constants_t

SSLeay$Config{'obj_ext'} : constants.c $constants_t

MAKE
}

sub ssleay {
    my %args;

    if ($^O eq 'VMS') {
        my @paths;
        my @links;
        if (-r 'sslroot:[000000]openssl.cnf') {       # openssl.org source install
            @paths = ('SSLLIB');
            @links = qw( ssl_libssl32.olb ssl_libcrypto32.olb );
        }
        elsif (-r 'ssl1$root:[000000]openssl.cnf') {  # VSI or HPE SSL1 install
            @paths = ('SYS$SHARE');
            @links = qw( SSL1$LIBSSL_SHR32 SSL1$LIBCRYPTO_SHR32 );
        }
        elsif (-r 'ssl$root:[000000]openssl.cnf') {   # HP install
            @paths = ('SYS$SHARE');
            @links = qw( SSL$LIBSSL_SHR32 SSL$LIBCRYPTO_SHR32 );
        }
        @links = map { $_ =~ s/32\b//g } @links if $Config{use64bitall};
        %args = (
            LIBS => join(' ', (map "-L$_", @paths), (map {"-l$_"} @links)),
        );
    }

    else {

        if (defined $ENV{OPENSSL_PREFIX} && -d "$ENV{OPENSSL_PREFIX}/lib/pkgconfig") {
            unshift @PKG_CONFIG_PATH, "$ENV{OPENSSL_PREFIX}/lib/pkgconfig";
        }

        if (can_run('pkg-config') && system('pkg-config', '--exists', 'openssl') == 0) {
            my($name)    = map { [split /\s+/, $_ ]->[1] } grep /^openssl\s/, `pkg-config --list-all`;
            my $cflags  = `pkg-config --cflags     openssl`;
            my $libs    = `pkg-config --libs       openssl`;
            my $version = `pkg-config --modversion openssl`;
            chomp $cflags;
            chomp $libs;
            chomp $version;
            check_openssl_version($name, $version);
            %args = (
                INC  => $cflags,
                LIBS => $libs,
            );

            # From HMBRAND to handle multple version of OPENSSL installed
            my @paths = grep /^-L/, shellwords($libs);
            if (my $lp = join " " => map '-L'.maybe_quote($_), @paths)
            {
                ($args{uc $_} = $Config{$_}) =~ s/-L/$lp -L/ for qw(lddlflags ldflags);
            }

        }

        else {
            my $alien = 'Alien::OpenSSL';

            # On Windows LibreSSL installs more reliably
            # On OpenBSD LibreSSL is the native SSL implementation
            if ($^O eq 'MSWin32' || $^O eq 'openbsd') {
                $alien = 'Alien::LibreSSL'
            }

            print "*** Could not find OpenSSL\n",
                  "    We will try to use $alien instead.\n";

            # Alien::Base::Wrapper already handles multiple versions of OpenSSL.
            %args = (
                CC => "\$(FULLPERL) -MAlien::Base::Wrapper=$alien -e cc --",
                LD => "\$(FULLPERL) -MAlien::Base::Wrapper=$alien -e ld --",
                BUILD_REQUIRES => {
                    'Alien::Base::Wrapper' => "0",
                    $alien                 => "0",
                },
            );
        }

        if (($Config{cc} =~ /aCC/i) && $^O eq 'hpux') {
            print "*** Enabling HPUX aCC options (+e)\n";
            $args{OPTIMIZE} = "+e $Config{optimize}";
        }

        if ( (($Config{ccname} || $Config{cc}) eq 'gcc') && ($Config{cccdlflags} =~ /-fpic/) ) {
            print "*** Enabling gcc -fPIC optimization\n";
            $args{CCDLFLAGS} = "$Config{ccdlflags} -fPIC";
        }

    }

    %args;
}

sub maybe_quote { $_[0] =~ / / ? qq{"$_[0]"} : $_[0] }

sub check_openssl_version {
    my ($name, $version) = @_;
    my ($major, $minor, $letter);

    if (($major, $minor, $letter) = $version =~ /(\d+\.\d+)\.(\d+)([a-z]?)/) {
        print "*** Found $name-$version installed\n";
    } else {
            die <<EOM
*** OpenSSL version test failed
    (`$version' has been returned)
    Either you have bogus OpenSSL or a new version has changed the version
    number format. Please inform the authors!
EOM
    }

    if ($major < 0.9 || ($major == 0.9 && $minor < 3)) {
        print <<EOM;
*** That's too old!
    Please upgrade OpenSSL to the latest version (http://www.openssl.org/)
EOM
        exit 0; # according http://wiki.cpantesters.org/wiki/CPANAuthorNotes this is best-practice when "missing library"
    }

    if ($major == 1.1 && $minor > 1) {
        print <<EOM;
*** That's newer than what this module was tested with
    You should consider checking if there is a newer release of this module
    available. Everything will probably work OK, though.
EOM
    }
}

sub fixpath {
    my ($text) = @_;
    my $sep = File::Spec->catdir('');
    $text =~ s{\b/}{$sep}g;
    return $text;
}
