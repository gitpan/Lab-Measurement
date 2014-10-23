#!/usr/bin/perl -w

package Lab::Instrument;
our $VERSION = '2.92';

use strict;

use Lab::Exception;
use Lab::Connection;
use Carp qw(cluck croak);
use Data::Dumper;
use Clone qw(clone);

use Time::HiRes qw (usleep sleep);
use POSIX; # added for int() function

# setup this variable to add inherited functions later
our @ISA = ();

our $AUTOLOAD;


our %fields = (

	device_name => undef,
	device_comment => undef,

	ins_debug => 0, # do we need additional output?

	connection => undef,
	supported_connections => [ 'ALL' ],
	# for connection default settings/user supplied settings. see accessor method.
	connection_settings => {
		connection_type => 'LinuxGPIB',	
	},

	# default device settings/user supplied settings. see accessor method.
	device_settings => {
		wait_status => 10, # usec
		wait_query => 100, # usec
		query_length => 300, # bytes
		query_long_length => 10240, # bytes
	},

	config => {},
);



sub new { 
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $config = undef;
	if (ref $_[0] eq 'HASH') { $config=shift }
	else { $config={@_} }

	my $self={};
	bless ($self, $class);

	$self->_construct(__PACKAGE__, \%fields);

	$self->config($config);

	# $self->configure($self->config()); # This calls Lab::Instrument::Source::configure() !!! work arount, rethink
	# _setconnection after providing $config - needed for direct instantiation of Lab::Instrument
	if( $class eq __PACKAGE__ ) {
		warn "ins configure\n";
		$self->configure($self->config());
		$self->_setconnection();
	}

	# digest parameters
	$self->device_name($self->config('device_name')) if defined $self->config('device_name');
	$self->device_comment($self->config('device_comment')) if defined $self->config('device_comment');

	#warn "Instantiated instrument\n";

	return $self;
}



#
# Call this in inheriting class's constructors to conveniently initialize the %fields object data.
#
sub _construct {	# _construct(__PACKAGE__);
	(my $self, my $package, my $fields) = (shift, shift, shift);
	my $class = ref($self);

	foreach my $element (keys %{$fields}) {
		# handle special subarrays
		if( $element eq 'device_settings' ) {
			# don't overwrite filled hash from ancestor
			# warn "Setting device settings:\n" . Dumper(clone($fields->{device_settings})) . "\n\n";
			$self->{device_settings} = clone($fields->{device_settings}) if ! exists($self->{device_settings});
			for my $s_key ( keys %{$fields->{'device_settings'}} ) {
				# warn "Setze Feld " . $s_key . "\n";
				$self->{$element}->{$s_key} = $fields->{device_settings}->{$s_key};
			}
			# warn "Jetzt schauts so aus:\n" . Dumper($self->{$element}) . "\n";
		}
		elsif( $element eq 'connection_settings' ) {
			# don't overwrite filled hash from ancestor
			$self->{$element} = clone($fields->{$element}) if ! exists($self->{$element});
			for my $s_key ( keys %{$fields->{connection_settings}} ) {
				$self->{$element}->{$s_key} = $fields->{connection_settings}->{$s_key};
			}
		}
		else {
			# handle the normal fields - can also be hash refs etc, so use clone to get a deep copy
			$self->{$element} = clone($fields->{$element});
		}
		$self->{_permitted}->{$element} = $fields->{$element};
	}
	# @{$self}{keys %{$fields}} = values %{$fields};

	#
	# Check the connection data OR the connection object in $self->config(), but only if 
	# _construct() has been called from the instantiated class (and not from somewhere up the heritance hierarchy)
	# That's because child classes can add new entrys to $self->supported_connections(), so delay checking to the top class.
	#
	if( $class eq $package && $class ne 'Lab::Instrument' ) {
		# warn "Doing the configure\n";
		$self->configure($self->config());
		$self->_setconnection();
	}
}

#
# Fill $self->device_settings() from config parameters
#
sub configure {
	my $self=shift;
	my $config=shift;

	if( ref($config) ne 'HASH' ) {
		Lab::Exception::CorruptParameter->throw( error=>'Given Configuration is not a hash.' . Lab::Exception::Base::Appendix());
	}
	else {
		$self->device_settings($config);
# 		for my $conf_name (keys %{$self->device_settings()}) {
# 			# print "Key: $conf_name, default: ",$self->{default_config}->{$conf_name},", old config: ",$self->{config}->{$conf_name},", new config: ",$config->{$conf_name},"\n";
# 			if( exists($config->{$conf_name}) ) {		# in given config? => set value
# 				 print "Setting $conf_name to $config->{$conf_name}\n";
# 				$self->device_settings()->{$conf_name} = $config->{$conf_name};
# 			}
# 		}
	}
	return $self; # what for? let's not break something...
}



sub _checkconnection { # Connection object or connection_type string (as in Lab::Connections::<connection_type>)
	my $self=shift;
	my $connection=shift || undef;
	my $found = 0;

	$connection = ref($connection) || $connection;

	return 0 if ! defined $connection;

	no strict 'refs';
	if( grep(/^ALL$/, @{$self->supported_connections()}) == 1 ) {
		return $connection;
	}
	else {
		for my $conn_supp ( @{$self->supported_connections()} ) {
			return $conn_supp if( $connection->isa('Lab::Connection::'.$conn_supp));
		}
	}

	return undef;
}



sub _setconnection { # $self->setconnection() create new or use existing connection
	my $self=shift;

	# merge default settings
	my $config = $self->config();
	my $connection_type = undef;
	my $full_connection = undef;

	for my $setting_key ( keys %{$self->connection_settings()} ) {
		$config->{$setting_key} = $self->connection_settings($setting_key) if ! defined $config->{$setting_key};
	}

	# check the configuration hash for a valid connection object or connection type, and set the connection
	if( defined($self->config('connection')) ) {
		if($self->_checkconnection($self->config('connection')) ) {
			$self->connection($self->config('connection'));
		}
		else { Lab::Exception::CorruptParameter->throw( error => "Received invalid connection object!\n" . Lab::Exception::Base::Appendix() ); }
	}
#	else {
#		Lab::Exception::CorruptParameter->throw( error => 'Received no connection object!\n' . Lab::Exception::Base::Appendix() );
#	}
	elsif( defined $self->config('connection_type') ) {
		$connection_type = $self->config('connection_type');

		if( $connection_type !~ /^[A-Za-z0-9_\-\:]*$/ ) { Lab::Exception::CorruptParameter->throw( error => "Given connection type is does not look like a valid module name.\n" . Lab::Exception::Base::Appendix()); };

		if( $connection_type eq 'none' ) { return; };
		# todo: allow this only iff the device supports connection_type none

		$full_connection = "Lab::Connection::" . $connection_type;
		eval("require ${full_connection};") || Lab::Exception::Error->throw( error => "Sorry, I was not able to load the connection ${full_connection}. Is it installed?\n" . Lab::Exception::Base::Appendix() );

		if($self->_checkconnection("Lab::Connection::" . $connection_type)) {

			# let's get creative
			no strict 'refs';

			# yep - pass all the parameters on to the connection, it will take the ones it needs.
			# This way connection setup can be handled generically. Conflicting parameter names? Let's try it.
			$self->connection( $full_connection->new ($config) ) || Lab::Exception::Error->throw( error => "Failed to create connection $full_connection!\n" . Lab::Exception::Base::Appendix() );

			use strict;
		}
		else { Lab::Exception::CorruptParameter->throw( error => "Given Connection not supported!\n" . Lab::Exception::Base::Appendix()); }
	}
	else {
		Lab::Exception::CorruptParameter->throw( error => "Neither a connection nor a connection type was supplied.\n" . Lab::Exception::Base::Appendix());	}
}


sub _checkconfig {
	my $self=shift;
	my $config = $self->config();

	return 1;
}


#
# Generic utility methods for string based connections (most common, SCPI etc.).
# For connections not based on command strings these should probably be overwritten/disabled!
#

#
# passing through generic Write, Read and Query from the connection.
#

sub write {
			# don't overwrite filled hash from ancestor
	my $self=shift;
	my $command=shift;
	my $options=undef;
	if (ref $_[0] eq 'HASH') { $options=shift }
	else { $options={@_} }

	$options->{'command'} = $command;
	
	return $self->connection()->Write($options);
}


sub read {
	my $self=shift;
	my $options=undef;
	if (ref $_[0] eq 'HASH') { $options=shift }
	else { $options={@_} }

	return $self->connection()->Read($options);
}


sub query {
	my $self=shift;
	my $command=shift;
	my $options=undef;
	if (ref $_[0] eq 'HASH') { $options=shift }
	else { $options={@_} }

	$options->{'command'} = $command;

	return $self->connection()->Query($options);
}








#
# infrastructure stuff below
#



#
# accessor for device_settings
#
sub device_settings {
	my $self = shift;
	my $value = undef;
		
	#warn "device_settings got this:\n" . Dumper(@_) . "\n";

	if( scalar(@_) == 0 ) {  # empty parameters - return whole device_settings hash
		return $self->{'device_settings'};
	}
	elsif( scalar(@_) == 1 ) {  # one parm - either a scalar (key) or a hashref (try to merge)
		$value = shift;
	}
	elsif( scalar(@_) > 1 && scalar(@_)%2 == 0 ) { # even sized list - assume it's keys and values and try to merge it
		$value = {@_};
	}
	else {  # uneven sized list - don't know what to do with that one
		Lab::Exception::CorruptParameter->throw( error => "Corrupt parameters given to " . __PACKAGE__ . "::device_settings().\n"  . Lab::Exception::Base::Appendix() );
	}

	#warn "Keys present: \n" . Dumper($self->{device_settings}) . "\n";

	if(ref($value) =~ /HASH/) {  # it's a hash - merge into current settings
		for my $ext_key ( keys %{$value} ) {
			$self->{'device_settings'}->{$ext_key} = $value->{$ext_key} if( exists($self->device_settings()->{$ext_key}) );
			# warn "merge: set $ext_key to " . $value->{$ext_key} . "\n" if( exists($self->device_settings()->{$ext_key}) );
		}
		return $self->{'device_settings'};
	}
	else {  # it's a key - return the corresponding value
		return $self->{'device_settings'}->{$value};
	}
}


#
# accessor for connection_settings
#
sub connection_settings {
	my $self = shift;
	my $value = undef;

	if( scalar(@_) == 0 ) {  # empty parameters - return whole device_settings hash
		return $self->{'connection_settings'};
	}
	elsif( scalar(@_) == 1 ) {  # one parm - either a scalar (key) or a hashref (try to merge)
		$value = shift;
	}
	elsif( scalar(@_) > 1 && scalar(@_)%2 == 0 ) { # even sized list - assume it's keys and values and try to merge it
		$value = {@_};
	}
	else {  # uneven sized list - don't know what to do with that one
		Lab::Exception::CorruptParameter->throw( error => "Corrupt parameters given to " . __PACKAGE__ . "::connection_settings().\n"  . Lab::Exception::Base::Appendix() );
	}

	if(ref($value) =~ /HASH/) {  # it's a hash - merge into current settings
		for my $ext_key ( keys %{$value} ) {
			$self->{'connection_settings'}->{$ext_key} = $value->{$ext_key} if( exists($self->{'connection_settings'}->{$ext_key}) );
			# warn "merge: set $ext_key to " . $value->{$ext_key} . "\n";
		}
		return $self->{'connection_settings'};
	}
	else {  # it's a key - return the corresponding value
		return $self->{'connection_settings'}->{$value};
	}
}


#
# config gets it's own accessor - convenient access like $self->config('GPIB_Paddress') instead of $self->config()->{'GPIB_Paddress'}
# with a hashref as argument, set $self->{'config'} to the given hashref.
# without an argument it returns a reference to $self->config (just like AUTOLOAD would)
#
sub config {	# $value = self->config($key);
	(my $self, my $key) = (shift, shift);

	if(!defined $key) {
		return $self->{'config'};
	}
	elsif(ref($key) =~ /HASH/) {
		return $self->{'config'} = $key;
	}
	else {
		return $self->{'config'}->{$key};
	}
}

#
# provides generic accessor methods to the fields defined in %fields and to the elements of $self->device_settings
#
sub AUTOLOAD {

	my $self = shift;
	my $type = ref($self) or croak "\$self is not an object";
	my $value = undef;

	my $name = $AUTOLOAD;
	$name =~ s/.*://; # strip fully qualified portion

	if( exists $self->{_permitted}->{$name} ) {
		if (@_) {
			return $self->{$name} = shift;
		} else {
			return $self->{$name};
		}
	}
	elsif( $name =~ qr/^(get_|set_)(.*)$/ && exists $self->device_settings()->{$2} ) {
		if( $1 eq 'set_' ) {
			$value = shift;
			if( !defined $value || ref($value) ne "" ) { Lab::Exception::CorruptParameter->throw( error => "No or no scalar value given to generic set function $AUTOLOAD in " . __PACKAGE__ . "::AUTOLOAD().\n"  . Lab::Exception::Base::Appendix() ); }
			if( @_ > 0 ) { Lab::Exception::CorruptParameter->throw( error => "Too many values given to generic set function $AUTOLOAD " . __PACKAGE__ . "::AUTOLOAD().\n"  . Lab::Exception::Base::Appendix() ); }
			return $self->device_settings()->{$2} = $value;
		}
		else {
			if( @_ > 0 ) { Lab::Exception::CorruptParameter->throw( error => "Too many values given to generic get function $AUTOLOAD " . __PACKAGE__ . "::AUTOLOAD().\n"  . Lab::Exception::Base::Appendix() ); }
			return $self->device_settings($2);
		}
	}
	elsif( exists $self->{'device_settings'}->{$name} ) {
		if (@_) {
			return $self->{'device_settings'}->{$name} = shift;
		} else {
			return $self->{'device_settings'}->{$name};
		}
	}
	else {
		cluck ("this is it");
		Lab::Exception::Warning->throw( error => "AUTOLOAD in " . __PACKAGE__ . " couldn't access field '${name}'.\n" . Lab::Exception::Base::Appendix() );
	}
}

# needed so AUTOLOAD doesn't try to call DESTROY on cleanup and prevent the inherited DESTROY
sub DESTROY {
        my $self = shift;
	#$self->connection()->DESTROY();
        $self -> SUPER::DESTROY if $self -> can ("SUPER::DESTROY");
}


# sub WriteConfig {
#         my $self = shift;
# 
#         my %config = @_;
# 	%config = %{$_[0]} if (ref($_[0]));
# 
# 	my $command = "";
# 	# function characters init
# 	my $inCommand = "";
# 	my $betweenCmdAndData = "";
# 	my $postData = "";
# 	# config data
# 	if (exists $self->{'CommandRules'}) {
# 		# write stating value by default to command
# 		$command = $self->{'CommandRules'}->{'preCommand'} 
# 			if (exists $self->{'CommandRules'}->{'preCommand'});
# 		$inCommand = $self->{'CommandRules'}->{'inCommand'} 
# 			if (exists $self->{'CommandRules'}->{'inCommand'});
# 		$betweenCmdAndData = $self->{'CommandRules'}->{'betweenCmdAndData'} 
# 			if (exists $self->{'CommandRules'}->{'betweenCmdAndData'});
# 		$postData = $self->{'CommandRules'}->{'postData'} 
# 			if (exists $self->{'CommandRules'}->{'postData'});
# 	}
# 	# get command if sub call from itself
# 	$command = $_[1] if (ref($_[0])); 
# 
#         # build up commands buffer
#         foreach my $key (keys %config) {
# 		my $value = $config{$key};
# 
# 		# reference again?
# 		if (ref($value)) {
# 			$self->WriteConfig($value,$command.$key.$inCommand);
# 		} else {
# 			# end of search
# 			$self->Write($command.$key.$betweenCmdAndData.$value.$postData);
# 		}
# 	}
# 
# }

1;



=pod

=encoding utf-8

=head1 NAME

Lab::Instrument - General instrument package

=head1 SYNOPSIS

Lab::Instrument is meant to be used as a base class for inheriting instruments. For very simple 
applications it can also be used directly.
Every inheriting class constructor should start as follows:

  sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = $class->SUPER::new(@_);
    $self->_construct(__PACKAGE__);  # check for supported connections, initialize fields etc.
    ...
  }

Beware that only the first set of parameters specific to an individual GPIB board 
or any other bus hardware gets used. Settings for EOI assertion for example. 
Right now, this doesn't really matter because the options aren't there yet, you 
just can't set anything. :) Just keep it in mind.

If you know what you're doing or you have an exotic scenario you can use the connection 
parameter "IgnoreTwin => 1", but this is discouraged - it will kill bus management 
and you might run into hardware/resource sharing issues.



=head1 DESCRIPTION

C<Lab::Instrument> is the base class for Instruments. It doesn't do much by itself, but
is meant to be inherited in specific instrument drivers.
It provides general C<read>, C<write> and C<query> methods and basic connection handling 
(internal, C<_set_connection>, C<_check_connection>).

The connection object can be obtained by calling C<connection()>.

Also, fields common to all instrument classes are created and set to default values where applicable, e.g.:

  connection => undef,
  connection_type => "",
  supported_connections => [ ],
  config => {},

=head1 CONSTRUCTOR

=head2 new

This blesses $self (don't do it in an inheriting class!), initializes the basic "fields" to be accessed
via AUTOLOAD and puts the configuration hash in $self->Config to be accessed in methods and inherited
classes.

Arguments: just the configuration hash passed along from a child class constructor.

=head1 METHODS

=head2 write

 $instrument->write($command);
 
Sends the command C<$command> to the instrument. An option hash can be supplied as second or also as only argument.
Generally, all options are passed to the connection, so additional options may be supported based on the connection.

=head2 read

 $result=$instrument->read({ ReadLength => <max length>, Brutal => <1/0>);

Reads a result of C<ReadLength> from the instrument and returns it.
Returns an exception on error.

If the parameter C<Brutal> is set, a timeout in the connection will not result in an Exception thrown,
but will return the data obtained until the timeout without further comment.
Be aware that this data is also contained in the the timeout exception object (see C<Lab::Exception>).

Generally, all options are passed to the connection, so additional options may be supported based on the connection.

=head2 query

 $result=$instrument->query({ Cmd => $command, WaitQuery => $wait_query, ReadLength => $max length, 
                              WaitStatus => $wait_status);

Sends the command C<$command> to the instrument and reads a result from the
instrument and returns it. The length of the read buffer is set to C<ReadLength> or to the
default set in the connection.

Waits for C<WaitQuery> microseconds before trying to read the answer.

WaitStatus not implemented yet - needed?

The default value of 'wait_query' can be overwritten
by defining the corresponding object key.

Generally, all options are passed to the connection, so additional options may be supported based on the connection.

=head2 connection

 $connection=$instrument->connection();

Returns the connection object used by this instrument. It can then be passed on to another object on the
same connection, or be used to change connection parameters.

=head2 WriteConfig

this is NOT YET IMPLEMENTED in this base class so far

 $instrument->WriteConfig( 'TRIGGER' => { 'SOURCE' => 'CHANNEL1',
  			  	                          'EDGE'   => 'RISE' },
    	               'AQUIRE'  => 'HRES',
    	               'MEASURE' => { 'VRISE' => 'ON' });

Builds up the commands and sends them to the instrument. To get the correct format a 
command rules hash has to be set up by the driver package

e.g. for SCPI commands
$instrument->{'CommandRules'} = { 
                  'preCommand'        => ':',
    		  'inCommand'         => ':',
    		  'betweenCmdAndData' => ' ',
    		  'postData'          => '' # empty entries can be skipped
    		};

=head1 CAVEATS/BUGS

Probably many, with all the porting. This will get better.

=head1 SEE ALSO

=over 4

=item * L<Lab::Bus>

=item * L<Lab::Connection>

=item * L<Lab::Instrument::HP34401A>

=item * L<Lab::Instrument::HP34970A>

=item * L<Lab::Instrument::Source>

=item * L<Lab::Instrument::Yokogawa7651>

=item * and many more...

=back

=head1 AUTHOR/COPYRIGHT

 Copyright 2004-2006 Daniel Schröer <schroeer@cpan.org>, 
           2009-2010 Daniel Schröer, Andreas K. Hüttel (L<http://www.akhuettel.de/>) and David Kalok,
           2010      Matthias Völker <mvoelker@cpan.org>
           2011      Florian Olbrich, Andreas K. Hüttel

This library is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.

=cut

