package Zonemod::Test::Cli;

use strict;
use warnings;

use File::Basename;
use File::Path qw(make_path rmtree);

use Exporter qw(import);
our @EXPORT_OK = qw(
	run $OUT_DIR
);

our $OUT_DIR = './t/data/output';

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

  my $out = qx[./bin/zonemod $cliArgs 2>&1];
	my $exit = ($? >> 8);
	return ( $out, $exit );
}

1;
