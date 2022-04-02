package Zonemod::Driver::Hetzner;

=head1 OVERVIEW C<Zonemod::Driver::Hetzner>

zonemod driver for interacting with Hetzner DNS

Can find zone's ID as final component of URL by selecting it from dashboard at:
https://dns.hetzner.com/

=cut

use strict;
use warnings;

use JSON::XS qw(decode_json);
use Try::Tiny;

use Zonemod::Utils   qw(verbose get_ua);
use Zonemod::Diff    qw(compute_record_set_diff apply_diff);
use Zonemod::ZoneDb  qw(parse_zonedb encode_zonedb);

use Exporter qw(import);
our @EXPORT_OK = qw(
  can_handle get_records set_records write_diff
);

my $API_ENDPOINT = 'https://dns.hetzner.com/api/v1';
my $URI_REGEX    = qr|^hetzner://(.+)$|;

sub _get_api_token {
	my $token = $ENV{ZONEMOD_HETZNER_API_TOKEN};
	die "Must specify ZONEMOD_HETNZER_API_TOKEN env variable" unless $token;
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

Fetches the existing records from Hetzner

=cut
sub get_records {
	my ($uri) = @_;

	die "Invalid Hetzner URI: $uri" unless $uri =~ $URI_REGEX;
	my $zoneId = $1;

	my $ua = get_ua();

	my $res = $ua->request(HTTP::Request->new(
		'GET'            => "${API_ENDPOINT}/zones/$zoneId/export",
		[ 'Auth-API-Token' => _get_api_token() ],
	));

	die 'Failed to fetch existing records from hetzner: ' . $res->status_line unless $res->is_success;

  my $body = $res->decoded_content;
	return parse_zonedb($body);
}

=item C<write_diff>

Writes a set of diffs to Hetzner

=cut
sub write_diff {
	my ($uri, $diff, $args) = @_;

	my $existing = $args->{existing} || get_records($uri);

	my @final = apply_diff($existing->{records}, $diff);

	return set_records(
		$uri,
		{
			records => \@final,
			origin  => $args->{origin} || $existing->{origin},
			ttl     => $existing->{ttl}
		},
		$args
	);
}

=item C<set_records>

Writes records to Hetzner, replacing any existing data

=cut
sub set_records {
	my ($uri, $zonedb, $args) = @_;

	die "Invalid Hetzner URI: $uri" unless $uri =~ $URI_REGEX;
	my $zoneId = $1;

	my $zonefile = encode_zonedb($zonedb);

	my $ua = get_ua();

	my $res = $ua->request(HTTP::Request->new(
		'POST'             => "${API_ENDPOINT}/zones/$zoneId/import",
		[ 'Auth-API-Token' => _get_api_token(),
			'Content-Type'   => 'text/plain',
		],
		$zonefile,
	));
	die 'Failed to update hetzner records: ' . $res->status_line . "\n" . $res->decoded_content unless $res->is_success;

	my $body = try {
	  return decode_json($res->decoded_content);
	} catch {
		die "Unexpected hetzner response after update (bad json: $!)";
	};
	die "Unexpected hetzner response after update (bad zone id)" unless $body->{zone}{id} eq $zoneId;

	print "Updated Hetzner Zone Successfully\n";
}

=back

=cut

1;
