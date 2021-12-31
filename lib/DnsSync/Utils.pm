package DnsSync::Utils;

use Exporter qw(import);
our @EXPORT_OK = qw(
  set_verbosity verbose
);

my $VERBOSITY = 0;

sub set_verbosity {
	$VERBOSITY = shift;
}

sub verbose {
	return unless $VERBOSITY;
	print "@_" . "\n";
}

1;
