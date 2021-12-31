package DnsSync::Provider::ZoneFile;

=head1 OVERVIEW C<ZoneFile>

sync-dns provider for interacting zone files on local disk

=over

=cut

use strict;
use warnings;

use DnsSync::Utils qw(verbose);

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
	my ($uri) = @_;

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
		die "No such file or directory: $path";
	}

	my @results;

	foreach my $path (@files) {
		next if $isDir and $path !~ /.+\.(zone|db)$/;

		open(my $fh, '<', $path) or die $!;
		my $raw = do { local $/; <$fh> };
		close($fh);

		my @lines = split(/\n/, $raw);

		foreach my $line (@lines) {
			my ($label, $ttl, $class, $type, $data) = split(/\t/, $line);
			die "Only Internet (aka: IN class) records are supported, got: $label $ttl $class $type $data in file $path" unless $class eq "IN";
			die "TXT record data must be wrapped in quotes" if $type eq "TXT" and $data !~ /^"[^"]+"$/;
			push @results, { label => $label, ttl => $ttl + 0, class => $class, type => $type, data => $data };
		}
	}

	return { records => \@results, origin => undef };
}

=item C<write_records>

Writes records to zone file

=cut
sub write_changes {
	my ($uri, $records, $args) = @_;

	my $path = _parse_uri($uri);

	die "Unimplemented: write to zone file";
}

=back

=cut

1;
