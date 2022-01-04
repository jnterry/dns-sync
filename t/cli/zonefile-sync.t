#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep qw(cmp_set);
use Test::File::Contents;
use File::Basename;
use File::Path qw(make_path rmtree);

use Data::Dumper;

my ($out, $exit);

my $OUT_DIR = './t/data/output';

sub run {
	my ($cliArgs, $files) = @_;

	rmtree $OUT_DIR;
	make_path($OUT_DIR);
	for my $name (keys %$files) {
		my $filePath =  "${OUT_DIR}/${name}";
		my $parent = dirname($filePath);
		make_path($parent);

		if(ref $files->{$name} eq "ARRAY") {
			mkdir $filePath;
		} else {
			open(my $fh, '>', $filePath) or die $!;
			print $fh $files->{$name};
			close $fh;
		}
	}

  my $out = qx[./bin/dns-sync sync $cliArgs 2>&1];
	my $exit = ($? >> 8);
	return ( $out, $exit );
}

# ------------------------------------------------------
# - TEST: bad invocations                              -
# ------------------------------------------------------

($out, $exit) = run('');
isnt($exit, 0, "Exit with bad status code when usage invalid (no args)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/source/i,               "Error message contains reference to 'source'");
like($out, qr/target/i,               "Error message contains reference to 'target'");

($out, $exit) = run('./test');
isnt($exit, 0, "Exit with bad status code when usage invalid (single arg)");
like($out, qr/positional arguments/i, "Error message contains reference to 'positional arguments'");
like($out, qr/target/i,               "Error message contains reference to 'target'");

($out, $exit) = run('bad-protocol://test ./out.zone');
isnt($exit, 0, "Exit with bad status code when usage invalid (unparseable arg)");
like($out, qr/no.+provider/i, "Error message contains reference to bad 'provider'");
like($out, qr/bad-protocol/i, "Error message contains reference to the bad argument");
like($out, qr/source/i,       "Error message specifies which argument was invalid");

($out, $exit) = run('./t/data/in-dir bad-protocol://test');
isnt($exit, 0, "Exit with bad status code when usage invalid (unparseable arg)");
like($out, qr/no.+provider/i, "Error message contains reference to bad 'provider'");
like($out, qr/bad-protocol/i, "Error message contains reference to the bad argument");
like($out, qr/target/i,       "Error message specifies which argument was invalid");

($out, $exit) = run('./t/data/in-dir ./out.zone --hello');
isnt($exit, 0, "Exit with bad status code when invalid cli switch is specified");
like($out, qr/unknown option/i, "Error message contains reference to 'unknown option'");
like($out, qr/hello/i,          "Error message contains the invalid switch name");

# ------------------------------------------------------
# - TEST: --delete and --managed behavior              -
# ------------------------------------------------------

($out, $exit) = run('./t/data/input/dir ./t/data/output/out.zone');
is($exit, 0, "Sync dir to new file works");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
}, "Sync to new file works as expected");

($out, $exit) = run('./t/data/input/dir ./t/data/output/out.zone', {
	'out.zone' => q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
}});
is($exit, 0, "Sync dir to existing file");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
test-e	100	IN	TXT	"testing"
}, "Sync to existing file merges records with existing items");

($out, $exit) = run('./t/data/input/dir ./t/data/output/out.zone --delete', {
	'out.zone' => q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
}});
is($exit, 0, "Sync dir to existing file (with delete)");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
}, "Sync --delete will clear existing items not in source");

($out, $exit) = run('./t/data/input/dir ./t/data/output/out.zone --delete --managed ./t/data/output/managed.zone', {
	'out.zone' => q{
; this comment will get nuked... as will the next record...
test-a	100	IN	A	127.0.0.5
test-e	100	IN	TXT	"testing"
test-f	100	IN	TXT	"testing"
},
	'managed.zone' => q{
test-e	100	IN	TXT	"testing"
}});
is($exit, 0, "Sync dir to existing file (with delete and managed)");
file_contents_eq('./t/data/output/out.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-b	600	IN	CNAME	example.com
test-c	600	IN	TXT	"Test Text"
test-f	100	IN	TXT	"testing"
}, "Sync --delete will NOT clear items that are not in --managed set");

# ------------------------------------------------------
# - TEST: sync to dir                                  -
# ------------------------------------------------------
($out, $exit) = run('./t/data/input/dir ./t/data/output/out/');
is($exit, 0, "Sync to non-existant dir will create it");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
}, 'Created test-a.zone');
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});

($out, $exit) = run('./t/data/input/dir ./t/data/output/out/');
is($exit, 0, "Sync to non-existant dir will create it");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
});
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});

($out, $exit) = run('./t/data/input/dir ./t/data/output/out', { out => [] });
is($exit, 0, "Syncing to dir without trailing slash will act as dir sync rather than file sync");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
});
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});

($out, $exit) = run('./t/data/input/dir ./t/data/output/out/', {
	'out/test.txt' => 'hello world',
	'out/test-a.zone' => q{test-a	100	IN	TXT	"existing"
},
	'out/test-z.zone' => q{test-z	100	IN	A	127.0.0.255
},
});
is($exit, 0, "Existing non-zone files are ignored, existing zone files are merged");
file_contents_eq('./t/data/output/out/test-a.zone', q{test-a	600	IN	A	127.0.0.1
test-a	600	IN	A	127.0.0.2
test-a	600	IN	AAAA	::1
test-a	100	IN	TXT	"existing"
});
file_contents_eq('./t/data/output/out/test-b.zone', q{test-b	600	IN	CNAME	example.com
});
file_contents_eq('./t/data/output/out/test-c.zone', q{test-c	600	IN	TXT	"Test Text"
});
file_contents_eq('./t/data/output/out/test-z.zone', q{test-z	100	IN	A	127.0.0.255
});
file_contents_eq('./t/data/output/out/test.txt', q{hello world});


done_testing();
