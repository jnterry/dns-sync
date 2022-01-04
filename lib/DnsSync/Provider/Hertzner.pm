package DnsSync::Provider::Hertzner;

=head1 OVERVIEW C<DnsSync::Provider::Hertzner>

sync-dns provider for interacting with Hertzner DNS

Can find zone's ID as final component of URL by selecting it from dashboard at:
https://dns.hetzner.com/

=cut

use strict;
use warnings;

use JSON::XS qw(decode_json);
use LWP::UserAgent;
use Try::Tiny;

use DnsSync::Utils  qw(verbose get_ua compute_record_set_delta apply_deltas);
use DnsSync::ZoneDb qw(parse_zonedb encode_zonedb);

use Exporter qw(import);
our @EXPORT_OK = qw(
  can_handle get_current write_changes
);

my $API_ENDPOINT = 'https://dns.hetzner.com/api/v1';
my $URI_REGEX    = qr|^hertzner://(.+)$|;

sub _get_api_token {
	my $token = $ENV{DNS_SYNC_HERTZNER_API_TOKEN};
	die "Must specify DNS_SNC_HERTNZER_API_TOKEN env variable" unless $token;
	return $token;
}

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

Fetches the existing records from Hertzner

=cut
sub get_records {
	my ($uri) = @_;

	die "Invalid Hertzner URI: $uri" unless $uri =~ $URI_REGEX;
	my $zoneId = $1;

	my $ua = get_ua();

	my $res = $ua->request(HTTP::Request->new(
		'GET'            => "${API_ENDPOINT}/zones/$zoneId/export",
		[ 'Auth-API-Token' => _get_api_token() ],
	));

	die 'Failed to fetch existing records from hertzner: ' . $res->status_line unless $res->is_success;

  my $body = $res->decoded_content;
	return parse_zonedb($body);
}

=item C<write_records>

Writes records to Hertzner

=cut
sub write_records {
	my ($uri, $records, $args) = @_;

	die "Invalid Hertzner URI: $uri" unless $uri =~ $URI_REGEX;
	my $zoneId = $1;

	# Compute final set of records after deltas are applied
	my $current  = get_records($uri);
	my $delta = compute_record_set_delta($current->{records}, $records, {
		managed => $args->{managed},
	});
	$delta->{deletions} = [] unless $args->{delete};
	my @finalRecords  = apply_deltas($current->{records}, $delta);
	my $finalZonefile = encode_zonedb({
		records => \@finalRecords,
		origin  => $args->{origin} || $current->{origin},
		ttl     => $current->{ttl}
	});

	my $ua = get_ua();

	print "Sending updated zonefile to Hertzner...\n";

	my $res = $ua->request(HTTP::Request->new(
		'POST'             => "${API_ENDPOINT}/zones/$zoneId/import",
		[ 'Auth-API-Token' => _get_api_token(),
			'Content-Type'   => 'text/plain',
		],
		$finalZonefile,
	));
	die 'Failed to update hertzner records: ' . $res->status_line . "\n" . $res->decoded_content unless $res->is_success;

	my $body = try {
	  return decode_json($res->decoded_content);
	} catch {
		die "Unexpected hertzner response after update (bad json: $!)";
	};
	die "Unexpected hertzner response after update (bad zone id)" unless $body->{zone}{id} eq $zoneId;

	print "Updated Hertzner Zone Successfully\n";
}

=back

=cut

1;
