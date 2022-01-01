package DnsSync::Utils;

use strict;
use warnings;
use Data::Compare;

use Data::Dumper;

use Exporter qw(import);
our @EXPORT_OK = qw(
  set_verbosity verbose parse_zone_file compute_required_updates compute_required_deletions group_records replace_records
);

my $VERBOSITY = 0;

sub set_verbosity {
	$VERBOSITY = shift;
}

sub verbose {
	return unless $VERBOSITY;
	print "@_" . "\n";
}

# Parses contents of zone file string
# Can optionally specify the path for more descriptive error messages including path name
sub parse_zone_file {
	my ($raw, $path) = @_;

	my @lines = split(/\n/, $raw);

	my @results;
	my $lineNum = 0;
	foreach my $line (@lines) {
		++$lineNum;
		next if $line =~ /^\s*$/;

		my $errorLoc = defined $path ? "$path:$lineNum" : "line $line";

		my ($label, $ttl, $class, $type, $data) = split(/\t/, $line);
		die "Only Internet (aka: IN class) records are supported, found $class at $errorLoc" unless $class eq "IN";
		die "TXT record data must be wrapped in quotes: $errorLoc" if $type eq "TXT" and $data !~ /^"[^"]+"$/;
		push @results, { label => $label, ttl => $ttl + 0, class => $class, type => $type, data => $data };
	}

	return @results;
}

# Computes list of records which require creation/update
sub compute_required_updates {
	my ($existing, $desired) = @_;

	my $existingMap = ref($existing) eq "ARRAY" ? group_records($existing) : $existing;
	my $desiredMap  = ref($desired ) eq "ARRAY" ? group_records($desired ) : $desired;

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

# Helper which takes two outputs from `group_records`, and replaces any in $a with those in $b
sub replace_records {
	my ($a, $b) = @_;

	my $final = { %$a };

	for my $n (keys %$b) {
		for my $t (keys %{$b->{$n}}) {
			$final->{$n}{$t} = $b->{$n}{$t};
		}
	}

	return $final;
}

1;
