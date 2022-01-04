#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 10;
use Test::Deep qw(cmp_set);

require_ok('DnsSync::Utils');

use DnsSync::ZoneDb qw(parse_zonedb);
use DnsSync::Utils  qw(group_records ungroup_records compute_record_set_delta apply_deltas);

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


# ------------------------------------------------------
# - TEST: compute_record_set_delta and apply_deltas    -
# ------------------------------------------------------

my $parsed = parse_zonedb(q{
test-a	300	IN	A	127.0.0.1
test-a	300	IN	A	127.0.0.5
test-b	999	IN	TXT	"abc"
test-d	900	IN	MX	127.0.0.1
});

my $delta = compute_record_set_delta($grouped, $parsed->{records});
cmp_set($delta->{upserts}, [
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => '127.0.0.1' },
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => '127.0.0.5' }, # modified content, so whole A set changes
	{ label => 'test-b', ttl => 999, class => 'IN', type => 'TXT',  data => '"abc"'     }, # new TTL
	{ label => 'test-d', ttl => 900, class => 'IN', type => 'MX',   data => '127.0.0.1' }, # brand new host
], "Upserts include replacements for all conflicting records in the same set");
cmp_set($delta->{deletions}, [
	{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA', data => '::1'       }, # no longer present (even though A records are!)
	{ label => 'test-c', ttl => 150, class => 'IN', type => 'MX',   data => '127.0.0.1' }, # entire host deleted
], "Deletions include only fully removed record sets");

my @final = apply_deltas($grouped, $delta);
cmp_set(\@final, $parsed->{records}, "Applying deltas results in correct output set");

$delta = compute_record_set_delta($grouped, $parsed->{records}, {
	managed => {
		'test-a' => { 'A' => [{}], 'AAAA' => [{}] },
		'test-b' => { 'TXT' => [{}] },
	},
});
cmp_set($delta->{upserts}, [
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => '127.0.0.1' },
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => '127.0.0.5' }, # modified content, so whole A set changes
	{ label => 'test-b', ttl => 999, class => 'IN', type => 'TXT',  data => '"abc"'     }, # new TTL
	{ label => 'test-d', ttl => 900, class => 'IN', type => 'MX',   data => '127.0.0.1' }, # brand new host
], "Upserts include replacements for all conflicting records in the same set");
cmp_set($delta->{deletions}, [
	{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA', data => '::1'       }, # no longer present (even though A records are!)
], "Deletions exclude records not in managed set");

@final = apply_deltas($grouped, $delta);
cmp_set(\@final, [
	@{$parsed->{records}},
	{ label => 'test-c', ttl => 150, class => 'IN', type => 'MX',   data => '127.0.0.1' },
], "Applying deltas results in correct output set, with unmanged records not deleted");

=cut
