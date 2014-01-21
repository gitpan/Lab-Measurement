#!/usr/bin/perl

package Lab::Instrument::HP34420A;
our $VERSION = '3.30';

use strict;
use Scalar::Util qw(weaken);
use Lab::Instrument;
use Carp;
use Data::Dumper;
use Lab::Instrument::Multimeter;


our @ISA = ("Lab::Instrument::Multimeter");

our %fields = (
	supported_connections => [ 'GPIB' ],

	# default settings for the supported connections
	connection_settings => {
		gpib_board => 0,
		gpib_address => undef,
	},

	device_settings => { 
		pl_freq => 50,
	},
	
	device_cache =>{
		# TO DO: add range and resolution + get/setter
	}

);


sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new(@_);
	$self->${\(__PACKAGE__.'::_construct')}(__PACKAGE__);
	return $self;
}


# 
# first, all internal stuff
# 



#
# all methods that fill in general Multimeter methods
#




sub _display_clear {
    my $self=shift;
    $self->connection()->Write( command => "DISPlay:TEXT:CLEar");
}

sub _id {
    my $self=shift;
    return $self->query('*IDN?');
}

sub _get_value {
    my $self=shift;
    my $value=$self->query('READ?');
    chomp $value;
    return $value;
}

sub _device_init{
	my $self = shift;
	
	
	
}

#
# all methods that are called directly
#


sub get_resistance {
    my $self=shift;
    my ($range,$resolution)=@_;
    
    $range="DEF" unless (defined $range);
    $resolution="DEF" unless (defined $resolution);
    
	my $cmd=sprintf("MEASure:SCALar:RESIStance? %s,%s",$range,$resolution);
	my $value = $self->query($cmd);
    return $value;
}


sub get_4wresistance {
    my $self=shift;
    my ($range,$resolution)=@_;
    
    $range="DEF" unless (defined $range);
    $resolution="DEF" unless (defined $resolution);
    
	my $cmd=sprintf("MEASure:SCALar:FRESIStance? %s,%s",$range,$resolution);
	my $value = $self->query($cmd);
    return $value;
}


sub get_voltage_dc {
    my $self=shift;
    my ($range,$resolution)=@_;
    
    $range="DEF" unless (defined $range);
    $resolution="DEF" unless (defined $resolution);
    
    my $cmd=sprintf("MEASure:VOLTage:DC? %s,%s",$range,$resolution);
    my $value = $self->query($cmd);
    return $value;
}


sub get_voltage_ac {
    my $self=shift;
    my ($range,$resolution)=@_;
    
    $range="DEF" unless (defined $range);
    $resolution="DEF" unless (defined $resolution);
    
    my $cmd=sprintf("MEASure:VOLTage:AC? %s,%s",$range,$resolution);
    my $value = $self->query($cmd);
    return $value;
}


sub get_current_dc {
    my $self=shift;
    my ($range,$resolution)=@_;
    
    $range="DEF" unless (defined $range);
    $resolution="DEF" unless (defined $resolution);
    
    my $cmd=sprintf("MEASure:CURRent:DC? %s,%s",$range,$resolution);
    my $value = $self->query($cmd);
    return $value;
}


sub get_current_ac {
    my $self=shift;
    my ($range,$resolution)=@_;
    
    $range="DEF" unless (defined $range);
    $resolution="DEF" unless (defined $resolution);
    
    my $cmd=sprintf("MEASure:CURRent:AC? %s,%s",$range,$resolution);
    my $value = $self->query($cmd);
    return $value;
}

sub beep {
    my $self=shift;
    $self->write("SYSTem:BEEPer");
}


sub get_error {
	my $self=shift;
	my $error = $self->query( "SYST:ERR?" );
	if($error !~ /\+0,/) {
		if ($error =~ /^(\+[0-9]*)\,\"?(.*)\"?$/) {
			return ($1, $2); # ($code, $message)
		}
		else {
			Lab::Exception::DeviceError->throw(
				error => "Reading the error status of the device failed in Instrument::HP34401A::get_error(). Something's going wrong here.\n",
			)	
		}
	}
	else {
		return undef;
	}
}

sub get_status{
	my $self = shift;
	
	# This is to be implemented with code that queries the status bit

	my $request = shift;
	my $status = {};
	
	($status->{NOT_USED1}, $status->{NOT_USED2}, $status->{NOT_USED3}, $status->{CORR_DATA}, $status->{MSG_AVAIL}, $status->{EVNT}, $status->{SRQ}, $status->{NOT_USED4} ) = $self->connection()->serial_poll();
	return $status->{$request} if defined $request;
	return $status;
}


sub set_display_state {
    my $self=shift;
    my $value=shift;
	
    if($value==1 || $value =~ /on/i ) {
    	$self->write("DISP ON", @_);
    }
    elsif($value==0 || $value =~ /off/i ) {
    	$self->write("DISP OFF", @_);
    }
    else {
    	Lab::Exception::CorruptParameter->throw( "set_display_state(): Illegal parameter.\n" );
    }
}

sub set_display_text {
    my $self=shift;
    my $text=shift;
    if( $text !~ /^[A-Za-z0-9\ \!\#\$\%\&\'\(\)\^\\\/\@\;\:\[\]\,\.\+\-\=\<\>\?\_]*$/ ) { # characters allowed by the 3458A
    	Lab::Exception::CorruptParameter->throw( "set_display_text(): Illegal characters in given text.\n" );
    }
    $self->write("DISP:TEXT $text");
    
    $self->check_errors();
}




sub reset {
    my $self=shift;
    $self->connection()->Write( command => "*CLS");
    $self->connection()->Write( command => "*RST");
#	$self->connection()->InstrumentClear($self->instrument_handle());
}


sub wait_done{
	my $self = shift;
	
	# wait until currently running program is finished.
	
	while (! $self->get_status()->{"EVNT"}){
    	sleep 1;
    }
	
	
}

sub autozero {
	my $self=shift;
	my $enable=shift;
	my $az_status=undef;
	my $command = "";
	
	if(!defined $enable) {
		# read autozero setting
		$command = "ZERO:AUTO?";
		$az_status=$self->query( $command, error_check => 1 );
	}
	else {
		if ($enable =~ /^ONCE$/i) {
			$command = "ZERO:AUTO ONCE";
		}
		elsif($enable =~ /^(ON|1)$/i) {
			$command = "ZERO:AUTO ONCE";
		}
		elsif($enable =~ /^(OFF|0)$/i) {
			$command = "ZERO:AUTO OFF";
		}
		else {
			Lab::Exception::CorruptParameter->throw( error => "HP34401A::autozero() can be set to 'ON'/1, 'OFF'/0 or 'ONCE'. Received '${enable}'\n" );
		}
		$self->write( $command, error_check => 1 );
	}	
	
	return $az_status;
}

sub _configure_voltage_dc {
	my $self=shift;
    my $range=shift; # in V, or "AUTO", "MIN", "MAX"
    my $tint=shift;  # integration time in sec, "DEFAULT", "MIN", "MAX"
    my $res_cmd=shift;
    
    if($range eq 'AUTO' || !defined($range)) {
    	$range='DEF';
    }
    elsif($range =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) {
	    #$range = sprintf("%e",abs($range));
    }
    elsif($range !~ /^(MIN|MAX)$/) {
    	Lab::Exception::CorruptParameter->throw( error => "Range has to be set to a decimal value or 'AUTO', 'MIN' or 'MAX' in HP34401A::configure_voltage_dc()\n" );	
    }
    
    if($tint =~ /^([+]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) {
    	# Convert seconds to PLC (power line cycles)
    	$tint*=$self->pl_freq(); 
    }
    elsif($tint !~ /^(MIN|MAX|DEFAULT)$/) {
		Lab::Exception::CorruptParameter->throw( error => "Integration time has to be set to a positive value or 'AUTO', 'MIN' or 'MAX' in HP34401A::configure_voltage_dc()\n" )    	
    }
    
    if(!defined($res_cmd)) {
    	$res_cmd='';
    }
 
    
    
	# do it
	$self->write( "CONF:VOLT:DC ${range} ${res_cmd}", error_check => 1 );
	$self->write( "VOLT:DC:NPLC ${tint}", error_check => 1 ) if $res_cmd eq ''; # integration time implicitly set through resolution
}

sub configure_voltage_dc_trigger {
	my $self=shift;
    my $tint=shift;  # integration time in sec, Default is 10PLC*pl_freq(), "MIN" = 0.02PLC , "MAX" = 200PLC
    my $range=shift; # in V, or "DEF"(Default), "MIN", "MAX"
    my $count=shift; # Measurment count, Default = 1
    my $delay=shift; # in seconds, Default = 'MIN'
    my $res_cmd = shift; # Resolution. Decimal (not number of digits!). NOT VALID FOR AC MEASUREMENT
    
    ### Check the parameters for errors 
    
    $count=1 if !defined($count);
    Lab::Exception::CorruptParameter->throw( error => "Sample count has to be an integer between 1 and 512\n" )
    	if($count !~ /^[0-9]*$/ || $count < 1 || $count > 512); 

	$delay=0 if !defined($delay);
    Lab::Exception::CorruptParameter->throw( error => "Trigger delay has to be a positive decimal value\n" )
    	if($count !~ /^([+]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/);
    	
    if(!defined($tint)){
    	$tint = 10;
    }	
    elsif($tint =~ /^([+]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) {
    	# Convert seconds to PLC (power line cycles)
    	$tint*=$self->pl_freq(); 
    	if( $tint > 200 || $tint < 0.02){
    		Lab::Exception::CorruptParameter->throw( error => "Integration time out of bounds (int. time = $tint) in HP34401A::configure_voltage_dc()\n" )
    	}
    }
    elsif($tint !~ /^(MIN|MAX)$/ ) {
		Lab::Exception::CorruptParameter->throw( error => "Integration time has to be set to a positive value, 'MIN' or 'MAX' in HP34401A::configure_voltage_dc()\n" )    	
    }
    
    if(!defined($range)) {
    	$range='DEF';
    }
    elsif($range =~ /^([+-]?)(?=\d|\.\d)\d*(\.\d*)?([Ee]([+-]?\d+))?$/) {
	    $range = sprintf("%e",abs($range));
    }
    elsif($range !~ /^(MIN|MAX)$/) {
    	Lab::Exception::CorruptParameter->throw( error => "Range has to be set to a decimal value or 'AUTO', 'MIN' or 'MAX' in HP34401A::configure_voltage_dc()\n" );	
    }
        
    if(!defined($res_cmd)) {
    	$res_cmd='';
    }

    $self->write( "CONF:VOLT:DC ${range} ${res_cmd}", error_check => 1 );
	$self->write( "VOLT:DC:NPLC ${tint}", error_check => 1 ) if $res_cmd eq ''; # integration time implicitly set if resolution given
    
    $self->write("*ESE 1");
    $self->write("*CLS");
        
    $self->write( "TRIG:SOURce BUS" );
    $self->write( "SAMPle:COUNt $count");
    $self->write( "TRIG:DELay $delay");

    
}

sub trigger{
	my $self=shift;
	$self->write( "INIT" );

    $self->write( "*TRG");
    $self->write("*OPC");
    	
}

sub fetch{
	my $self = shift;
	
	my $value = $self->query( "FETCh?");

    chomp $value;

    my @valarray = split(",",$value);

    return @valarray;
}
	

sub trigger_read {
    my $self=shift;
	my $args=undef;
	if (ref $_[0] eq 'HASH') { $args=shift }
	else { $args={@_} }
	
	
	
	#$args->{'timeout'} = $args->{'timeout'} || $self->timeout();

    $self->write( "INIT" );
    $self->write( "*TRG");
    my $value = $self->query( "FETCh?", $args);
	


    chomp $value;

    my @valarray = split(",",$value);

    return @valarray;
}


sub scroll_message {
    use Time::HiRes (qw/usleep/);
    my $self=shift;
    my $message=shift || "            Lab::Measurement - designed to make measuring fun!            ";
    for my $i (0..(length($message)-12)) {
        $self->display_text(sprintf "%12.12s",substr($message,$i));
        usleep(100000);
    }
    $self->display_clear();
}

1;



=pod

=encoding utf-8

=head1 NAME

Lab::Instrument::HP34420A - HP/Agilent 34420A digital multimeter

=head1 SYNOPSIS

  use Lab::Instrument::HP34420A;
  
  my $Agi = new Lab::Instrument::HP34420A({
    connection => new Lab::Connection::GPIB(
		gpib_board => 0,
		gpib_address => 14,
	),
  }


=head1 DESCRIPTION

The Lab::Instrument::HP34420A class implements an interface to the 34420A digital 
multimeter by Agilent (formerly HP). This module is in big parts equal to the 
34410A and 34411A multimeter drivers.

=head1 CONSTRUCTOR

    my $Agi=new(\%options);

=head1 METHODS

=head2 fetch

	$hp->fetch();

Fetches the instrument buffer. Returns an array of values.

=head2 autozero

    $hp->autozero($setting);

$setting can be 1/'ON', 0/'OFF' or 'ONCE'.

When set to "ON", the device takes a zero reading after every measurement.
"ONCE" perform one zero reading and disables the automatic zero reading.
"OFF" does... you get it.

=head2 configure_voltage_dc

    $hp->configure_voltage_dc($range, $integration_time);

Configures all the details of the device's DC voltage measurement function.

$range is a positive numeric value (the largest expected value to be measured) or one of 'MIN', 'MAX', 'AUTO'.
It specifies the largest value to be measured. You can set any value, but the HP/Agilent 34401A effectively uses
one of the values 0.1, 1, 10, 100 and 1000V.

$integration_time is the integration time in seconds. This implicitly sets the provided resolution.


=head2 pl_freq
Parameter: pl_freq

	$hp->pl_freq($new_freq);
	$npl_freq = $hp->pl_freq();
	
Get/set the power line frequency at your location (50 Hz for most countries, which is the default). This
is the basis of the integration time setting (which is internally specified as a count of power
line cycles, or PLCs). The integration time will be set incorrectly if this parameter is set incorrectly.

=head2 set_display_text

    $Agi->display_text($text);
    print $Agi->display_text();

Display a message on the front panel. The multimeter will display up to 12
characters in a message; any additional characters are truncated.
Without parameter the displayed message is returned.
Inherited from L<Lab::Instrument::Multimeter>

=head2 set_display_state

    $Agi->set_display_state($state);

Turn the front-panel display on ($state = "ON") or off ($state = "OFF").


=head2 get_resistance

    $resistance=$Agi->get_resistance($range,$resolution);

Preset and measure resistance with specified range and resolution.

=head2 get_voltage_dc

    $datum=$Agi->get_voltage_dc($range,$resolution);

Preset and make a dc voltage measurement with the specified range
and resolution.

=over 4

=item $range

Range is given in terms of volts and can be C<[0.1|1|10|100|1000|MIN|MAX|DEF]>. C<DEF> is default.

=item $resolution

Resolution is given in terms of C<$range> or C<[MIN|MAX|DEF]>.
C<$resolution=0.0001> means 4 1/2 digits for example.
The best resolution is 100nV: C<$range=0.1>; C<$resolution=0.000001>.

=back

=head2 get_voltage_ac

    $datum=$Agi->get_voltage_ac($range,$resolution);

Preset and make an ac voltage measurement with the specified range
and resolution. For ac measurements, resolution is actually fixed
at 6 1/2 digits. The resolution parameter only affects the front-panel display.

=head2 get_current_dc

    $datum=$Agi->get_current_dc($range,$resolution);

Preset and make a dc current measurement with the specified range
and resolution.

=head2 get_current_ac

    $datum=$Agi->get_current_ac($range,$resolution);

Preset and make an ac current measurement with the specified range
and resolution. For ac measurements, resolution is actually fixed
at 6 1/2 digits. The resolution parameter only affects the front-panel display.

=head2 configure_voltage_dc_trigger

	$device->configure_voltage_dc_trigger($intt, $range, $count, $delay, $resolution)
	
Configure the multimeter for a triggered reading. 

=over 4

=item $intt

The integration time in seconds. You can also set "MIN" or "MAX". This value is overwritten if the resolution is specified.

=item $range

The range for the measurment. 

=item $count

The number of measurements which are performed after one single trigger impulse.

=item $delay 

The delay between the C<$count> measurements (the integration time is not included).

=item $resolution

The resolution for the measurement. If given, this overwrites the C<$intt> parameter.

=back

=head2 trigger_read

	$data = $device->trigger_read()
	
Sends a trigger signal and fetches the value(s) from the multimeter.

=head2 trigger

	$device->trigger()
	
Sends a trigger signal to the device.

=head2 fetch

	$data = $device->fetch()

Fetches the data which is currently in the output buffer of the device.

=head2 beep

    $Agi->beep();

Issue a single beep immediately.

=head2 get_error

    ($err_num,$err_msg)=$Agi->get_error();

Query the multimeter's error queue. Up to 20 errors can be stored in the
queue. Errors are retrieved in first-in-first out (FIFO) order.

=head2 reset

    $Agi->reset();

Reset the multimeter to its power-on configuration.

=head1 CAVEATS/BUGS

probably many

=head1 SEE ALSO

=over 4

=item * L<Lab::Instrument>

=item * L<Lab::Instrument::Multimeter>

=item * L<Lab::Instrument::HP3458A>

=back

=head1 AUTHOR/COPYRIGHT

  Copyright 2004-2006 Daniel Schröer (<schroeer@cpan.org>), 2009-2010 Daniela Taubert, 
            2011 Florian Olbrich, Andreas Hüttel

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut
