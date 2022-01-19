#!/usr/bin/env perl

use strict;
use warnings;

use Zonemod::Test::Cli qw(run $OUT_DIR);

use Test::More;
use Test::Deep qw(cmp_set);
use Test::File::Contents;

my ($out, $exit);

# ------------------------------------------------------
# - TEST: bad invocations                              -
# ------------------------------------------------------

($out, $exit) = run('create');
isnt($exit, 0, "Exit with bad status code when usage invalid (no args)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/record/i,               "Error message contains reference to 'record'");
like($out, qr/target/i,               "Error message contains reference to 'target'");

($out, $exit) = run("create 'test-a 100 IN A 127.0.0.1'");
isnt($exit, 0, "Exit with bad status code when usage invalid (single arg)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/target/i,               "Error message contains reference to 'target'");


# ------------------------------------------------------
# - TEST: simple test cases                            -
# ------------------------------------------------------

($out, $exit) = run("create 'test-a 100 IN A 127.0.0.1' ./t/data/output/testa.zone");
is($exit, 0, "Can create new zone and record");
file_contents_eq('./t/data/output/testa.zone', q{test-a	100	IN	A	127.0.0.1
});

($out, $exit) = run("create 'test-a 100 IN A 127.0.0.1' ./t/data/output/test.zone", {
	'test.zone' => q{test-b 100 IN A 127.0.0.1
}});
is($exit, 0, "Can create new record in existing zone");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
test-b	100	IN	A	127.0.0.1
});

# ensure dryrun prevents creation
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.1' ./t/data/output/test.zone --dryrun", {
	'test.zone' => q{test-b	100	IN	A	127.0.0.1
}});
is($exit, 0, "Can skip create with --dryrun flag");
file_contents_eq('./t/data/output/test.zone', q{test-b	100	IN	A	127.0.0.1
});

# behaves as no-op if record already exists
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.1' ./t/data/output/test.zone", {
	'test.zone' => q{test-a	100	IN	A	127.0.0.1
}});
is($exit, 0, "Can no-op if record already exists");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
});

# complains if record already exists and --strict is set
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.1' ./t/data/output/test.zone --strict", {
	'test.zone' => q{test-a	100	IN	A	127.0.0.1
}});
isnt($exit, 0, "Dies with non 0 if record already exists and strict is set");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
});

# same record with different ttl still counts as the record "existing" in strict mode
($out, $exit) = run("create 'test-a 300 IN A 127.0.0.1' ./t/data/output/test.zone --strict", {
	'test.zone' => q{test-a	100	IN	A	127.0.0.1
}});
isnt($exit, 0, "Dies with non 0 if conflicting record exists and strict is set");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
});

# updates ttl of existing record if it already exists with different value
($out, $exit) = run("create 'test-a 300 IN A 127.0.0.1' ./t/data/output/test.zone", {
	'test.zone' => q{test-a	100	IN	A	127.0.0.1
}});
is($exit, 0, "Updates TTL if exact records exist with different TTL");
file_contents_eq('./t/data/output/test.zone', q{test-a	300	IN	A	127.0.0.1
});

# ------------------------------------------------------
# - TEST: managed set (grouping=none)                  -
# ------------------------------------------------------

# Same type already managed by target
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping none", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Can create item in with managed set (same type exists, grouping=none)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});

# Same host already managed by target
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping none", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
},
	'managed.zone' => q{test-a	100	IN	AAAA	::1},
});
is($exit, 0, "Can create item in with managed set (same host exists, grouping=none)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});

# No match managed by target
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping none", {
	'test.zone' => q{test-b 100 IN AAAA ::1
},
	'managed.zone' => q{test-b	100	IN	AAAA	::1},
});
is($exit, 0, "Can create item in with managed set (no match exists, grouping=none)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
test-b	100	IN	AAAA	::1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.2
test-b	100	IN	AAAA	::1
});

# ------------------------------------------------------
# - TEST: managed set (grouping=type)                  -
# ------------------------------------------------------

# Same type already managed by target, and we manage it
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping type", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Can create item in with managed set (same type exists, we manage the type, grouping=type)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});

# Same type already managed by target, and we DONT manage it
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping type", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
},
	'managed.zone' => q{test-b	100	IN	A	127.0.0.1},
});
isnt($exit, 0, "Cannot create item in with managed set (same type exists, we don't manage the type, grouping=type)");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
});
file_contents_eq('./t/data/output/managed.zone', q{test-b	100	IN	A	127.0.0.1});

# Same host already managed by target, we manage the type
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping type", {
	'test.zone' => q{test-a 100 IN AAAA ::1
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Can create item in with managed set (same host exists, we manage the type, grouping=type)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});

# Same host already managed by target, we DONT manage the type
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping type", {
	'test.zone' => q{test-a 100 IN AAAA ::1
},
	'managed.zone' => q{test-a	100	IN	AAAA	::1},
});
is($exit, 0, "Can create item in with managed set (same host exists, we DONT manage the type, grouping=type)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});

# Same host already managed by target, we DONT manage the host
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping type", {
	'test.zone' => q{test-a 100 IN AAAA ::1
},
	'managed.zone' => q{test-b	100	IN	AAAA	::1},
});
is($exit, 0, "Can create item in with managed set (same host exists, we DONT manage the host, grouping=type)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.2
test-b	100	IN	AAAA	::1
});


# ------------------------------------------------------
# - TEST: managed set (grouping=host)                  -
# ------------------------------------------------------

# Same type already managed by target, and we manage it
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping host", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Can create item in with managed set (same type exists, we manage the type, grouping=host)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});

# Same type already managed by target, and we DONT manage it
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping host", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
},
	'managed.zone' => q{test-b	100	IN	A	127.0.0.1},
});
isnt($exit, 0, "Cannot create item in with managed set (same type exists, we don't manage the type, grouping=host)");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
});
file_contents_eq('./t/data/output/managed.zone', q{test-b	100	IN	A	127.0.0.1});

# Same host already managed by target, we manage the type
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping host", {
	'test.zone' => q{test-a 100 IN AAAA ::1
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Can create item in with managed set (same host exists, we manage the type, grouping=host)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.1
test-a	100	IN	A	127.0.0.2
});

# Same host already managed by target, we DONT manage the type
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping host", {
	'test.zone' => q{test-a 100 IN AAAA ::1
},
	'managed.zone' => q{test-a	100	IN	AAAA	::1},
});
is($exit, 0, "Can create item in with managed set (same host exists, we DONT manage the type, grouping=host)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.2
test-a	100	IN	AAAA	::1
});

# Same host already managed by target, we DONT manage the host
($out, $exit) = run("create 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping host", {
	'test.zone' => q{test-a 100 IN AAAA ::1
},
	'managed.zone' => q{test-b	100	IN	AAAA	::1},
});
isnt($exit, 0, "Cannot create item in with managed set (same host exists, we DONT manage the host, grouping=host)");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN AAAA ::1
});
file_contents_eq('./t/data/output/managed.zone', q{test-b	100	IN	AAAA	::1});


###############################

done_testing();
