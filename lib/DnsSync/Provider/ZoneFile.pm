package DnsSync::Provider::ZoneFile;

=head1 OVERVIEW C<ZoneFile>

sync-dns provider for interacting zone files on local disk

=over

=cut

use strict;
use warnings;

use File::Basename;
use File::Path qw(make_path);

use DnsSync::RecordSet qw(replace_records group_records compute_record_set_delta apply_deltas);
use DnsSync::Utils     qw(verbose);
use DnsSync::ZoneDb    qw(parse_zonedb encode_resource_records);

use Exporter qw(import);
our @EXPORT_OK = qw(
  can_handle get_current write_changes write_records
);

sub _parse_uri {
	my ($uri) = @_;
	return $uri if $uri =~ qr{^\.?/};
	return $1 if $uri =~ qr{^(file|unix)://(.+)$};
	return;
}

=back

=head1 FUNCTIONS

=over 4

=item C<can_handle>

Checks whether this provider is able to handle a particular dns uri

=cut

sub can_handle {
	my ($uri) = @_;
	my $path = _parse_uri($uri);
	return defined $path;
}

=item C<load_current>

Loads records from a zone file (or directory containing zone files)

Returns list of objects of the form:
{ label,      ttl, class, type, data }
  example.com 600  IN     A     127.0.0.1

=cut
sub get_records {
	my ($uri, $args) = @_;

	my $path = _parse_uri($uri);

	my @files;
	my $isDir = 0;
	if(-f $path) {
		@files = ( $path );
	} elsif (-d $path) {
		$isDir = 1;
		opendir(my $dh, $path);
		@files = map { "$path/$_" } readdir($dh);
		closedir($dh);
	} else {
		if($args->{allowNonExistent}) {
			return { records => [], origin => undef };
		} else {
			die "No such file or directory: $path";
		}
	}

	my $results = { records => [], origin => undef, ttl => undef };
	foreach my $path (@files) {
		next if $isDir and $path !~ /.+\.(zone|db)$/;
		my $data = _load_zone_file($path);
		push @{$results->{records}}, @{$data->{records}};
		$results->{origin} ||= $data->{origin};
		$results->{ttl}    ||= $data->{ttl};
	}
	return $results;
}

# Helper which loads contents of a DNS zone file
sub _load_zone_file {
	my ($path) = @_;

	open(my $fh, '<', $path) or die $!;
	my $raw = do { local $/; <$fh> };
	close($fh);

	return parse_zonedb($raw, $path);
}

=item C<write_records>

Writes records to zone file

=cut
sub write_records {
	my ($uri, $records, $args) = @_;

	# To match the behaviour of other providers, we need to merge the data into the target
	# (subject to the --delete and --managed-set flags) - hence we must read the existing
	# data before writing
	my $path     = _parse_uri($uri);
	my $existing = group_records(get_records($uri, { allowNonExistent => 1 })->{records});

	# Compute final set of records after deltas are applied
	my $delta = compute_record_set_delta($existing, $records, {
		managed => $args->{managed},
	});
	$delta->{deletions} = [] unless $args->{delete};
	my @finalRecords = apply_deltas($existing, $delta);
	my $groupedFinal = group_records(\@finalRecords);

	my $parentDir = dirname($path);
	make_path($parentDir) if $parentDir;

	if($path =~ qr|.+/$| or -d $path) {
		my $dirPath = $path =~ qr|/^| ? $path : "${path}/";

		make_path($dirPath);
		unlink glob "'${dirPath}*.zone'";

		for my $n (keys %$groupedFinal) {
			my $filePath = "${dirPath}${n}.zone";
			_write_records_to_file($filePath, { $n => $groupedFinal->{$n} });
		}
	} else {
		_write_records_to_file($path, $groupedFinal);
	}
}

# Helper which writes a set of grouped records into a file
sub _write_records_to_file {
	my ($path, $grouped, $args) = @_;

	open(my $fh, '>', $path);
	print $fh encode_resource_records($grouped);
	close($fh);
}

=back

=cut

1;
