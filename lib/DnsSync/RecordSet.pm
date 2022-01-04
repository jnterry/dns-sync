package DnsSync::RecordSet;

=head1 OVERVIEW C<DnsSync::RecordSet>

Helper functions for dealing with sets of DNS resource records

=cut

use strict;
use warnings;

use Clone qw(clone);
use Data::Compare;
use Try::Tiny;

use Exporter qw(import);
our @EXPORT_OK = qw(
  compute_record_set_delta group_records ungroup_records replace_records apply_deltas
);

=head1 FUNCTIONS

=over 4

=item C<compute_record_set_delta>

Computes list of records which require creation/update/deletion
Note this function operates by "record sets", IE: all records for the same host and of the same
type are considered as a group

In other words, syncing "A 127.0.0.2" to a host with existing "A 127.0.0.1" will update & replace
the existing record with the new, rather than resulting in two A records for the same host

=cut
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

=item C<compute_required_deletions>

Compute list of items that need to be deleted as they exist in $existing but NOT $desired

=cut
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

=item C<group_records>

Helper which groups a list of DNS records into map of $map->{name}{type} => array of records

=cut
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


=item C<ungroup_records>

Reverses `group_records`

=cut
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

=item C<replace_records>

Helper which takes two outputs from `group_records`, and replaces any in $a with those in $b

=cut
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

=item C<delete_records>

Helper which takes two outputs from `group_records`, and deletes any in $a also in $b

=cut
sub delete_records {
	my ($a, $b) = @_;

	my $final = { %$a };
	for my $n (keys %$b) {
		for my $t (keys %{$b->{$n}}) {
			delete $final->{$n}{$t} if $b->{$n}{$t};
		}
	}

	return $final;
}

=item C<apply_deltas>

Helper which applies set of changes in $deltas object to an input set of records
Returns list of final records
Does not modify $initial, instead returns copy

=cut
sub apply_deltas {
	my ($initial, $deltas) = @_;

	my $inMap = ref($initial) eq "ARRAY" ? group_records($initial) : $initial;
	my $updated = clone($inMap);
	$updated = replace_records($updated, group_records($deltas->{upserts}));
  $updated = delete_records($updated, group_records($deltas->{deletions}));
	return ungroup_records($updated);
}

=back

=cut

1;
