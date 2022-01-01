#!/usr/bin/env perl

use strict;
use warnings;

use Test::Perl::Critic (-profile => 't/criticrc');

# Run Perl::Critic over all library files
all_critic_ok(qw( lib ));