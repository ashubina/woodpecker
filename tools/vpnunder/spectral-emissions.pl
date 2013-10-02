#!/usr/bin/perl

use strict;
use SVG;

#
#  Generate an SVG for a data series. We use Inkscape's inkview to view from  
#    command line. Usage: 
#     ./spectral-emissions.pl  datafile  > lines.svg 
#     inkview lines.svg
#
#  Datafile format is one number per line.
#

# Global tunables.
my $w = 400; # Overall width. All other arithmetic must scale up with it.
my $h = 50;  # Overall height, ditto.
my $margins = 0.1; # 10% empty margins on both sides of the actual band

# warn "Parsing $ARGV[0]\n";

my $rectid = 100; # Global rectangle element id counter

my @known_data_files = <knowndata/*>;
my $datafile_count = scalar @known_data_files;

#we add one for our test data and one for the full spectra
my $svg= SVG->new(width=>$w, height=>($h*($datafile_count+2)));

# optional: add title derived from 1st arg. Inkview doesn't show
#   the title anyway, but some other viewer might. Also,
#   could add it to the picture in a text box if desired.
$svg->title(id=>'document-title')->cdata("Dataset ". $ARGV[0]) if @ARGV;

# Top-level box
my $box=$svg->group(
    id    => 'group_outer_box',
    style => { stroke=>'white', fill=>'white' } # not used
    );


# black background
#we add one for our test data and one for the full spectra
rect(0, 0, $w, $h*($datafile_count+2), 'black');
my @data;
my $max;
my $min;
getDataFromFile( $ARGV[0], \$min, \$max, \@data );
my @nullData;

processData( \@data, 0, $min, $max );
$box->text( x=>5, y=>0+25, fill=>'rgb(200,30,100)')->cdata($ARGV[0]);
#display the known ones
my $i = 1;
for( @known_data_files )
{
  my @knowdata;
  my $t = "$_";
  $t =~ s/knowndata\///;
  $t =~ s/\.txt//;
  my $temp = $i*$h;
#  warn "processing $t ($temp)...";
  
  getDataFromFile( $_, \$min, \$max, \@knowdata );
  processData( \@knowdata, $i*$h, $min, $max ); 
  $box->text( x=>5, y=>($i*$h)+25, fill=>'rgb(200,30,100)')->cdata($t);
  $i++;
}
#show the full spectra
#warn $h*$datafile_count, "\n";
#processData( \@nullData, $h*($datafile_count+1), $min, $max );

# render the SVG object, implicitly use svg namespace
print $svg->xmlify;



################################################################
## Subs
###############

#
#  Add a rectangle to the top-level box
#
sub rect {
    my($x, $y, $width, $height, $color) = @_;
    $box->rectangle(
    x=>$x, y=>$y,
    width=>$width, height=>$height,
    style => { stroke=>$color, fill=>$color },
    id=>"rect_$rectid"
    );    
    $rectid++;
}

#
#  Take one coordinate, scale & draw respective box 
#
sub line {
    my($x, $y, $color) = @_;
    rect($x, $y, 1, $h, $color);
}



#
#   Read the data file in and create a spectral image
#

sub processData
{
  my (@data) = @{$_[0]};

  my( $y, $min, $max ) = ($_[1], $_[2], $_[3]);
  
  # leave margins (default 10%, see globals above) beyond max & min, on both sides
  my $band = $max - $min;
  my $border = $band * $margins; # tunable
  my $lmargin = ( ($min - $border) < 0 ) ? 0 : $min - $border;
  my $rmargin = $max + $border;
  
  $band = $rmargin - $lmargin; # new band
  
  # scale band to box width, make per-pixel bins
  my @bins;
  my $max_bin_count = 0;
  for (@data){
      # which pixel bin is this datapoint in?
      my $n = int( ($_-$lmargin)*$w/$band ); # * or / first? darn floats :(
      $bins[$n] += 1;
      $max_bin_count = $bins[$n] if $bins[$n] > $max_bin_count;
  }
  warn "Max bin count : $max_bin_count\n";
  # now paint pixels
  my $red = 0;
  my $green = 0;
  my $blue = 0;    
  for( my $p=0; $p < $w; $p++ ){
      # scale intensity by $max_bin_count

      if( $p < 80) 
      {
        $red = 80+($p * 2);   
#        $red = int( $bins[$p]*255/$max_bin_count );    
        $green=0;
        $blue = 0;
      }
      elsif( ($p < 160) && ($p >= 80) )
      {
        $red = 240;
        $green = (($p - 80)*3);
#        $red = 255;
#        $green = int( $bins[$p]*255/$max_bin_count );
        $blue = 0;
      }
      elsif( ($p >= 160) && ($p < 240 ) )
      {
        $red = 240 - (( $p - 160 ) * 3 );
        $green = 240;
#        $red = int( $bins[$p]*255/$max_bin_count );
#        $green = 255;
        $blue = 0;
      }
      elsif( ($p >= 240) && ($p <320 ) )
      {
        $red = 0;
        $green = 240 - (( $p - 240 ) * 3);
        $blue = (($p - 240)*3);
#         $green = int( $bins[$p]*255/$max_bin_count );
#         $blue = int( $bins[$p]*255/$max_bin_count );
      }
      elsif( ($p >= 320) )
      {
        $red = (($p - 320)*3);
        $green=0;
#        $red = int( $bins[$p]*255/$max_bin_count );
#        $blue = 255;
        $blue = 240;
      }
  
      #my $intensity = int( $bins[$p]*255/$max_bin_count );
      if( !@data )
      {
        line( $p, $y, "rgb( $red, $green, $blue)" );
      }
      elsif( $bins[$p] > 0 )
      {
      #  line( $p, "rgb(0, $intensity, 0)" );
        line( $p, $y, "rgb($red, $green, $blue)" );
        warn "\tbin[$p] = $bins[$p]\n";
      }
      else
      {
        line( $p, $y, 'black' );
      }
  }
}

#
# reads data in from file and returns the data and the min and max
#
sub getDataFromFile
{
  my ( $filename ) = @_[0];
#  my (@data) = @{$_[1]};
  my $INFILE;
  
  
  #read the data and find the max and min
 open $INFILE, $filename or die "Failed to open $filename\n";
  
#  my $m1 = 1000000;
  my ($min, $max) = ( 1000000, -1 );
  
  while(<$INFILE>){
      chomp;
      next unless /\S/;
      push @{$_[3]}, $_;
      $min = $_ if $_ < $min;
      $max = $_ if $_ > $max;
  }
  ${$_[1]} = $min;
  ${$_[2]} = $max;
}

#
# goes through the data and finds the max and min
#
sub getMinMax
{
  my (@data) = @{$_[0]};
  
  my( $min, $max ) = ( 1000000, -1 );

  for( @data )
  {
    $min = $_ if $_ < $min;
    $max = $_ if $_ > $max;
  }
  ${$_[1]} = $min;
  ${$_[2]} = $max;
}

