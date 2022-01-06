package Zonemod::Cmd::Delete;

use strict;
use warnings;

use Zonemod::Driver    qw(get_driver_for_uri);
use Zonemod::Utils     qw(verbose);
use Zonemod::RecordSet qw(contains_record);
use Zonemod::Diff      qw(compute_record_set_diff apply_diff);
use Zonemod::ZoneDb    qw(parse_resource_record);

use Data::Dumper;
use Try::Tiny;

=head1 C<delete>

Delete single record from DNS zone

=head1 USAGE

	zonemod delete 'test-a 100 A 127.0.0.1' ./zonefile.db

=head1 ALIASES

delete, del, remove, rm

=head1 FLAGS

=over 4

=item --managed MANAGED

If set, will read/write from an additional DNS storage backend to keep track of the set of "managed"
records. This allows zonemod to be used in conjunction with other automatted tools and/or manual
modifications of a DNS provider's records.

zonemod will refuse to delete an entry not in the managed set, and will also update the managed set
to remeber the record in question is no longer managed

=item --force

Prevent unsuccessful exit when record does not already exist

Additionally, will forceably delete the record from both TARGET and managed set, even if zonemod does
not currently manage the record in question

=back

=cut

sub aliases {
	return qw(delete del remove rm);
}

sub run {
	my ($cli, $recordStr, $targetUri) = @_;
	die "Delete command expects 2 positional arguments: RECORD and TARGET" unless $recordStr && $targetUri;

	my $record = try {
		return parse_resource_record($recordStr);
	} catch {
		print STDERR "Failed to parse record: $_";
	  exit 255;
	};
	my $target  = get_driver_for_uri($targetUri, 'target');
  my $managed = get_driver_for_uri($cli->{managed_set}, 'managed-set');

	my $existing = $target->can('get_records')->($targetUri);

	unless($cli->{force} || contains_record($existing->{records}, $record)) {
		print STDERR "Specified record does not exist\n";
		return 1;
	}

	# Fetch data for managed set
	my $managedData;
	if($managed) {
		$managedData = $managed->can('get_records')->($cli->{managed_set}, {
			allowNonExistent => 1,
		});

		unless($cli->{force} || contains_record($managed->{records}, $record)) {
			print STDERR "Refusing to delete record: does not exist in managed set";
			return 1;
		}
	}

	my $diff = [{diff => '-', %$record }];
	$target->can('write_diff')->($targetUri, $diff, { wait => $cli->{wait} });
	if($managed) {
		$managed->can('write_diff')->($targetUri, $diff, { wait => $cli->{wait} });
	}

	return 0;
}

1;
