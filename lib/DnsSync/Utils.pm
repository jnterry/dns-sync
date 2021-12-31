package DnsSync::Utils;

use strict;
use warnings;
use Data::Compare;

use Exporter qw(import);
our @EXPORT_OK = qw(
  set_verbosity verbose compute_required_updates group_records
);

my $VERBOSITY = 0;

sub set_verbosity {
	$VERBOSITY = shift;
}

sub verbose {
	return unless $VERBOSITY;
	print "@_" . "\n";
}

# Computes list of records which require creation/update
sub compute_required_updates {
	my ($existing, $desired) = @_;

	my $existingMap = group_records($existing);
	my $desiredMap  = group_records($desired);

	my @results;
  for my $n (keys %$desiredMap) {
		for my $t (keys %{$desiredMap->{$n}}) {

			my $d = $desiredMap->{$n}{$t};
			my $e = $existingMap->{$n}{$t};

			push @results, @$d unless Compare($d, $e);

		}
	}

	return @results;
}

# Helper which groups a list of DNS records into map of $map->{name}{type} => array of records
sub group_records {
	my ($records) = @_;

	my $map = {};
	push @{$map->{$_->{label}}{$_->{type}}}, $_ foreach @$records;

	for my $n (keys %$map) {
		for my $t (keys %{$map->{$n}}) {
			my @list = sort { $a->{data} cmp $b->{data} } @{$map->{$n}{$t}};
			$map->{$n}{$t} = \@list;
		}
	}

	return $map;
}

1;
