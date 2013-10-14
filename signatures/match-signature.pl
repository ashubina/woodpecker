#!/usr/bin/perl

#
#  Takes distribution source file with format:
#  <id>    <time> 
#
#  and a file of fingerprints in XML format, dumped by repeated use of 
#     generate-signature.pl
#
#  Prints an ordered list of signatures, sorted by averaged match distance.
#
use Algorithm::KMeans;

use SigFile; # read_from_xml_file

use strict;

my($fname1, $fname2) = @ARGV;

die "Usage: $0 sourcefile fingerprintfile\n" unless @ARGV == 2;

my $err;

my $mask = "N1";  # first column is id, second is to be used

# Asking for 0 clusters means the algorithm will determine optimal clustering.
# In our case, perhaps we should be asking for 4.

my $clusterer1 = Algorithm::KMeans->new( datafile => $fname1,               
					mask     => $mask,                   
					K        => 0,                      
					terminal_output => 1,  
    );             


$clusterer1->read_data_from_file();                                           
my ($clusters1, $cluster_centers1) = $clusterer1->kmeans();                     

print "Dist 1 has " . scalar(@$clusters1) . " clusters.\n";                    

print "Sorting...\n";

my ($sorted_clusters1, $sorted_centers1) = sort_dist($clusters1, $cluster_centers1); 

sub normalize_dist {
    my ($clusters) = @_;
    my $i = 1;
    my $total = 0;
    my @dist;

    print "There are ", scalar(@$clusters), " clusters\n";

    foreach my $cluster (@$clusters) {
	print "Cluster " , $i , ", size " , scalar(@$cluster) , "; "; 
	print "Cluster:   @$cluster\n";
	$i = $i + 1;
	push @dist, scalar(@$cluster);
	$total = $total + scalar(@$cluster);
    }                                                                          

    for ($i = 0; $i < scalar(@$clusters); $i++) {
	$dist[$i] = $dist[$i]/$total;
    }

    print "Normalized distribution is " , join(" ", @dist) , "\n";

    return \@dist;
}

my $dist1 = normalize_dist($sorted_clusters1);

my $dist2;        
my $clusterer2;
my $clusters2;
my $cluster_centers2;

#
#  Take arrayrefs of clusters and their centers;
#   return new arrayrefs where clusters are sorted by 
#   the location of their centers (first element in
#   each cluster_centers tuple).
#
sub sort_dist{
    my($clusters, $cluster_centers) = @_;

    my %h;
    for (@$cluster_centers){
	$h{$_} = shift @$clusters;
    }

    my @sorted_centers = sort { $a->[0] <=> $b->[0] } @$cluster_centers;
    my @sorted_clusters = map { $h{$_} } @sorted_centers;  

    return (\@sorted_clusters, \@sorted_centers);
}

sub process_signature{
    my($rec) = @_;
    my $siglen = scalar(@{$rec->[2]});

    print "Testing record ", join(" ", @{$rec->[2]}) , "\n";
    print "Signature length ", $siglen, "\n";

    print "Recomputing our dist to ", $siglen , " clusters\n";
    $clusterer1 = Algorithm::KMeans->new( datafile => $fname1,          
					  mask     => $mask,                
					  K        => $siglen,       
					  terminal_output => 1,  
	);             
    $clusterer1->read_data_from_file();                             
    
    ($clusters1, $cluster_centers1) = $clusterer1->kmeans();     
    
    ($sorted_clusters1, $sorted_centers1) = sort_dist($clusters1, $cluster_centers1); 

    print "Record length ", scalar(@$sorted_clusters1), "\n";
    
    $dist1 = normalize_dist($sorted_clusters1);
    
    print "Sorted distribution: ", join(" ", @$dist1), "\n";
    return ($dist1, \@{$rec->[2]});
}

my $signatures = read_from_xml_file($fname2);

my $dist2;
my $dist1;
my @final;

for my $r (@$signatures) {
    print "Desc: ", $r->[0], "\n";
    print "Weights: ", join(" ", @{$r->[2]}), "\n";

    ($dist1, $dist2) = process_signature($r);
    print "Signature processed\n";
    print "Old weights: ", join(" ", @{$r->[2]}), "\n";
    print "New weights: ", join(" ", @$dist2), "\n";
    my ($js, $l1, $l2) = compute_distance($dist1, $dist2);
    push @final, [$r->[0], $js, $l1, $l2];
}

# Here I will just sort the dists by the average of the measures and print
# them out.

my @best_dists = sort { $a->[1] + $a->[2] + $a->[3] <=> $b->[1] + $b->[2] + $b->[3] } @final;

print "Likely matches, from best to worst:\n\n";

for my $r (@best_dists) {
    print $r->[0] , " JS: ", $r->[1], " L1: ", $r->[2], " L2: ", $r->[3], 
    " Avg: ", ($r->[1] + $r->[2] + $r->[3])/3 , "\n";
}

sub entropy {
    my @v = @_;
    my $res = 0;
    my $l;
    foreach my $x (@v) {
        if ($x > 0) {
            $l = log($x);
	    $res = $res - $x * log($x);
        }
    }
    return $res;
}

sub L1 {
    my ($v1, $v2) = @_;
    my $res = 0;
    for (my $i=0; $i < scalar(@$v1); $i++) {
	$res = $res + abs($v1->[$i] - $v2->[$i]);
    }
    return $res;
}

sub L2 {
    my ($v1, $v2) = @_;
    my $res = 0;
    for (my $i=0; $i < scalar(@$v1); $i++) {
	$res = $res + ($v1->[$i] - $v2->[$i]) * ($v1->[$i] - $v2->[$i]);
    }
    return $res;
}

sub compute_distance {

    my ($d1, $d2) = @_;

    my @distavg;
    
    for (my $i = 0; $i < scalar(@$d2); $i++) {
	push @distavg, ($d1->[$i] + $d2->[$i])/2;
    }

    print "Dist 1: @$d1\n\n";
    print "Dist 2: @$d2\n\n";
    print "Avg: @distavg\n\n";

    my $e1 = entropy(@$d1);
    my $e2 = entropy(@$d2);
    my $ed = entropy(@distavg);

    print "Entropy 1: $e1\n\n";
    print "Entropy 2: $e2\n\n";
    print "Entropy of the avg: $ed\n\n";

    my $js = $ed - $e1/2 - $e2/2;

    print "JS divergence: $js\n\n";

    my $l1 = L1($dist1, $dist2);
    my $l2 = L2($dist1, $dist2);

    print "L1 distance " . $l1 . "\n\n";
    print "L2 distance " . $l2 . "\n\n";

    print "Avg on these 3 measures: " . ($js + $l1 + $l2)/3 . "\n\n\n";

    return ($js, $l1, $l2);
}
