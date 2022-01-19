package Zonemod::Cmd::Create;

use strict;
use warnings;

use Zonemod::Driver    qw(get_driver_for_uri);
use Zonemod::Utils     qw(verbose);
use Zonemod::RecordSet qw(contains_record);
use Zonemod::Diff      qw(is_managed encode_diff);
use Zonemod::ZoneDb    qw(parse_resource_record);

use Data::Dumper;
use Try::Tiny;

=head1 C<delete>

Creates single record in DNS zone

=head1 USAGE

	zonemod create 'test-a 100 A 127.0.0.1' ./zonefile.db

=head1 ALIASES

create make mk add

=head1 FLAGS

=over 4

=item --managed MANAGED

If set, will read/write from an additional DNS storage backend to keep track of the set of "managed"
records. This allows zonemod to be used in conjunction with other automatted tools and/or manual
modifications of a DNS provider's records.

zonemod will refuse to create a record if it is managed by the target zone (under the active
 --grouping rules) unless it also exists in the managed set. Create command willalso update the
managed set to include the new record

=back

=cut

sub aliases {
	return qw(create make mk add);
}

sub run {
	my ($cli, $recordStr, $targetUri) = @_;
	die "Create command expects 2 positional arguments: RECORD and TARGET" unless $recordStr && $targetUri;

	my $record = try {
		return parse_resource_record($recordStr);
	} catch {
		print STDERR "Failed to parse record: $_";
	  exit 255;
	};
	my $target  = get_driver_for_uri($targetUri, 'target');
  my $managed = get_driver_for_uri($cli->{managed_set}, 'managed-set');

	my $existing = $target->can('get_records')->($targetUri, { allowNonExistent => 1 });

	if(contains_record($existing->{records}, { %$record, ttl => $cli->{strict} ? undef : $record->{ttl} })) {
		($cli->{strict} ? *STDOUT : *STDERR)->print("Specified record already exists\n");
		return $cli->{strict} // 0;
	}

	# Fetch data for managed set
	my $managedData;
	if($managed) {
		$managedData = $managed->can('get_records')->($cli->{managed_set}, {
			allowNonExistent => 1,
		});

		if(
			is_managed($existing->{records}, $cli->{record_grouping}, $record) &&
			!is_managed($managedData->{records}, $cli->{record_grouping}, $record)
		) {
			print STDERR "Refusing to create record: group already managed by target zone, but not by managed set";
			return 1;
		}
	}

	my $diff = [
		{diff => '-', %$record, ttl => undef },
		{diff => '+', %$record },
	];
	if($cli->{dryrun}) {
		print "Dryrun mode set - would have applied diff:\n";
		print encode_diff($diff);
	} else {
		$target->can('write_diff')->($targetUri, $diff, { wait => $cli->{wait}, dryrun => $cli->{dryrun}, allowNonExistent => 1 });
		if($managed) {
			$managed->can('write_diff')->($cli->{managed_set}, $diff, { wait => $cli->{wait}, dryrun => $cli->{dryrun} });
		}
	}

	return 0;
}

1;
