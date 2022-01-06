#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;;
use Test::Deep qw(cmp_set);

require_ok('DnsSync::Diff');

use Data::Dumper;
use DnsSync::Diff qw(compute_record_set_diff apply_diff);
use DnsSync::RecordSet qw(ungroup_records);
use DnsSync::ZoneDb qw(encode_zonedb);

sub test_case {
	my ($name, $initial, $desired, $diffArgs, $expectedDiff, $expectedFinal) = @_;

	my ($allowedDiff, $disallowedDiff) = compute_record_set_diff($initial, $desired, $diffArgs);
	my @flatDiff = ungroup_records($allowedDiff);
  cmp_set(\@flatDiff, $expectedDiff, "$name - compute_diff");

	my @final = apply_diff($initial, $allowedDiff);
	cmp_set(\@final, $expectedFinal || $desired, "$name - apply_diff");

	#print "DIFF\n";
	#print Dumper(\@flatDiff);
	#print "GOT\n";
	#print encode_zonedb({ records => \@final });

	my @totalDiff;
	push @totalDiff, @flatDiff;
	push @totalDiff, ungroup_records($disallowedDiff);
  @final = apply_diff($initial, \@totalDiff);
	cmp_set(\@final, $desired, "$name - apply_diff (even disallowed)");
}

# ------------------------------------------------------
# - TEST: compute_record_set_diff (unmanaged)          -
# ------------------------------------------------------
test_case(
	"Add single to empty set",
	[ ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
	{},
	[ { diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
);

test_case(
	"Delete single record to make empty set",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
	[ ],
	{},
  [ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
);

test_case(
	"noDelete flag prevents creation of delete diffs",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
	[ ],
	{ noDelete => 1 },
	[],
  [ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
);

test_case(
	"No changes",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
	{},
	[],
);

test_case(
	"TTL only change still triggers recreation",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
	[ { label => 'test-a', ttl => 999, class => 'IN', type => 'A',    data => "127.0.0.1" } ],
	{},
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
		{ diff => '+', label => 'test-a', ttl => 999, class => 'IN', type => 'A',    data => "127.0.0.1" },
	],
);

test_case(
	"Add single record to non-empty set",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
		{ label => 'test-b', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" },
	],
	{},
	[ { diff => '+', label => 'test-b', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" }, ],
);

test_case(
	"Remove record to make non-empty set",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
		{ label => 'test-b', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" },
	],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" }, ],
	{},
  [ { diff => '-', label => 'test-b', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" }, ],
);

test_case(
	"Swap records",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" }, ],
	[ { label => 'test-b', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" }, ],
	{},
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ diff => '+', label => 'test-b', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" },
	],
);

# --------------------------------------------------------------
# - TEST: compute_record_set_diff (various flag combinations)  -
# --------------------------------------------------------------
{
	my $initial = [
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',     data => "127.0.0.1" },
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',     data => "127.0.0.2" },
		{ label => 'test-a', ttl => 500, class => 'IN', type => 'AAAA',  data => "::1" },
		{ label => 'test-z', ttl => 999, class => 'IN', type => 'TXT',   data => "Hello World" },
	];
	my $desired = [
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" },
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
	];

	# With no flags set, the final desired set should exactly equal that which is requested,
	# with a minimal diff generated to get from source to target
	test_case(
	  "Complex change with multiple of same host/type (no flags)",
		$initial, $desired,
		{},
		[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
			{ diff => '-', label => 'test-a', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" },
			{ diff => '-', label => 'test-z', ttl => 999, class => 'IN', type => 'TXT',  data => "Hello World" },
			{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
			{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
			{ diff => '+', label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
		],
	);

	# In noDelete mode with hostGrouping set to 'none' we do not treat a label/type as a group,
	# hence we avoid deleting ANY records even when there is a replacement
	test_case(
		"Complex change with multiple of same host/type (noDelete, group=none)",
		$initial, $desired,
		{ noDelete => 1, grouping => 'none' },
		[	{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
			{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
			{ diff => '+', label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
		],
		[
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" },
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
			{ label => 'test-a', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" },
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
			{ label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
			{ label => 'test-z', ttl => 999, class => 'IN', type => 'TXT',  data => "Hello World" },
		],
	);

	# In noDelete mode grouping by type, entire host/type groups with no replacement are NOT deleted
	# Note however we still delete records which are being replaced by other items in the host
	test_case(
		"Complex change with multiple of same host/type (noDelete, group=type)",
		$initial, $desired,
		{ noDelete => 1, grouping => 'type' },
		[	{ diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
			{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
			{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
			{ diff => '+', label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
		],
		[
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" },
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
			{ label => 'test-a', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" },
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
			{ label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
			{ label => 'test-z', ttl => 999, class => 'IN', type => 'TXT',  data => "Hello World" },
		],
	);

	# In noDelete mode with hostGrouping set to 'host' we even delete records from a
	# label/type group if we've made any other changes to to host
	test_case(
		"Complex change with multiple of same host/type (noDelete, group=host)",
		$initial, $desired,
		{ noDelete => 1, grouping => 'host' },
		[	{ diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
			{ diff => '-', label => 'test-a', ttl => 500, class => 'IN', type => 'AAAA', data => "::1" },
			{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
			{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
			{ diff => '+', label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
		],
		[
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.2" },
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.3" },
			{ label => 'test-a', ttl => 300, class => 'IN', type => 'MX',   data => "10 example.com" },
			{ label => 'test-b', ttl => 300, class => 'IN', type => 'A',    data => "127.0.0.1" },
			{ label => 'test-z', ttl => 999, class => 'IN', type => 'TXT',  data => "Hello World" },
		],
	);
}


# --------------------------------------------------------------
# - TEST: compute_record_set_diff (with managed set)           -
# --------------------------------------------------------------

test_case(
	"Avoid deleting items not in managed (empty management set)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" },
	],
	[],
	{ managed => [] },
	[],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" },
	],
);
test_case(
	"Avoid deleting items not in managed (item in managed)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" },
	],
	[],
	{ managed => [
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
	] },
	[ { diff  => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" }, ],
);
test_case(
	"Avoid deleting items not in managed (other type in managed, grouping by type)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" },
	],
	[],
	{ grouping => 'type', managed => [
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'AAAA', data => "::1" },
	] },
	[ ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" },
	],
);
test_case(
	"Avoid deleting items not in managed (other type in managed, grouping by host)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" },
	],
	[],
	{ grouping => 'host', managed => [
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'AAAA', data => "::1" },
	] },
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },],
	[ { label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.2" }, ],
);

########
test_case(
	"Avoid overwriting items not in managed (empty management set)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ managed => [] },
	[],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
);
test_case(
	"Avoid overwriting items not in managed (managing exact record)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ grouping => 'none', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }] },
  [ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" },
	],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
);

##########
test_case(
	"Avoid overwriting items not in managed (managing record with different data, group none)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	# we can always create new records in grouping = none, as target side does not implicitly own the record via the group
	{ grouping => 'none', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.3" }] },
	[ { diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" },
	],
);
test_case(
	"Avoid overwriting items not in managed (managing record with different data, group type)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ grouping => 'type', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.3" }] },
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" },
	],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
);
test_case(
	"Avoid overwriting items not in managed (managing record with different data)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ grouping => 'host', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.3" }] },
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" },
	],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
);

##########
test_case(
	"Avoid overwriting items not in managed (managing record with different type, group none)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ grouping => 'none', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'AAAA', data => "::1" }] },
	# we can always create new records in grouping = none, as target side does not implicitly own the record via the group
	[ { diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" } ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" },
	],
);

test_case(
	"Avoid overwriting items not in managed (managing record with different type, group type)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ grouping => 'type', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'AAAA', data => "::1" }] },
	[ ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
);
test_case(
	"Avoid overwriting items not in managed (managing record with different type, group host)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ grouping => 'host', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'AAAA', data => "::1" }] },
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" },
		{ diff => '+', label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" },
	],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
);

##########
test_case(
	"Avoid overwriting items not in managed (managing record with different label, group host)",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.5" }, ],
	{ grouping => 'host', managed => [{ label => 'test-b', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }] },
	[ ],
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'A', data => "127.0.0.1" }, ],
);

##########
test_case(
	"Different hosts do not interfer with each other - type mode",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'TXT', data => "testing" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'TXT', data => "testing" },
	],
	[ ],
	{ grouping => 'type', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'TXT', data => "testing" }] },
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'TXT', data => "testing" },],
	[ { label => 'test-b', ttl => 300, class => 'IN', type => 'TXT', data => "testing" }, ],
);
test_case(
	"Different hosts do not interfer with each other - host mode",
	[ { label => 'test-a', ttl => 300, class => 'IN', type => 'TXT', data => "testing" },
		{ label => 'test-b', ttl => 300, class => 'IN', type => 'TXT', data => "testing" },
	],
	[ ],
	{ grouping => 'host', managed => [{ label => 'test-a', ttl => 300, class => 'IN', type => 'TXT', data => "testing" }] },
	[ { diff => '-', label => 'test-a', ttl => 300, class => 'IN', type => 'TXT', data => "testing" },],
	[ { label => 'test-b', ttl => 300, class => 'IN', type => 'TXT', data => "testing" }, ],
);

##########
test_case(
	"Complex - managed, grouping=type",
	[ { label => 'test-a', ttl => 100, class => 'IN', type => 'A',   data => '127.0.0.5' },
		{ label => 'test-e', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
		{ label => 'test-f', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
	],
	[ { label => 'test-a', ttl => 600, class => 'IN', type => 'A',     data => '127.0.0.1'   },
		{ label => 'test-a', ttl => 600, class => 'IN', type => 'A',     data => '127.0.0.2'   },
		{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA',  data => '::1'         },
		{ label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },
	],
	{ grouping => 'type', managed => [ { label => 'test-e', ttl => 100, class => 'IN', type => 'TXT', data => "testing" } ] },
	[ { diff => '+', label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA',  data => '::1' },
		{ diff => '-', label => 'test-e', ttl => 100, class => 'IN', type => 'TXT',   data => 'testing' },
		{ diff => '+', label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },
	],
	[
		# test-a A left unchanged, since we do NOT manage it, and it already exists
		{ label => 'test-a', ttl => 100, class => 'IN', type => 'A',     data => '127.0.0.5'   },

		# test-a AAAA is created, since while we don't manage it, neither does the destination
		{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA',  data => '::1'         },

		# test-b is created, since while we don't manage it, neither does the destination
		{ label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },

		# test-e is managed by us, so we can delete it

		# test-f is NOT managed by us, so we can't delete it
		{ label => 'test-f', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
	],
);
test_case(
	"Complex - managed, grouping=host",
	[ { label => 'test-a', ttl => 100, class => 'IN', type => 'A',   data => '127.0.0.5' },
		{ label => 'test-e', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
		{ label => 'test-f', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
	],
	[ { label => 'test-a', ttl => 600, class => 'IN', type => 'A',     data => '127.0.0.1'   },
		{ label => 'test-a', ttl => 600, class => 'IN', type => 'A',     data => '127.0.0.2'   },
		{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA',  data => '::1'         },
		{ label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },
	],
	{ grouping => 'host', managed => [ { label => 'test-e', ttl => 100, class => 'IN', type => 'TXT', data => "testing" } ] },
  [ { diff => '-', label => 'test-e', ttl => 100, class => 'IN', type => 'TXT',   data => 'testing' },
		{ diff => '+', label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },
	],
	[
		# test-a A left unchanged, since we do NOT manage it, and it already exists
		{ label => 'test-a', ttl => 100, class => 'IN', type => 'A',     data => '127.0.0.5'   },

		# we can't create AAAA, since destination manages A and grouping is host

		# test-b is created, since while we don't manage it, neither does the destination
		{ label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },

		# test-e is managed by us, so we can delete it

		# test-f is NOT managed by us, so we can't delete it
		{ label => 'test-f', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
	],
);
test_case(
	"Complex - managed, grouping=host",
	[ { label => 'test-a', ttl => 100, class => 'IN', type => 'A',   data => '127.0.0.5' },
		{ label => 'test-e', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
		{ label => 'test-f', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
	],
	[ { label => 'test-a', ttl => 600, class => 'IN', type => 'A',     data => '127.0.0.1'   },
		{ label => 'test-a', ttl => 600, class => 'IN', type => 'A',     data => '127.0.0.2'   },
		{ label => 'test-a', ttl => 600, class => 'IN', type => 'AAAA',  data => '::1'         },
		{ label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },
	],
	{ grouping => 'host', noDelete => 1, managed => [ { label => 'test-e', ttl => 100, class => 'IN', type => 'TXT', data => "testing" } ] },
  [ { diff => '+', label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' } ],
	[
		# test-a A left unchanged, since we do NOT manage it, and it already exists
		{ label => 'test-a', ttl => 100, class => 'IN', type => 'A',     data => '127.0.0.5'   },

		# we can't create AAAA, since destination manages A and grouping is host

		# test-b is created, since while we don't manage it, neither does the destination
		{ label => 'test-b', ttl => 600, class => 'IN', type => 'CNAME', data => 'example.com' },

		# test-e is managed by us, but noDelete is set, and we have no replacement, hence it sticks around
		{ label => 'test-e', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },

		# test-f is NOT managed by us, so we can't delete it
		{ label => 'test-f', ttl => 100, class => 'IN', type => 'TXT', data => 'testing'   },
	],
);

done_testing();
