#!/usr/bin/perl

use Net::Pcap;
use Getopt::Long;
use Algorithm::KMeans;

use strict;

my $dev;                #default device to monitor.
my $promise = 0;        #use promiscuous mode true/false
my $snaplen = 60;       #number of bytes to capture
my $timeout_ms = 1024;  #capture timeout in milliseconds(if supported)
                        # 0  - capture until error
                        # -1 -  capture indefinitely
my $packet_count = 30000;  #number of packets to capture
my $user_data = "";     #user configurable data passed to packet_anal_func                        
my $dump_file;
my $source_ip = "";
my $dest_ip = "";
my $filter = "";
my $max_len;
my $min_len;
my @monitor_prots;
my $output_file = "data.txt";

#Usage: vpnunder.pl -dev [dev] -src [source_ip] -dst [dest_ip] -protos [prototype] -min_len [min packet size] -max_len [max packet size]

GetOptions('dev=s' => \$dev, 
           'dumpfile=s' => \$dump_file, 
           'w=s' => \$dump_file,
           'packetcount=i' => \$packet_count,
           'c=i' => \$packet_count,
           'filter=s' => \$filter,
           'src=s' =>  \$source_ip,
           'dst=s' => \$dest_ip,
           'max_len=i' => \$max_len,
           'min_len=i' => \$min_len,
           'p=s' => \@monitor_prots,
           'protos=s' => \@monitor_prots,
           'outputfile=s' => \$output_file );

@monitor_prots = split(/,/,join(',',@monitor_prots ));

my $err;
if( !$dev )
{
  $dev = Net::Pcap::lookupdev(\$err);

  if( defined $err ) {
    die 'Unable to determine network device for monitoring - ', $err;
  }
}

my %devinfo;
my @devs = Net::Pcap::findalldevs(\%devinfo, \$err );
my $dev_valid = 0;
for my $d (@devs)
{
  if( $d eq $dev )
  {
    $dev_valid = 1;
  }
}

if( !$dev_valid )
{
  print STDERR "Invalid network device requested: $dev \n";
  exit;
}

iptables_drop_every_nth_packet(\@monitor_prots, 5, $dev);

my $object = Net::Pcap::open_live( $dev, $snaplen, $promise, $timeout_ms, \$err ) ||
  die "Can't open live connection : $err\n";
my $dumper;
my $packet_counter = 0;
my $tempDumpFile = "temp" . time . ".pcap";
  
$dumper = Net::Pcap::dump_open( $object, $tempDumpFile );

my @timings;
print "Starting Capture...\n";

Net::Pcap::loop( $object, $packet_count, \&packet_collect_func, $user_data );
#Net::Pcap::loop( $object, $packet_count, \&packet_anal_func, $user_data );

if( $dumper )
{
  Net::Pcap::dump_close($dumper);
}
Net::Pcap::close( $object );

print "Done capturing live sample...\n";

# We are done with the capture and can clear out our delay

clear_iptables_drop_every_nth_packet(\@monitor_prots, 5, $dev);

# Now we have to apply our filter to the captured data

# Open the file for processing 
$object = Net::Pcap::open_offline( $tempDumpFile, \$err ) ||
  die "Failed to open temp file : $err\n";

if( $filter ne "" )
{
  my $compiled_filter;
  $err = Net::Pcap::compile( $object, \$compiled_filter, $filter, 0, 0 );
  if( $err == -1 )
  {
    die 'Filter "', $filter, '" failed to compile.';
  }
  Net::Pcap::setfilter( $object, $compiled_filter );
}
elsif( $source_ip ne "" && $dest_ip ne "" && $max_len && $min_len )
{
  my $compiled_filter;
  my $t_filter = "src host $source_ip and dst host $dest_ip and greater $min_len and less $max_len";
  $err = Net::Pcap::compile( $object, \$compiled_filter, $t_filter, 0, 0 );
  if( $err == -1 )
  {
    die 'Filter "', $t_filter, '" failed to compile.';
  }
  Net::Pcap::setfilter( $object, $compiled_filter );
}
else
{
  print "You need to provide src and dst arguments along with max(max_len) and min(min_len) packet lengths, or a filter\n";
  exit;
}

$packet_counter = 0;
if( $dump_file ne "" )
{
  $dumper = Net::Pcap::dump_open( $object, $dump_file );
}

my @timings;
print "Starting Capture from temp file...\n";

#Net::Pcap::loop( $object, $packet_count, \&packet_collect_func, $user_data );
Net::Pcap::loop( $object, -1, \&packet_anal_func, {} );

print "Done filtering...";

if( $dumper )
{
  Net::Pcap::dump_close($dumper);
}
Net::Pcap::close( $object );

# Now we work on the clustering
# separate the timings into groups of 100

print "Processing capture file...\n";
my @hundreds;
my $prev_hundred  = $timings[0];

# Store the data  in a format compatible with the clustering function
my $c_filename = "clusters_" . $output_file;
open( my $cluster_file, ">", $c_filename )
  or die "Can't open cluster file...\n";

for (my $i = 1; $i < scalar(@timings); $i++) {
    if ($i % 100 == 0) {
    	push @hundreds, $timings[$i] - $prev_hundred;
    	$prev_hundred = $timings[$i];
    # This print can be redirected or done straight to file
    	print $cluster_file $i/100 . " " . $hundreds[$i/100-1] . "\n";
    }
}
close( $cluster_file );
print "Processing clusterized data from $c_filename ...\n";
#cluster the file
my @clusters = clusterFile( $c_filename );
print $output_file . " is the output_file \n";
open (my $clusterOutfile, ">", $output_file )
  or die "Can't open '$output_file' for writing...";
print $clusterOutfile join("\n", @clusters );
close $clusterOutfile;



# You now have the array of time gaps @hundreds
#print $output_file, " is the outputfile\n";
#open (my $HUNDIFILE, ">", $output_file)
#  or die "Can't open $output_file for writing...";
#print $HUNDIFILE join("\n", @hundreds), "\n";
#close ($HUNDIFILE);







####################################
## Subs
############
sub packet_anal_func
{
    my($udata, $hdr, $pkt) = @_;
    
  if( $dumper )
  {
    Net::Pcap::dump($dumper, $hdr, $pkt );
  }
  
  # make a proper floating point number out of
  #  sec and usec. usec is always less than 10^6,
  #  so supply needed # of zeros
  my $ulen = length($hdr->{tv_usec});
  die "Microseconds can't be a 7-digit number $ulen!" unless $ulen<=6;
  my $usec_str;
  for(my $i=0; $i<6-$ulen; $i++){
    $usec_str .= '0';
  }
  push @timings, $hdr->{tv_sec} . ".$usec_str" . $hdr->{tv_usec};  
  print $packet_counter++, "\r";
}

#
# packet collector
sub packet_collect_func
{
    my($udata, $hdr, $pkt) = @_;
    
  if( $dumper )
  {
    Net::Pcap::dump($dumper, $hdr, $pkt );
  }
  print $packet_counter++, "\r";

}

#
# calls iptables to apply the following rule to drop forwarded packets using:
#
# iptables -I FORWARD -i $IN_ETH -p 51 -m statistic --mode nth --every $N --packet $WHICH_IN_N -j DROP
#

sub iptables_drop_every_nth_packet #(@protos, $n, $dev)
{
  my (@protos) = @{$_[0]};
  my ($n) = $_[1];
  my ($dev) = $_[2];
  my $n_minus_1 = $n - 1;
  
  foreach my $proto(@protos) 
  {
    my $iptables_string = "iptables -I FORWARD -i $dev -p $proto -m statistic --mode nth --every $n --packet $n_minus_1 -j DROP";
    print "applying : '", $iptables_string, "'\n";
    `$iptables_string`;
  }
}

sub clear_iptables_drop_every_nth_packet #(@protos, $n, $dev)
{
  my (@protos) = @{$_[0]};
  my ($n) = $_[1];
  my ($dev) = $_[2];
  my $n_minus_1 = $n - 1;
  
  foreach my $proto(@protos) 
  {
    my $iptables_string = "iptables -D FORWARD -i $dev -p $proto -m statistic --mode nth --every $n --packet $n_minus_1 -j DROP";
    print "applying : '", $iptables_string, "'\n";
    `$iptables_string`;
  }
}

#
# reads in a file and returns data in a list based on the cluster means rather than the original values
#
sub clusterFile
{
  my ($fname) = $_[0];

  my $mask = "N1";  # first column is id, second is to be used
  
  # Asking for 0 clusters means the algorithm will determine optimal clustering.
  # In our case, perhaps we should be asking for 4.
  
  my $clusterer = Algorithm::KMeans->new( datafile => $fname,               
  					mask     => $mask,                   
  					K        => 0,                      
  					terminal_output => 0,  
      );             
  
  $clusterer->read_data_from_file();                                           
  $clusterer->kmeans();         
  
  my ($clusters, $cluster_centers) = $clusterer->kmeans();                     
  my @cluster_datas = @$clusters;
  my @centers = @$cluster_centers;
  
  
  my @bins;
  for( my $i = 0; $i<scalar(@cluster_datas); $i++ )
  {
    my @cluster = @{$cluster_datas[$i]};
    my $cluster_size = scalar(@cluster);
    my $center = $centers[$i][0];
  #  print "Cluster $i ($cluster_size) : @cluster\n";
    foreach my $c (@cluster)
    {
      $bins[$c] = $center;
    }
  }
  
  return @bins;
 
}                                      