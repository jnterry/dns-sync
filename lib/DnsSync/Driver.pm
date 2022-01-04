package DnsSync::Driver;

use strict;
use warnings;

use Module::Pluggable search_path => ['DnsSync::Driver'], sub_name => 'drivers', require => 1;

=head1 OVERVIEW C<DnsSync::Driver>

Utility functions for interacting with DNS drivers (IE: functionality
for interacting with actual DNS storage mechanisms)

=cut

use Exporter qw(import);
our @EXPORT_OK = qw(
  get_driver_for_uri
);

=head1 FUNCTIONS

=over 4

=item

Gets the driver able to handle specified $uri

$label is used to generate more descriptive error messages if no driver could be found

=cut
sub get_driver_for_uri {
	my ($uri, $label) = @_;

	return unless $uri;

	my @drivers = drivers();
  @drivers = grep { $_->can('can_handle')->($uri) } @drivers;
	my $count = @drivers;
	if($count == 0) {
		die "No DNS provider found for which can handle '$uri' (for $label)";
	} elsif ($count > 1) {
		die "$label '$uri' is ambigious and can be handled by multiple DNS drivers: " . join(',', @drivers);
	} else {
		return $drivers[0];
	}
}

=back

=cut

1;
