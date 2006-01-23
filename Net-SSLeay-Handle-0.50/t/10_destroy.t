#!/usr/bin/perl

use strict;
use Test::More;

my @uris = qw(
		debianforum.de
		bacus.pt
		perldition.org
);

plan tests => scalar @uris;

use File::Spec;
use Symbol qw(gensym);
use Net::SSLeay::Handle qw(shutdown);

my $fdcount_start = count_fds();

for my $uri (@uris) {
	{
		my $ssl = gensym();
		tie(*$ssl, "Net::SSLeay::Handle", $uri, 443);
		print $ssl "GET / HTTP/1.0\r\n\r\n";
		shutdown($ssl, 1);

		my @response;
		push @response, $_ while <$ssl>;
	}

	my $fdcount_end = count_fds();
	is ($fdcount_end, $fdcount_start, 'handle gets destroyed when it goes out of scope');
}

sub count_fds {
	my $fdpath = File::Spec->devnull();
	my $fh = gensym();
	open($fh, $fdpath) or die;
	my $count = fileno($fh);
	close($fh);
	return $count;
}