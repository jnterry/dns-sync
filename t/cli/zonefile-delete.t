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

($out, $exit) = run('delete');
isnt($exit, 0, "Exit with bad status code when usage invalid (no args)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/record/i,               "Error message contains reference to 'record'");
like($out, qr/target/i,               "Error message contains reference to 'target'");

($out, $exit) = run("delete 'test-a 100 IN A 127.0.0.1'");
isnt($exit, 0, "Exit with bad status code when usage invalid (single arg)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/target/i,               "Error message contains reference to 'target'");

($out, $exit) = run("delete 'test-a 100 IN A 127.0.0.1' ./t/data/output/testa.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
},
});
isnt($exit, 0, "Exit with bad status code when usage invalid (non-existent file)");
like($out, qr/No such file or directory/i, "Error message contains reference to missing file");
like($out, qr/testa\.zone/i,               "Error message contains reference to missing file name");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
}, "File unchanged since we used wrong path in cli args");

($out, $exit) = run("delete 'test-a 127.0.0.1' ./t/data/output/testa.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
},
});
isnt($exit, 0, "Exit with bad status code when record is unparseable");
like($out, qr/parse/i, "Error message contains reference to 'parse'");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
});


# ------------------------------------------------------
# - TEST: simple test cases                            -
# ------------------------------------------------------

# delete single record works
($out, $exit) = run("delete 'test-a 100 IN A 127.0.0.1' ./t/data/output/test.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
},
});
is($exit, 0, "Exit success");
file_contents_eq('./t/data/output/test.zone', q{test-b	100	IN	A	127.0.0.1
});

# ensure dryrun prevents delete
($out, $exit) = run("delete 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --dryrun", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
});
is($exit, 0, "Exit success with dryrun");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
});

# delete with unspecified TTL
($out, $exit) = run("delete 'test-a IN A 127.0.0.1' ./t/data/output/test.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
});
is($exit, 0, "Exit success when delting single record (with undef ttl)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
});

# delete with unspecified TTL and Class
($out, $exit) = run("delete 'test-a A 127.0.0.1' ./t/data/output/test.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
});
is($exit, 0, "Exit success when delting single record (with undef ttl and class)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
});

# ensure exit success (but noop) if recod does not exist
($out, $exit) = run("delete 'test-c 100 IN A 127.0.0.1' ./t/data/output/test.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
},
});
is($exit, 0, "Exit success even when record to delete does not exist");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
});

# ensure --strict complains
($out, $exit) = run("delete 'test-a 100 IN A 127.0.0.2' ./t/data/output/test.zone --strict", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
},
});
isnt($exit, 0, "Exit non-zero when record to delete does not exist and strict is set");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
test-b 100 IN A 127.0.0.1
});

# ------------------------------------------------------
# - TEST: managed                                      -
# ------------------------------------------------------

# default grouping, can delete any with same label/type
# don't remove from managed unless deleting exact record
($out, $exit) = run("delete 'test-a IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Exit success with managed set");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.1
});

# as above, do delete from managed with the exact record
# this should clear out the managed set too
($out, $exit) = run("delete 'test-a IN A 127.0.0.1' ./t/data/output/test.zone --managed ./t/data/output/managed.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Exit success with managed set");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{});

# default grouping, cannot delete with different type
($out, $exit) = run("delete 'test-a IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
	'managed.zone' => q{test-a	100	IN	AAAA	::1},
});
isnt($exit, 0, "Exit with bad status code when item to delete is not in managed set");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	AAAA	::1});

# host grouping - CAN delete with different type
($out, $exit) = run("delete 'test-a IN A 127.0.0.2' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping host", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
	'managed.zone' => q{test-a	100	IN	AAAA	::1},
});
is($exit, 0, "Exit with status code 0 when item to delete is in managed set (grouping=host)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.1
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	AAAA	::1
});

# none grouping, cannot delete unless explicitly listed
($out, $exit) = run("delete 'test-a IN A 127.0.0.1' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping none", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.2},
});
isnt($exit, 0, "Exit with bad status code when item to delete is not in managed set");
file_contents_eq('./t/data/output/test.zone', q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{test-a	100	IN	A	127.0.0.2});

# none groputing, can delete with explictly listed
($out, $exit) = run("delete 'test-a IN A 127.0.0.1' ./t/data/output/test.zone --managed ./t/data/output/managed.zone --grouping none", {
	'test.zone' => q{test-a 100 IN A 127.0.0.1
test-a 100 IN A 127.0.0.2
},
	'managed.zone' => q{test-a	100	IN	A	127.0.0.1},
});
is($exit, 0, "Exit success with managed set (grouping=none)");
file_contents_eq('./t/data/output/test.zone', q{test-a	100	IN	A	127.0.0.2
});
file_contents_eq('./t/data/output/managed.zone', q{});


done_testing();
