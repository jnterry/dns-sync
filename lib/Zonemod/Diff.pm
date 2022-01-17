package Zonemod::Diff;

=head1 OVERVIEW C<Zonemod::Diff>

Helper functions for computing and applying 'diffs', IE sets of changes to a RecordSet

=cut

use strict;
use warnings;

use Zonemod::RecordSet qw(group_records ungroup_records contains_record does_record_match);
use Zonemod::ZoneDb    qw(encode_resource_record parse_resource_record);

use Clone qw(clone);
use Data::Compare;
use Try::Tiny;

use Data::Dumper;

use Exporter qw(import);
our @EXPORT_OK = qw(
	compute_record_set_diff apply_diff is_managed encode_diff parse_diff
);

my @GROUPINGS = ( 'none', 'type', 'host' );

=head1 FUNCTIONS

=over 4

=item C<compute_record_set_diff>

Computes list of records which require creation/deletion

Returns object of same form as group_records, however each record has an additional `diff` field
set to either '+' or '-' to indicate whether to create or delete it

In scalar context, returns just the diff, in array context, returns both the diff, and the diff
that is disallowed due to $opts->{managed}

OPTIONS

=over 4

=item C<managed>

If set to list of records, will generate diff which:
- Does not delete records not also in managed
- Does not overwrite records not also in managed

=item C<noDelete>

If set generates diff which does not delete records. Note that since we treat a
label/type combination as a "unit", we may still delete records if a new record exists
for the same host, in order to set the new record

=item C<grouping>

Controls how records are grouped together, set to one of:
- 'none'
- 'type' (default)
- 'host'

Affects behaviour of noDelete and managed flags.

When multiple records are grouped together, a record will be considered to be managed when ANY of
the records in the group are managed, and eligible for deletion (even when noDelete is set) when
there exist replacement records in the same group

In 'none' mode, records are never grouped - they must exist exactly as stated in the managed set
to be changed, and noDelete will AWLAYS prevent deletion of ALL existing data.

In 'type' mode, records are grouped by the label/type combination, eg, all "A" records for "www".
If any A record for "www" is managed, we assume we manage ALL A records for "www", and as long
as there exists at least 1 A record for "www" in the $desired set, we can delete existing ones

In 'host' mode, records are grouped by the label, eg, all records for "www". This works as 'type'
mode, but groups work across record types (eg, both A and AAAA are considerd together) for each host

=back

=cut
sub compute_record_set_diff {
	my ($existing, $desired, $opts) = @_;

	my $grouping = $opts->{grouping} || 'type';
	unless(grep { $_ eq $grouping } @GROUPINGS) {
		die "Invalid 'grouping' argument - got '$grouping' - expected one of: " . join(', ', @GROUPINGS);
	}

	my $existingMap = ref($existing) eq "ARRAY" ? group_records($existing) : $existing;
	my $desiredMap  = ref($desired ) eq "ARRAY" ? group_records($desired ) : $desired;
	my $managedMap;
	if($opts->{managed}) {
		$managedMap = ref($opts->{managed}) eq "ARRAY" ? group_records($opts->{managed}) : $opts->{managed};
	}

	my ($allowedDiff, $blockedDiff) = ({}, {});

	# Loop over desired items to find items that need creating/updating
  for my $n (keys %$desiredMap) {
		for my $t (keys %{$desiredMap->{$n}}) {

			my $d = $desiredMap->{$n}{$t};
			my $e = $existingMap->{$n}{$t};

			my $isReplacing = 0;

			# delete everything in existing not also in desired
			for my $r (@$e) {
				next if contains_record($d, $r);

				# Check we manage the record in question
				my $allowed = !defined $opts->{managed} || is_managed($managedMap, $grouping, $r);

				# Prevent delete if we don't group with other records
				$allowed = 0 if($opts->{noDelete} && $grouping eq 'none');

				if($allowed) {
					push @{$allowedDiff->{$n}{$t}}, { diff => '-', %$r };
				} else {
					push @{$blockedDiff->{$n}{$t}}, { diff => '-', %$r };
				}
			}

			# create everything in desired not yet in existing
		  for my $r (@$d) {
				next if contains_record($e, $r); # skip if it already exists

				# allow creation if...
				my $allowed = (
					# there is no managment restrictions
					!defined $opts->{managed} ||

					# We are explictly managing the record in question
					is_managed($managedMap, $grouping, $r) ||

					# The existing data is NOT managing the record group in question,
					# hence we can freely create it
					!is_managed($existingMap, $grouping, $r) ||

					# We have ALREADY deleted a record in the same group, and hence are now allowed to replace it
					is_managed($allowedDiff, $grouping, $r)
				);

				if($allowed) {
					push @{$allowedDiff->{$n}{$t}}, { diff => '+', %$r };
				} else {
					push @{$blockedDiff->{$n}{$t}}, { diff => '+', %$r };
				}
			}
		}
	}

	# Loop over existing items to find items that need deleting
	for my $n (keys %$existingMap) {
		for my $t (keys %{$existingMap->{$n}}) {
			my $d = $desiredMap->{$n}{$t};
			my $e = $existingMap->{$n}{$t};

			# skip deletion if it exists in desired (we will have handled replacements already when
			# looping over desired)
			next if defined $d && scalar @$d != 0;

			for my $r (@$e) {
				# check we manage the record
				my $allowed = !defined $opts->{managed} || is_managed($managedMap, $grouping, $r);

				# if noDelete is set, we are not allowed to delete the record, unless
				# we are grouping by complete host, and there do exist SOME records for the host in question
				# in desired map
				if($opts->{noDelete}) {
					$allowed = 0 unless $grouping eq 'host' && scalar (ungroup_records({ $n => $desiredMap->{$n} }) > 0);
				}

				if($allowed) {
					push @{$allowedDiff->{$n}{$t}}, { diff => '-', %$r };
				} else {
					push @{$blockedDiff->{$n}{$t}}, { diff => '-', %$r };
				}
			}
		}
	}

	return ($allowedDiff, $blockedDiff) if wantarray;
	return $allowedDiff;
}

=item C<is_managed>

Helper to check if a particular record is managed by a particular record set

Params (managedRecords, groupingType, record)

=cut
sub is_managed {
	my ($map, $grouping, $record) = @_;
	$grouping //= 'type';

	if($grouping eq 'host') {
		return contains_record($map, { class => $record->{class}, label => $record->{label} });
	} elsif ($grouping eq 'type') {
		return contains_record($map, { class => $record->{class}, label => $record->{label}, type => $record->{type} });
	} else {
		return contains_record($map, { class => $record->{class}, label => $record->{label}, type => $record->{type}, data => $record->{data} });
	}
}

=item C<apply_diff>

Applies a diff produced by compute_record_set_delta to in memory RecordSet

=cut
sub apply_diff {
	my ($initial, $diff) = @_;

	my $inMap   = ref($initial) eq "ARRAY" ? group_records($initial) : $initial;
	my $updated = clone($inMap);

	my @changes = ref($diff)    eq "ARRAY" ? @$diff : ungroup_records($diff);
	for my $change (@changes) {
		my $rs = ($updated->{$change->{label}}{$change->{type}} || []);

		if($change->{diff} eq '-') {
			$rs = [ grep { not does_record_match($_, $change) } @$rs ];
		} elsif ($change->{diff} eq '+') {
			my $r = { %$change };
			delete $r->{diff};
		  push @$rs, $r unless contains_record($rs, $change);
		} else {
			die "Diff included invalid change type: $change->{diff}";
		}

		$updated->{$change->{label}}{$change->{type}} = $rs;
	}

	return ungroup_records($updated);
}

=item C<encode_diff>

Writes a diff to string - looks like zonemod file, with an additional  + / - column before main record

=cut
sub encode_diff {
	my ($diff) = @_;

  my $map = ref($diff) eq "ARRAY" ? group_records($diff) : $diff;

	my $result = '';

	my @names = sort keys %$map;
	for my $n (@names) {
		my @types = sort keys %{$map->{$n}};
		for my $t (@types) {
			# sort to put - before +
			for my $r (sort { $b->{diff} cmp $a->{diff} } @{$map->{$n}{$t}}) {
				$result .= $r->{diff} . ' ' . encode_resource_record($r) . "\n";
			}
		}
	}

	return $result;
}

=item C<parse_diff>

Loads a diff from string previously generated with encode_diff

=cut
sub parse_diff {
	my ($raw) = @_;

  my @results = ();

	for my $line (split("\n", $raw )) {
		next if $line =~ /^\s*(;.+)?$/; # skip empty lines and comments

	  die "Cannot parse diff line '$line'" unless $line =~ qr{([+\-])\s+(.+)};
		my $diff   = $1;
		my $record = parse_resource_record($2);
		$record->{diff} = $1;
		push @results, $record;
	}

	return @results;
}

=back

=cut

1;
