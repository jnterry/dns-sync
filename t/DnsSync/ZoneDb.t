#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep qw(cmp_set);
use List::MoreUtils qw(uniq);

use Data::Dumper;

require_ok('DnsSync::ZoneDb');

use DnsSync::ZoneDb qw(parse_zonedb parse_resource_record);

# ------------------------------------------------------
# - TEST: parse_zone_record                            -
# ------------------------------------------------------

is_deeply(
	parse_resource_record('a 100 IN A 127.0.0.1'),
	{ label => 'a', ttl => 100, class => 'IN', type => 'A',    data => "127.0.0.1" },
	'Simple parse'
);

is_deeply(
	parse_resource_record('a IN A 127.0.0.1'),
	{ label => 'a', ttl => undef, class => 'IN', type => 'A',    data => "127.0.0.1" },
	'Missing TTL'
);

is_deeply(
	parse_resource_record('a 999 A 127.0.0.1'),
	{ label => 'a', ttl => 999, class => undef, type => 'A',    data => "127.0.0.1" },
	'Missing Class'
);

is_deeply(
	parse_resource_record('a A 127.0.0.1'),
	{ label => 'a', ttl => undef, class => undef, type => 'A',    data => "127.0.0.1" },
	'Missing TTL & Class'
);

is_deeply(
	parse_resource_record('  A 127.0.0.1', 'label', 123, 'CH'),
	{ label => 'label', ttl => 123, class => 'CH', type => 'A',    data => "127.0.0.1" },
	'Missing All'
);

is_deeply(
	parse_resource_record('  100 A 127.0.0.1', 'label', 123, 'CH'),
	{ label => 'label', ttl => 100, class => 'CH', type => 'A',    data => "127.0.0.1" },
	'Missing label & class'
);

is_deeply(
	parse_resource_record('100 A 127.0.0.1'),
	{ label => '100', ttl => undef, class => undef, type => 'A',    data => "127.0.0.1" },
	'Label looks like TTL'
);

is_deeply(
	parse_resource_record('100 200 A 127.0.0.1'),
	{ label => '100', ttl => 200, class => undef, type => 'A',    data => "127.0.0.1" },
	'Label looks like TTL with a TTL'
);

is_deeply(
	parse_resource_record('@ 100 IN MX 10 example.com'),
	{ label => '@', ttl => 100, class => 'IN', type => 'MX', data => "10 example.com" },
	'Record data containing whitespace'
);

# ------------------------------------------------------
# - TEST: parse_zonedb                                 -
# ------------------------------------------------------
my $data = parse_zonedb(q{
test-a	300	IN	A	127.0.0.1
test-a	300	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	100	IN	TXT	"abc"
test-c	150	IN	MX	127.0.0.1
});
my @rs = @{$data->{records}};
is($data->{origin}, undef, "Expected no origin");
is($data->{ttl},    undef, "Expected no TTL");
is_deeply(scalar @rs, 5, "5 records parsed");
is_deeply($rs[0], { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" }, "Record 0 Parsed");
is_deeply($rs[1], { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" }, "Record 1 Parsed");
is_deeply($rs[2], { label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA', data => "::1"       }, "Record 2 Parsed");
is_deeply($rs[3], { label => 'test-b', ttl => 100, class => 'IN', type => 'TXT',  data => '"abc"'     }, "Record 3 Parsed");
is_deeply($rs[4], { label => 'test-c', ttl => 150, class => 'IN', type => 'MX',   data => '127.0.0.1' }, "Record 4 Parsed");


# Try again with missing data and variables
$data = parse_zonedb(q{
$ORIGIN  example.com
$TTL     999
test-a	300	IN	A     127.0.0.1
        300 IN	A     127.0.0.2
	              AAAA  ::1
test-b	100	    TXT	"abc"
test-c		      MX	127.0.0.1
});
@rs = @{$data->{records}};
is($data->{origin}, 'example.com', 'Expected example.com as origin');
is($data->{ttl},    999,           'Expected 999 as ttl');
is_deeply(scalar @rs, 5, "5 records parsed");
is_deeply($rs[0], { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" }, "Record 0 Parsed");
is_deeply($rs[1], { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" }, "Record 1 Parsed");
is_deeply($rs[2], { label => 'test-a', ttl => 999, class => 'IN', type => 'AAAA', data => "::1"       }, "Record 2 Parsed");
is_deeply($rs[3], { label => 'test-b', ttl => 100, class => 'IN', type => 'TXT',  data => '"abc"'     }, "Record 3 Parsed");
is_deeply($rs[4], { label => 'test-c', ttl => 999, class => 'IN', type => 'MX',   data => '127.0.0.1' }, "Record 4 Parsed");


done_testing();
