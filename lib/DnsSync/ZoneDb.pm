package DnsSync::ZoneDb;

=head1 OVERVIEW C<DnsSync::ZoneDb>

Functions for parsing and writing zone db format

=over

=cut

use strict;
use warnings;

use DnsSync::Utils qw(group_records);

use Try::Tiny;

use Exporter qw(import);
our @EXPORT_OK = qw(
  parse_resource_record encode_resource_record encode_resource_records
	parse_zonedb  encode_zonedb encode_resource_record
);

my $VERBOSITY = 0;

# https://en.wikipedia.org/wiki/List_of_DNS_record_types
my $REG_TYPE = qr/A|NS|CNAME|SOA|PTR|HINFO|MX|TXT|RP|AFSDB|SIG|KEY|AAAA|LOC|SRV|NAPTR|KX|CERT|DNAME|APL|DS|SSHFP|IPSECKEY|RRSIG|NSEC|DNSKEY|DHCID|NSEC3|NSEC3PARAM|TLSA|SMIMEA|HIP|CDS|DCNSKEY|OPENPGPKEY|CSYNC|ZONEMD|SVCB|HTTPS|EUI48|EUI64|TKEY|TSIG|URI|CAA|TA|DVA/;

# IN = internet, CH = chaosnet, HS = Hesiod
my $REG_CLASS = qr/IN|CH|HS/;

my $REG_TTL   = qr/\d+/;

=item C<parse_resource_record>

Parses a single resource record line

Returns object of the form { label, ttl, class, type, data }

=cut
sub parse_resource_record {
	my ($line, $defaultLabel, $defaultTtl, $defaultClass) = @_;

	my @fields = split(/\s+/, $line); # fields are seperated by any amount and type of whitespace

	my ($label, $ttl, $class, $type, $data) = ($defaultLabel, $defaultTtl, $defaultClass);

	# label field is optional, use previous if line starts with whitespace (indicating empty first field)
	$label = $fields[0] unless $line =~ /^\s+/;
	shift @fields;

	# we now have two optional fields, the class (IN for internet) and TTL
	# Additional, the order in which these are specified is not defined!
	#
	# We know we've reached the end if we find the $type
	my ($a, $b, $c) = (shift @fields, shift @fields, shift @fields);
	if($a =~ $REG_TYPE) {
		$type = $a;
	} elsif (($a =~ $REG_TTL or $REG_CLASS) and $b =~ $REG_TYPE) {
		if($a =~ $REG_TTL) {
			$ttl = $a + 0;
		} else {
			$class = $a;
		}
		$type = $b;
	} elsif ($c =~ $REG_TYPE) {
		if($a =~ $REG_TTL && $b =~ $REG_CLASS) {
			$ttl   = $a + 0;
			$class = $b;
		} elsif ($b =~ $REG_TTL && $a =~ $REG_CLASS) {
			$ttl   = $b + 0;
			$class = $a;
		} else {
			die "Failed to parse optional resource record TTL and CLASS fields, got: '$a' and '$b'";
		}
		$type = $c;
	} else {
		die "Did not get valid resource record type";
	}

	# Extract data as everything AFTER the $type - note that the format of data depends on record type
	# but we don't attempt to parse it here anyway
	$line =~ qr/\s$type\s+(.+)$/;
	$data = $1;

	die "TXT record data must be wrapped in quotes" if $type eq "TXT" and $data !~ /^"[^"]+"$/;

	return { label => $label, ttl => $ttl, class => $class, type => $type, data => $data };
}

=item C<parse_zonedb>

Parses contents of a zone file database represented as string

Can optionally specify the path/name of the file for more descriptive error messages

Returns { records => [], origin => string, ttl => string } object where each item of
records is of the form: { label, ttl, class, type, data }

=cut
sub parse_zonedb {
	my ($raw, $path) = @_;

	my @lines = split(/\n/, $raw);

	my $result = { records => [], origin => undef, ttl => undef };
	my ($lastLabel, $lastClass);

	my $lineNum = 0;
	foreach my $line (@lines) {
		++$lineNum;
		next if $line =~ /^(\s*|\s*;.+)$/; # skip empty lines, or comments (starting with ';')

		my $errorLoc = defined $path ? "$path:$lineNum" : "line $line";

		if($line =~ /^\$([A-Z]+)\s+(.+)/) { # parse variable (eg: $ORIGIN example.com)
			my ($var, $val) = ($1, $2);
			if($var eq 'ORIGIN') {
				$result->{origin} = $val;
			} elsif ($var eq 'TTL') {
				$result->{ttl} = $val + 0;
			} else {
				die "Invalid zone file variable '$var' at $errorLoc";
			}
		} else {
			try {
				my $rec = parse_resource_record($line, $lastLabel, $result->{ttl}, $lastClass);
				push @{$result->{records}}, $rec;
				$lastLabel = $rec->{label};
				$lastClass = $rec->{class};
			} catch {
				die "$_ at $errorLoc";
			};
		}
	}

	return $result;
}

=item C<encode_zonedb>

Writes a { records => [], origin => string, ttl => string } object to zonedb format
and returns resultant string

=cut
sub encode_zonedb {
	my ($data) = @_;

	my $result = '';

	$result .= "\$ORIGIN $data->{origin}\n" if $data->{origin};
	$result .= "\$TTL    $data->{ttl}\n"    if $data->{ttl};
	$result .= encode_resource_records($data->{records});

	return $result;
}

=item C<encode_zonedb>

Writes a list of resource records to lines of a zonedb, can accept either array or output
of C<group_records>

=cut
sub encode_resource_records {
	my ($records) = @_;

	my $recMap = ref($records) eq "ARRAY" ? group_records($records) : $records;

	my $result = '';

	my @names = sort keys %$recMap;
	for my $n (@names) {
		my @types = sort keys %{$recMap->{$n}};
		for my $t (@types) {
			$result .= encode_resource_record($_) . "\n" foreach @{$recMap->{$n}{$t}};
		}
	}

	return $result;
}

=item C<encode_resource_record>

Formats a single resource record as string

=cut
sub encode_resource_record {
	my ($r) = @_;
	return "$r->{label}\t$r->{ttl}\tIN\t$r->{type}\t$r->{data}";
}



=back

=cut

1;
