package DnsSync::Utils;

use strict;
use warnings;
use Data::Compare;

use Data::Dumper;

use Exporter qw(import);
our @EXPORT_OK = qw(
  set_verbosity verbose parse_zone_file compute_record_set_delta group_records ungroup_records replace_records
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
		next if $line =~ /^(\s*|\s*;.+)$/;

		my $errorLoc = defined $path ? "$path:$lineNum" : "line $line";

		my ($label, $ttl, $class, $type, $data) = split(/\t/, $line);
		die "Only Internet (aka: IN class) records are supported, found $class at $errorLoc" unless $class eq "IN";
		die "TXT record data must be wrapped in quotes: $errorLoc" if $type eq "TXT" and $data !~ /^"[^"]+"$/;
		push @results, { label => $label, ttl => $ttl + 0, class => $class, type => $type, data => $data };
	}

	return @results;
}

# Computes list of records which require creation/update/deletion
# Note this function operates by "record sets", IE: all records for the same host and of the same
# type are considered as a group
#
# In other words, syncing "A 127.0.0.2" to a host with existing "A 127.0.0.1" will update & replace
# the existing record with the new, rather than resulting in two A records for the same host
sub compute_record_set_delta {
	my ($existing, $desired, $opts) = @_;

	my $existingMap = ref($existing) eq "ARRAY" ? group_records($existing) : $existing;
	my $desiredMap  = ref($desired ) eq "ARRAY" ? group_records($desired ) : $desired;
	my $managedMap;
	if($opts->{managed}) {
		$managedMap = ref($opts->{managed}) eq "ARRAY" ? group_records($opts->{managed}) : $opts->{managed};
	}

	# 2d hash with same keys as group_records, but maps to a boolean as to whether an
	# upsert/deletion is required
	my $upserts = {};
	my $deletions = {};

  for my $n (keys %$desiredMap) {
		for my $t (keys %{$desiredMap->{$n}}) {
			my $d = $desiredMap->{$n}{$t};
			my $e = $existingMap->{$n}{$t};

			$upserts->{$n}{$t} = $d unless Compare($d, $e);
		}
	}

	for my $n (keys %$existingMap) {
		for my $t (keys %{$existingMap->{$n}}) {
			my $d = $desiredMap->{$n}{$t};
			my $e = $existingMap->{$n}{$t};

			# skip delete if we're already upserting the record, or it exists in desired set
			next if (defined $upserts->{$n}{$t}) or (defined $d and scalar @$d != 0);

			# If a managed set if defined, then don't delete anything we don't manage ourselves
			if(defined $managedMap) {
				next unless defined $managedMap->{$n}{$t};
			}

			$deletions->{$n}{$t} = $e
		}
	}

	my @flatUpserts   = ungroup_records($upserts);
	my @flatDeletions = ungroup_records($deletions);

	return { upserts => \@flatUpserts, deletions => \@flatDeletions };
}

# Compute list of items that need to be deleted as they exist in $existing but NOT $desired
sub compute_required_deletions {
	my ($existing, $desired) = @_;

	my $existingMap = ref($existing) eq "ARRAY" ? group_records($existing) : $existing;
	my $desiredMap  = ref($desired ) eq "ARRAY" ? group_records($desired ) : $desired;

	my @results;
	for my $n (keys %$existingMap) {
		for my $t (keys %{$existingMap->{$n}}) {
			my $d = $desiredMap->{$n}{$t};
			my $e = $existingMap->{$n}{$t};

			push @results, @$e unless $d and @$d;
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

# Reverses `group_records`
sub ungroup_records {
	my ($grouped) = @_;

	my @results;
	for my $n (keys %$grouped) {
		for my $t (keys %{$grouped->{$n}}) {
			for my $r (@{$grouped->{$n}{$t}}) {
				push @results, { label => $n, type => $t, %$r };
			}
		}
	}
	return @results;
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
