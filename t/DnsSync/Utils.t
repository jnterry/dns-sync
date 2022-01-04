#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 16;
use Test::Deep qw(cmp_set);
use List::MoreUtils qw(uniq);

require_ok('DnsSync::Utils');

use DnsSync::Utils qw(parse_zone_file group_records ungroup_records compute_record_set_delta apply_deltas);

sub parse_and_group {
	my ($raw) = @_;
	my @records = parse_zone_file($raw);
	return group_records(\@records);
}

# ------------------------------------------------------
# - TEST: parse_zone_file                              -
# ------------------------------------------------------
my @records = parse_zone_file(q{
test-a	300	IN	A	127.0.0.1
test-a	300	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	100	IN	TXT	"abc"
test-c	150	IN	MX	127.0.0.1
});

my @rs = (
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" },
	{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA', data => "::1"       },
	{ label => 'test-b', ttl => 100, class => 'IN', type => 'TXT',  data => '"abc"'     },
	{ label => 'test-c', ttl => 150, class => 'IN', type => 'MX',   data => '127.0.0.1' },
);

is_deeply(scalar @records, 5, "5 records parsed");
is_deeply($records[0], $rs[0], "Record 0 Parsed");
is_deeply($records[1], $rs[1], "Record 1 Parsed");
is_deeply($records[2], $rs[2], "Record 2 Parsed");
is_deeply($records[3], $rs[3], "Record 3 Parsed");
is_deeply($records[4], $rs[4], "Record 4 Parsed");

# ------------------------------------------------------
# - TEST: group_records                                -
# ------------------------------------------------------
my $grouped = group_records(\@records);

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
cmp_set(\@ungrouped, \@records, "ungroup(group) is no-op");

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

my @new = parse_zone_file(q{
test-a	300	IN	A	127.0.0.1
test-a	300	IN	A	127.0.0.5
test-b	999	IN	TXT	"abc"
test-d	900	IN	MX	127.0.0.1
});

my $delta = compute_record_set_delta($grouped, \@new);
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
cmp_set(\@final, \@new, "Applying deltas results in correct output set");

$delta = compute_record_set_delta($grouped, \@new, {
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
	@new,
	{ label => 'test-c', ttl => 150, class => 'IN', type => 'MX',   data => '127.0.0.1' },
], "Applying deltas results in correct output set, with unmanged records not deleted");

=cut
