package DnsSync::ZoneDb;

=head1 OVERVIEW C<DnsSync::ZoneDb>

Functions for parsing and writing zone db format

=over

=cut

use strict;
use warnings;
use Exporter qw(import);
use Try::Tiny;
our @EXPORT_OK = qw(
  parse_zone_db parse_resource_record
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

# Parses contents of zone file string
# Can optionally specify the path for more descriptive error messages including path name
# Returns { records => [], origin => string, ttl => string } object
sub parse_zone_db {
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

=back

=cut

1;
