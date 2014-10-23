package Lab::Generic;

our $VERSION = '3.31';

use Term::ReadKey;


sub new { 
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	my $self={};
	bless ($self, $class);
	
	return $self;
	
}




sub print {
	my $self = shift;
	my @data = @_;
	my ($package, $filename, $line, $subroutine) = caller(1);
	
	if ( ref(@data[0]) eq 'HASH' )
		{
		while ( my ($k,$v) = each %{@data[0]} ) 
			{
			my $line = "$k => ";
			$line.= $self->print($v);
			if ($subroutine =~ /print/)
				{
				return $line;
				}
			else
				{
				print $line."\n";
				}
			}
		}
	elsif ( ref(@data[0]) eq 'ARRAY' )
		{
		my $line ="[";
		foreach (@{@data[0]})
			{
			$line .= $self->print($_);
			$line .= ", ";
			}
		chop ($line);
		chop ($line);
		$line .= "]";
		if ($subroutine =~ /print/)
				{
				return $line;
				}
			else
				{
				print $line."\n";
				}
		}
	else
		{
		if ($subroutine =~ /print/)
				{
				return @data[0];
				}
			else
				{
				print @data[0]."\n";
				}
		}	
		
}







sub _check_args {
	my $self = shift;
	my $args = shift;
	my $params = shift;
	
	my $arguments = {};

	my $i = 0;
	foreach my $arg (@{$args}) 
	{
		if ( ref($arg) ne "HASH" )
			{
			if ( defined @{$params}[$i] )
				{
				$arguments->{@{$params}[$i]} = $arg;				
				}
			$i++;
			}
		else
			{
			%{$arguments} = (%{$arguments}, %{$arg});
			$i++;
			}
	}

			
	my @return_args = ();
	
	foreach my $param (@{$params}) 
		{
		if (exists $arguments->{$param}) 
			{
			push (@return_args, $arguments->{$param});
			delete $arguments->{$param};
			}
		else
			{
			push (@return_args, undef);
			}
		}

	foreach my $param ('from_device', 'from_cache') 	# Delete Standard option parameters from $arguments hash if not defined in device driver function
		{
		if (exists $arguments->{$param}) 
			{
			delete $arguments->{$param};
			}
		}
		

	push(@return_args, $arguments);
	# if (scalar(keys %{$arguments}) > 0) 
		# {
		# my $errmess = "Unknown parameter given in $self :";
		# while ( my ($k,$v) = each %{$arguments} ) 
			# {
			# $errmess .= $k." => ".$v."\t";
			# }
		# print Lab::Exception::Warning->new( error => $errmess);
		# }
			
	return @return_args;
}
	
sub my_sleep {
	my $sleeptime = shift;
	my $self = shift;
	my $user_command = shift;
	if ( $sleeptime >= 5 )
		{
		countdown($sleeptime*1e6, $self, $user_command); 
		}
	else
		{
		usleep($sleeptime*1e6)
		}
}

sub my_usleep {
	my $sleeptime = shift;
	my $self = shift;
	my $user_command = shift;
	if ( $sleep_time >= 5 )
		{
		countdown($sleeptime, $self, $user_command); 
		}
	else
		{
		usleep($sleeptime)
		}
}

sub countdown {
	my $self = shift;
	my $duration = shift;	
	my $user_command = shift;

	ReadMode('cbreak');

	$duration /= 1e6;	
	my $hours = int($duration/3600);
	my $minutes = int(($duration-$hours*3600)/60);
	my $seconds = $duration -$hours*3600 - $minutes*60;

	my $t_0 = time();

	local $| = 1;

	my $message = "Waiting for ";

	if ($hours > 1) { $message .= "$hours hours "; } 
	elsif ($hours == 1) { $message .= "one hour "; } 
	if ($minutes > 1) { $message .= "$minutes minutes "; } 
	elsif ($minutes == 1) { $message .= "one minute "; } 
	if ($seconds > 1) { $message .= "$seconds seconds "; }
	elsif ($seconds == 1) { $message .= "one second "; } 

	$message .= "\n";

	print $message;

	while (($t_0+$duration-time()) > 0) {

		my $char = ReadKey(1);
		
		if (defined($char) && $char eq 'c') {
			last;
		}
		elsif ( defined($char) )
			{
			if (defined $user_command)
				{
				$user_command->($self, $char);
				}
			else
				{
				user_command($char);
				}
			}
		
		my $left = ($t_0+$duration-time());
		my $hours = int($left/3600);
		my $minutes = int(($left-$hours*3600)/60);
		my $seconds = $left -$hours*3600 - $minutes*60;
		
		print sprintf("%02d:%02d:%02d", $hours, $minutes, $seconds);
		print "\r";
		#sleep(1);
	
	}  
	ReadMode('normal');
	$| = 0;
	print "\n\nGO!\n";
	
}

sub timestamp {

	my ($Sekunden, $Minuten, $Stunden, $Monatstag, $Monat,
    $Jahr, $Wochentag, $Jahrestag, $Sommerzeit) = localtime(time);
	
	$Monat+=1;
	$Jahrestag+=1;
	$Monat = $Monat < 10 ? $Monat = "0".$Monat : $Monat;
	$Monatstag = $Monatstag < 10 ? $Monatstag = "0".$Monatstag : $Monatstag;
	$Stunden = $Stunden < 10 ? $Stunden = "0".$Stunden : $Stunden;
	$Minuten = $Minuten < 10 ? $Minuten = "0".$Minuten : $Minuten;
	$Sekunden = $Sekunden < 10 ? $Sekunden = "0".$Sekunden : $Sekunden;
	$Jahr+=1900;
	
	return   "$Monatstag.$Monat.$Jahr", "$Stunden:$Minuten:$Sekunden";

}

sub seconds2time {
	my $duration = shift;
	
	my $hours = int($duration/3600);
	my $minutes = int(($duration-$hours*3600)/60);
	my $seconds = $duration -$hours*3600 - $minutes*60;
	
	my $formated = $hours."h ".$minutes."m ".$seconds."s ";
	
	
	return $formated;
}
1;
