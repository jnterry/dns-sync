#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Pod;

# Check the Perldoc is valid for all scripts and modules
all_pod_files_ok(qw( lib ));

done_testing();