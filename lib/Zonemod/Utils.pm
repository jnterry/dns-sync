package Zonemod::Utils;

use strict;
use warnings;

use LWP::UserAgent;

use Exporter qw(import);
our @EXPORT_OK = qw(
  set_verbosity verbose get_ua
);

my $VERBOSITY = 0;

sub set_verbosity {
	$VERBOSITY = shift;
}

sub verbose {
	return unless $VERBOSITY;
	print "@_" . "\n";
}

my $ua;
# Helper to get a user agent for making HTTP requests
sub get_ua {
	return $ua if defined $ua;
	$ua = LWP::UserAgent->new;
	$ua->agent('zonemod');
	return $ua;
}

1;
