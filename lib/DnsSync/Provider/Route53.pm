package DnsSync::Provider::Route53;

=head1 OVERVIEW C<route53>

sync-dns provider for interacting with AWS Route53

=over

=cut

use strict;
use warnings;

use File::Temp qw(tempfile);
use JSON::XS qw(decode_json encode_json);

use DnsSync::Utils qw(verbose group_records compute_required_updates);

use Exporter qw(import);
our @EXPORT_OK = qw(
  can_handle get_current write_changes
);

my $URI_REGEX = qr|^route53://(.+)$|;

=back

=head1 FUNCTIONS

=over 4

=item C<can_handle>

Checks whether this provider is able to handle a particular dns uri

=cut

sub can_handle {
	my ($input) = @_;
	return $input =~ $URI_REGEX;
}

=item C<get_records>

Fetches the existing records from AWS

=cut
sub get_records {
	my ($uri) = @_;

	die "Invalid Route53 URI: $uri" unless $uri =~ $URI_REGEX;
	my $zoneId = $1;

	# Fetch AWS meta data
	verbose("Fetching Route53 zone meta data...\n");
	my $zone = `aws route53 get-hosted-zone --id ${zoneId}`;
	die "Failed to fetch Route53 zone meta data" unless ($? >> 8 == 0);
	$zone = decode_json($zone);
	my $origin = $zone->{HostedZone}{Name};

	# Fetch AWS Records
  verbose("Listing existing DNS records...\n");
	my @awsRecords;
	my $existing = `aws route53 list-resource-record-sets --hosted-zone-id $zoneId`;
	die "Failed to list Route53 records" unless ($? >> 8 == 0);
	$existing = decode_json($existing);
	push @awsRecords, @{$existing->{ResourceRecordSets}};
	while($existing->{NextToken}) {
	  $existing = `aws route53 list-resource-record-sets --hosted-zone-id $zoneId --starting-token $existing->{NextToken}`;
	  die "Failed to list Route53 records" unless ($? >> 8 != 0);
		$existing = decode_json($existing);
		push @awsRecords, @{$existing->{ResourceRecordSets}};
	}

	# Convert from AWS record format to zone file object format
	my @results;
	for my $rec (@awsRecords) {
		for my $val (@{$rec->{ResourceRecords}}) {
			my $label = substr($rec->{Name}, 0, -length($origin)-1);
			$label = '@' if length($label) == 0;
			push @results, {
				label => $label,
				ttl   => $rec->{TTL},
				class => 'IN',
				type  => $rec->{Type},
				data  => $val->{Value},
			};
		}
	}

	return { records => \@results, origin => $origin };
}

=item C<write_records>

Writes records to AWS. Note that intnerally this first calls get_records, and only updates those
which have changed

=over 4

=item C<uri>     route53://$zoneId uri to write changes to

=item C<records> list of records to write

=item C<args.origin> DNS Origin to prepend to records label's

=item C<args.wait> If set, will wait for change to propogate to DNS servers before returning

=back

=cut
sub write_records {
	my ($uri, $records, $args) = @_;

	die "Invalid Route53 URI: $uri" unless $uri =~ $URI_REGEX;
	my $zoneId = $1;

	# Compute the set of changes that need to be made
	my $existing = get_records($uri);
	my @updates  = compute_required_updates($existing->{records}, $records);
	if(scalar(@updates)== 0) {
		print "No updates required\n";
		return;
	}

	my $origin = $args->{origin} || $existing->{origin};

	# Convert from list of zone file style record objects to AWS API objects
	my @actions;
	my $grouped = group_records(\@updates);
	for my $n (keys %$grouped) {
		for my $t (keys %{$grouped->{$n}}) {
			my $ttl = 999999999;
			my @values;

			for my $r (@{$grouped->{$n}{$t}}) {
				$ttl = $r->{ttl} if $r->{ttl} < $ttl;
				push @values, { Value => $r->{data} };
			}

			push @actions, {
				Name            => "${n}.${origin}",
				Type            => $t,
				TTL             => $ttl,
				ResourceRecords => \@values,
			};
		}
	}
	@actions = map { { Action => "UPSERT", "ResourceRecordSet" => $_ } } @actions;
	my $awsUpdate = {
		Comment => "route53-sync update",
		Changes => \@actions,
	};
	my $updateJson = encode_json($awsUpdate);

	my $changeCount = scalar(@actions);
	print "Performing AWS update ($changeCount record" . ($changeCount == 1 ? '' : 's') . " to change)\n";

	my ($fh, $updateFilename) = tempfile("route53-sync-XXXXXXXX", DIR => '/tmp');
	print $fh $updateJson;
	close($fh);

	# Make change and wait for completion
	my $out = `aws route53 change-resource-record-sets --hosted-zone-id $zoneId --change-batch file://${updateFilename}`;
	my $retcode = $?;
	unlink $fh;
  exit ($retcode >> 8) if ($retcode >> 8 != 0);

	if($args->{wait}) {
		my $change = decode_json($out);
		verbose("Waiting for Route53 update '$change->{ChangeInfo}{Id}' to complete\n");
		my $elapsed = 20;
		sleep($elapsed);
		while($change->{ChangeInfo}{Status} ne "INSYNC") {
			verbose("Waiting for Route53 update '$change->{ChangeInfo}{Id}' to complete (elapsed: ${elapsed}s)\n");
			sleep(5);
			$elapsed += 5;
			$out = `aws route53 get-change --id $change->{ChangeInfo}{Id}`;
			exit ($? >> 8) if ($? >> 8 != 0);
			$change = decode_json($out);
		}
	}

	print "Update complete\n";
}

=back

=cut

1;
