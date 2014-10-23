
package Lab::Instrument::TemperatureControl;
our $VERSION = '3.32';

use strict;

our @ISA=('Lab::Instrument');

our %fields = (
	supported_connections => [],

	# supported config options
	device_settings => {
		has_pidcontroller => undef,
		num_heaters => 0,
		num_sensors => 0,
		sample_sensor => undef,
		sample_heater => undef,
	},

	# Config hash passed to subchannel objects or $self->configure()
	default_device_settings => {},
);

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new(@_);
	$self->${\(__PACKAGE__.'::_construct')}(__PACKAGE__);

	print "Temperature control support is experimental. You have been warned.\n";
	return $self;
}


sub set_sample_sensor() {
	my $self=shift;
	my $channel=shift;
	
	# setze sample sensor if this is a valid channel number
};

sub get_temperature() {
	my $self=shift;
	my $channel=shift;
	
	# no channel -> use default channel
	# use method from hardware
	return $self->_get_temperature($channel);
};

sub get_sample_temperature() {
	my $self=shift;
	return $self->get_temperature($self->get_sample_sensor);
};


sub _get_temperature() {
	die "get_temperature not implemented for this instrument\n";
};



1;



=head1 NAME

Lab::Instrument::TemperatureControl - base class for temperature control instruments

  (c) 2011 Andreas K. Hüttel

=cut

