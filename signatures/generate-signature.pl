#!/usr/bin/perl

#
#  Takes a file with format:
#  <id>    <time> 
# 
# Appends a line to the signature file describing the distribution

use Algorithm::KMeans;

use SigFile; # import save_to_xml_file, read_from_xml_file

use strict;

my($fname, $desc, $destfile) = @ARGV;

die "Usage: $0 datafile description destinationfile\n" unless @ARGV == 3;

my $err;

my $mask = "N1";  # first column is id, second is to be used

# Asking for 0 clusters means the algorithm will determine optimal clustering.
# In our case, perhaps we should be asking for 4.

my $clusterer = Algorithm::KMeans->new( datafile => $fname,               
					mask     => $mask,                   
					K        => 0,                      
					terminal_output => 1,  
    );             

$clusterer->read_data_from_file();                                           
$clusterer->kmeans();         

my ($clusters, $cluster_centers) = $clusterer->kmeans();                     

print "We have " . scalar(@$clusters) . " clusters.\n";                    

my $i = 1;    
                                                    
foreach my $cluster (@$clusters) {
    print "Cluster " . $i . ", size " . scalar(@$cluster) . "\n"; 
    print "Cluster:   @$cluster\n\n";
    $i = $i + 1;
}                                                                            

#
#   Sort cluster_centers; we must preserve the same order of clusters 
#
my %h;

for (@$cluster_centers){
    $h{$_} = shift @$clusters;
}

my @sorted_centers  = sort { $a->[0] <=> $b->[0] } @$cluster_centers;
my @sorted_clusters = map { $h{$_} } @sorted_centers;  

my @dist;
my @weighted;
my $total = 0;
                                                    
foreach my $cluster (@sorted_clusters) {
    push @dist, scalar(@$cluster);
    $total = $total + scalar(@$cluster);
}                                           

foreach my $n (@dist) {
    push @weighted, $n/$total;
}

save_to_xml_file($destfile, $desc, \@sorted_centers, \@weighted);
my $new_recs = read_from_xml_file($destfile);

# Pretty-print records
for my $r (@$new_recs){
    print "Desc: ", $r->[0], " : ";
    print "Clusters: ", join(" ", @{$r->[1]}), " ; ";
    print "Weights: ", join(" ", @{$r->[2]}), "\n";
}
