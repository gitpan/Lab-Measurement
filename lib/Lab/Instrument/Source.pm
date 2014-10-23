package Lab::Instrument::Source;
use strict;
use warnings;

our $VERSION = '3.30';

use Lab::Exception;
use Lab::Instrument;
use Lab::Measurement::KeyboardHandling qw(labkey_check);

use Time::HiRes qw(usleep gettimeofday);
use Clone qw(clone);

our @ISA=('Lab::Instrument');

our %fields = (
	supported_connections => [],

	parent_source => undef,
	child_sources => [],

	# supported config options
	device_settings => {
		gate_protect => undef,
		gp_max_units_per_second => undef,
		gp_max_units_per_step => undef,
		gp_max_step_per_second => undef,
		gp_min_units => undef,
		gp_max_units => undef,
		
		gp_equal_level => 0,
		fast_set => undef,
		autorange => 0, 	# silently ignored by instruments (or drivers) which don't support autorange
	},

	# Config hash passed to subchannel objects, or to $self->configure()
	default_device_settings => {},

	gpData => {},

	default_channel => 1,
	max_channels => 1,
	
	device_cache => { 
		level => undef,
		range => undef
		}
);

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	#
	# The following is for compatibility with the old syntax for subchannel object derivation.
	# If we get some Instrument::Source object along with an integer (channel number), use it to derive a subchannel and return this. 
	#
	# Is it an object at all? Is it a Source object? 
	if ( ref($_[0]) && UNIVERSAL::can($_[0],'can') && UNIVERSAL::isa($_[0],"Lab::Instrument::Source" ) ) {
		Lab::Exception::CorruptParameter->throw(
			error=>"Got a valid Source object, but an invalid channel number: $_[1]. Can't create subchannel, sorry."
		) if !defined $_[1] || $_[1] !~ /^[0-9]*$/;
		
		# Use the given parent object to derive a subchannel and return it
		my ($parent, $channel) = (shift, shift);
		my %conf=();
		if (ref $_[0] eq 'HASH') { %conf=%{;shift} }
		else { %conf=(@_) }
		return $parent->create_subsource(channel=>$channel, %conf);
	}
	# compatibility mode stop, continue normally (phew)
	my $self = $class->SUPER::new(@_);
	$self->${\(__PACKAGE__.'::_construct')}(__PACKAGE__);

	
	#
	# Parameter parsing
	#

	# checking if a valid default_device_settings hash was set by _construct.
	# if not, initialize it with $self->device_settings
	if(defined($self->default_device_settings())) {
		if( ref($self->default_device_settings()) !~ /HASH/ ) {
			Lab::Exception::CorruptParameter->throw( error=>'Given default config is not a hash.');
		}
		elsif( scalar keys %{$self->default_device_settings()} == 0 ) { # poor thing's empty
			$self->default_device_settings(clone($self->device_settings()));
		}
	}
	else {
		$self->default_device_settings(clone($self->device_settings()));
	}
	

	# check max channels
	if(defined($self->config('max_channels'))) {
		if( $self->config('max_channels') !~ /^[0-9]*$/ ) {
			Lab::Exception::CorruptParameter->throw( error=>'Parameter max_channels has to be an Integer');
		}
		else { $self->max_channels($self->config('max_channels')); }
	}

	# checking default channel number
	if( defined($self->default_channel()) && ( $self->default_channel() > $self->max_channels() || $self->default_channel() < 1 )) {
		Lab::Exception::CorruptParameter->throw( error=>'Default channel number is not within the available channels.');
	}

	if(defined($self->parent_source())) {
		if( !UNIVERSAL::isa($self->parent_source(),"Lab::Instrument::Source" ) ) {
			Lab::Exception::CorruptParameter->throw( error=>'Given parent_source object is not a valid Lab::Instrument::Source.');
		}
		# instead of maintaining our own one, check if a valid reference to the gpData from the parent object was given
		if( !defined($self->gpData()) || ! ref($self->gpData()) =~ /HASH/ )  {
			Lab::Exception::CorruptParameter->throw( error=>'Given gpData from parent_source is invalid.');
		}

		# shared connection *should* be okay, but keep this in mind
		$self->connection($self->parent_source()->connection());
	}
	else {
		# fill gpData
		for (my $i=1; $i<=$self->max_channels(); $i++) {
			$self->gpData()->{$i} = { LastSettimeMus => undef };
		}
	}

	return $self;
}

sub configure {
	my $self=shift;

	my $config=shift;
	if( ref($config) ne 'HASH' ) {
		Lab::Exception::CorruptParameter->throw( error=>'Given Configuration is not a hash.');
	}
	else {
		#		
		# first do the standard Instrument::configure() on $config
		#
		$self->SUPER::configure($config);
		
		#
		# now parse in default_device_settings
		#
		for my $conf_name (keys %{$self->device_settings()}) {
			$self->device_settings()->{$conf_name} = $self->default_device_settings()->{$conf_name} if exists($self->default_device_settings()->{$conf_name}) && !defined($self->device_settings($conf_name));
		}
	}
}



sub create_subsource { # create_subsource( channel => $channel_nr, more=>options );
	my $self=shift;
	my $class = ref($self);
	my $args=undef;
	if (ref $_[0] eq 'HASH') { $args=shift }
	else { $args={@_} }
	
	# we may be a subsource ourselfes, here - in this case, use our parent source instead of $self
	my $parent_to_be = $self->parent_source() || $self;
	
	Lab::Exception::CorruptParameter->throw(
		error=>'No channel number specified! You have to set the channel=>$number parameter.'
	) if (!exists($args->{'channel'}));
	Lab::Exception::CorruptParameter->throw(
		error=>"Invalid channel number: " . $args->{'channel'} . ". Integer expected."
	) if ( $args->{'channel'} !~ /^[0-9]*/ );
	
	my %default_device_settings = %{$parent_to_be->default_device_settings()};
	delete local $default_device_settings{'channel'};
	@default_device_settings{keys %{$args}} = values %{$args};	 
		
	no strict 'refs';
	my $subsource = $class->new ({ parent_source=>$parent_to_be, gpData=>$parent_to_be->gpData(), %default_device_settings });
	use strict;
	$parent_to_be->child_sources([ @{$parent_to_be->child_sources()}, $subsource ]);
	return $subsource;
}



sub set_level {
	my $self = shift;
	my ($target, $tail) = $self->_check_args( \@_, ['target'] );

	my $current_level = $self->get_level({read_mode => 'cache'});

	if ( $target == $current_level) {
		return $current_level;
	}

	if ( $self->device_settings()->{'gate_protect'} and $self->device_settings()->{'gp_max_units_per_step'} < abs($target - $current_level) ) {
		return $self->sweep_to_level($target,$tail);
	} else {
		return $self->_set_level($target,$tail);
	}
}



sub sweep_to_level {
	my $self = shift;
	my $target = shift;
	
	my($time, $args) = $self->parse_optional(@_);
	
	if(!defined $target || ref($target) eq 'HASH') {
		Lab::Exception::CorruptParameter->throw( error=>'No voltage given.');
	}
	
	# Check correct channel setup
	
	$self->_check_gate_protect();
	
	# Make sure stepsize is within gate_protect boundaries. 
	
	my $stepsize = $args->{stepsize} || $self->get_stepsize();
	my $upstep = $self->get_gp_max_units_per_step();
	$upstep = $stepsize if $stepsize < $upstep;
	
	if(!defined $stepsize){
		Lab::Exception::CorruptParameter->throw( 'No stepsize given. Please specify either stepsize or gp_max_units_per_step.');
	}
	
	my $apsec = $self->get_gp_max_units_per_second();
	
	my $spsec = $self->get_gp_max_step_per_second();
	
	my $current = $self->get_level( from_device => 1 )+ 0.;
	
	if( $target == $current ){
		return $target;
	}
	
	if( $self->device_settings()->{"gate_protect"} && $time ){
		$time = ( abs($target - $current)/$time < $apsec ) ? $time : abs($target-$current)/$apsec;
	}	
	elsif(!defined($time)){
		$time = (abs($target-$current)+0.)/$apsec;
	}
	
	# sweep to current

	if($self->can("_sweep_to_level")) {
		return $self->_sweep_to_level($target,$time,$args);
	}
	else{
			
		my $steptime = $time / ( abs($current - $target)/$upstep );
		
		unless( $current != $target){
			if( abs($target-$current) <= $upstep ){
				$self->_set_level($target, $args);
			}
			my $next = ($target - $current > 0) 
				? $self->_set_level( $target+$upstep, $args) 
				: $self->_set_level( $target-$upstep, $args);
			sleep($steptime);
			labkey_check();
			
			$current = $next;		
		}
		return $current;			
	}
	
}

sub is_me_channel{
	my $self = shift;
	my $channel = shift;
	if ($channel < 0) { 
		Lab::Exception::CorruptParameter->throw( 
		error=>'Channel must not be negative! Did you swap voltage and channel number?'); }
	if (int($channel) != $channel) {
		Lab::Exception::CorruptParameter->throw(
		error=>'Channel must be an integer! Did you swap voltage and channel number?'); }
	
}


# Check if all gate protect variables are set correctly. And if not, calculate the missing values. Error if
# volt_per_step
# or volt_per_sec / steps_per_sec is not given

sub _check_gate_protect{
	my $self =shift;
	my $mode = shift;
	
	if( $self->device_settings()->{'gate_protect'}){
	# Check if one of gp_max_units_per_second or gp_max_step_per_second is given
	
		my $apsec = $self->device_settings()->{gp_max_units_per_second};
		my $apstep = $self->device_settings()->{gp_max_units_per_step};
		my $spsec = $self->device_settings()->{gp_max_step_per_second};
	
		# Make sure the gate protect vars are correctly set and consistent	
			
		if( (!defined($apstep) || $apstep<=0 ) ) {
			Lab::Exception::CorruptParameter->throw(error=>"To use gate protection, you have to gp_max_units_per_step (now: $apstep) to a positive, non-zero value.");
		}
				
				
		if ( (defined($apsec) && $apsec > 0) && (!defined($spsec) || $spsec < 0 )){
			$spsec = $apsec/$apstep; 
		}
		elsif( (defined($spsec) && $spsec >0) && (!defined($apsec) || $apsec < 0 ) ){
			$apsec = $spsec*$apstep;
		}
		elsif( (! defined($apsec) || $apsec <= 0) && (!defined($spsec) || $spsec < 0 )){
			Lab::Exception::CorruptParameter->throw(
			"Please supply one of either gp_max_units_per_second or gp_max_steps_per_second.");
		}
		else{
			if($apsec <= $spsec*$apstep){
				$spsec = $apsec/$apstep;
			}
			else{
				$apsec	= $spsec*$apstep;
			}
		}
	
	$self->device_settings()->{gp_max_units_per_second} = $apsec;
	$self->device_settings()->{gp_max_units_per_step} = $apstep;
	$self->device_settings()->{gp_max_step_per_second} = $spsec;
	
	}
	
	
	
	
}


sub _set_level {
	my $self=shift;
	
	Lab::Exception::DriverError->throw( "The unimplemented method stub ".__PACKAGE__."::_set_level() has been called. I can't work like this.\n" );
}

sub get_level {
	my $self=shift;
	
	Lab::Exception::DriverError->throw( "The unimplemented method stub ".__PACKAGE__."::get_level() has been called. I can't work like this.\n" );
	
}


sub get_range() {
	my $self=shift;
	
	Lab::Exception::DriverError->throw( "The unimplemented method stub ".__PACKAGE__."::get_range() has been called. I can't work like this.\n" );
}

sub set_range() {
	my $self=shift;
	
	Lab::Exception::DriverError->throw( "The unimplemented method stub ".__PACKAGE__."::set_range() has been called. I can't work like this.\n" );
	
}





1;

=pod

=encoding utf-8

=head1 NAME

Lab::Instrument::Source - base class for voltage source instruments

=head1 SYNOPSIS

=head1 DESCRIPTION

This class implements a general voltage source, if necessary with several 
channels. It is meant to be inherited by instrument classes that implement
real voltage sources (e.g. the L<Lab::Instrument::Yokogawa7651> class).

The class provides a unified user interface for those voltage sources
to support the exchangeability of instruments.

Additionally, this class provides a safety mechanism called C<gate_protect>
to protect delicate samples. It includes automatic limitations of sweep rates,
voltage step sizes, minimal and maximal voltages.

There's no direct user application of this class.

=head1 CONSTRUCTOR

  $self=new Lab::Instrument::Source(\%config);

This constructor will only be used by instrument drivers that inherit this class,
not by the user. It accepts an additional configuration hash as parameter 
'default_device_settings'. The first hash contains the parameters used by 
default for this device and its subchannels, if any. The second hash can be used 
to override options for this instance while still using the defaults for derived 
objects. If \%config is missing, \%default_config is used.

The instrument driver (e.g. L<Lab::Instrument::Yokogawa7651>)
has e.g. a constructor like this:

  $yoko=new Lab::Instrument::Yokogawa7651({
	connection_type => 'LinuxGPIB',
	gpib_board      => $board,
	gpib_address    => $address,
	
	gate_protect    => $gp,
	[...]
  });

=head1 METHODS

=head2 configure

  $self->configure(\%config);

Supported configure options:

In general, all parameters which can be changed by access methods of the 
class/object can be used. In fact this is what happens, and the config hash 
given to configure() ist just a shorthand for this. The following are equivalent:

  $source->set_gate_protect(1);
  $source->set_gp_max_units_per_second(0.1);
  ...

  $source->configure({ gate_protect=>1, gp_max_units_per_second=>0.1, ...)

Options in detail:

=over 2

=item fast_set

This parameter controls the return value of the set_voltage function and can be set to 0 (off, 
default) or 1 (on). For fast_set off, set_voltage first requests the hardware to set the voltage, 
and then reads out the actually set voltage via get_voltage. The resulting number is returned. 
For fast_set on, set_voltage requests the hardware to set the voltage and returns without double-check
the requested value. This, albeit less secure, may speed up measurements a lot. 

=item gate_protect

Whether to use the automatic sweep speed limitation. Can be set to 0 (off) or 1 (on).
If it is turned on, the output voltage will not be changed faster than allowed
by the C<gp_max_units_per_second>, C<gp_max_units_per_step> and C<gp_max_step_per_second>
values. These three parameters overdefine the allowed speed. Only two
parameters are necessary. If all three are set, the smallest allowed sweep rate
is chosen.

Additionally the maximal and minimal output voltages are limited.

This mechanism is useful to protect sensible samples that are destroyed by
abrupt voltage changes. One example is gate electrodes on semiconductor electronics
samples, hence the name.

=item gp_max_units_per_second

How much the output voltage is allowed to change per second.

=item gp_max_units_per_step

How much the output voltage is allowed to change per step.

=item gp_max_step_per_second

How many steps are allowed per second.

=item gp_min_units

The smallest allowed output voltage.

=item gp_max_units

The largest allowed output voltage.

=item gp_equal_level

Voltages with a difference less than this value are considered equal.

=back

=head2 set_level

  $new_volt=$self->set_level($srclvl);

Sets the output to C<$srclvl> (in Volts or Ampere). If the configure option C<gate_protect> is set
to a true value, the safety mechanism takes into account the C<gp_max_units_per_step>,
C<gp_max_units_per_second> etc. settings, by employing the C<sweep_to_level> method.

Returns for C<fast_set> off the actually set output source level. This can be different 
from C<$srclvl>, due to the C<gp_max_units>, C<gp_min_units> settings. For C<fast_set> on,
C<set_level> returns always C<$level>.

For a multi-channel device, add the channel number as a parameter:

  $new_volt=$self->set_voltage($voltage,$channel);
  
=head2 _set_level($targetlvl)

Function Stub. Has to be overwritten by device driver.

The function should set the source level to $targetlvl on the device.
Should return the newly set source level.

=head2 get_level()

Function Stub. Has to be overwritten by device driver.

The function should return the source level from the device cache.
If called with the option C< from_device =E<gt> 1 >, the value should be fetched from the device.
Should return the current source level.


=head2 get_range()

Function Stub. Has to be overwritten by device driver.

The function should return the source range from the device cache.
If called with the option C< from_device =E<gt> 1 >, the value should be fetched from the device.
Should return the current source range.

=head2 set_range()

Function Stub. Has to be overwritten by device driver.

The function should set the source range on the device.
Should return the newly set source range.


=head2 sweep_to_level

  $new_volt=$self->sweep_to_level($srclvl);
  $new_volt=$self->sweep_to_level($srclvl,$channel);

This method sweeps the output source level to the desired value and only returns then.
If the specific Instrument implemented _sweep_to_level, this version is preferred.

Returns the actually set output source level. This can be different from C<$srclvl>, due
to the C<gp_max_units>, C<gp_min_units> settings.

=head2 get_level

  $new_volt=$self->get_level();
  $new_volt=$self->get_level($channel);

Returns the source level currently set.

=head2 create_subsource

  $bigc2 = $bigsource->create_subsource( channel=>2, gp_max_units_per_second=>0.01 );

  Returns a new instrument object with its default channel set to channel $channel_nr of the parent multi-channel source.
  The device_settings given to the parent at instantiation (or the default_device_settings if present) will be used as default
  values, which can be overwritten by parameters to create_subsource().  


=head1 CAVEATS/BUGS

Probably many.

=head1 SEE ALSO

=over 4

=item L<Time::HiRes>

Used internally for the sweep timing.

=item L<Lab::Instrument::KnickS252>

This class inherits the gate protection mechanism.

=item L<Lab::Instrument::Yokogawa7651>

This class inherits the gate protection mechanism.

=back

=head1 AUTHOR/COPYRIGHT

 Copyright 2004-2008 Daniel Schröer (<schroeer@cpan.org>)
           2009-2010 Daniel Schröer, Andreas K. Hüttel (L<http://www.akhuettel.de/>) and Daniela Taubert
           2011      Florian Olbrich and Andreas K. Hüttel

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=cut
