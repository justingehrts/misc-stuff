#c:\strawberry\perl\bin
##written by Joe Ziskovsky of The Weather Company, Copyright 2024
##This program utilized freely available River Guage data made available by NOAA
##
use warnings;
use strict;
use Data::Dumper; #used for data output verification only...not needed for processing
use File::Slurp; #for reading from a file into a variable
use JSON::XS; #used to parse JSON data from a file
use JSON::Parse; #used for handling the internal array of the data
use Time::Piece; #used to convert GMT time stamps in the data to local time.
#
#
##MainLoop

##Method for calling the command must include debug mode option and whether to use embedded names or user defined names for locations.
##Example: (GetRiverData.pl N NameOverride Y);
if ($#ARGV != 2 ) {
	print "usage: [script] [debug (Y|N) NameOverride (Y|N)]-> example: GetRiverData.pl N NameOverride N\n";
	exit;
}

#############Debug Mode################
my $debug= lc $ARGV[0];
#
#set locations to process from file in the form of (code,name)
#define if embedded names in API should be used or if user define name in configuration is to be used this is the Name Override argument. Yes uses the names from the configuration file.
my $NameOverride= lc $ARGV[1];

#note - read in files as an object of arrays we will break up
my @locations = read_file("C:\\LOCAL\\PERL\\GetRiverData-Config.txt", chomp => 1) or die ("Could not READ locations data - aborting");

#declare constants for things we know will be there.
my $regionKey;;
my $LocationID;;
my $Longitude;
my $Latitude;
my $actionStage;
my $minorStage;
my $moderateStage;
my $majorStage;
my $recordStage;
my $currentStage;
my $currentStageCode;
my $trend;
my $obsValidTime;
my $obsPrimary;
##Set the following to null as a default. We'll write a value if a value is present in the data.
my $crestValidTime = "";
my $crestStageCode = "";
my $crestStage = "";
my $crestPrimary = "";
my $crestRelative = "";
my $fcst1ValidTime = "";
my $fcst1Primary = "";
my $fcst1TrendVal = "";
my $fcst1TrendCode = "";
my $fcst2ValidTime = "";
my $fcst2Primary = "";
my $fcst2TrendVal = "";
my $fcst2TrendCode = "";
my $fcst3ValidTime = "";
my $fcst3Primary = "";
my $fcst3TrendVal = "";
my $fcst3TrendCode = "";
my $fcst4ValidTime = "";
my $fcst4Primary = "";
my $fcst4TrendVal = "";
my $fcst4TrendCode = "";
my $fcst5ValidTime = "";
my $fcst5Primary = "";
my $fcst5TrendVal = "";
my $fcst5TrendCode = "";
my $fcst6ValidTime = "";
my $fcst6Primary = "";
my $fcst6TrendVal = "";
my $fcst6TrendCode = "";
my $fcst7ValidTime = "";
my $fcst7Primary = "";
my $fcst7TrendVal = "";
my $fcst7TrendCode = "";
my $fcst8ValidTime = "";
my $fcst8Primary = "";
my $fcst8TrendVal = "";
my $fcst8TrendCode = "";
my $fcst9ValidTime = "";
my $fcst9Primary = "";
my $fcst9TrendVal = "";
my $fcst9TrendCode = "";
#
#Set URL line with all options needed - from documentation of the WeatherFlow SDK
my $APIBaseURL="https://api.water.noaa.gov/nwps/v1/gauges/"; 

##Set Filename and path for output and open the file
my $outfile = "D:\\WSI\\FTPINGEST\\local_ncsv\\NOAARiverGauge.csv";##Set Customer output location. May need to occasionally modify for Cloud, but points to LDI ingest folder structure by default.
##set up special test case with secret code word ~ Thank you Professor, how about a nice game of chess?"
if($debug eq "joshua")
{
	$outfile = "C:\\Temp\\NOAARiverGauge.csv"; ##if special test case, change this for non-Max systems
}
open(DATAOF, '>', $outfile) or die $!;

#Set Filename and path for holding file and open the file - this is for troubleshooting and gets remade each run
my $datafilename1 = "C:\\ProgramData\\WSI\\Logs\\PERL-Holding-NOAARG-creststatus.txt";
my $datafilename2 = "C:\\ProgramData\\WSI\\Logs\\PERL-Holding-NOAARG-Streamdata.txt";
##set up special test case with secret code word ~ Thank you Professor, how about a nice game of ThermoNuclear War?"
if($debug eq "joshua")
{
	$datafilename1 = "C:\\TEMP\\PERL-Holding-NOAARG-creststatus.txt"; ##if special test case, change this for non-Max systems
	$datafilename2 = "C:\\TEMP\\PERL-Holding-NOAARG-Streamdata.txt"; ##if special test case, change this for non-Max systems
}

#Define and print out headerline for data intended to be pulled form the API reply into data file, leave file open
my $headerline="LocationID,LocationName,Latitude,Longitude,Action Stage Level,Minor Flood Stage Level,Moderate Flood Level,Major Flood Level,OBS Time,OBS Stage Code,OBS Stage Description,OBS FLOW VALUE,Crest Time,Crest Stage Code,Crest Stage Description,Crest FLOW VALUE,Fcst Crest RELATIVE TO Stage VALUE,FCST1 VALID TIME,FCST1 FLOW VALUE,FCST1 TREND VALUE,FCST1 TREND CODE,FCST2 VALID TIME,FCST2 FLOW VALUE,FCST2 TREND VALUE,FCST2 TREND CODE,FCST3 VALID TIME,FCST3 FLOW VALUE,FCST3 TREND VALUE,FCST3 TREND CODE,FCST4 VALID TIME,FCST4 FLOW VALUE,FCST4 TREND VALUE,FCST4 TREND CODE,FCST5 VALID TIME,FCST5 FLOW VALUE,FCST5 TREND VALUE,FCST5 TREND CODE,FCST6 VALID TIME,FCST6 FLOW VALUE,FCST6 TREND VALUE,FCST6 TREND CODE,FCST7 VALID TIME,FCST7 FLOW VALUE,FCST7 TREND VALUE,FCST7 TREND CODE,FCST8 VALID TIME,FCST8 FLOW VALUE,FCST8 TREND VALUE,FCST8 TREND CODE,FCST9 VALID TIME,FCST9 FLOW VALUE,FCST9 TREND VALUE,FCST9 TREND CODE";

#
print DATAOF $headerline."\n";
#
####################THE MEAT - GETTING THE DATA#####################
#
#
####################BEGIN CYCLING THROUGH LOCATIONS##################
#
foreach my $location (@locations)
{
#create mini-array of the four components of a location line.
my @locationinfo = split(',', $location);
#
#set constants from location
$regionKey = $locationinfo[0];
$LocationID = $locationinfo[1]; #by default we want a name in the config file
#$Latitude = $locationinfo[2];
#$Longitude = $locationinfo[3];
#$actionStage = $locationinfo[4];
#$minorStage = $locationinfo[5];
#$moderateStage = $locationinfo[6];
#$majorStage = $locationinfo[7];
#$recordStage = $locationinfo[8];
#
#foreach loop to loop through station
##############################foreach(@station_list){
		#generate custom URL request based on station from the list
		my $URLRequest1=$APIBaseURL.$regionKey;
		my $URLRequest2=$APIBaseURL.$regionKey."/stageflow";
#see actual requested URL for debug purposes
		if ($debug eq "y" || $debug eq "joshua") 
		{
			print("Starting new Request for location: ".$LocationID."\n");
			print("\n");
			print("Making a request to: ".$URLRequest1."\n");
			print("\n");
			print("Making a request to: ".$URLRequest2."\n");
#
		}
#make the request already!
			my $requeststring1 = '"c:\Program Files\WSI\TruVu Core\Bin\Curl.exe" -X GET -o '.$datafilename1.' --header "Content-Type: application/json" '.$URLRequest1;
			my $requeststring2 = '"c:\Program Files\WSI\TruVu Core\Bin\Curl.exe" -X GET -o '.$datafilename2.' --header "Content-Type: application/json" '.$URLRequest2;
#
#SERIOUSLY ...make the request already!
			if ($debug eq "y" || $debug eq "joshua") 
			{
				print("\n");
				printf ("Executing command: ".$requeststring1."\n");
				print("\n");
				printf ("Executing command: ".$requeststring2."\n");
			}
###store in holding file
			system($requeststring1);
			system($requeststring2);

#
#read in resoinse form holding file
			my $URLResponse1 = read_file $datafilename1;
			my $URLResponse2 = read_file $datafilename2;
			
#assign the response to an object
			my $jsondata1 = decode_json $URLResponse1 or die ("Could not decode JSON data - aborting");
			my $jsondata2 = decode_json $URLResponse2 or die ("Could not decode JSON data - aborting");
			if ($debug eq "y" || $debug eq "joshua") {
				print("\n");
				print Dumper($jsondata1);
				print("\n");
				print Dumper($jsondata2);
			}

#store the return in an array for later keeping as array
			my @jsonobjects1 = decode_json($URLResponse1);
			my @jsonobjects2 = decode_json($URLResponse2);

#store the results in an object for parsing main level items
			my $jsonobjects1 = decode_json($URLResponse1);			
			my $jsonobjects2 = decode_json($URLResponse2);

#start grabbing the essential elements we know are in the return from the SDK documentation
			my $station_id = $regionKey;
			if ($NameOverride eq "n")
			{
				$LocationID = $jsonobjects1->{name};
			}
			my $station_name = $LocationID;
			my $station_lat = $jsonobjects1->{latitude};
			my $station_lon = $jsonobjects1->{longitude};
			if ($debug eq "y" || $debug eq "joshua")
			{
								print("\n");
				print("station ID is: ".$station_id, "\n");
				print("station Name is: ".$station_name, "\n");
				print("Latitude is: ".$station_lat, "\n");
				print("Longitude is: ".$station_lon, "\n");
				print("\n");
				print("Checking for data", "\n");
				print("\n");
			}
			my $stagearray = $jsonobjects1->{flood}; ## from API 1
			my $obsarray = $jsonobjects1->{status}; ## from API 1
			my $fcstarray = $jsonobjects2->{forecast}; ## from API 2

#Check first that a obs exists in the obseervation data by seeing if the entry returns blank
			if (($obsarray->{observed}->{floodCategory}) eq "obs_not_current")
			{
				goto CheckObsForecast; #skip to Crest forecast
			}
#get flood stage reference info
			$majorStage = $stagearray->{categories}->{major}->{stage};
			$moderateStage = $stagearray->{categories}->{moderate}->{stage};
			$minorStage = $stagearray->{categories}->{minor}->{stage};
			$actionStage = $stagearray->{categories}->{action}->{stage};

#get Latest Observation
			$obsValidTime = GMT2LT($obsarray->{observed}->{validTime},$debug,"Observed River Level");
			$currentStage = ModifySD($obsarray->{observed}->{floodCategory});
			$currentStageCode = SD2SC($obsarray->{observed}->{floodCategory});
			$obsPrimary = $obsarray->{observed}->{primary};
#			my $obsPrimary = $obsarray->{observed}->{secondary}; ##might use this in the future
CheckObsForecast:
#get Forecast Crest information
#Check first that a crest exists in the forecast by seeing if the entry returns blank
			if (($obsarray->{forecast}->{floodCategory}) eq "fcst_not_current")
			{
				$crestValidTime = "";
				$crestStage = "No Flooding";
				$crestStageCode = "0";
				$crestPrimary = "";
				$crestRelative = "";
				goto CheckForecast; #skip to forecast
			}
#otherwise...
			else
			{
				$crestValidTime = GMT2LT($obsarray->{forecast}->{validTime},$debug,"Forecast Crest Level");
				$crestStage = ModifySD($obsarray->{forecast}->{floodCategory});
				$crestStageCode = SD2SC($obsarray->{forecast}->{floodCategory});
				$crestPrimary = $obsarray->{forecast}->{primary};
				$crestRelative = sprintf("%.2f",($crestPrimary - $minorStage));
#				my $crestSecondary = $crestdatalist->{secondary}; ##might use this in the future
			}
CheckForecast:
#Check if there is forecast data in the forecast API.
			my @fcstdatalist = @{$fcstarray->{'data'} };
			my $arraysize = @fcstdatalist;
			if ($debug eq "y" || $debug eq "joshua")
			{
				print "\nforecast array is: ".$arraysize." entries long\n\n";
			}
			if ($arraysize > 1){
#Get forecast for next 9 time periods if data exists.
				$fcst1ValidTime = GMT2LT($fcstdatalist[0]->{validTime},$debug,"Fcst1");
				$fcst1Primary = $fcstdatalist[0]->{primary};
	 #           my $fcst1Secondary = $fcstdatalist[0]->{secondary};
				$fcst2ValidTime = GMT2LT($fcstdatalist[1]->{validTime},$debug,"Fcst2");
				$fcst2Primary = $fcstdatalist[1]->{primary};
	 #           my $fcst2Secondary = $fcstdatalist[1]->{secondary};
				$fcst3ValidTime = GMT2LT($fcstdatalist[2]->{validTime},$debug,"Fcst3");
				$fcst3Primary = $fcstdatalist[2]->{primary};
	#            my $fcst3Secondary = $fcstdatalist[2]->{secondary};
				$fcst4ValidTime = GMT2LT($fcstdatalist[3]->{validTime},$debug,"Fcst4");
				$fcst4Primary = $fcstdatalist[3]->{primary};
	#            my $fcst4Secondary = $fcstdatalist[3]->{secondary};
				$fcst5ValidTime = GMT2LT($fcstdatalist[4]->{validTime},$debug,"Fcst5");
				$fcst5Primary = $fcstdatalist[4]->{primary};
	#            my $fcst5Secondary = $fcstdatalist[5]->{secondary};
				$fcst6ValidTime = GMT2LT($fcstdatalist[5]->{validTime},$debug,"Fcst6");
				$fcst6Primary = $fcstdatalist[5]->{primary};
	#            my $fcst6Secondary = $fcstdatalist[5]->{secondary};
				$fcst7ValidTime = GMT2LT($fcstdatalist[6]->{validTime},$debug,"Fcst7");
				$fcst7Primary = $fcstdatalist[6]->{primary};
	 #           my $fcst7Secondary = $fcstdatalist[6]->{secondary};
				$fcst8ValidTime = GMT2LT($fcstdatalist[7]->{validTime},$debug,"Fcst8");
				$fcst8Primary = $fcstdatalist[7]->{primary};
	#            my $fcst8Secondary = $fcstdatalist[7]->{secondary};
				$fcst9ValidTime = GMT2LT($fcstdatalist[8]->{validTime},$debug,"Fcst9");
				$fcst9Primary = $fcstdatalist[8]->{primary};
	 #           my $fcst9Secondary = $fcstdatalist[8]->{secondary};
				$fcst1TrendVal = sprintf("%.2f",($obsPrimary - $fcst1Primary));
				$fcst1TrendCode = Trend($fcst1TrendVal);
				$fcst2TrendVal = sprintf("%.2f",($fcst1Primary - $fcst2Primary));
				$fcst2TrendCode = Trend($fcst2TrendVal);
				$fcst3TrendVal = sprintf("%.2f",($fcst2Primary - $fcst3Primary));
				$fcst3TrendCode = Trend($fcst2TrendVal);
				$fcst4TrendVal = sprintf("%.2f",($fcst3Primary - $fcst4Primary));
				$fcst4TrendCode = Trend($fcst2TrendVal);
				$fcst5TrendVal = sprintf("%.2f",($fcst4Primary - $fcst5Primary));
				$fcst5TrendCode = Trend($fcst2TrendVal);
				$fcst6TrendVal = sprintf("%.2f",($fcst5Primary - $fcst6Primary));
				$fcst6TrendCode = Trend($fcst2TrendVal);
				$fcst7TrendVal = sprintf("%.2f",($fcst6Primary - $fcst7Primary));
				$fcst7TrendCode = Trend($fcst2TrendVal);
				$fcst8TrendVal = sprintf("%.2f",($fcst7Primary - $fcst8Primary));
				$fcst8TrendCode = Trend($fcst2TrendVal);
				$fcst9TrendVal = sprintf("%.2f",($fcst8Primary - $fcst9Primary));
				$fcst9TrendCode = Trend($fcst2TrendVal);
			}
# Concate all the data collected for this station
#
###this includes the secondary flow rates for future use perhaps ----> ###
#$my $cumulativedataline = $station_id.",".$station_name.",".$station_lat.",".$station_lon.",".$actionStage.",".$minorStage.",".$moderateStage.",".$majorStage.",".$obsValidTime.",".$currentStageCode.",".$currentStage.",".$obsPrimary.",".$obsSecondary.",".$crestValidTime.",".$crestStageCode.",".$crestStage.",".$crestPrimary.",".$fcst1ValidTime.",".$crestRelative.",".$fcst1ValidTime.",".$fcst1Primary.",".$fcst1Secondary.",".$fcst1TrendVal.",".$fcst1TrendCode.",".$fcst2ValidTime.",".$fcst2Primary.",".$fcst2Secondary.",".$fcst2TrendVal.",".$fcst2TrendCode.",".$fcst3ValidTime.",".$fcst3Primary.",".$fcst3Secondary.",".$fcst4TrendVal.",".$fcst4TrendCode.",".$fcst4ValidTime.",".$fcst4Primary.",".$fcst4Secondary.",".$fcst4TrendVal.",".$fcst4TrendCode.",".$fcst5ValidTime.",".$fcst5Primary.",".$fcst5Secondary.",".$fcst5TrendVal.",".$fcst5TrendCode.",".$fcst6ValidTime.",".$fcst6Primary.",".$fcst6Secondary.",".$fcst6TrendVal.",".$fcst6TrendCode.",".$fcst7ValidTime.",".$fcst7Primary.",".$fcst7Secondary.",".$fcst7TrendVal.",".$fcst7TrendCode.",".$fcst8ValidTime.",".$fcst8Primary.",".$fcst8Secondary.",".$fcst8TrendVal.",".$fcst8TrendCode.",".$fcst9ValidTime.",".$fcst9Primary.",".$fcst9Secondary.",".$fcst9TrendVal.",".$fcst9TrendCode;
			my $cumulativedataline = $station_id.",".$station_name.",".$station_lat.",".$station_lon.",".$actionStage.",".$minorStage.",".$moderateStage.",".$majorStage.",".$obsValidTime.",".$currentStageCode.",".$currentStage.",".$obsPrimary.",".$crestValidTime.",".$crestStageCode.",".$crestStage.",".$crestPrimary.",".$crestRelative.",".$fcst1ValidTime.",".$fcst1Primary.",".$fcst1TrendVal.",".$fcst1TrendCode.",".$fcst2ValidTime.",".$fcst2Primary.",".$fcst2TrendVal.",".$fcst2TrendCode.",".$fcst3ValidTime.",".$fcst3Primary.",".$fcst3TrendVal.",".$fcst3TrendCode.",".$fcst4ValidTime.",".$fcst4Primary.",".$fcst4TrendVal.",".$fcst4TrendCode.",".$fcst5ValidTime.",".$fcst5Primary.",".$fcst5TrendVal.",".$fcst5TrendCode.",".$fcst6ValidTime.",".$fcst6Primary.",".$fcst6TrendVal.",".$fcst6TrendCode.",".$fcst7ValidTime.",".$fcst7Primary.",".$fcst7TrendVal.",".$fcst7TrendCode.",".$fcst8ValidTime.",".$fcst8Primary.",".$fcst8TrendVal.",".$fcst8TrendCode.",".$fcst9ValidTime.",".$fcst9Primary.",".$fcst9TrendVal.",".$fcst9TrendCode;
			if ($debug eq "y" || $debug eq "joshua")
			{
				print("\n");
				print "data line is: ".$cumulativedataline."\n\n";
			}
#write to file the data line
			print DATAOF $cumulativedataline."\n";
				
#Note in console that we have finished for this particular station
			print("Data processing for station: ".$station_name." completed", "\n");
			print("==================================================");
			print("\n");
}
#Close Data file
		close(DATAOF);

##Subroutine to determine trend
sub Trend {
	my $tVal = shift;
	my $tcode;
	if ($tVal gt "0"){
		$tcode = "R";
	}
	if ($tVal lt "0"){
		$tcode = "F";
	}
	if ($tVal eq "0"){
		$tcode = "S";
	}
	return $tcode;
}

##Subroutine to change case on stage notation
sub ModifySD {
	my $SD = shift;
	my $modSD;
	if	($SD eq "no_flooding")
	{
		$modSD = "No Flooding";
	}
	if ($SD eq "action")
	{
		$modSD = "Action";
	}
	if ($SD eq "minor")
	{
		$modSD = "Minor";
	}
	if ($SD eq "moderate")
	{
		$modSD = "Moderate";
	}
	if ($SD eq "major")
	{
		$modSD = "Major";
	}
	return $modSD;
}

##Subroutine to change stage notation to code
sub SD2SC {
	my $SD = shift;
	my $SC;
	if	($SD eq "no_flooding")
	{
		$SC = "0";
	}
	if ($SD eq "action")
	{
		$SC = "1";
	}
	if ($SD eq "minor")
	{
		$SC = "2";
	}
	if ($SD eq "moderate")
	{
		$SC = "3";
	}
	if ($SD eq "major")
	{
		$SC = "4";
	}
	return $SC;
}

##Subroutine to change time from GMT to Local
sub GMT2LT {
	my $GMtime = shift;
	my $dbmode = shift;
	my $notation = shift;
	if ($debug eq "y" || $debug eq "joshua")
	{
		print ("data time for ".$notation." is: ".$GMtime." ");
	}
	my $LocTime;
	my $time = Time::Piece->strptime($GMtime, "%Y-%m-%dT%H:%M:%SZ"); #read in date format, we assume this to be GMT un datetime format with a "Z" we need to remove.
	if ($debug eq "y" || $debug eq "joshua")
	{
		print ("which is converted to time: ".$time."\n");
		print ("gmt time is: ".$time->strftime("%H %m/%d")." which makes ");
	}
	$time = localtime($time->epoch); #create localtime object refering the universal epoch from the GMT time object
	if ($debug eq "y" || $debug eq "joshua")
	{
		print ("local time: ".$time->strftime("%#I%p %m/%d")."\n");
	}
	$LocTime = $time->strftime("%#I%p %m/%d");
	return $LocTime;
}