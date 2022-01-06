#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep qw(cmp_set);

require_ok('Zonemod::RecordSet');

use Zonemod::ZoneDb    qw(parse_zonedb);
use Zonemod::RecordSet qw(group_records ungroup_records does_record_match);

my @rs = (
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" },
	{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA', data => "::1"       },
	{ label => 'test-b', ttl => 100, class => 'IN', type => 'TXT',  data => '"abc"'     },
	{ label => 'test-c', ttl => 150, class => 'IN', type => 'MX',   data => '127.0.0.1' },
);

# ------------------------------------------------------
# - TEST: group_records                                -
# ------------------------------------------------------
my $grouped = group_records(\@rs);

is_deeply($grouped, {
	'test-a' => {
		'A'    => [ $rs[0], $rs[1] ],
		'AAAA' => [ $rs[2] ],
	},
	'test-b' => {
		'TXT' => [ $rs[3] ],
	},
	'test-c' => {
		'MX' => [ $rs[4] ],
	},
}, "Grouping works as expected");

# ------------------------------------------------------
# - TEST: ungroup_records                              -
# ------------------------------------------------------
my @ungrouped = ungroup_records($grouped);
cmp_set(\@ungrouped, \@rs, "ungroup(group) is no-op");

@ungrouped = ungroup_records({
	'test-a' => {
		'X' => [{ hello => 'world' }],
	},
	'test-b' => {
		'Y' => [{ meta => 6 }],
	},
});
cmp_set(\@ungrouped, [
	{ label => 'test-a', type => 'X', hello => 'world' },
	{ label => 'test-b', type => 'Y', meta  => 6       },
], "ungroup can handle arbitrary meta data, and auto-inserts label and type names");

@ungrouped = ungroup_records({});
is_deeply(\@ungrouped, [], "Ungroup of empty object returns empty arrray");

# ------------------------------------------------------
# - TEST: does_record_match                            -
# ------------------------------------------------------

# exact match
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
), 1, 'does_record_match - exact');

# exact match - single field different
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" },
), 0, 'does_record_match - different data');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "127.0.0.1" },
), 0, 'does_record_match - different type');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a', ttl => 300, class => 'HS', type => 'A',    data => "127.0.0.1" },
), 0, 'does_record_match - different class');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a', ttl => 301, class => 'IN', type => 'A',    data => "127.0.0.1" },
), 0, 'does_record_match - different ttl');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
), 0, 'does_record_match - different label');

# single field - label
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a' },
), 1, 'does_record_match - label only - match');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-b' },
), 0, 'does_record_match - label only - no match');

# single field - ttl
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ ttl => 300 },
), 1, 'does_record_match - ttl only - match');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ ttl => 301 },
), 0, 'does_record_match - ttl only - no match');

# single field - class
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ class => 'IN' },
), 1, 'does_record_match - class only - match');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ class => 'HS' },
), 0, 'does_record_match - class only - no match');

# single field - type
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ type => 'A' },
), 1, 'does_record_match - type only - match');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ type => 'AAAA' },
), 0, 'does_record_match - type only - no match');

# single field - data
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ data => '127.0.0.1' },
), 1, 'does_record_match - data only - match');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ data => '127.0.0.2' },
), 0, 'does_record_match - data only - no match');

# data field flexible parsing
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'MX', data => "10 example.com" },
  { label => 'test-a', ttl => 300, class => 'IN', type => 'MX', data => "10   example.com" },
), 1, 'data field whitespace does not matter (field seperator size)');
is_deeply(does_record_match(
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'MX', data => "10 example.com" },
  { label => 'test-a', ttl => 300, class => 'IN', type => 'MX', data => "10	example.com " },
), 1, 'data field whitespace does not matter (tab & trailing)');


done_testing();
