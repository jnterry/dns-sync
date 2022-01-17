package Zonemod::Cmd::Delete;

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

	unless(contains_record($existing->{records}, $record)) {
		($cli->{strict} ? *STDOUT : *STDERR)->print("Specified record does not exist\n");
		return $cli->{strict};
	}

	# Fetch data for managed set
	my $managedData;
	if($managed) {
		$managedData = $managed->can('get_records')->($cli->{managed_set}, {
			allowNonExistent => 1,
		});

		unless(is_managed($managedData->{records}, $cli->{record_grouping}, $record)) {
			print STDERR "Refusing to delete record: not present in managed set";
			return 1;
		}
	}

	my $diff = [{diff => '-', %$record }];

	if($cli->{dryrun}) {
		print "Dryrun mode set - would have applied diff:\n";
		print encode_diff($diff);
	} else {
		$target->can('write_diff')->($targetUri, $diff, { wait => $cli->{wait}, dryrun => $cli->{dryrun} });
		if($managed) {
			$managed->can('write_diff')->($cli->{managed_set}, $diff, { wait => $cli->{wait}, dryrun => $cli->{dryrun} });
		}
	}

	return 0;
}

1;
