#!/usr/bin/perl

use strict;
use warnings;
use File::Find       ();
use HTML::TokeParser ();

use Data::Dumper ();

my $dir = $ARGV[0] || '.';

if ( !-d $dir ) {
    warn "Sorry, $dir is not a valid directory: $!";
    exit 1;
}

my $file_name_match = '\.html?$';

print "Checking directory \'$dir\' for files matching regex \'$file_name_match\'.\n";

my @files  = qw();
my @images = qw();

sub wanted {
    if (m/$file_name_match/o) {
        push @files, $File::Find::name;
    }
}

File::Find::find( \&wanted, $dir );

# print "Files:\n" . join( "\n", @files ) . "\n";

my %file_stats = (
    'TOTALS' => {
        'line_count' => 0,
        'word_count' => 0,
        'url_count'  => 0,
        'topics'     => 0,
    }
);

foreach my $file (@files) {
    my $file_fh;
    unless ( open( $file_fh, '<', $file ) ) {
        warn "Failed to open $file: $!";
        next;
    }

    $file_stats{$file} = {
        'line_count' => 0,
        'word_count' => 0,
        'url_count'  => 0,
        'URLs'       => [],
    };

    # Begin file operations
    while ( my $line = <$file_fh> ) {

        # Strip XML/HTML tags
        $line =~ s/\<(?:[^>])+\>//g;

        # Only proceed if there is non-whitespace content
        if ( my $word_count = () = $line =~ m/\S+/g ) {

            # Process URLs
            if ( my @line_URLs = $line =~ m/[a-z]+\:\/\/\S+/gi ) {
                foreach my $url (@line_URLs) {

                    # Trim trailing non-URL characters
                    $url =~ s/[.:\]"'\)]$//;

                    next if !verify_URL($url);

                    $file_stats{$file}{'url_count'}++;
                    push @{ $file_stats{$file}{'URLs'} }, $url;
                }
            }
            $file_stats{$file}{'line_count'}++;
            $file_stats{$file}{'word_count'} += $word_count;

        }
    }
    close $file_fh;

    # Re-open and Parse HTML for a tag href URLs and img src values
    my $p = HTML::TokeParser->new($file) or die "Could not open $file: $!";

    while ( my $t = $p->get_token ) {

        # Skip start or end tags that are not "p" tags
        if ( $t->[0] eq 'S' && ( lc $t->[1] eq 'a' || lc $t->[1] eq 'img' ) ) {

            if ( lc $t->[1] eq 'a' ) {
                my $url = $t->[2]{'href'} || '-';
                next if !verify_URL($url);

                $file_stats{$file}{'url_count'}++;
                push @{ $file_stats{$file}{'URLs'} }, $url;
            }
            else {
                my $img = $t->[2]{'src'} || '-';
                next if $img !~ m/attachments/;
                push @images, $img;

            }

        }

    }

    $file_stats{'TOTALS'}{'line_count'} += $file_stats{$file}{'line_count'};
    $file_stats{'TOTALS'}{'word_count'} += $file_stats{$file}{'word_count'};
    $file_stats{'TOTALS'}{'url_count'}  += $file_stats{$file}{'url_count'};
    $file_stats{'TOTALS'}{'topics'}++;
}

my $image_count = @images;

# All time in hours
my $image_edit_time = sprintf( "%.1f", $image_count * ( 4 / 60 ) );
my $topics__review_time =
    sprintf( "%.1f", $file_stats{'TOTALS'}{'topics'} * ( 10 / 60 ) );
my $style_edit_time = sprintf( "%.1f", ( $file_stats{'TOTALS'}{'word_count'} / 100 ) * ( 4 / 60 ) );
my $URL_edit_time =
    sprintf( "%.1f", $file_stats{'TOTALS'}{'url_count'} * ( 3 / 60 ) );

my $total_time  = $topics__review_time + $style_edit_time + $image_edit_time + $URL_edit_time;
my $total_days  = sprintf( "%.1f", $total_time / 6 );
my $total_weeks = sprintf( "%.1f", ( $total_time / 6 ) / 5 );

print <<"EOM";
===============================
Total Statistics:
    Topics - $file_stats{'TOTALS'}{'topics'}
    Lines  - $file_stats{'TOTALS'}{'line_count'}
    Words  - $file_stats{'TOTALS'}{'word_count'}
    URLs   - $file_stats{'TOTALS'}{'url_count'}
    Images - $image_count

Time Estimates:
    Topic Review - $topics__review_time hours
    Style Edit   - $style_edit_time hours
    Image Edit   - $image_edit_time hours
    URL Verify   - $URL_edit_time hours
    
    Total: $total_time hours / $total_days days / $total_weeks weeks
===============================

External URLs:

EOM

foreach my $file ( sort keys %file_stats ) {
    next if $file eq 'TOTALS';
    if ( @{ $file_stats{$file}{'URLs'} } ) {
        print "$file:\n";
        foreach my $url ( @{ $file_stats{$file}{'URLs'} } ) {
            print "\t$url\n";
        }
    }
}

sub verify_URL {
    my ($url) = @_;

    # Skip Incomplete URLs
    return if $url !~ m/[a-z]+\:\/\/\S+/i;

    # Skip URLs that have variable expansion characters
    return if $url =~ m/\$/;

    # Skip URLs that use IP addresses/localhost
    return
        if $url =~ m/\/\/(?:\d+\.\d+\.\d+\.\d+|localhost|\&lt\;\w+\&gt\;)/i;

    # Skip URLs that are for r1soft.com sites
    return if $url =~ m/\W?r1soft\.com/i;

    # Skip file URLs
    return if $url =~ m/file\:/i;

    return 1;
}
