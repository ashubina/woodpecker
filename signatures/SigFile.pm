
package SigFile;

use strict;

# export parsing functions 
require Exporter;
use vars qw(@ISA @EXPORT);
@ISA               = qw(Exporter);
@EXPORT            = qw(save_to_txt_file save_to_xml_file read_from_txt_file read_from_xml_file);

# for XML reading/writing
use IO::File;
use XML::Writer;
use XML::Simple;
# use Data::Dumper; -- for debugging

#
#  Append a model to file, as plain text
#  Args: file name, description, two arrayrefs (assumed of equal size)
#        Description not allowed to contain spaces or newlines! 
#        Space is the field separator, newline record separator.
#
sub save_to_txt_file {
    my($destfile, $desc, $cluster_centers, $weighted) = @_;
    open(OUT, ">>$destfile") || die "Cannot append to $destfile: $!\n";
    
    my $len1 = scalar @$cluster_centers;
    my $len2 = scalar @$weighted;
    warn "Arrayrefs disagree in length: $len1 $len2\n" unless $len1 == $len2;

    print OUT "$desc $len1 ";
    foreach my $c (@$cluster_centers) {
	print OUT $c->[0] . " ";
    }
#    print OUT join(" ", @$cluster_centers), " ";
    print OUT join(" ", @$weighted), "\n";

    close OUT;
}

#
#  Append a model to file, as XML fragments
#  Args: file name, description, two arrayrefs (assumed of equal size)
#        Description may contain whatever, even the entire text of "War and Peace".
#        Note: a valid XML file must have a single root. Reader must correct for this,
#              by creating a single fake root element.
#
sub save_to_xml_file {
    my($destfile, $desc, $cluster_centers, $weighted) = @_;

    my $output = IO::File->new(">>$destfile");
    my $writer = XML::Writer->new(OUTPUT => $output);

    # $writer->xmlDecl('UTF-8');

    # Make sure there's a weight for each cluster
    my $len1 = scalar @$cluster_centers;
    my $len2 = scalar @$weighted;
    warn "Arrayrefs disagree in length: $len1 $len2\n" unless $len1 == $len2;
    
    $writer->startTag("sig");
    $writer->startTag("name");
    $writer->characters($desc);
    $writer->endTag("name");
    my $i=0;
    foreach my $c (@$cluster_centers) {
	$writer->emptyTag("cluster", 'center' => $c->[0] , 'weight' => $weighted->[$i++] );
    }
    $writer->endTag("sig");
    $writer->end();
    $output->close();
}

#
#  Read records saved as above from text file.
#
sub read_from_txt_file {
    my($srcfile) = @_;
    open(IN, "<$srcfile") || die "cannot open $srcfile: $!\n";
    my @records;
    while(<IN>){
	chomp;
	next unless /\S/; # skip empty lines
	my($desc, $len, @vals) = split(' ', $_);
	warn "Non-positive length $len in record $_\n" unless $len > 0;
	warn "Fewer values than 2*$len in record $_\n" if scalar @vals < 2*$len;
	warn "Extra values over 2*$len in record $_\n" if scalar @vals > 2*$len;
	# byte off last $len values
	my @head = splice( @vals, 0, $len );
	# create record 
	push @records, [$desc, \@head, \@vals];
    }
    return \@records;
}


#
#  Read records saved as above from XML file. 
#    Quirks: insert fake root element, assume UTF-8 encoding
#
sub read_from_xml_file {
    my($srcfile) = @_;
    my $xml_fragments;
    { local $/ = undef;
      open(IN, "<$srcfile") || die "cannot open $srcfile: $!\n";
      $xml_fragments = <IN>;
    }
    my @records;

    my $doc = XMLin( '<doc>'. $xml_fragments . '</doc>', 
		     KeyAttr => {}, ForceArray => 1 );

    # print Dumper($doc);  -- uncomment Data::Dumper at start to use it.

    for my $s (@{$doc->{sig}}){
	my $desc = $s->{name}->[0];
	my @centers;
	my @weights;
	for my $c (@{$s->{cluster}}){ 
	    push @centers, $c->{center};
	    push @weights, $c->{weight};
	}
	# create record 
	push @records, [$desc, \@centers, \@weights];
    }
    return \@records;
}

1;

