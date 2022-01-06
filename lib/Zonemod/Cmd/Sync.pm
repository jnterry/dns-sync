package Zonemod::Cmd::Sync;

use strict;
use warnings;

use Zonemod::Diff      qw(compute_record_set_diff apply_diff);
use Zonemod::Driver    qw(get_driver_for_uri);
use Zonemod::RecordSet qw(ungroup_records);
use Zonemod::Utils     qw(verbose);
use Zonemod::ZoneDb    qw(encode_zonedb);

=head1 C<sync> - rsync for dns

Synchronises records from source DNS provider to target DNS provider

=head1 USAGE

	zonemod sync SOURCE TARGET [--delete] [--managed MANAGED]

=head1 FLAGS

=over 4

=item --delete

If set, will delete records in TARGET not found in SOURCE. By default, only new/replaced records are
synced from SOURCE to TARGET

See also --managed

=item --managed MANAGED

If set, will read/write from a third DNS storage backend to keep track of the set of "managed"
records. This allows zonemod to be used in conjunction with other automatted tools and/or manual
modifications of a DNS provider's records.

zonemod will refuse to overwrite existing records not in the managed set, and will also skip
deletion when --delete flag is set

=back

=cut

# Gets list of names that this command can run under
sub aliases {
	return qw(sync);
}

# Execute the command
sub run {
	my ($cli, $sourceUri, $targetUri) = @_;
	die "Sync command expects 2 positional arguments: SOURCE and TARGET" unless $sourceUri && $targetUri;

	# Find the providers for the source and dest
	my $source  = get_driver_for_uri($sourceUri, 'source');
	my $target  = get_driver_for_uri($targetUri, 'target');
	my $managed = get_driver_for_uri($cli->{managed_set}, 'managed-set');

	# Fetch data for managed set
	my $managedData;
	if($managed) {
		$managedData = $managed->can('get_records')->($cli->{managed_set}, {
			allowNonExistent => 1,
		});
	}

	# Compute diff for target
	my $desired  = $source->can('get_records')->($sourceUri);
	my $existing = $target->can('get_records')->($targetUri, { allowNonExistent => 1 });

	my ($allowedDiff, $blockedDiff) = compute_record_set_diff($existing->{records}, $desired->{records}, {
		managed  => $managedData->{records},
		noDelete => !$cli->{delete},
		grouping => $cli->{record_grouping},
	});
	my @blockedCreations = grep { $_->{diff} eq '+' } ungroup_records($blockedDiff);
	if(@blockedCreations) {
		print STDERR "Cannot sync - the following records would conflict with existing records in the target which are not in our management set\n";
		print STDERR encode_zonedb({ records => \@blockedCreations });
		return 1;
	}

	# Perform sync
	my %writeArgs = (
		wait     => $cli->{wait},
		origin   => $cli->{origin},
		existing => $existing,
	);
	my @flatDiff = ungroup_records($allowedDiff);
	unless(scalar @flatDiff) {
		print "No updates required\n";
	} else {
		verbose "Writing updates to target";
		$target->can('write_diff')->($targetUri, $allowedDiff, \%writeArgs);
	}

	# Update managed set for use next run
	if($managed) {
		verbose "Updating managed set";
		$managed->can('set_records')->($cli->{managed_set}, {
			origin  => $cli->{origin} || $managedData->{origin},
			ttl     => $managedData->{origin},
			records => $desired->{records},
		}, \%writeArgs);
	}

	return 0;
}

1;
