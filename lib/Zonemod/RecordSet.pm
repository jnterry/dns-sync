package Zonemod::RecordSet;

=head1 OVERVIEW C<Zonemod::RecordSet>

Helper functions for dealing with sets of DNS resource records

=cut

use strict;
use warnings;

use Clone qw(clone);
use Data::Compare;
use Try::Tiny;

use Data::Dumper;

use Exporter qw(import);
our @EXPORT_OK = qw(
  group_records ungroup_records contains_record does_record_match
);

=head1 FUNCTIONS

=over 4

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

=item C<contains_record>

Checks if given record set contains a particular record. Internally
calls C<does_record_match> hence can exclude fields from filter by
setting to undef

=cut
sub contains_record {
	my ($records, $filter) = @_;

	my $haystack;
	if(ref ($records) eq "ARRAY") {
	  $haystack = $records;
	} else {
		# assume its a grouped RecordSet
		if(defined $filter->{label} and defined $filter->{type}) {
			$haystack = $records->{$filter->{label}}{$filter->{type}};
		} elsif(defined $filter->{label}) {
		  my @tmp = ungroup_records({ $filter->{label} => $records->{$filter->{label}} });
			$haystack = \@tmp;
		} else {
			my @tmp = ungroup_records($records);
			$haystack = \@tmp;
		}
	}

	for my $r (@$haystack) {
		return 1 if does_record_match($r, $filter);
	}
	return 0;
}

=item C<does_record_match>

Determines if a record matches the specified filter

Filter is hash of the same form as the record. Note however that any of the fields
of the filter may be set to undef to ignore filtering on that field of the record

=cut
sub does_record_match {
	my ($record, $filter) = @_;

  return 0 if defined $filter->{label} && $record->{label} ne $filter->{label};
	return 0 if defined $filter->{class} && $record->{class} ne $filter->{class};
	return 0 if defined $filter->{type}  && $record->{type}  ne $filter->{type};
	return 0 if defined $filter->{ttl}   && (!defined $record->{ttl} || $record->{ttl} != $filter->{ttl});

	if(defined $filter->{data}) {
		my $val_r = join(' ', split(/\s+/, $record->{data}));
		my $val_n = join(' ', split(/\s+/, $filter->{data}));
		return 0 unless $val_r eq $val_n;
	}

	return 1;
}

=back

=cut

1;
