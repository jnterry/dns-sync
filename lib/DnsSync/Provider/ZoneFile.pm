package DnsSync::Provider::ZoneFile;

=head1 OVERVIEW C<ZoneFile>

sync-dns provider for interacting zone files on local disk

=over

=cut

use strict;
use warnings;

use File::Path qw(make_path);

use DnsSync::Utils qw(verbose replace_records group_records parse_zone_file);

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

	my @results;

	foreach my $path (@files) {
		next if $isDir and $path !~ /.+\.(zone|db)$/;
		push @results, _load_zone_file($path);
	}

	return { records => \@results, origin => undef };
}

# Helper which loads contents of a DNS zone file
sub _load_zone_file {
	my ($path) = @_;

	open(my $fh, '<', $path) or die $!;
	my $raw = do { local $/; <$fh> };
	close($fh);

	return parse_zone_file($raw, $path);
}

=item C<write_records>

Writes records to zone file

=cut
sub write_records {
	my ($uri, $records, $args) = @_;

	my $path = _parse_uri($uri);
	my $grouped = group_records($records);

	# When writing to a directory, we write each hostname to a seperate file
	# Otherwise just write to a single file
	#
	# Note that to match the behaviour of other providers, we need to merge
	# the data into the target (unless --delete flag is set) and hence we must read the
	# file to see what is already exists before writing
	if($path =~ qr|.+/$| or -d $path) {
		my $dirPath = $path =~ qr|/^| ? $path : "${path}/";

		make_path($dirPath) unless -d $dirPath;
		unlink glob "'${dirPath}*.zone'" if $args->{delete};

		for my $n (keys %$grouped) {
			my $filePath = "${dirPath}${n}.zone";
			_merge_grouped_records_into_file($filePath, { $n => $grouped->{$n} }, $args);
		}
	} else {
		_merge_grouped_records_into_file($path, $grouped, $args);
	}
}

# Helper which writes a set of grouped records into a file, if it already exists
# first loads the file and merges the grouped records with existing ones
sub _merge_grouped_records_into_file {
	my ($path, $grouped, $args) = @_;

	my $final = $grouped;

	unless($args->{delete}) {
		my @current;
		@current = _load_zone_file($path) if -f $path;
		my $existing = group_records(\@current);

		$final = replace_records($existing, $grouped);
	}

	open(my $fh, '>', $path);
	my @names = sort keys %$final;
	for my $n (@names) {
		my @types = sort keys %{$final->{$n}};
		for my $t (@types) {
			for my $r (@{$final->{$n}{$t}}) {
				print $fh "$r->{label}\t$r->{ttl}\tIN\t$r->{type}\t$r->{data}\n";
			}
		}
	}
	close($fh);
}

=back

=cut

1;
